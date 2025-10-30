#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.3 - Phase 4.3: Auto-Recovery & Multi-SpeedOculus"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  User: mrolivershea-cyber"
echo "  Tag: PHASE_4_3_PRODUCTION"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"
MAX_PPP_CONCURRENCY=3
BATCH_SIZE=3

# ============================================================================
# STEP 1: Create database migration for Phase 4.3
# ============================================================================
echo ""
echo "📦 [Step 1/12] Creating database migration..."

cat > "$APP_DIR/migrations/phase_4_3.sql" <<'SQL'
-- Phase 4.3: Enhanced watchdog_events and node tracking

CREATE TABLE IF NOT EXISTS watchdog_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts DATETIME DEFAULT CURRENT_TIMESTAMP,
    event TEXT NOT NULL,
    details TEXT
);

CREATE INDEX IF NOT EXISTS idx_watchdog_events_ts ON watchdog_events(ts DESC);
CREATE INDEX IF NOT EXISTS idx_watchdog_events_event ON watchdog_events(event);

-- Add ppp_iface tracking to nodes
ALTER TABLE nodes ADD COLUMN ppp_iface TEXT;
ALTER TABLE nodes ADD COLUMN socks_port INTEGER;
ALTER TABLE nodes ADD COLUMN last_ppp_up DATETIME;
ALTER TABLE nodes ADD COLUMN ppp_flaps INTEGER DEFAULT 0;
SQL

# Apply migration
if [ -f "$APP_DIR/connexa.db" ]; then
    sqlite3 "$APP_DIR/connexa.db" < "$APP_DIR/migrations/phase_4_3.sql" 2>&1 | grep -v "duplicate column" || true
    echo "✅ Database migration applied"
fi

# ============================================================================
# STEP 2: Create recovery.py module
# ============================================================================
echo ""
echo "📦 [Step 2/12] Creating recovery.py..."

cat > "$APP_DIR/recovery.py" <<'PYEOF'
"""
CONNEXA Phase 4.3 - Auto-Recovery Module
Handles PPP recovery, SOCKS rebinding, and event logging
"""
import subprocess
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

DB_PATH = "/app/backend/connexa.db"

def log_event(event: str, details: str = ""):
    """Log event to watchdog_events table."""
    try:
        con = sqlite3.connect(DB_PATH)
        con.execute(
            "INSERT INTO watchdog_events (event, details) VALUES (?, ?)",
            (event, details)
        )
        con.commit()
        con.close()
    except Exception as e:
        print(f"[RECOVERY] Failed to log event: {e}")

def _run(cmd: str) -> Tuple[int, str, str]:
    """Execute shell command."""
    try:
        p = subprocess.Popen(
            cmd, shell=True, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            text=True
        )
        out, err = p.communicate()
        return p.returncode, out.strip(), err.strip()
    except Exception as e:
        return 1, "", str(e)

def get_ppp_up_count() -> int:
    """Get number of PPP interfaces UP."""
    rc, out, _ = _run("ip -o link show | grep -c 'ppp.*state UP' || echo 0")
    try:
        return int(out)
    except:
        return 0

def get_socks_listening_count() -> int:
    """Get number of SOCKS ports listening."""
    rc, out, _ = _run("ss -lntp | grep -E ':(108[0-9])' | wc -l")
    try:
        return int(out)
    except:
        return 0

def list_active_ppp() -> List[str]:
    """List active PPP interfaces."""
    rc, out, _ = _run("ip -o link show | grep 'ppp' | awk '{print $2}' | tr -d ':'")
    if rc == 0 and out:
        return [iface.strip() for iface in out.split('\n') if iface.strip()]
    return []

def recover_if_needed(threshold: int = 1) -> Dict:
    """
    Recover PPP/SOCKS if count below threshold.
    
    Returns:
        {"acted": bool, "ppp_before": int, "ppp_after": int, "details": str}
    """
    ppp_before = get_ppp_up_count()
    
    if ppp_before >= threshold:
        return {
            "acted": False,
            "ppp_before": ppp_before,
            "ppp_after": ppp_before,
            "details": "No recovery needed"
        }
    
    log_event("recovery_triggered", f"PPP count below threshold: {ppp_before} < {threshold}")
    
    # Stop stuck pppd processes
    rc, out, _ = _run("pkill -9 -f 'pppd.*pptp' || true")
    log_event("pppd_cleanup", f"Killed stuck pppd processes")
    
    # Restart danted
    rc, out, _ = _run("systemctl restart danted 2>&1")
    if rc == 0:
        log_event("danted_restart", "Successfully restarted danted")
    else:
        log_event("danted_restart_fail", out)
    
    # Trigger tunnel restart via API
    rc, out, _ = _run("curl -s -X POST http://localhost:8001/tunnels/start-batch?limit=3")
    
    # Wait for recovery
    import time
    time.sleep(10)
    
    ppp_after = get_ppp_up_count()
    
    log_event("recovery_complete", f"PPP count: {ppp_before} -> {ppp_after}")
    
    return {
        "acted": True,
        "ppp_before": ppp_before,
        "ppp_after": ppp_after,
        "details": f"Recovery executed: {ppp_before} -> {ppp_after}"
    }
