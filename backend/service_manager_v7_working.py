#!/usr/bin/env python3
"""
Service Manager for CONNEXA PPTP/SOCKS Service
Manages PPTP tunnel startup/shutdown with unique unit IDs and SOCKS binding
"""
import os
import re
import sqlite3
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple, List

DB_PATH = os.environ.get("CONNEXA_DB", "/app/backend/connexa.db")
PEER_NAME = "connexa"
PEER_DIR = "/etc/ppp/peers"
CHAP_FILE = "/etc/ppp/chap-secrets"
SOCKS_PORT_BASE = 1080
PPP_LOG_DIR = "/var/log/ppp"
MAX_CONCURRENT_NODES = 3  # Reduced from 5 to prevent fd exhaustion

class ServiceManager:
    def __init__(self):
        self.db_path = DB_PATH
        Path(PPP_LOG_DIR).mkdir(parents=True, exist_ok=True)
        # Increase FD limit for current process
        try:
            import resource
            resource.setrlimit(resource.RLIMIT_NOFILE, (65535, 65535))
        except:
            pass
    
    def _run(self, cmd: str) -> Tuple[int, str, str]:
        """Execute shell command and return result."""
        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, 
                           stderr=subprocess.PIPE, text=True)
        out, err = p.communicate()
        return p.returncode, out.strip(), err.strip()
    
    def _cleanup_old_interfaces(self) -> None:
        """Remove stale ppp interfaces."""
        rc, out, _ = self._run("ip -o link show | grep -oP 'ppp\\d+' || true")
        for iface in out.split('\n'):
            if iface.strip():
                self._run(f"ip link delete {iface} 2>/dev/null || true")
        
        # Clean old pid files
        self._run("rm -f /var/run/ppp*.pid 2>/dev/null || true")
    
    def _is_port_listening(self, port: int) -> bool:
        """Check if port is listening."""
        rc, out, _ = self._run(f"netstat -tulnp 2>/dev/null | grep ':{port}' || true")
        return len(out) > 0
    
    def _is_ppp_interface_up(self, iface: str) -> bool:
        """Check if PPP interface is UP and POINTOPOINT."""
        try:
            result = subprocess.check_output(
                ["ip", "link", "show", iface],
                text=True,
                stderr=subprocess.DEVNULL
            )
            return "state UP" in result and "POINTOPOINT" in result
        except subprocess.CalledProcessError:
            return False
    
    def _wait_for_ppp_interface(self, unit: int, timeout: int = 30) -> Optional[str]:
        """Wait for ppp interface to be created and UP."""
        iface = f"ppp{unit}"
        
        for attempt in range(timeout):
            # Check if interface exists
            if Path(f"/sys/class/net/{iface}").exists():
                # Check if UP
                if self._is_ppp_interface_up(iface):
                    return iface
            time.sleep(1)
        
        return None
    
    def _detect_cred_columns(self, cur) -> Tuple[str, str]:
        """Auto-detect username and password column names."""
        cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall() 
                if len(r) >= 2}
        user_col = next((c for c in ("username", "user", "login") if c in cols), None)
        pass_col = next((c for c in ("password", "pass") if c in cols), None)
        if not user_col or pass_col:
            raise RuntimeError(f"Cannot detect credentials columns (found: {sorted(cols)})")
        return user_col, pass_col
    
    def _get_active_nodes(self, limit: int = MAX_CONCURRENT_NODES) -> List[Dict]:
        """Get active nodes from database with status speed_ok or ping_light."""
        if not Path(self.db_path).exists():
            return []
        
        con = sqlite3.connect(self.db_path)
        con.row_factory = sqlite3.Row
        cur = con.cursor()
        user_col, pass_col = self._detect_cred_columns(cur)
        
        nodes = []
        for status in ("speed_ok", "ping_light"):
            rows = cur.execute(
                f"SELECT id, ip, {user_col} AS username, {pass_col} AS password FROM nodes "
                f"WHERE status=? AND ip!='' AND {user_col}!='' AND {pass_col}!='' LIMIT ?;",
                (status, limit - len(nodes))
            ).fetchall()
            nodes.extend([dict(row) for row in rows])
            if len(nodes) >= limit:
                break
        
        con.close()
        return nodes[:limit]
    
    def _write_peer_conf(self, node_id: int, unit: int, ip: str, username: str) -> str:
        """Write PPP peer configuration with UNIT ID."""
        Path(PEER_DIR).mkdir(parents=True, exist_ok=True)
        peer_file = f"{PEER_DIR}/{PEER_NAME}-{node_id}"
        
        peer_config = f'''pty "pptp {ip} --nolaunchpppd"
unit {unit}
user {username}
remotename {PEER_NAME}-{node_id}
refuse-eap
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
persist
maxfail 3
usepeerdns
mtu 1460
mru 1460
debug
logfile {PPP_LOG_DIR}/pptp_node_{node_id}.log
'''
        Path(peer_file).write_text(peer_config)
        return peer_file
    
    def _write_chap(self, username: str, remotename: str, password: str) -> None:
        """Append credentials to chap-secrets."""
        line = f'{username} {remotename} {password} *\n'
        with open(CHAP_FILE, 'a') as f:
            f.write(line)
        os.chmod(CHAP_FILE, 0o600)
    
    def _start_pptp_tunnel(self, node: Dict, unit: int) -> Optional[str]:
        """Start PPTP tunnel with specific unit ID."""
        node_id = node['id']
        ip = node['ip']
        username = node['username']
        password = node['password']
        
        # Write configs
        self._write_peer_conf(node_id, unit, ip, username)
        self._write_chap(username, f"{PEER_NAME}-{node_id}", password)
        
        # Start pppd
        peer_file = f"{PEER_DIR}/{PEER_NAME}-{node_id}"
        rc, out, err = self._run(f"pppd file {peer_file} &")
        
        # Wait for interface
        iface = self._wait_for_ppp_interface(unit, timeout=30)
        return iface
    
    def _update_node_interface(self, node_id: int, iface: str) -> None:
        """Update database with PPP interface name."""
        if not Path(self.db_path).exists():
            return
        
        con = sqlite3.connect(self.db_path)
        cur = con.cursor()
        try:
            cur.execute("UPDATE nodes SET ppp_interface=? WHERE id=?", (iface, node_id))
            con.commit()
        except:
            pass
        con.close()
    
    def _get_diagnostics(self) -> Dict[str, Any]:
        """Get diagnostic information."""
        ppp_check = self._run("ip -o link show | grep ppp || echo 'No PPP interfaces'")[1]
        ports = self._run("netstat -tulnp | grep -E ':(1080|108[0-9])' || echo 'No SOCKS ports'")[1]
        routes = self._run("ip route | head -10")[1]
        fd_limit = self._run("ulimit -n")[1]
        
        pppd_logs = {}
        for log_file in Path(PPP_LOG_DIR).glob("pptp_node_*.log"):
            try:
                pppd_logs[log_file.name] = log_file.read_text()[-500:]
            except:
                pass
        
        link_log = ""
        if Path("/var/log/link_socks_to_ppp.log").exists():
            try:
                link_log = Path("/var/log/link_socks_to_ppp.log").read_text()[-1000:]
            except:
                pass
        
        return {
            "ppp_interfaces": ppp_check,
            "listening_ports": ports,
            "routes": routes,
            "fd_limit": fd_limit,
            "pppd_logs": pppd_logs,
            "link_log": link_log
        }
    
    def start(self) -> Dict[str, Any]:
        """Start PPTP tunnels with unique unit IDs."""
        # Cleanup
        self._cleanup_old_interfaces()
        
        # Stop existing processes
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._run("systemctl stop danted 2>/dev/null || true")
        time.sleep(2)
        
        # Clear chap-secrets
        Path(CHAP_FILE).write_text("")
        
        # Get active nodes
        nodes = self._get_active_nodes(limit=MAX_CONCURRENT_NODES)
        if not nodes:
            return {
                "ok": False,
                "error": "No suitable nodes (need speed_ok or ping_light)",
                "diagnostics": self._get_diagnostics()
            }
        
        results = []
        for idx, node in enumerate(nodes):
            unit = idx  # Unit ID = index
            try:
                # Start PPTP tunnel with unit ID
                iface = self._start_pptp_tunnel(node, unit)
                if not iface:
                    results.append({
                        "node_id": node['id'],
                        "ip": node['ip'],
                        "unit": unit,
                        "error": "PPTP connection failed or timeout"
                    })
                    continue
                
                # Update DB with interface name
                self._update_node_interface(node['id'], iface)
                
                # Bind SOCKS to PPP
                socks_port = SOCKS_PORT_BASE + idx
                rc, out, err = self._run(
                    f"/usr/local/bin/link_socks_to_ppp.sh {socks_port} {iface}"
                )
                
                time.sleep(2)
                socks_active = self._is_port_listening(socks_port)
                
                results.append({
                    "node_id": node['id'],
                    "ip": node['ip'],
                    "unit": unit,
                    "interface": iface,
                    "socks_port": socks_port,
                    "socks_active": socks_active,
                    "status": "ok" if socks_active else "degraded"
                })
                
            except Exception as e:
                results.append({
                    "node_id": node['id'],
                    "ip": node.get('ip', 'N/A'),
                    "unit": unit,
                    "error": str(e)
                })
        
        successful = [r for r in results if r.get("status") == "ok"]
        
        return {
            "ok": len(successful) > 0,
            "status": "running" if len(successful) > 0 else "failed",
            "started": len(successful),
            "total": len(nodes),
            "details": results,
            "diagnostics": self._get_diagnostics()
        }
    
    def stop(self) -> Dict[str, Any]:
        """Stop all PPTP tunnels and SOCKS proxies."""
        self._run("systemctl stop danted 2>/dev/null || true")
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._cleanup_old_interfaces()
        Path(CHAP_FILE).write_text("")
        time.sleep(2)
        
        return {
            "ok": True,
            "status": "stopped",
            "diagnostics": self._get_diagnostics()
        }
    
    def status(self) -> Dict[str, Any]:
        """Get current service status."""
        ppp_interfaces = self._run("ip -o link show | grep -c ppp || echo 0")[1].strip()
        socks_ports = []
        for port in range(SOCKS_PORT_BASE, SOCKS_PORT_BASE + 10):
            if self._is_port_listening(port):
                socks_ports.append(port)
        
        try:
            ppp_count = int(ppp_interfaces)
        except:
            ppp_count = 0
        
        status = "running" if ppp_count > 0 and len(socks_ports) > 0 else \
                 "degraded" if ppp_count > 0 or len(socks_ports) > 0 else "stopped"
        
        return {
            "ok": True,
            "status": status,
            "ppp_interfaces": ppp_count,
            "socks_ports": socks_ports,
            "diagnostics": self._get_diagnostics()
        }
