#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA SERVICE MANAGER v7.3 - PRODUCTION (Fixed FD + Unit ID)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Fixes: Too many files, Unit ID, Dante timing, Read-only FS"
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
echo "📦 Step 1/11: Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y pptp-linux ppp dante-server net-tools sqlite3 supervisor iproute2

echo "✅ Packages installed"

# ============================================================================
# STEP 2: Increase file descriptor limits (CRITICAL FIX)
# ============================================================================
echo ""
echo "📦 Step 2/11: Increasing file descriptor limits..."

# System-wide limits
cat > /etc/security/limits.d/99-connexa.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# Current session
ulimit -n 65535 2>/dev/null || true

echo "✅ File descriptor limit increased to 65535"
ulimit -n

# ============================================================================
# STEP 3: Load PPP kernel modules and create /dev/ppp
# ============================================================================
echo ""
echo "📦 Step 3/11: Loading PPP kernel modules..."

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
# STEP 4: Create writable log directories (Fix Read-only FS)
# ============================================================================
echo ""
echo "📦 Step 4/11: Creating writable log directories..."
mkdir -p /etc/ppp/peers
mkdir -p /var/log/ppp
mkdir -p /tmp/dante-logs
mkdir -p "$ROUTER_DIR"

# Make sure danted can write logs
touch /tmp/dante-logs/danted.log
chmod 666 /tmp/dante-logs/danted.log
ln -sf /tmp/dante-logs/danted.log /var/log/danted.log 2>/dev/null || true

echo "✅ Directories created"

# ============================================================================
# STEP 5: Create link_socks_to_ppp.sh with 30sec wait
# ============================================================================
echo ""
echo "📦 Step 5/11: Creating link_socks_to_ppp.sh..."
cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "$(date) - Linking SOCKS port $PORT to interface $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Wait for interface to exist and be UP (max 30 seconds)
echo "Waiting for $IFACE to exist and be UP..."
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
    echo "Attempting to bring up..."
    ip link set "$IFACE" up 2>/dev/null || true
    sleep 2
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
echo "✅ link_socks_to_ppp.sh created with 30s wait"

# ============================================================================
# STEP 6: Create service_manager.py with UNIT ID support
# ============================================================================
echo ""
echo "📦 Step 6/11: Creating service_manager.py with Unit ID..."
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
        self._run(f"pppd call {PEER_NAME}-{node_id} &")
        
        # Wait for interface to be created and UP
        iface = self._wait_for_ppp_interface(unit, timeout=30)
        
        return iface
    
    def _update_node_interface(self, node_id: int, iface: str) -> None:
        """Update node with ppp interface name in DB."""
        try:
            con = sqlite3.connect(self.db_path)
            cur = con.cursor()
            
            # Check if ppp_interface column exists
            cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall()}
            if 'ppp_interface' not in cols:
                cur.execute("ALTER TABLE nodes ADD COLUMN ppp_interface TEXT")
            
            cur.execute("UPDATE nodes SET ppp_interface=? WHERE id=?", (iface, node_id))
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
PYEOF
echo "✅ service_manager.py created with Unit ID support"

# Continue with remaining steps...
echo ""
echo "📦 Step 7/11: Creating FastAPI router..."
cat > "$ROUTER_DIR/service_router.py" <<'PYEOF'
from fastapi import APIRouter
import sys
sys.path.insert(0, '/app/backend')
from service_manager import ServiceManager

router = APIRouter(prefix="/service", tags=["Service Management"])
manager = ServiceManager()

@router.post("/start")
async def start_service():
    """Start PPTP tunnels with unique unit IDs."""
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

echo ""
echo "📦 Step 8/11: Patching server.py..."
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

echo ""
echo "📦 Step 9/11: Configuring systemd with FD limit..."
cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend (Uvicorn)
After=network-online.target

[Service]
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable connexa-backend.service 2>/dev/null || true
echo "✅ Systemd configured with LimitNOFILE=65535"

echo ""
echo "📦 Step 10/11: Enabling danted..."
systemctl enable danted 2>/dev/null || true
echo "✅ danted enabled"

echo ""
echo "📦 Step 11/11: Restarting backend..."
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
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ v7.3 INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔧 Critical Fixes Applied:"
echo "  ✅ File descriptor limit: 65535"
echo "  ✅ Unique PPP unit IDs (ppp0, ppp1, ppp2)"
echo "  ✅ 30-second wait for interface creation"
echo "  ✅ Writable dante logs (/tmp/dante-logs/)"
echo "  ✅ Max 3 concurrent tunnels (prevents FD exhaustion)"
echo "  ✅ Cleanup of stale pid files"
echo ""
echo "🔍 Verification:"
echo "  ulimit -n                                # Should show 65535"
echo "  ip a | grep ppp                          # Should show ppp0, ppp1, ppp2"
echo "  netstat -tulnp | grep 108                # SOCKS on 1080, 1081, 1082"
echo "  tail -f /var/log/link_socks_to_ppp.log   # Watch binding"
echo "  tail -f /tmp/dante-logs/danted.log       # Watch Dante"
echo ""
echo "🚀 Test: Click 'Start Service' in Admin Panel"
echo "════════════════════════════════════════════════════════════════"
