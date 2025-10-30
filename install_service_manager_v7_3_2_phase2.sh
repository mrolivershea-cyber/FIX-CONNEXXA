#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.3.2-dev - PHASE 2: Unit ID + Dante Synchronization"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Tag: PHASE_2_UNIT_DANTE"
echo "  Features: Deterministic PPP interfaces, ip-up/down hooks, Dante sync"
echo "  Requires: Phase 1 (v7.3.1-dev) completed"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"
ROUTER_DIR="$APP_DIR/router"

# ============================================================================
# VERIFY PHASE 1 PREREQUISITES
# ============================================================================
echo ""
echo "🔍 [Phase2] Verifying Phase 1 prerequisites..."

CURRENT_ULIMIT=$(ulimit -n)
if [ "$CURRENT_ULIMIT" -lt 65535 ]; then
    echo "⚠️ WARNING: ulimit -n is $CURRENT_ULIMIT (expected 65535)"
    echo "Phase 1 may not be fully applied. Continue anyway? (y/n)"
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

if ! lsmod | grep -q ppp_generic; then
    echo "⚠️ WARNING: ppp_generic module not loaded"
    echo "Loading now..."
    modprobe ppp_generic || true
fi

echo "✅ Prerequisites verified"

# ============================================================================
# STEP 1: Create PPP ip-up hook
# ============================================================================
echo ""
echo "📦 [Phase2] Step 1/8: Creating PPP ip-up hook..."

cat > /etc/ppp/ip-up.d/connexa-dante <<'IPUP'
#!/bin/bash
# PPP ip-up hook for Connexa
# Called when PPP interface comes UP
# Args: $1=interface $2=tty $3=speed $4=local-ip $5=remote-ip $6=ipparam

IFACE="$1"
LOCAL_IP="$4"
REMOTE_IP="$5"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-up] $(date) - Interface $IFACE UP"
echo "  Local IP: $LOCAL_IP"
echo "  Remote IP: $REMOTE_IP"
echo "  ipparam: $IPPARAM"
echo "════════════════════════════════════════════════════════════════"

# Extract SOCKS port from ipparam (format: "socks:1080")
if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-up] Detected SOCKS port: $SOCKS_PORT"
    
    # Trigger SOCKS binding
    /usr/local/bin/link_socks_to_ppp.sh "$SOCKS_PORT" "$IFACE" &
    
    echo "[ip-up] SOCKS binding triggered for port $SOCKS_PORT"
else
    echo "[ip-up] No SOCKS port in ipparam, skipping Dante config"
fi

echo "[ip-up] Hook completed"
IPUP

chmod +x /etc/ppp/ip-up.d/connexa-dante
echo "✅ ip-up hook created"

# ============================================================================
# STEP 2: Create PPP ip-down hook
# ============================================================================
echo ""
echo "📦 [Phase2] Step 2/8: Creating PPP ip-down hook..."

cat > /etc/ppp/ip-down.d/connexa-dante <<'IPDOWN'
#!/bin/bash
# PPP ip-down hook for Connexa
# Called when PPP interface goes DOWN

IFACE="$1"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-down] $(date) - Interface $IFACE DOWN"
echo "  ipparam: $IPPARAM"
echo "════════════════════════════════════════════════════════════════"

# Extract SOCKS port
if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-down] SOCKS port $SOCKS_PORT released"
    
    # Could optionally restart danted here if needed
fi

echo "[ip-down] Hook completed"
IPDOWN

chmod +x /etc/ppp/ip-down.d/connexa-dante
echo "✅ ip-down hook created"

# ============================================================================
# STEP 3: Update link_socks_to_ppp.sh (Phase 1 preserved + enhanced)
# ============================================================================
echo ""
echo "📦 [Phase2] Step 3/8: Updating link_socks_to_ppp.sh..."

cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[Phase2] $(date) - Linking SOCKS port $PORT to interface $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Wait for interface (30 seconds max)
MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
    if ip link show "$IFACE" &>/dev/null; then
        if ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
            echo "✅ Interface $IFACE is UP (attempt $i/$MAX_WAIT)"
            break
        else
            echo "⏳ Interface exists but not UP yet ($i/$MAX_WAIT)"
        fi
    else
        echo "⏳ Waiting for $IFACE to be created ($i/$MAX_WAIT)"
    fi
    sleep 1
done

# Final check
if ! ip link show "$IFACE" &>/dev/null; then
    echo "❌ ERROR: Interface $IFACE does not exist after ${MAX_WAIT}s"
    exit 1
fi

if ! ip link show "$IFACE" | grep -q "state UP"; then
    echo "⚠️ WARNING: Interface $IFACE exists but not UP"
    exit 1
fi

# Get external IP
EXTERNAL_IP=$(ip addr show "$IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "📍 External IP on $IFACE: ${EXTERNAL_IP:-N/A}"

# Generate danted.conf with writable log path
echo "📝 Generating /etc/danted.conf for port $PORT..."
cat > /etc/danted.conf <<DANTE
logoutput: /tmp/dante-logs/danted.log
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}
method: none
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect
    log: connect disconnect
}
DANTE

# Restart danted
echo "🔄 Restarting danted..."
systemctl restart danted 2>&1 || true
sleep 3

# Verify SOCKS port is listening
if netstat -tulnp 2>/dev/null | grep -q ":${PORT}"; then
    echo "✅ SUCCESS: Dante listening on port ${PORT}"
    echo "$(date) - Bind successful: ${PORT} -> ${IFACE} (${EXTERNAL_IP})"
    exit 0
else
    echo "❌ ERROR: Dante not listening on port ${PORT}"
    echo "Danted status:"
    systemctl status danted --no-pager || true
    exit 1
fi
SCRIPT

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh updated"

# ============================================================================
# STEP 4: Create service_manager.py with Unit ID and ipparam
# ============================================================================
echo ""
echo "📦 [Phase2] Step 4/8: Creating service_manager.py with Unit ID..."

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
MAX_CONCURRENT_NODES = 3  # Phase 1: Reduced to prevent FD exhaustion

