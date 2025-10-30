#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA WORKING SERVICE INSTALLER v3.0"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Root required"
    exit 1
fi

APP_DIR="/app/backend"
ROUTER_DIR="$APP_DIR/router"
DB_PATH="$APP_DIR/connexa.db"

echo ""
echo "Step 1/6: Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y pptp-linux ppp dante-server net-tools sqlite3 2>/dev/null
echo "OK: Packages installed"

echo ""
echo "Step 2/6: Creating service_manager.py..."
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
DANTED_CONF = "/etc/danted.conf"
SOCKS_PORT = 1080

def _run(cmd: str) -> Tuple[int, str, str]:
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    return p.returncode, out.strip(), err.strip()

def _is_port_listening(port: int) -> bool:
    rc, out, _ = _run(f"ss -lntp | grep ':{port}' || true")
    return len(out) > 0

def _detect_cred_columns(cur) -> Tuple[str, str]:
    cols = {r[1] for r in cur.execute("PRAGMA table_info(nodes);").fetchall() if len(r) >= 2}
    user_col = next((c for c in ("username", "user", "login") if c in cols), None)
    pass_col = next((c for c in ("password", "pass") if c in cols), None)
    if not user_col or not pass_col:
        raise RuntimeError(f"Cannot detect credentials columns (have: {sorted(cols)})")
    return user_col, pass_col

def _pick_node() -> Optional[Tuple[str, str, str]]:
    if not Path(DB_PATH).exists():
        return None
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    user_col, pass_col = _detect_cred_columns(cur)
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

def _write_peer_conf(ip: str, user: str) -> None:
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

def _write_chap(user: str, password: str) -> None:
    line = f'"{user}" {PEER_NAME} "{password}" *\n'
    Path(CHAP_FILE).write_text(line)
    os.chmod(CHAP_FILE, 0o600)

def _start_pptp() -> Dict[str, Any]:
    _run("pkill -9 pppd 2>/dev/null || true")
    _run(f"poff {PEER_NAME} 2>/dev/null || true")
    time.sleep(1)
    rc, out, err = _run(f"pon {PEER_NAME}")
    time.sleep(6)
    rc2, out2, _ = _run("ip -o link show | awk -F': ' '$2 ~ /^ppp/ {print $2}'")
    ppps = [ln.strip() for ln in out2.splitlines() if ln.strip()]
    syslog = _run("tail -n 80 /var/log/syslog | grep -i pppd || true")[1]
    return {"rc": rc, "err": err, "ppp": ppps, "syslog": syslog}

def _write_dante_conf() -> None:
    conf = f"""logoutput: /var/log/danted.log
internal: 0.0.0.0 port = {SOCKS_PORT}
external: ppp0
method: none
user.notprivileged: nobody
client pass {{
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}}
pass {{
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
}}
"""
    Path(DANTED_CONF).write_text(conf)

def _start_socks() -> Dict[str, Any]:
    _write_dante_conf()
    _run("systemctl restart danted 2>/dev/null || true")
    time.sleep(2)
    listening = _is_port_listening(SOCKS_PORT)
    return {"listening": listening, "port": SOCKS_PORT}

def _stop_socks() -> None:
    _run("systemctl stop danted 2>/dev/null || true")

def _get_diagnostics() -> Dict[str, Any]:
    ss = _run("ss -lntp")[1]
    ip_a = _run("ip a")[1]
    routes = _run("ip route")[1]
    return {"ports": ss, "ip": ip_a, "routes": routes}

async def start_service() -> Dict[str, Any]:
    for mod in ("ppp_generic", "ppp_async", "ppp_mppe"):
        _run(f"modprobe {mod} 2>/dev/null || true")
    
    node = _pick_node()
    if not node:
        return {"ok": False, "error": "No suitable node in DB"}
    
    ip, user, password = node
    _write_peer_conf(ip, user)
    _write_chap(user, password)
    pptp_res = _start_pptp()
    socks_res = _start_socks()
    
    status = "running" if ("ppp0" in (pptp_res.get("ppp") or [])) and socks_res.get("listening") else "degraded"
    return {
        "ok": status in ("running", "degraded"),
        "status": status,
        "node": {"ip": ip, "user": user},
        "pptp": pptp_res,
        "socks": socks_res,
        "diagnostics": _get_diagnostics()
    }

async def stop_service() -> Dict[str, Any]:
    _stop_socks()
    _run(f"poff {PEER_NAME} 2>/dev/null || true")
    _run("pkill -9 pppd 2>/dev/null || true")
    time.sleep(1)
    return {"ok": True, "status": "stopped", "diagnostics": _get_diagnostics()}

async def service_status() -> Dict[str, Any]:
    ppp = "ppp0" in _run("ip -o link show | awk -F': ' '$2 ~ /^ppp/ {print $2}'")[1]
    socks = _is_port_listening(SOCKS_PORT)
    return {
        "ok": True,
        "status": "running" if ppp and socks else "degraded" if (ppp or socks) else "stopped",
        "ppp0": ppp,
        "socks_1080": socks,
        "diagnostics": _get_diagnostics()
    }
PYEOF
echo "OK: service_manager.py created"

echo ""
echo "Step 3*

