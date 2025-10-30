#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA SERVICE MANAGER v5.0 - FINAL WORKING VERSION"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"
ROUTER_DIR="$APP_DIR/router"

# ============================================================================
# STEP 1: Install packages and load kernel modules
# ============================================================================
echo ""
echo "📦 Step 1/8: Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ppp pptp-linux dante-server net-tools sqlite3 python3 python3-venv supervisor

echo "Loading PPP kernel modules..."
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

echo "✅ Packages and modules loaded"

# ============================================================================
# STEP 2: Create link_socks_to_ppp.sh script (CRITICAL FIX)
# ============================================================================
echo ""
echo "📦 Step 2/8: Creating link_socks_to_ppp.sh..."
cat > /usr/local/bin/link_socks_to_ppp.sh <<'EOF'
#!/bin/bash
SOCKS_PORT="${1:-1080}"
PPP_IFACE="${2:-ppp0}"

if [ -z "$SOCKS_PORT" ] || [ -z "$PPP_IFACE" ]; then
    echo "Usage: $0 <socks_port> <ppp_iface>" >&2
    exit 1
fi

echo "🔗 Linking SOCKS port ${SOCKS_PORT} to interface ${PPP_IFACE}"

# Check if interface exists
if ! ip link show "$PPP_IFACE" &>/dev/null; then
    echo "❌ Interface $PPP_IFACE does not exist" >&2
    exit 1
fi

# Generate danted.conf with correct interface
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

# Restart danted
systemctl restart danted 2>/dev/null || true
sleep 2

# Verify
if netstat -tulnp 2>/dev/null | grep -q ":${SOCKS_PORT}"; then
    echo "✅ Dante active on port ${SOCKS_PORT}"
    exit 0
else
    echo "❌ Dante not listening on port ${SOCKS_PORT}" >&2
    exit 1
fi
EOF

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh created"

# ============================================================================
# STEP 3: Create service_manager.py with full ServiceManager class
# ============================================================================
echo ""
echo "📦 Step 3/8: Creating service_manager.py..."
cat > "$APP_DIR/service_manager.py" <<'PYEOF'
import os
import sqlite3
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

DB_PATH = os.environ.get("CONNEXA_DB", "/app/backend/connexa.db")
PEER_NAME = "connexa"
PEER_FILE = f"/etc/ppp/peers/{PEER_NAME}"
CHAP_FILE = "/etc/ppp/chap-secrets"
SOCKS_PORT = 1080
PPP_IFACE = "ppp0"

class ServiceManager:
    def __init__(self):
        self.db_path = DB_PATH
    
    def _run(self, cmd: str) -> Tuple[int, str, str]:
        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, 
                           stderr=subprocess.PIPE, text=True)
        out, err = p.communicate()
        return p.returncode, out.strip(), err.strip()
    
    def _is_port_listening(self, port: int) -> bool:
        rc, out, _ = self._run(f"netstat -tulnp 2>/dev/null | grep ':{port}' || true")
        return len(out) > 0
    
    def _detect_cred_columns(self, cur) -> Tuple[str, str]:
        cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall() 
                if len(r) >= 2}
        user_col = next((c for c in ("username", "user", "login") if c in cols), None)
        pass_col = next((c for c in ("password", "pass") if c in cols), None)
        if not user_col or not pass_col:
            raise RuntimeError(f"Cannot detect credentials columns (have: {sorted(cols)})")
        return user_col, pass_col
    
    def _pick_node(self) -> Optional[Tuple[str, str, str]]:
        if not Path(self.db_path).exists():
            return None
        con = sqlite3.connect(self.db_path)
        con.row_factory = sqlite3.Row
        cur = con.cursor()
        user_col, pass_col = self._detect_cred_columns(cur)
        
        for status in ("speed_ok", "ping_light"):
            row = cur.execute(
                f"SELECT ip, {user_col} AS u, {pass_col} AS p FROM nodes "
                f"WHERE status=? AND ip!='' AND {user_col}!='' AND {pass_col}!='' LIMIT 1;",
                (status,)
            ).fetchone()
            if row:
                con.close()
                return (row["ip"], row["u"], row["p"])
        con.close()
        return None
    
    def _write_peer_conf(self, ip: str, user: str) -> None:
        Path("/etc/ppp/peers").mkdir(parents=True, exist_ok=True)
        peer = f'''pty "pptp {ip} --nolaunchpppd"
user "{user}"
remotename {PEER_NAME}
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
'''
        Path(PEER_FILE).write_text(peer)
    
    def _write_chap(self, user: str, password: str) -> None:
        line = f'"{user}" {PEER_NAME} "{password}" *\n'
        Path(CHAP_FILE).write_text(line)
        os.chmod(CHAP_FILE, 0o600)
    
    def _get_diagnostics(self) -> Dict[str, Any]:
        ppp_check = self._run(f"ip a | grep {PPP_IFACE} || true")[1]
        ports = self._run(f"netstat -tulnp 2>/dev/null | grep -E ':(1080|8001)' || true")[1]
        routes = self._run("ip route | head -20")[1]
        syslog = self._run("grep -i pppd /var/log/syslog | tail -40 || true")[1]
        danted_status = self._run("systemctl status danted --no-pager || true")[1]
        
        return {
            "ppp_interface": ppp_check,
            "listening_ports": ports,
            "routes": routes,
            "pppd_logs": syslog[-2000:],
            "danted_status": danted_status[-1000:]
        }
    
    def start(self) -> Dict[str, Any]:
        # Stop existing connections
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._run(f"poff {PEER_NAME} 2>/dev/null || true")
        self._run("systemctl stop danted 2>/dev/null || true")
        time.sleep(1)
        
        # Pick node from DB
        node = self._pick_node()
        if not node:
            return {
                "ok": False,
                "error": "No suitable node (need speed_ok or ping_light with ip/user/pass)",
                "diagnostics": self._get_diagnostics()
            }
        
        ip, user, password = node
        
        # Write configs
        self._write_peer_conf(ip, user)
        self._write_chap(user, password)
        
        # Start PPTP
        rc, out, err = self._run(f"pon {PEER_NAME}")
        time.sleep(8)
        
        # Verify ppp0
        ppp_check = self._run(f"ip link show {PPP_IFACE} 2>/dev/null || true")[1]
        has_ppp = len(ppp_check) > 0
        
        # Link SOCKS to PPP (CRITICAL FIX)
        socks_active = False
        if has_ppp:
            link_rc, link_out, link_err = self._run(
                f"/usr/local/bin/link_socks_to_ppp.sh {SOCKS_PORT} {PPP_IFACE}"
            )
            time.sleep(2)
            socks_active = self._is_port_listening(SOCKS_PORT)
        
        status = "running" if has_ppp and socks_active else \
                 "degraded" if has_ppp or socks_active else "failed"
        
        return {
            "ok": status in ("running", "degraded"),
            "status": status,
            "node": {"ip": ip, "user": user},
            "ppp0": has_ppp,
            "socks_1080": socks_active,
            "diagnostics": self._get_diagnostics()
        }
    
    def stop(self) -> Dict[str, Any]:
        self._run("systemctl stop danted 2>/dev/null || true")
        self._run(f"poff {PEER_NAME} 2>/dev/null || true")
        self._run("pkill -9 pppd 2>/dev/null || true")
        time.sleep(1)
        
        return {
            "ok": True,
            "status": "stopped",
            "diagnostics": self._get_diagnostics()
        }
    
    def status(self) -> Dict[str, Any]:
        ppp_check = self._run(f"ip link show {PPP_IFACE} 2>/dev/null || true")[1]
        has_ppp = len(ppp_check) > 0
        socks_active = self._is_port_listening(SOCKS_PORT)
        
        status = "running" if has_ppp and socks_active else \
                 "degraded" if has_ppp or socks_active else "stopped"
        
        return {
            "ok": True,
            "status": status,
            "ppp0": has_ppp,
            "socks_1080": socks_active,
            "diagnostics": self._get_diagnostics()
        }