class ServiceManager:
    def __init__(self):
        self.db_path = DB_PATH
        Path(PPP_LOG_DIR).mkdir(parents=True, exist_ok=True)
        # Phase 1: Increase FD limit for current process
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
        """Remove stale ppp interfaces and pid files."""
        rc, out, _ = self._run("ip -o link show | grep -oP 'ppp\\d+' || true")
        for iface in out.split('\n'):
            if iface.strip():
                self._run(f"ip link delete {iface} 2>/dev/null || true")
        
        # Phase 1: Clean old pid files
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
        """Phase 2: Wait for ppp interface via /sys/class/net."""
        iface = f"ppp{unit}"
        
        for attempt in range(timeout):
            # Check if interface exists in /sys
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
        if not user_col or not pass_col:
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
    
    def _write_peer_conf(self, node_id: int, unit: int, socks_port: int, ip: str, username: str) -> str:
        """Phase 2: Write PPP peer configuration with unit ID and ipparam."""
        Path(PEER_DIR).mkdir(parents=True, exist_ok=True)
        peer_file = f"{PEER_DIR}/{PEER_NAME}-{node_id}"
        
        # Phase 2: Add ipparam with SOCKS port for ip-up hook
        peer_config = f'''pty "pptp {ip} --nolaunchpppd"
unit {unit}
linkname ppp{unit}
ipparam socks:{socks_port}
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
    
    def _start_pptp_tunnel(self, node: Dict, unit: int, socks_port: int) -> Optional[str]:
        """Phase 2: Start PPTP tunnel with unit ID and ipparam."""
        node_id = node['id']
        ip = node['ip']
        username = node['username']
        password = node['password']
        
        # Write configs
        self._write_peer_conf(node_id, unit, socks_port, ip, username)
        self._write_chap(username, f"{PEER_NAME}-{node_id}", password)
        
        # Start pppd
        self._run(f"pppd call {PEER_NAME}-{node_id} &")
        
        # Phase 2: Wait for interface via /sys/class/net
        iface = self._wait_for_ppp_interface(unit, timeout=30)
        
        return iface
    
    def _update_node_interface(self, node_id: int, iface: str, socks_port: int) -> None:
        """Update node with ppp interface and SOCKS port in DB."""
        try:
            con = sqlite3.connect(self.db_path)
            cur = con.cursor()
            
            # Check if columns exist
            cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall()}
            if 'ppp_interface' not in cols:
                cur.execute("ALTER TABLE nodes ADD COLUMN ppp_interface TEXT")
            if 'socks_port' not in cols:
                cur.execute("ALTER TABLE nodes ADD COLUMN socks_port INTEGER")
            
            cur.execute(
                "UPDATE nodes SET ppp_interface=?, socks_port=? WHERE id=?",
                (iface, socks_port, node_id)
            )
            con.commit()
            con.close()
        except Exception as e:
            print(f"Warning: Could not update DB: {e}")
    
    def _get_diagnostics(self) -> Dict[str, Any]:
        """Collect system diagnostics."""
        ppp_check = self._run("ip a | grep ppp || true")[1]
        ports = self._run("netstat -tulnp 2>/dev/null | grep -E ':(108[0-9]|8001)' || true")[1]
        routes = self._run("ip route | head -10")[1]
        fd_limit = self._run("ulimit -n")[1]
        
        # Phase 2: Include hook log
        hook_log = ""
        if Path("/var/log/connexa-ppp-hooks.log").exists():
            try:
                hook_log = Path("/var/log/connexa-ppp-hooks.log").read_text()[-1000:]
            except:
                pass
        
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
            "hook_log": hook_log,
            "pppd_logs": pppd_logs,
            "link_log": link_log
        }
    
    def start(self) -> Dict[str, Any]:
        """Phase 2: Start PPTP tunnels with unique unit IDs and ip-up hooks."""
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
            unit = idx  # Unit ID = index (0, 1, 2)
            socks_port = SOCKS_PORT_BASE + idx  # 1080, 1081, 1082
            
            try:
                # Phase 2: Start with unit and ipparam
                iface = self._start_pptp_tunnel(node, unit, socks_port)
                if not iface:
                    results.append({
                        "node_id": node['id'],
                        "ip": node['ip'],
                        "unit": unit,
                        "socks_port": socks_port,
                        "error": "PPTP connection failed or timeout"
                    })
                    continue
                
                # Update DB
                self._update_node_interface(node['id'], iface, socks_port)
                
                # Phase 2: ip-up hook will handle SOCKS binding automatically
                # Wait a bit for hook to complete
                time.sleep(3)
                
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
                    "socks_port": socks_port,
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
PYEOF
echo "✅ service_manager.py created with Phase 2 features"

# ============================================================================
# STEP 5: Create FastAPI router (Phase 1 preserved)
# ============================================================================
echo ""
echo "📦 [Phase2] Step 5/8: Creating FastAPI router..."

mkdir -p "$ROUTER_DIR"
cat > "$ROUTER_DIR/service_router.py" <<'PYEOF'
from fastapi import APIRouter
import sys
sys.path.insert(0, '/app/backend')
from service_manager import ServiceManager

router = APIRouter(prefix="/service", tags=["Service Management"])
manager = ServiceManager()

@router.post("/start")
async def start_service():
    """Phase 2: Start PPTP tunnels with unique unit IDs and ip-up hooks."""
    return manager.start()

@router.post("/stop")
async def stop_service():
    """Stop all PPTP tunnels and SOCKS proxies."""
    return manager.stop()

@router.get("/status")
async def status_service():
    """Get current service status."""
    return manager.status()
PYEOF

touch "$ROUTER_DIR/__init__.py"
echo "✅ Router created"

# ============================================================================
# STEP 6: Patch server.py
# ============================================================================
echo ""
echo "📦 [Phase2] Step 6/8: Patching server.py..."

SERVER="$APP_DIR/server.py"
if [ -f "$SERVER" ]; then
    if ! grep -q "service_router" "$SERVER"; then
        sed -i '1i from router.service_router import router as service_router' "$SERVER"
        sed -i '/^app = FastAPI/a app.include_router(service_router)' "$SERVER"
        echo "✅ server.py patched"
    else
        echo "✅ server.py already has router"
    fi
fi

# ============================================================================
# STEP 7: Restart backend
# ============================================================================
echo ""
echo "📦 [Phase2] Step 7/8: Restarting backend..."

supervisorctl restart backend 2>/dev/null || systemctl restart connexa-backend.service || true
sleep 5

BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || systemctl is-active connexa-backend.service 2>/dev/null || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

# ============================================================================
# STEP 8: Post-install verification
# ============================================================================
echo ""
echo "📦 [Phase2] Step 8/8: Post-install verification..."

VERIFY_LOG="/root/phase2_verification_$(date +%Y%m%d_%H%M%S).log"

cat > "$VERIFY_LOG" <<VERIFY
════════════════════════════════════════════════════════════════
CONNEXA Phase 2 Verification Report
Generated: $(date)
════════════════════════════════════════════════════════════════

[PPP HOOKS]
ip-up hook: $(ls -l /etc/ppp/ip-up.d/connexa-dante 2>/dev/null || echo "NOT FOUND")
ip-down hook: $(ls -l /etc/ppp/ip-down.d/connexa-dante 2>/dev/null || echo "NOT FOUND")

[SERVICE_MANAGER.PY]
$(grep -c "unit {unit}" $APP_DIR/service_manager.py 2>/dev/null || echo 0) unit ID references found
$(grep -c "ipparam" $APP_DIR/service_manager.py 2>/dev/null || echo 0) ipparam references found

[BACKEND STATUS]
Backend: $BACKEND_STATUS

[LOGS]
Hook log: /var/log/connexa-ppp-hooks.log
SOCKS log: /var/log/link_socks_to_ppp.log
Dante log: /tmp/dante-logs/danted.log

════════════════════════════════════════════════════════════════
VERIFY

cat "$VERIFY_LOG"

echo ""
echo "✅ Verification log saved to: $VERIFY_LOG"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Phase 2 (v7.3.2-dev) INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔧 Applied Features:"
echo "  ✅ PPP ip-up hook for automatic Dante binding"
echo "  ✅ PPP ip-down hook for cleanup"
echo "  ✅ Unit ID in peer configs (unit 0, 1, 2)"
echo "  ✅ ipparam with SOCKS port (socks:1080, etc)"
echo "  ✅ Deterministic PPP interfaces (ppp0, ppp1, ppp2)"
echo "  ✅ DB columns: ppp_interface, socks_port"
echo ""
echo "📊 Current Status:"
echo "  - Backend: $BACKEND_STATUS"
echo "  - Hooks: $(ls /etc/ppp/ip-up.d/connexa-dante 2>/dev/null && echo 'installed' || echo 'missing')"
echo ""
echo "🔍 Test Commands:"
echo "  1. Start service: curl -X POST http://localhost:8001/service/start"
echo "  2. Wait 60 seconds for tunnels"
echo "  3. Check interfaces: ip a | grep ppp"
echo "  4. Check SOCKS: netstat -tulnp | grep 108"
echo "  5. View hook log: tail -f /var/log/connexa-ppp-hooks.log"
echo "  6. Test SOCKS: curl --socks5 127.0.0.1:1080 ifconfig.me"
echo ""
echo "📋 Phase 3 (Auto-recovery) will be applied next"
echo "════════════════════════════════════════════════════════════════"
