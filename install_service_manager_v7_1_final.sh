#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA SERVICE MANAGER v7.1 - FINAL FIX (plugin pptp.so)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Fixing: PPTP plugin, interface creation, GRE tunnel"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"

# ============================================================================
# STEP 1: Install/Reinstall packages to ensure pptp.so plugin
# ============================================================================
echo ""
echo "📦 Step 1/8: Installing/Reinstalling packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install --reinstall -y pptp-linux ppp dante-server net-tools sqlite3 supervisor

# Verify pptp.so plugin exists
PPTP_PLUGIN=$(find /usr/lib/pppd -name pptp.so 2>/dev/null | head -1)
if [ -z "$PPTP_PLUGIN" ]; then
    echo "❌ CRITICAL: pptp.so plugin not found"
    exit 1
fi
echo "✅ pptp.so plugin found at: $PPTP_PLUGIN"

# Load kernel modules
modprobe ppp_generic || true
modprobe ppp_mppe || true
modprobe ppp_deflate || true
modprobe ppp_async || true

cat > /etc/modules-load.d/ppp.conf <<EOF
ppp_generic
ppp_mppe
ppp_deflate
ppp_async
EOF

echo "✅ Packages and modules ready"

# ============================================================================
# STEP 2: Create CORRECT /etc/ppp/peers/connexa with plugin pptp.so
# ============================================================================
echo ""
echo "📦 Step 2/8: Creating /etc/ppp/peers/connexa with plugin pptp.so..."
mkdir -p /etc/ppp/peers
mkdir -p /var/log/ppp

cat > /etc/ppp/peers/connexa <<'PEER'
plugin pptp.so
pptp_server 144.229.29.35
user "admin"
require-mppe-128
refuse-eap
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
persist
maxfail 3
defaultroute
usepeerdns
mtu 1460
mru 1460
noauth
logfile /var/log/ppp/connexa.log
PEER

echo "✅ /etc/ppp/peers/connexa created with plugin pptp.so"

# ============================================================================
# STEP 3: Create /etc/ppp/chap-secrets
# ============================================================================
echo ""
echo "📦 Step 3/8: Creating /etc/ppp/chap-secrets..."
cat > /etc/ppp/chap-secrets <<'CHAP'
"admin" * "admin" *
CHAP

chmod 600 /etc/ppp/chap-secrets
echo "✅ /etc/ppp/chap-secrets created"

# ============================================================================
# STEP 4: Update link_socks_to_ppp.sh with auto-restart
# ============================================================================
echo ""
echo "📦 Step 4/8: Updating link_socks_to_ppp.sh..."
cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
SOCKS_PORT="${1:-1080}"
PPP_IFACE="${2:-ppp0}"
LOG_FILE="/var/log/link_socks_to_ppp.log"

exec >> "$LOG_FILE" 2>&1
echo "=== $(date) ==="
echo "🔗 Linking SOCKS port ${SOCKS_PORT} to interface ${PPP_IFACE}"

# Check if interface exists, if not try to restart pppd
if ! ip link show "$PPP_IFACE" &>/dev/null; then
    echo "⚠️ Interface $PPP_IFACE not found, attempting to restart pppd..."
    pkill -f "pppd.*$PPP_IFACE" || true
    pppd call connexa &
    sleep 5
fi

# Wait for interface to be UP (max 15 seconds)
for i in {1..15}; do
    if ip link show "$PPP_IFACE" 2>/dev/null | grep -q "state UP"; then
        echo "✅ Interface $PPP_IFACE is UP"
        break
    fi
    echo "⏳ Waiting for $PPP_IFACE to be UP (attempt $i/15)..."
    sleep 1
done

# Final check
if ! ip link show "$PPP_IFACE" &>/dev/null; then
    echo "❌ Interface $PPP_IFACE does not exist after restart" >&2
    exit 1
fi

if ! ip link show "$PPP_IFACE" | grep -q "state UP"; then
    echo "❌ Interface $PPP_IFACE is not UP" >&2
    exit 1
fi

# Get external IP
EXTERNAL_IP=$(ip addr show "$PPP_IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "📍 External IP on $PPP_IFACE: $EXTERNAL_IP"

# Generate danted.conf
echo "📝 Generating /etc/danted.conf..."
cat > /etc/danted.conf <<DANTE
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${PPP_IFACE}
method: none
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect
}
DANTE

echo "🔄 Restarting danted..."
systemctl restart danted 2>&1
sleep 2

# Verify
if netstat -tulnp 2>/dev/null | grep -q ":${SOCKS_PORT}"; then
    echo "✅ Dante active on port ${SOCKS_PORT}"
    echo "$(date) bind ${SOCKS_PORT} -> ${PPP_IFACE} (${EXTERNAL_IP})"
    exit 0
else
    echo "❌ Dante not listening on port ${SOCKS_PORT}" >&2
    systemctl status danted --no-pager >&2
    exit 1
fi
SCRIPT

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh updated"

