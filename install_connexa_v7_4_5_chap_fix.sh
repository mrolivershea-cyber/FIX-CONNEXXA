cat > /root/install_connexa_v7_4_5_chap_fix.sh <<'PATCH745'
#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.5 - CHAP-SECRETS FIX PATCH"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Fix: Proper chap-secrets format with quotes + noauth"
echo "════════════════════════════════════════════════════════════════"

# STEP 1: Backup old chap-secrets
echo ""
echo "📦 [Step 1/6] Backing up chap-secrets..."
cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets.bak.$(date +%s) 2>/dev/null || true
echo "✅ Backup created"

# STEP 2: Clear chap-secrets
echo ""
echo "📦 [Step 2/6] Clearing old chap-secrets..."
echo "# CONNEXA v7.4.5 - Auto-generated chap-secrets" > /etc/ppp/chap-secrets
chmod 600 /etc/ppp/chap-secrets
echo "✅ chap-secrets cleared and permissions set to 600"

# STEP 3: Update pptp_tunnel_manager.py with FIXED chap-secrets format
echo ""
echo "📦 [Step 3/6] Updating pptp_tunnel_manager.py with proper chap-secrets format..."

cat > /app/backend/pptp_tunnel_manager.py <<'PYEOF'
"""
CONNEXA v7.4.5 - PPTP Tunnel Manager (CHAP-SECRETS FIX)
Fixed: Proper quoted format in chap-secrets + noauth config
"""
import os
import sqlite3
import subprocess
import time
import threading
import logging
from pathlib import Path
from typing import List, Dict, Optional

DB_PATH = "/app/backend/connexa.db"
MAX_PPP_CONCURRENCY = 3
BATCH_SIZE = 3
PPPD_PATH = "/usr/sbin/pppd"

batch_lock = threading.Lock()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def log_event(event: str, details: str = ""):
    """Log to watchdog_events."""
    try:
        con = sqlite3.connect(DB_PATH)
        con.execute("INSERT INTO watchdog_events (event, details) VALUES (?, ?)", (event, details))
        con.commit()
        con.close()
    except Exception as e:
        logger.error(f"Failed to log event: {e}")

def get_priority_nodes(limit: int = BATCH_SIZE) -> List[Dict]:
    """Get nodes by priority."""
    if not Path(DB_PATH).exists():
        return []
    
    try:
        con = sqlite3.connect(DB_PATH)
        con.row_factory = sqlite3.Row
        cur = con.cursor()
        
        rows = cur.execute("""
            SELECT id, ip, login, password, status, 
                   ppp_iface, socks_port, country, provider
            FROM nodes
            WHERE status IN ('SpeedOculus', 'SPEEDOG', 'speed_ok', 'ping_ok')
              AND ip IS NOT NULL AND ip != ''
            ORDER BY
              CASE status
                WHEN 'SpeedOculus' THEN 1
                WHEN 'SPEEDOG' THEN 2
                WHEN 'speed_ok' THEN 3
                WHEN 'ping_ok' THEN 4
                ELSE 5
              END,
              RANDOM()
            LIMIT ?
        """, (limit,)).fetchall()
        
        con.close()
        
        nodes = []
        for row in rows:
            node = dict(row)
            node['username'] = node['login']
            nodes.append(node)
        
        return nodes
        
    except Exception as e:
        logger.error(f"Error getting nodes: {e}")
        return []

def start_batch(limit: int = BATCH_SIZE) -> Dict:
    """Start batch of tunnels."""
    with batch_lock:
        nodes = get_priority_nodes(limit=limit)
        
        if not nodes:
            return {"started": 0, "failed": 0, "error": "No eligible nodes"}
        
        log_event("batch_start", f"limit={limit} nodes={len(nodes)}")
        
        return {
            "started": 0,
            "failed": 0,
            "count": len(nodes),
            "details": nodes,
            "message": "Phase 4.5: Nodes ready"
        }

