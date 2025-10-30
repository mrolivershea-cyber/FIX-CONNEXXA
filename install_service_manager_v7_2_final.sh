#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA SERVICE MANAGER v7.2 - FINAL PRODUCTION RELEASE"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Based on: Full diagnostic analysis"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"
ROUTER_DIR="$APP_DIR/router"

# ============================================================================
# STEP 1: Install packages
# ============================================================================
echo ""
echo "📦 Step 1/10: Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y pptp-linux ppp dante-server net-tools sqlite3 supervisor iproute2

echo "✅ Packages installed"

# ============================================================================
# STEP 2: Load PPP kernel modules and create /dev/ppp
# ============================================================================
echo ""
echo "📦 Step 2/10: Loading PPP kernel modules..."

modprobe ppp_generic || true
modprobe ppp_async || true
modprobe ppp_mppe || true
modprobe ppp_deflate || true

cat > /etc/modules-load.d/ppp.conf <<EOF
ppp_generic
ppp_async
ppp_mppe
ppp_deflate
EOF

# Create /dev/ppp if not exists
[ -c /dev/ppp ] || mknod /dev/ppp c 108 0
chmod 600 /dev/ppp

echo "✅ Modules loaded:"
lsmod | grep ppp

# ============================================================================
# STEP 3: Create directories
# ============================================================================
echo ""
echo "📦 Step 3/10: Creating directories..."
mkdir -p /etc/ppp/peers
mkdir -p /var/log/ppp
mkdir -p "$ROUTER_DIR"

echo "✅ Directories created"

# ============================================================================
# STEP 4: Create link_socks_to_ppp.sh (CRITICAL SCRIPT)
# ============================================================================
echo ""
echo "📦 Step 4/10: Creating link_socks_to_ppp.sh..."
cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "$(date) - Linking SOCKS port $PORT to interface $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Wait for interface to be UP (max 20 seconds)
echo "Waiting for $IFACE to be UP..."
for i in {1..20}; do
    if ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
        echo "✅ Interface $IFACE is UP (attempt $i)"
        break
    fi
    echo "⏳ Waiting... ($i/20)"
    sleep 1
done

# Final check
if ! ip link show "$IFACE" &>/dev/null; then
    echo "❌ ERROR: Interface $IFACE does not exist"
    exit 1
fi

if ! ip link show "$IFACE" | grep -q "state UP"; then
    echo "⚠️ WARNING: Interface $IFACE exists but not UP"
    echo "Attempting to bring up..."
    ip link set "$IFACE" up 2>/dev/null || true
    sleep 2
fi