# ============================================================================
# STEP 5: Update service_manager.py with interface cleanup
# ============================================================================
echo ""
echo "📦 Step 5/8: Updating service_manager.py..."
cat > "$APP_DIR/service_manager.py" <<'PYEOF'
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
MAX_CONCURRENT_NODES = 5

class ServiceManager:
    def __init__(self):
        self.db_path = DB_PATH
        Path(PPP_LOG_DIR).mkdir(parents=True, exist_ok=True)
    
    def _run(self, cmd: str) -> Tuple[int, str, str]:
        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, 
                           stderr=subprocess.PIPE, text=True)
        out, err = p.communicate()
        return p.returncode, out.strip(), err.strip()
    
    def _cleanup_old_interfaces(self) -> None:
        """Remove stale ppp interfaces."""
        rc, out, _ = self._run("ip -o link show | grep -oP 'ppp\\d+' || true")
        for iface in out.split('\n'):
            if iface:
                self._run(f"ip link delete {iface} 2>/dev/null || true")
    
    def _is_port_listening(self, port: int) -> bool:
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
    
    def _wait_for_ppp_connect(self, log_file: str, timeout: int = 20) -> Optional[str]:
        """Wait for 'Connect:' or 'Using interface' in pppd log."""
        for _ in range(timeout):
            if os.path.exists(log_file):
                try:
                    with open(log_file, 'r') as f:
                        content = f.read()
                        if 'Using interface' in content:
                            match = re.search(r'Using interface (ppp\d+)', content)
                            if match:
                                return match.group(1)
                        if 'Connect:' in content:
                            match = re.search(r'Connect: (ppp\d+)', content)
                            if match:
                                return match.group(1)
                except Exception:
                    pass
            time.sleep(1)
        return None
    
    def _detect_cred_columns(self, cur) -> Tuple[str, str]:
        cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall() 
                if len(r) >= 2}
        user_col = next((c for c in ("username", "user", "login") if c in cols), None)
        pass_col = next((c for c in ("password", "pass") if c in cols), None)
        if not user_col or not pass_col:
            raise RuntimeError(f"Cannot detect credentials")
        return user_col, pass_col
    
    def _get_active_nodes(self, limit: int = MAX_CONCURRENT_NODES) -> List[Dict]:
        """Get active nodes from database."""
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
    
    def _write_peer_conf(self, node_id: int, ip: str, username: str) -> str:
        """Write PPP peer configuration using plugin pptp.so."""
        Path(PEER_DIR).mkdir(parents=True, exist_ok=True)
        peer_file = f"{PEER_DIR}/{PEER_NAME}-{node_id}"
        peer_config = f'''plugin pptp.so
pptp_server {ip}
user "{username}"
require-mppe-128
refuse-eap
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
persist
maxfail 3
defaultroute
usepeerdns
mtu 1460
mru 1460
noauth
logfile {PPP_LOG_DIR}/pptp_node_{node_id}.log
'''
        Path(peer_file).write_text(peer_config)
        return peer_file
    
    def _write_chap(self, username: str, password: str) -> None:
        """Append credentials to chap-secrets."""
        line = f'"{username}" * "{password}" *\n'
        with open(CHAP_FILE, 'a') as f:
            f.write(line)
        os.chmod(CHAP_FILE, 0o600)
    
    def _start_pptp_tunnel(self, node: Dict) -> Optional[str]:
        """Start PPTP tunnel and wait for connection."""
        node_id = node['id']
        ip = node['ip']
        username = node['username']
        password = node['password']
        
        # Write configs
        self._write_peer_conf(node_id, ip, username)
        self._write_chap(username, password)
        
        # Start pppd
        log_file = f"{PPP_LOG_DIR}/pptp_node_{node_id}.log"
        self._run(f"pppd call {PEER_NAME}-{node_id} &")
        
        # Wait for connection
        iface = self._wait_for_ppp_connect(log_file, timeout=20)
        if not iface:
            return None
        
        # Verify interface is UP
        for _ in range(8):
            if self._is_ppp_interface_up(iface):
                return iface
            time.sleep(1)
        
        return None
    
    def _get_diagnostics(self) -> Dict[str, Any]:
        ppp_check = self._run("ip a | grep ppp || true")[1]
        ports = self._run("netstat -tulnp 2>/dev/null | grep -E ':(108[0-9]|8001)' || true")[1]
        routes = self._run("ip route | head -10")[1]
        pppd_log = Path(f"{PPP_LOG_DIR}/connexa.log").read_text()[-1000:] if Path(f"{PPP_LOG_DIR}/connexa.log").exists() else ""
        link_log = Path("/var/log/link_socks_to_ppp.log").read_text()[-1000:] if Path("/var/log/link_socks_to_ppp.log").exists() else ""
        
        return {
            "ppp_interfaces": ppp_check,
            "listening_ports": ports,
            "routes": routes,
            "pppd_log": pppd_log,
            "link_log": link_log
        }
    
    def start(self) -> Dict[str, Any]:
        """Start PPTP tunnels with interface cleanup."""
        # Cleanup old interfaces
        self._cleanup_old_interfaces()
        
        # Stop existing processes
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._run("systemctl stop danted 2>/dev/null || true")
        time.sleep(2)
        
        # Clear chap-secrets
        Path(CHAP_FILE).write_text("")
        
        nodes = self._get_active_nodes(limit=MAX_CONCURRENT_NODES)
        if not nodes:
            return {
                "ok": False,
                "error": "No suitable nodes",
                "diagnostics": self._get_diagnostics()
            }
        
        results = []
        for idx, node in enumerate(nodes):
            try:
                iface = self._start_pptp_tunnel(node)
                if not iface:
                    results.append({
                        "node_id": node['id'],
                        "error": "PPTP connection failed"
                    })
                    continue
                
                # Bind SOCKS
                socks_port = SOCKS_PORT_BASE + idx
                self._run(f"/usr/local/bin/link_socks_to_ppp.sh {socks_port} {iface}")
                time.sleep(1)
                
                results.append({
                    "node_id": node['id'],
                    "interface": iface,
                    "socks_port": socks_port,
                    "socks_active": self._is_port_listening(socks_port),
                    "status": "ok"
                })
                
            except Exception as e:
                results.append({"node_id": node['id'], "error": str(e)})
        
        successful = [r for r in results if r.get("status") == "ok"]
        
        return {
            "ok": len(successful) > 0,
            "status": "running" if len(successful) > 0 else "failed",
            "started": len(successful),
            "details": results,
            "diagnostics": self._get_diagnostics()
        }
    
    def stop(self) -> Dict[str, Any]:
        """Stop all services."""
        self._run("systemctl stop danted 2>/dev/null || true")
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._cleanup_old_interfaces()
        Path(CHAP_FILE).write_text("")
        time.sleep(2)
        
        return {"ok": True, "status": "stopped", "diagnostics": self._get_diagnostics()}
    
    def status(self) -> Dict[str, Any]:
        """Get status."""
        ppp_count = len(self._run("ip -o link show | grep -c ppp || echo 0")[1].strip())
        socks_ports = [p for p in range(SOCKS_PORT_BASE, SOCKS_PORT_BASE + 10) if self._is_port_listening(p)]
        
        return {
            "ok": True,
            "status": "running" if ppp_count > 0 and len(socks_ports) > 0 else "stopped",
            "ppp_interfaces": ppp_count,
            "socks_ports": socks_ports,
            "diagnostics": self._get_diagnostics()
        }