class PPTPTunnelManager:
    """PPTP Tunnel Manager with FIXED chap-secrets format."""
    
    def __init__(self):
        self.db_path = DB_PATH
        self.pppd_path = PPPD_PATH
        logger.info(f"PPTPTunnelManager v7.4.5 initialized")
    
    def create_tunnel(self, node_ip: str, username: str, password: str, node_id: int = None, socks_port: int = None) -> bool:
        """Create PPTP tunnel with PROPER chap-secrets format."""
        node_id = node_id or 0
        log_path = f"/tmp/pptp_node_{node_id}.log"
        
        logger.info(f"[v7.4.5] Creating tunnel for node {node_id} ({node_ip})")
        
        if not Path(self.pppd_path).exists():
            logger.error(f"❌ pppd not found at {self.pppd_path}")
            return False
        
        # Find free ppp unit
        ppp_unit = None
        for unit in range(20):
            if not Path(f"/sys/class/net/ppp{unit}").exists():
                ppp_unit = unit
                break
        
        if ppp_unit is None:
            logger.error(f"No free PPP unit available")
            return False
        
        # Create peer config with noauth (NO server auth required)
        peer_dir = "/etc/ppp/peers"
        Path(peer_dir).mkdir(parents=True, exist_ok=True)
        
        peer_name = f"connexa-node-{node_id}"
        
        # CRITICAL: noauth prevents "remote must authenticate" error
        peer_config = f'''pty "pptp {node_ip} --nolaunchpppd"
unit {ppp_unit}
linkname ppp{ppp_unit}
ipparam node_{node_id}_socks_{socks_port or 0}
name {username}
remotename {peer_name}
noauth
refuse-eap
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
persist
maxfail 3
holdoff 10
usepeerdns
nodeflate
nobsdcomp
noipdefault
mtu 1460
mru 1460
debug
logfile {log_path}
'''
        
        peer_file = f"{peer_dir}/{peer_name}"
        Path(peer_file).write_text(peer_config)
        
        # CRITICAL FIX: Proper quoted format for chap-secrets
        # Format: "username" "remotename" "password" *
        chap_line = f'"{username}" "{peer_name}" "{password}" *\n'
        
        logger.info(f"Adding to chap-secrets: {username} -> {peer_name}")
        
        # Check if line already exists
        chap_secrets_path = "/etc/ppp/chap-secrets"
        existing_content = ""
        if Path(chap_secrets_path).exists():
            existing_content = Path(chap_secrets_path).read_text()
        
        if chap_line not in existing_content:
            with open(chap_secrets_path, "a") as f:
                f.write(chap_line)
            
            # CRITICAL: Set proper permissions
            os.chmod(chap_secrets_path, 0o600)
            logger.info(f"✅ Added chap-secrets entry with quotes")
        else:
            logger.info(f"✅ chap-secrets entry already exists")
        
        # Start pppd
        try:
            with open(log_path, "w") as log_file:
                log_file.write(f"[{time.ctime()}] CONNEXA v7.4.5 - Starting tunnel\n")
                log_file.write(f"Node: {node_id} ({node_ip})\n")
                log_file.write(f"pppd: {self.pppd_path}\n")
                log_file.write(f"Peer: {peer_name}\n")
                log_file.write(f"Config: {peer_file}\n\n")
                
                proc = subprocess.Popen(
                    [self.pppd_path, "call", peer_name],
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin"}
                )
                
                log_file.write(f"pppd PID: {proc.pid}\n")
                log_file.write("="*60 + "\n\n")
            
            logger.info(f"pppd started with PID: {proc.pid}")
            
            # Wait for interface to come UP
            for attempt in range(30):
                time.sleep(0.5)
                
                if Path(f"/sys/class/net/ppp{ppp_unit}").exists():
                    # Interface exists, check if UP
                    result = subprocess.run(
                        ["ip", "link", "show", f"ppp{ppp_unit}"],
                        capture_output=True,
                        text=True
                    )
                    
                    if "state UP" in result.stdout:
                        logger.info(f"✅ ppp{ppp_unit} is UP for node {node_id}")
                        
                        # Wait for IP assignment
                        time.sleep(2)
                        
                        # Get IP address
                        ip_result = subprocess.run(
                            ["ip", "addr", "show", f"ppp{ppp_unit}"],
                            capture_output=True,
                            text=True
                        )
                        
                        logger.info(f"Interface details:\n{ip_result.stdout}")
                        
                        # Update database
                        try:
                            con = sqlite3.connect(DB_PATH)
                            con.execute("""
                                UPDATE nodes 
                                SET ppp_iface=?, last_ppp_up=CURRENT_TIMESTAMP, status='online'
                                WHERE id=?
                            """, (f"ppp{ppp_unit}", node_id))
                            con.commit()
                            con.close()
                            logger.info(f"✅ Database updated for node {node_id}")
                        except Exception as e:
                            logger.error(f"Failed to update DB: {e}")
                        
                        log_event("tunnel_created", f"node={node_id} ppp{ppp_unit} ip={node_ip}")
                        
                        # Bind SOCKS
                        if socks_port and Path("/usr/local/bin/link_socks_to_ppp.sh").exists():
                            logger.info(f"Binding SOCKS port {socks_port} to ppp{ppp_unit}")
                            time.sleep(2)
                            result = subprocess.run([
                                "/usr/local/bin/link_socks_to_ppp.sh",
                                str(socks_port),
                                f"ppp{ppp_unit}"
                            ])
                            
                            if result.returncode == 0:
                                logger.info(f"✅ SOCKS port {socks_port} bound successfully")
                            else:
                                logger.warning(f"⚠️ SOCKS binding failed for port {socks_port}")
                        
                        return True
            
            logger.error(f"❌ Timeout waiting for ppp{ppp_unit} to come UP")
            
            # Show last log lines
            if Path(log_path).exists():
                log_content = Path(log_path).read_text()
                last_lines = log_content.split('\n')[-20:]
                logger.error(f"Last log lines:\n" + "\n".join(last_lines))
            
            return False
            
        except Exception as e:
            logger.error(f"❌ Failed to create tunnel for node {node_id}: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def start_batch(self, limit: int = 3):
        return start_batch(limit=limit)
    
    def get_priority_nodes(self, limit: int = 3):
        return get_priority_nodes(limit=limit)

# Create singleton
pptp_tunnel_manager = PPTPTunnelManager()
PYEOF

echo "✅ pptp_tunnel_manager.py v7.4.5 created"

# STEP 4: Verify syntax
python3 -m py_compile /app/backend/pptp_tunnel_manager.py
echo "✅ Syntax check passed"

# STEP 5: Clean old configs
echo ""
echo "📦 [Step 4/6] Cleaning old peer configs..."
rm -f /etc/ppp/peers/connexa-node-* 2>/dev/null || true
pkill -9 pppd 2>/dev/null || true
sleep 2
echo "✅ Old configs removed"

# STEP 6: Restart backend
echo ""
echo "📦 [Step 5/6] Restarting backend..."
supervisorctl restart backend
sleep 7

# STEP 7: TEST!
echo ""
echo "📦 [Step 6/6] Testing tunnel creation..."
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  🚀 STARTING TUNNELS (v7.4.5 with chap-secrets fix)"
echo "════════════════════════════════════════════════════════════════"

START_RESULT=$(curl -s -X POST http://localhost:8001/service/start)
echo "Start result: $START_RESULT"

echo ""
echo "Waiting 20 seconds for tunnel establishment..."
sleep 20

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  📊 RESULTS"
echo "════════════════════════════════════════════════════════════════"

echo ""
echo "[1] PPP Interfaces:"
ip link show | grep ppp || echo "No PPP interfaces found"

echo ""
echo "[2] PPP IP Addresses:"
ip addr show | grep -A 3 "ppp" || echo "No PPP addresses"

echo ""
echo "[3] pppd Processes:"
ps aux | grep pppd | grep -v grep || echo "No pppd processes"

echo ""
echo "[4] Service Status:"
curl -s http://localhost:8001/service/status-v2

echo ""
echo ""
echo "[5] SOCKS Ports:"
ss -lntp | grep -E ":(108[0-9])" || echo "No SOCKS ports"

echo ""
echo "[6] chap-secrets content:"
echo "--- /etc/ppp/chap-secrets ---"
cat /etc/ppp/chap-secrets
echo "--- end ---"

echo ""
echo "[7] Tunnel Logs:"
for log in /tmp/pptp_node_[0-9]*.log; do
    if [ -f "$log" ]; then
        echo ""
        echo "=== $log ==="
        tail -40 "$log"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ CONNEXA v7.4.5 PATCH COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "If you see 'CHAP authentication succeeded' in logs above,"
echo "then tunnels are working! 🎉"
echo ""
echo "Expected output:"
echo "  - ppp0, ppp1, ppp2 interfaces UP"
echo "  - IP addresses assigned (10.0.0.x)"
echo "  - SOCKS ports 1083, 1084, 1086 listening"
echo ""
PATCH745

chmod +x /root/install_connexa_v7_4_5_chap_fix.sh

echo "✅ Patch v7.4.5 created!"
echo ""
echo "Execute with:"
echo "  bash /root/install_connexa_v7_4_5_chap_fix.sh"
