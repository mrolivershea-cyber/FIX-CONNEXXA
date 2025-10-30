#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA SERVICE MANAGER INSTALLER v4.0"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"
ROUTER_DIR="$APP_DIR/router"

# ============================================================================
# STEP 1: Install packages and kernel modules
# ============================================================================
echo ""
echo "📦 Step 1/7: Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ppp pptp-linux dante-server net-tools python3 python3-venv build-essential supervisor sqlite3

echo "Loading kernel modules..."
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

echo "✅ Packages and modules installed"

# ============================================================================
# STEP 2: Create systemd service for backend
# ============================================================================
echo ""
echo "📦 Step 2/7: Creating systemd service..."
cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend (Uvicorn)
After=network-online.target

[Service]
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable connexa-backend.service
echo "✅ Systemd service created"

# ============================================================================
# STEP 3: Create link_socks_to_ppp.sh helper script
# ============================================================================
echo ""
echo "📦 Step 3/7: Creating link_socks_to_ppp.sh..."
cat > /usr/local/bin/link_socks_to_ppp.sh <<'EOF'
#!/bin/bash
IFACE=$(ip -o link show | grep -Eo "ppp[0-9]+" | head -n1)
if [ -z "$IFACE" ]; then
  echo "No PPP interface found" >&2
  exit 1
fi
echo "Linking SOCKS to interface: $IFACE"

# Update danted config
cat > /etc/danted.conf <<DANTED
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = 1080
external: $IFACE
method: none
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
}
DANTED

systemctl restart danted || true
echo "SOCKS proxy linked to $IFACE"
EOF

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh created"

# ============================================================================
# STEP 4: Create service_manager.py with ServiceManager class
# ============================================================================
echo ""
echo "📦 Step 4/7: Creating service_manager.py..."
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

class ServiceManager:
    def __init__(self):
        self.db_path = DB_PATH
    
    def _run(self, cmd: str) -> Tuple[int, str, str]:
        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, 
                           stderr=subprocess.PIPE, text=True)
        out, err = p.communicate()
        return p.returncode, out.strip(), err.strip()
    
    def _is_port_listening(self, port: int) -> bool:
        rc, out, _ = self._run(f"ss -lntp | grep ':{port}' || true")
        return len(out) > 0
    
    def _detect_cred_columns(self, cur) -> Tuple[str, str]:
        cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall() 
                if len(r) >= 2}
        user_col = next((c for c in ("username", "user", "login") if c in cols), None)
        pass_col = next((c for c in ("password", "pass") if c in cols), None)
        if not user_col or not pass_col:
            raise RuntimeError(f"Cannot detect credentials (have: {sorted(cols)})")
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
        ppp_check = self._run("ip -o link show | grep -Eo 'ppp[0-9]+' || true")[1]
        ports = self._run("ss -lntp | grep -E ':(1080|8001)' || true")[1]
        routes = self._run("ip route | head -20")[1]
        syslog = self._run("grep -i pppd /var/log/syslog | tail -40 || true")[1]
        
        return {
            "ppp_interfaces": ppp_check.split('\n') if ppp_check else [],
            "listening_ports": ports,
            "routes": routes,
            "pppd_logs": syslog[-2000:]
        }
    
    def start(self) -> Dict[str, Any]:
        # Stop existing connections
        self._run("pkill -9 pppd 2>/dev/null || true")
        self._run(f"poff {PEER_NAME} 2>/dev/null || true")
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
        time.sleep(6)
        
        # Verify ppp0
        ppp_check = self._run("ip -o link show | grep -Eo 'ppp[0-9]+' || true")[1]
        has_ppp = "ppp0" in ppp_check
        
        # Link SOCKS to PPP
        if has_ppp:
            self._run("/usr/local/bin/link_socks_to_ppp.sh 2>&1")
            time.sleep(2)
        
        socks_active = self._is_port_listening(1080)
        
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
        ppp_check = self._run("ip -o link show | grep -Eo 'ppp[0-9]+' || true")[1]
        has_ppp = "ppp0" in ppp_check
        socks_active = self._is_port_listening(1080)
        
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
# STEP 5: Create FastAPI router
# ============================================================================
echo ""
echo "📦 Step 5/7: Creating router..."
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
# STEP 6: Patch server.py
# ============================================================================
echo ""
echo "📦 Step 6/7: Patching server.py..."
SERVER="$APP_DIR/server.py"
if [ ! -f "$SERVER" ]; then
    echo "⚠️ server.py not found, creating basic one..."
    cat > "$SERVER" <<'PYEOF'
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"status": "ok"}
PYEOF
fi

if ! grep -q "service_router" "$SERVER"; then
    sed -i '1i from router.service_router import router as service_router' "$SERVER"
    sed -i '/^app = FastAPI/a app.include_router(service_router)' "$SERVER"
    echo "✅ server.py patched"
else
    echo "✅ server.py already patched"
fi

# ============================================================================
# STEP 7: Restart backend
# ============================================================================
echo ""
echo "📦 Step 7/7: Restarting backend..."
systemctl restart connexa-backend.service
sleep 3

BACKEND_STATUS=$(systemctl is-active connexa-backend.service 2>/dev/null || echo "inactive")
echo "Backend: $BACKEND_STATUS"

if [ "$BACKEND_STATUS" = "active" ]; then
    API_RESPONSE=$(curl -s http://localhost:8001/service/status 2>/dev/null || echo '{"error":"no response"}')
    if echo "$API_RESPONSE" | grep -q '"ok"'; then
        echo "✅ API working"
        echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$API_RESPONSE"
    else
        echo "⚠️ API: $API_RESPONSE"
    fi
else
    echo "⚠️ Backend not running. Check logs:"
    echo "   journalctl -u connexa-backend.service -n 50"
fi

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
echo "  lsmod | grep ppp"
echo "  grep -i pppd /var/log/syslog | tail -40"
echo "  netstat -tulnp | grep 1080"
echo "  systemctl status connexa-backend"
echo ""
echo "════════════════════════════════════════════════════════════════"