PYEOF
echo "✅ service_manager.py updated"

# ============================================================================
# STEP 6: Test PPTP connection manually
# ============================================================================
echo ""
echo "📦 Step 6/8: Testing PPTP connection..."
pkill -f pppd || true
sleep 2
pppd call connexa &
sleep 10

if ip a | grep -q "ppp0"; then
    echo "✅ ppp0 interface created successfully!"
    ip a show ppp0
else
    echo "⚠️ ppp0 not created yet, check logs:"
    tail -20 /var/log/ppp/connexa.log
fi

# ============================================================================
# STEP 7: Create/update router
# ============================================================================
echo ""
echo "📦 Step 7/8: Creating router..."
mkdir -p "$APP_DIR/router"
cat > "$APP_DIR/router/service_router.py" <<'PYEOF'
from fastapi import APIRouter
import sys
sys.path.insert(0, '/app/backend')
from service_manager import ServiceManager

router = APIRouter(prefix="/service", tags=["Service Management"])
manager = ServiceManager()

@router.post("/start")
async def start_service():
    return manager.start()

@router.post("/stop")
async def stop_service():
    return manager.stop()

@router.get("/status")
async def status_service():
    return manager.status()
PYEOF
touch "$APP_DIR/router/__init__.py"

# Patch server.py
if [ -f "$APP_DIR/server.py" ]; then
    if ! grep -q "service_router" "$APP_DIR/server.py"; then
        sed -i '1i from router.service_router import router as service_router' "$APP_DIR/server.py"
        sed -i '/^app = FastAPI/a app.include_router(service_router)' "$APP_DIR/server.py"
    fi
fi
echo "✅ Router created"

# ============================================================================
# STEP 8: Restart backend
# ============================================================================
echo ""
echo "📦 Step 8/8: Restarting backend..."
supervisorctl restart backend 2>/dev/null || true
sleep 3

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ v7.1 INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔍 Verification:"
echo "  find /usr/lib/pppd -name pptp.so     # Check plugin"
echo "  ip a | grep ppp                       # Show interfaces"
echo "  tail -f /var/log/ppp/connexa.log     # Watch PPTP log"
echo "  tail -f /var/log/link_socks_to_ppp.log  # Watch SOCKS binding"
echo "  curl --socks5 127.0.0.1:1080 ifconfig.me  # Test via SOCKS"
echo ""
echo "🚀 Now click 'Start Service' in Admin Panel"
echo "════════════════════════════════════════════════════════════════"