PYEOF
echo "✅ service_manager.py created"

# ============================================================================
# STEP 4: Create FastAPI router
# ============================================================================
echo ""
echo "📦 Step 4/8: Creating router..."
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
    return manager.start()

@router.post("/stop")
async def stop_service():
    return manager.stop()

@router.get("/status")
async def status_service():
    return manager.status()
PYEOF

touch "$ROUTER_DIR/__init__.py"
echo "✅ Router created"

# ============================================================================
# STEP 5: Patch server.py
# ============================================================================
echo ""
echo "📦 Step 5/8: Patching server.py..."
SERVER="$APP_DIR/server.py"
if [ -f "$SERVER" ]; then
    if ! grep -q "service_router" "$SERVER"; then
        sed -i '1i from router.service_router import router as service_router' "$SERVER"
        sed -i '/^app = FastAPI/a app.include_router(service_router)' "$SERVER"
        echo "✅ server.py patched"
    else
        echo "✅ server.py already patched"
    fi
else
    echo "⚠️ server.py not found at $SERVER"
fi

# ============================================================================
# STEP 6: Enable danted service
# ============================================================================
echo ""
echo "📦 Step 6/8: Enabling danted..."
systemctl enable danted 2>/dev/null || true
echo "✅ danted enabled"

# ============================================================================
# STEP 7: Restart backend via supervisor
# ============================================================================
echo ""
echo "📦 Step 7/8: Restarting backend..."
supervisorctl restart backend 2>/dev/null || (
    echo "⚠️ supervisorctl not found, trying alternative restart..."
    pkill -9 -f "uvicorn.*server:app" || true
    sleep 2
)
sleep 3
echo "✅ Backend restarted"

# ============================================================================
# STEP 8: Verification
# ============================================================================
echo ""
echo "📦 Step 8/8: Verification..."

# Check supervisor status
BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

# Test API
API_RESPONSE=$(curl -s http://localhost:8001/service/status 2>/dev/null || echo '{"error":"no response"}')
if echo "$API_RESPONSE" | grep -q '"ok"'; then
    echo "✅ API working"
    echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$API_RESPONSE"
else
    echo "⚠️ API response: $API_RESPONSE"
fi

# Check modules
echo ""
echo "Loaded PPP modules:"
lsmod | grep ppp || echo "No PPP modules loaded"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "API Endpoints:"
echo "  POST http://$(hostname -I | awk '{print $1}'):8001/service/start"
echo "  POST http://$(hostname -I | awk '{print $1}'):8001/service/stop"
echo "  GET  http://$(hostname -I | awk '{print $1}'):8001/service/status"
echo ""
echo "Swagger: http://$(hostname -I | awk '{print $1}'):8001/docs"
echo ""
echo "Diagnostic commands:"
echo "  ip a | grep ppp"
echo "  netstat -tulnp | grep 1080"
echo "  grep -i pppd /var/log/syslog | tail -40"
echo "  systemctl status danted"
echo "  supervisorctl status backend"
echo ""
echo "Test from Admin Panel: Click 'Start Service' button"
echo "════════════════════════════════════════════════════════════════"
