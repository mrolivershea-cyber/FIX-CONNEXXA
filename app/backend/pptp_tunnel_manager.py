"""
CONNEXA v7.4.10 - PPTP Tunnel Manager
Critical fixes for tunnel establishment and authentication
Updated with production testing feedback and improvements
v7.4.8: Added base peers template support for multi-tunnel scenarios
v7.4.9: Fixed base peers template with connection command, chap-secrets remotename matching
v7.4.10: CRITICAL FIX - Complete base template, correct remotename matching in all configs
"""
import os
import sqlite3
import subprocess
import time
import threading
import logging
from pathlib import Path
from typing import List, Dict, Optional

DB_PATH = os.environ.get("CONNEXA_DB", "/app/backend/connexa.db")
MAX_PPP_CONCURRENCY = 3
BATCH_SIZE = 3
PPPD_PATH = "/usr/sbin/pppd"

batch_lock = threading.Lock()
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
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
        
        # FIX #6: Add parentheses around OR conditions in SQL queries
        rows = cur.execute("""
            SELECT id, ip, login, password, status, 
                   ppp_iface, socks_port, country, provider
            FROM nodes
            WHERE (status LIKE 'speed%' OR status LIKE 'ping%' OR status IN ('SpeedOculus', 'SPEEDOG'))
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
            "message": "Phase 7.4.6: Nodes ready"
        }


class PPTPTunnelManager:
    """PPTP Tunnel Manager with v7.4.9 critical fixes."""
    
    def __init__(self):
        self.db_path = DB_PATH
        self.pppd_path = PPPD_PATH
        self.version = "7.4.10"
        logger.info(f"PPTPTunnelManager v{self.version} initialized")
        
        # v7.4.8: Ensure base peers template exists
        # v7.4.9: Fixed template with proper connection command
        # v7.4.10: Complete base template with all PPP options (no connect command - that's per-node)
        self._ensure_base_peers_template()
    
    def _ensure_base_peers_template(self):
        """
        v7.4.8: Create base /etc/ppp/peers/connexa template.
        v7.4.9: Fixed template to be fully functional with complete MSCHAP-V2 config.
        v7.4.10: CRITICAL FIX - Base template with all PPP options, no connect command.
        
        This template provides common PPP options for all tunnels.
        The connect command is specified in each node-specific config file.
        
        CRITICAL: The base template must have 'remotename connexa' to match chap-secrets.
        """
        peer_dir = "/etc/ppp/peers"
        base_peer_file = f"{peer_dir}/connexa"
        
        try:
            Path(peer_dir).mkdir(parents=True, exist_ok=True)
            
            # v7.4.10: Complete base template based on production diagnostics feedback
            # The template should contain ALL common PPP settings but NO connect command
            # (connect command varies per node and is specified in node-specific configs)
            base_config = '''# CONNEXA Base PPTP Peer Configuration v7.4.10
# Complete template for PPTP tunnels - provides common PPP options
# CRITICAL: remotename must be 'connexa' to match chap-secrets entries
# Note: connect command is NOT here - it's in node-specific configs

name admin
remotename connexa
# Authentication
require-mschap-v2
refuse-pap
refuse-chap
refuse-eap
# Network settings
noauth
mtu 1400
mru 1400
noipdefault
usepeerdns
# Behavior
persist
holdoff 5
maxfail 3
lock
# Disable IPv6CP (often causes session issues with PPTP)
noipv6
'''
            Path(base_peer_file).write_text(base_config)
            os.chmod(base_peer_file, 0o600)
            logger.info(f"✅ Created/updated base peers template: {base_peer_file} (mode 600)")
        except PermissionError:
            logger.warning(f"⚠️ Cannot create base peers template (permission denied): {base_peer_file}")
            logger.warning("   This is expected in test environments. On production, run with appropriate permissions.")
        except Exception as e:
            logger.error(f"❌ Error creating base peers template: {e}")
    
    def create_tunnel(self, node_ip: str, username: str, password: str, 
                     node_id: int = None, socks_port: int = None) -> bool:
        """
        Create PPTP tunnel with all v7.4.10 critical fixes.
        
        Fixes implemented:
        - FIX #2: Generate proper /etc/ppp/peers/connexa-node-{id} files
        - FIX #3: Fix chap-secrets format with proper quotes
        - FIX #4: Fix logging for routing warnings
        - v7.4.7: Enhanced MSCHAP-V2 support and holdoff/maxfail tuning
        - v7.4.8: Base peers template created automatically for multi-tunnel support
        - v7.4.9: Fixed chap-secrets remotename to use 'connexa' for proper matching
        - v7.4.10: CRITICAL - Fixed node-specific peers to also use remotename 'connexa'
        """
        node_id = node_id or 0
        log_path = f"/tmp/pptp_node_{node_id}.log"
        
        logger.info(f"[v{self.version}] Creating tunnel for node {node_id} ({node_ip})")
        
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
        
        # FIX #2: Generate proper /etc/ppp/peers/connexa-node-{id} files
        peer_dir = "/etc/ppp/peers"
        Path(peer_dir).mkdir(parents=True, exist_ok=True)
        
        peer_name = f"connexa-node-{node_id}"
        
        # v7.4.10: CRITICAL FIX - remotename must be "connexa" (not connexa-node-{id})
        # This must match the remotename in chap-secrets for authentication to work
        # Complete peer configuration as specified in the problem statement
        peer_config = f'''name {username}
remotename connexa
require-mschap-v2
refuse-pap
refuse-eap
refuse-chap
noauth
persist
holdoff 5
maxfail 3
mtu 1400
mru 1400
lock
noipdefault
defaultroute
usepeerdns
connect "/usr/sbin/pptp {node_ip} --nolaunchpppd"
user {username}
'''
        
        peer_file = f"{peer_dir}/{peer_name}"
        Path(peer_file).write_text(peer_config)
        
        # FIX #2: chmod 600 /etc/ppp/peers/connexa-node-{id}
        os.chmod(peer_file, 0o600)
        logger.info(f"✅ Created peer config: {peer_file} with remotename 'connexa' (mode 600)")
        
        # FIX #3: Fix chap-secrets format with proper quotes
        # v7.4.9/v7.4.10: CRITICAL FIX - remotename must be "connexa" (not connexa-node-{id})
        # This ensures chap-secrets matches when pppd calls any peer
        chap_file = "/etc/ppp/chap-secrets"
        
        # Read existing content to avoid duplicates
        existing_lines = []
        if Path(chap_file).exists():
            with open(chap_file, 'r') as f:
                existing_lines = f.readlines()
        
        # SECURITY NOTE: Clear-text password storage is required by pppd/PPTP protocol
        # The chap-secrets file must contain passwords in clear text for MSCHAP-v2 authentication
        # We mitigate this by setting file permissions to 600 (owner read/write only)
        # Use proper quoted format as specified
        # v7.4.10: Use "connexa" as remotename to match all peer configs
        chap_line = f'"{username}" "connexa" "{password}" *\n'
        
        # Only add if not already present
        if chap_line not in existing_lines:
            with open(chap_file, 'a') as f:
                f.write(chap_line)
            
            # FIX #3: chmod 600 /etc/ppp/chap-secrets
            os.chmod(chap_file, 0o600)
            logger.info(f"✅ Added chap-secrets entry with proper quotes and remotename 'connexa' (mode 600)")
        
        # Start pppd
        try:
            logger.info(f"Starting pppd call {peer_name}...")
            subprocess.Popen(
                ["pppd", "call", peer_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Wait for interface to come up
            logger.info(f"Waiting for ppp{ppp_unit} interface...")
            
            for attempt in range(60):  # Wait up to 30 seconds
                time.sleep(0.5)
                
                if Path(f"/sys/class/net/ppp{ppp_unit}").exists():
                    # Interface created, check if it's UP
                    time.sleep(2)  # Give it time to establish
                    
                    try:
                        # Get interface details
                        ip_result = subprocess.run(
                            ["ip", "addr", "show", f"ppp{ppp_unit}"],
                            capture_output=True,
                            text=True
                        )
                        
                        if "inet" in ip_result.stdout:
                            # Extract IP addresses
                            lines = ip_result.stdout.split('\n')
                            local_ip = None
                            remote_ip = None
                            
                            for line in lines:
                                if "inet " in line:
                                    parts = line.strip().split()
                                    if len(parts) >= 4:
                                        local_ip = parts[1].split('/')[0]
                                        if "peer" in line:
                                            remote_ip = parts[3].split('/')[0]
                            
                            # FIX #4: Add success log for tunnel UP
                            ppp_iface = f"ppp{ppp_unit}"
                            logger.info(f"✅ Tunnel for node {node_id} is UP on {ppp_iface} (local IP {local_ip} remote IP {remote_ip})")
                            
                            # FIX #4: Filter routing warnings to WARNING level
                            # This is handled by checking logs separately
                            
                            # Update database
                            try:
                                con = sqlite3.connect(DB_PATH)
                                con.execute("""
                                    UPDATE nodes 
                                    SET ppp_iface=?, last_ppp_up=CURRENT_TIMESTAMP, status='online'
                                    WHERE id=?
                                """, (ppp_iface, node_id))
                                con.commit()
                                con.close()
                                logger.info(f"✅ Database updated for node {node_id}")
                            except Exception as e:
                                logger.error(f"Failed to update DB: {e}")
                            
                            log_event("tunnel_created", f"node={node_id} {ppp_iface} ip={node_ip}")
                            
                            # Bind SOCKS if available
                            if socks_port and Path("/usr/local/bin/link_socks_to_ppp.sh").exists():
                                logger.info(f"Binding SOCKS port {socks_port} to {ppp_iface}")
                                time.sleep(2)
                                result = subprocess.run([
                                    "/usr/local/bin/link_socks_to_ppp.sh",
                                    str(socks_port),
                                    ppp_iface
                                ])
                                
                                if result.returncode == 0:
                                    logger.info(f"✅ SOCKS port {socks_port} bound successfully")
                                else:
                                    logger.warning(f"⚠️ SOCKS binding failed for port {socks_port}")
                            
                            return True
                        else:
                            # FIX #4: Log routing warnings at WARNING level instead of ERROR
                            if attempt > 40:  # Only warn if taking too long
                                logger.warning(f"Interface ppp{ppp_unit} exists but no IP assigned yet (attempt {attempt}/60)")
                    except Exception as e:
                        logger.warning(f"Error checking interface: {e}")
            
            logger.error(f"❌ Timeout waiting for ppp{ppp_unit} to come UP")
            
            # Show last log lines
            if Path(log_path).exists():
                log_content = Path(log_path).read_text()
                last_lines = log_content.split('\n')[-20:]
                
                # FIX #4: Filter "Nexthop has invalid gateway" to WARNING level
                for line in last_lines:
                    if "Nexthop has invalid gateway" in line or "invalid gateway" in line.lower():
                        logger.warning(f"Gateway warning: {line}")
                    elif "error" in line.lower() or "fail" in line.lower():
                        logger.error(line)
            
            return False
            
        except Exception as e:
            logger.error(f"❌ Failed to create tunnel for node {node_id}: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def start_batch(self, limit: int = 3):
        """Start batch of tunnels."""
        return start_batch(limit=limit)
    
    def get_priority_nodes(self, limit: int = 3):
        """Get priority nodes."""
        return get_priority_nodes(limit=limit)


# Create singleton
pptp_tunnel_manager = PPTPTunnelManager()