PYEOF

echo "✅ recovery.py created"

# ============================================================================
# STEP 3: Create enhanced pptp_tunnel_manager.py
# ============================================================================
echo ""
echo "📦 [Step 3/12] Creating enhanced pptp_tunnel_manager.py..."

cat > "$APP_DIR/pptp_tunnel_manager.py" <<'PYEOF'
"""
CONNEXA Phase 4.3 - Enhanced PPTP Tunnel Manager
Supports multi-node startup with SpeedOculus priority
"""
import os
import sqlite3
import subprocess
import time
import threading
from pathlib import Path
from typing import List, Dict, Optional

DB_PATH = "/app/backend/connexa.db"
MAX_PPP_CONCURRENCY = 3
BATCH_SIZE = 3
BATCH_SLEEP_MIN = 0.1
BATCH_SLEEP_MAX = 0.3

# Global lock for batch operations
batch_lock = threading.Lock()

def log_event(event: str, details: str = ""):
    """Log to watchdog_events."""
    try:
        con = sqlite3.connect(DB_PATH)
        con.execute("INSERT INTO watchdog_events (event, details) VALUES (?, ?)", (event, details))
        con.commit()
        con.close()
    except:
        pass

def get_priority_nodes(limit: int = BATCH_SIZE) -> List[Dict]:
    """
    Get nodes prioritized by status:
    1. SpeedOculus
    2. SPEEDOG
    3. speed_ok
    """
    if not Path(DB_PATH).exists():
        return []
    
    try:
        con = sqlite3.connect(DB_PATH)
        con.row_factory = sqlite3.Row
        cur = con.cursor()
        
        rows = cur.execute("""
            SELECT id, ip, username, password, status
            FROM nodes
            WHERE status IN ('SpeedOculus', 'SPEEDOG', 'speed_ok')
              AND ip IS NOT NULL
              AND ip != ''
            ORDER BY
              CASE status
                WHEN 'SpeedOculus' THEN 1
                WHEN 'SPEEDOG' THEN 2
                WHEN 'speed_ok' THEN 3
                ELSE 4
              END,
              RANDOM()
            LIMIT ?
        """, (limit,)).fetchall()
        
        con.close()
        return [dict(row) for row in rows]
    except Exception as e:
        print(f"[PPTP] Error getting priority nodes: {e}")
        return []

def is_ppp_running(node_id: int) -> bool:
    """Check if pppd already running for node."""
    result = subprocess.run(
        ["pgrep", "-f", f"pppd.*connexa-{node_id}"],
        capture_output=True
    )
    return result.returncode == 0

def get_free_ppp_unit() -> Optional[int]:
    """Find free pppX unit number."""
    for unit in range(10):
        if not Path(f"/sys/class/net/ppp{unit}").exists():
            return unit
    return None

def create_tunnel(node: Dict, unit: int, socks_port: int) -> bool:
    """
    Create PPTP tunnel for node.
    
    Returns:
        True if successful, False otherwise
    """
    node_id = node['id']
    ip = node['ip']
    username = node.get('username', 'user')
    password = node.get('password', 'pass')
    
    log_event("tunnel_start_attempt", f"node={node_id} ip={ip} unit={unit}")
    
    # Create peer config
    peer_dir = "/etc/ppp/peers"
    Path(peer_dir).mkdir(parents=True, exist_ok=True)
    
    peer_config = f'''pty "pptp {ip} --nolaunchpppd"
unit {unit}
linkname ppp{unit}
ipparam node_{node_id}_socks_{socks_port}
user {username}
remotename connexa-{node_id}
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
logfile /var/log/ppp/pptp_node_{node_id}.log
'''
    
    peer_file = f"{peer_dir}/connexa-{node_id}"
    Path(peer_file).write_text(peer_config)
    
    # Add to chap-secrets
    chap_line = f"{username} connexa-{node_id} {password} *\n"
    with open("/etc/ppp/chap-secrets", "a") as f:
        f.write(chap_line)
    
    # Start pppd
    subprocess.Popen(["pppd", "call", f"connexa-{node_id}"])
    
    # Wait for interface
    for _ in range(20):
        if Path(f"/sys/class/net/ppp{unit}").exists():
            # Interface created, bind SOCKS
            time.sleep(2)
            
            result = subprocess.run([
                "/usr/local/bin/link_socks_to_ppp.sh",
                str(socks_port),
                f"ppp{unit}"
            ])
            
            if result.returncode == 0:
                log_event("tunnel_start_success", f"node={node_id} ppp{unit} port={socks_port}")
                
                # Update database
                try:
                    con = sqlite3.connect(DB_PATH)
                    con.execute("""
                        UPDATE nodes 
                        SET ppp_iface=?, socks_port=?, last_ppp_up=CURRENT_TIMESTAMP
                        WHERE id=?
                    """, (f"ppp{unit}", socks_port, node_id))
                    con.commit()
                    con.close()
                except:
                    pass
                
                return True
            else:
                log_event("link_bind_fail", f"node={node_id} ppp{unit} port={socks_port}")
                return False
        
        time.sleep(0.5)
    
    log_event("tunnel_start_timeout", f"node={node_id} unit={unit}")
    return False