# Get external IP
EXTERNAL_IP=$(ip addr show "$IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "📍 External IP on $IFACE: ${EXTERNAL_IP:-N/A}"

# Generate danted.conf
echo "📝 Generating /etc/danted.conf for port $PORT..."
cat > /etc/danted.conf <<DANTE
logoutput: /var/log/danted.log
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
systemctl restart danted 2>&1
sleep 2

# Verify SOCKS port is listening
if netstat -tulnp 2>/dev/null | grep -q ":${PORT}"; then
    echo "✅ SUCCESS: Dante listening on port ${PORT}"
    echo "$(date) - Bind successful: ${PORT} -> ${IFACE} (${EXTERNAL_IP})"
    exit 0
else
    echo "❌ ERROR: Dante not listening on port ${PORT}"
    echo "Danted status:"
    systemctl status danted --no-pager
    exit 1
fi
SCRIPT

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh created"

# ============================================================================
# STEP 5: Create service_manager.py (FULL PRODUCTION VERSION)
# ============================================================================
echo ""
echo "📦 Step 5/10: Creating service_manager.py..."
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
    
    def _write_peer_conf(self, node_id: int, ip: str, username: str) -> str:
        """Write PPP peer configuration for specific node."""
        Path(PEER_DIR).mkdir(parents=True, exist_ok=True)
        peer_file = f"{PEER_DIR}/{PEER_NAME}-{node_id}"
        
        peer_config = f'''pty "pptp {ip} --nolaunchpppd"
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
    
    def _start_pptp_tunnel(self, node: Dict) -> Optional[str]:
        """Start PPTP tunnel and wait for connection."""
        node_id = node['id']
        ip = node['ip']
        username = node['username']
        password = node['password']
        
        # Write configs
        self._write_peer_conf(node_id, ip, username)
        self._write_chap(username, f"{PEER_NAME}-{node_id}", password)
        
        # Start pppd
        log_file = f"{PPP_LOG_DIR}/pptp_node_{node_id}.log"
        self._run(f"pppd call {PEER_NAME}-{node_id} &")
        
        # Wait for connection
        iface = self._wait_for_ppp_connect(log_file, timeout=20)
        if not iface:
            return None
        
        # Verify interface is UP
        for _ in range(10):
            if self._is_ppp_interface_up(iface):
                return iface
            time.sleep(1)
        
        return None
    
    def _get_diagnostics(self) -> Dict[str, Any]:
        """Collect system diagnostics."""
        ppp_check = self._run("ip a | grep ppp || true")[1]
        ports = self._run("netstat -tulnp 2>/dev/null | grep -E ':(108[0-9]|8001)' || true")[1]
        routes = self._run("ip route | head -10")[1]
        
        pppd_logs = {}
        for log_file in Path(PPP_LOG_DIR).glob("pptp_node_*.log"):
            pppd_logs[log_file.name] = log_file.read_text()[-500:]
        
        link_log = ""
        if Path("/var/log/link_socks_to_ppp.log").exists():
            link_log = Path("/var/log/link_socks_to_ppp.log").read_text()[-1000:]
        
        return {
            "ppp_interfaces": ppp_check,
            "listening_ports": ports,
            "routes": routes,
            "pppd_logs": pppd_logs,
            "link_log": link_log
        }
    
    def start(self) -> Dict[str, Any]:
        """Start PPTP tunnels and SOCKS proxies (mass startup)."""
        # Cleanup old interfaces
        self._cleanup_old_interfaces()
        
        # Stop existing processes
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._run("systemctl stop danted 2>/dev/null || true")
        time.sleep(2)
        
        # Clear chap-secrets
        Path(CHAP_FILE).write_text("")
        
        # Get active nodes from DB
        nodes = self._get_active_nodes(limit=MAX_CONCURRENT_NODES)
        if not nodes:
            return {
                "ok": False,
                "error": "No suitable nodes (need speed_ok or ping_light)",
                "diagnostics": self._get_diagnostics()
            }
        
        results = []
        for idx, node in enumerate(nodes):
            try:
                # Start PPTP tunnel
                iface = self._start_pptp_tunnel(node)
                if not iface:
                    results.append({
                        "node_id": node['id'],
                        "ip": node['ip'],
                        "error": "PPTP connection failed or timeout"
                    })
                    continue
                
                # Verify interface is UP
                if not self._is_ppp_interface_up(iface):
                    results.append({
                        "node_id": node['id'],
                        "ip": node['ip'],
                        "interface": iface,
                        "error": "Interface not UP"
                    })
                    continue
                
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
                    "interface": iface,
                    "socks_port": socks_port,
                    "socks_active": socks_active,
                    "status": "ok" if socks_active else "degraded"
                })
                
            except Exception as e:
                results.append({
                    "node_id": node['id'],
                    "ip": node.get('ip', 'N/A'),
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
echo "✅ service_manager.py created"

# ============================================================================
# STEP 6: Create FastAPI router
# ============================================================================
echo ""
echo "📦 Step 6/10: Creating FastAPI router..."
cat > "$ROUTER_DIR/service_router.py" <<'PYEOF'
from fastapi import APIRouter
import sys
sys.path.insert(0, '/app/backend')
from service_manager import ServiceManager

router = APIRouter(prefix="/service", tags=["Service Management"])
manager = ServiceManager()

@router.post("/start")
async def start_service():
    """Start PPTP tunnels and SOCKS proxies for all speed_ok nodes."""
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
# STEP 7: Patch server.py to include router
# ============================================================================
echo ""
echo "📦 Step 7/10: Patching server.py..."
SERVER="$APP_DIR/server.py"
if [ -f "$SERVER" ]; then
    if ! grep -q "service_router" "$SERVER"; then
        sed -i '1i from router.service_router import router as service_router' "$SERVER"
        sed -i '/^app = FastAPI/a app.include_router(service_router)' "$SERVER"
        echo "✅ server.py patched"
    else
        echo "✅ server.py already has router"
    fi
else
    echo "⚠️ server.py not found at $SERVER"
fi

# ============================================================================
# STEP 8: Configure systemd service with resource limits
# ============================================================================
echo ""
echo "📦 Step 8/10: Configuring systemd..."
cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend (Uvicorn)
After=network-online.target

[Service]
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable connexa-backend.service 2>/dev/null || true
echo "✅ Systemd configured with LimitNOFILE=4096"

# ============================================================================
# STEP 9: Enable danted service
# ============================================================================
echo ""
echo "📦 Step 9/10: Enabling danted..."
systemctl enable danted 2>/dev/null || true
echo "✅ danted enabled"

# ============================================================================
# STEP 10: Restart backend and verify
# ============================================================================
echo ""
echo "📦 Step 10/10: Restarting backend..."
supervisorctl restart backend 2>/dev/null || systemctl restart connexa-backend.service || true
sleep 5

BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || systemctl is-active connexa-backend.service 2>/dev/null || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

if [ "$BACKEND_STATUS" = "RUNNING" ] || [ "$BACKEND_STATUS" = "active" ]; then
    API_RESPONSE=$(curl -s http://localhost:8001/service/status 2>/dev/null || echo '{"error":"timeout"}')
    if echo "$API_RESPONSE" | grep -q '"ok"'; then
        echo "✅ API working"
        echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$API_RESPONSE"
    else
        echo "⚠️ API response: $API_RESPONSE"
    fi
else
    echo "⚠️ Backend not running. Check logs:"
    echo "   tail -50 /var/log/supervisor/backend.err.log"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ v7.2 INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔍 Verification commands:"
echo "  lsmod | grep ppp                        # Check PPP modules"
echo "  ls -lh /usr/local/bin/link_socks_to_ppp.sh  # Check script"
echo "  cat /etc/ppp/chap-secrets               # Check credentials"
echo "  ip a | grep ppp                         # Show PPP interfaces"
echo "  netstat -tulnp | grep 108               # Show SOCKS ports"
echo "  tail -f /var/log/link_socks_to_ppp.log  # Watch SOCKS binding"
echo "  tail -f /var/log/ppp/pptp_node_*.log    # Watch PPTP logs"
echo ""
echo "🚀 API Endpoints:"
echo "  POST http://$(hostname -I | awk '{print $1}'):8001/service/start"
echo "  POST http://$(hostname -I | awk '{print $1}'):8001/service/stop"
echo "  GET  http://$(hostname -I | awk '{print $1}'):8001/service/status"
echo ""
echo "Swagger UI: http://$(hostname -I | awk '{print $1}'):8001/docs"
echo ""
echo "📋 Test from Admin Panel:"
echo "  1. Click 'Start Service'"
echo "  2. Wait 30-60 seconds for tunnels to establish"
echo "  3. Check: curl http://localhost:8001/service/status"
echo "  4. Verify SOCKS: curl --socks5 127.0.0.1:1080 ifconfig.me"
echo ""
echo "════════════════════════════════════════════════════════════════"