def start_batch(limit: int = BATCH_SIZE) -> Dict:
    """
    Start batch of tunnels with concurrency control.
    
    Returns:
        {"started": int, "failed": int, "details": List[Dict]}
    """
    with batch_lock:
        log_event("batch_start", f"limit={limit}")
        
        nodes = get_priority_nodes(limit=limit)
        
        if not nodes:
            return {"started": 0, "failed": 0, "details": [], "error": "No eligible nodes"}
        
        results = []
        started = 0
        failed = 0
        
        for idx, node in enumerate(nodes):
            if is_ppp_running(node['id']):
                results.append({"node_id": node['id'], "skipped": "already_running"})
                continue
            
            unit = get_free_ppp_unit()
            if unit is None:
                results.append({"node_id": node['id'], "error": "no_free_unit"})
                failed += 1
                continue
            
            socks_port = 1080 + idx
            
            success = create_tunnel(node, unit, socks_port)
            
            if success:
                started += 1
                results.append({
                    "node_id": node['id'],
                    "ip": node['ip'],
                    "status": node['status'],
                    "unit": unit,
                    "socks_port": socks_port,
                    "result": "success"
                })
            else:
                failed += 1
                results.append({
                    "node_id": node['id'],
                    "error": "tunnel_failed"
                })
            
            # Jitter between starts
            import random
            time.sleep(random.uniform(BATCH_SLEEP_MIN, BATCH_SLEEP_MAX))
        
        log_event("batch_complete", f"started={started} failed={failed}")
        
        return {
            "started": started,
            "failed": failed,
            "details": results
        }
PYEOF

echo "✅ pptp_tunnel_manager.py created"

# ============================================================================
# STEP 4: Create link_socks_to_ppp.sh script
# ============================================================================
echo ""
echo "📦 [Step 4/12] Creating link_socks_to_ppp.sh..."

cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
# Phase 4.3: SOCKS to PPP binding script

PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1

echo "════════════════════════════════════════════════════════════════"
echo "[$(date)] Binding SOCKS port $PORT to $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Wait for interface (20 attempts, 0.5s each = 10s total)
for i in {1..20}; do
    if ip link show "$IFACE" &>/dev/null; then
        if ip link show "$IFACE" | grep -q "state UP"; then
            echo "[$(date)] ✅ Interface $IFACE is UP (attempt $i)"
            break
        fi
    fi
    sleep 0.5
done

# Final check
if ! ip link show "$IFACE" &>/dev/null; then
    echo "[$(date)] ❌ ERROR: Interface $IFACE does not exist"
    
    # Log to database
    sqlite3 /app/backend/connexa.db <<SQL
INSERT INTO watchdog_events (event, details) 
VALUES ('link_bind_fail', 'Interface $IFACE not found for port $PORT');
SQL
    
    exit 1
fi

if ! ip link show "$IFACE" | grep -q "state UP"; then
    echo "[$(date)] ⚠️ WARNING: Interface $IFACE not UP"
    exit 1
fi

# Get IP
EXTERNAL_IP=$(ip addr show "$IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "[$(date)] 📍 External IP: ${EXTERNAL_IP:-N/A}"

# Configure danted
# Note: Using syslog to avoid read-only FS issues
cat > /etc/danted.conf <<DANTE
logoutput: syslog
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}
clientmethod: none
socksmethod: none
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect bind
    log: error
}
DANTE

# Restart danted
systemctl restart danted 2>&1
sleep 2

# Verify
if ss -lntp | grep -q ":${PORT}"; then
    echo "[$(date)] ✅ SUCCESS: SOCKS listening on ${PORT} -> ${IFACE} (${EXTERNAL_IP})"
    
    # Log success
    sqlite3 /app/backend/connexa.db <<SQL
INSERT INTO watchdog_events (event, details) 
VALUES ('link_bind_success', 'port=$PORT iface=$IFACE ip=$EXTERNAL_IP');
SQL
    
    exit 0
else
    echo "[$(date)] ❌ ERROR: SOCKS not listening on port ${PORT}"
    
    # Log failure
    sqlite3 /app/backend/connexa.db <<SQL
INSERT INTO watchdog_events (event, details) 
VALUES ('link_bind_fail', 'port=$PORT iface=$IFACE - danted not listening');
SQL
    
    exit 1
fi
SCRIPT

chmod 755 /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh created"

# Continuará en la siguiente parte...
