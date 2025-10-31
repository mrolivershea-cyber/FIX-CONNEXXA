#!/usr/bin/env python3
"""
CONNEXA PPTP Tunnel Manager - v7.9
Full automation with MS-CHAP-V2 authentication and retry logic
"""

import os
import sys
import time
import subprocess
import sqlite3
import logging
from pathlib import Path
from typing import Optional, Dict, List

# Configuration
DB_PATH = "/app/backend/connexa.db"
PEERS_DIR = "/etc/ppp/peers"
CHAP_SECRETS = "/etc/ppp/chap-secrets"
LOG_DIR = "/tmp"
MAX_RETRIES = 3
RETRY_DELAY = 5

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/var/log/connexa-tunnel-manager.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class PPTPTunnelManager:
    """Manages PPTP tunnel connections with automatic retry and validation"""
    
    def __init__(self):
        self.db_path = DB_PATH
        self.peers_dir = Path(PEERS_DIR)
        self.chap_secrets = Path(CHAP_SECRETS)
        self.active_tunnels: Dict[int, Dict] = {}
        
    def _validate_ip(self, ip: str) -> bool:
        """Validate IP address - reject invalid/private IPs"""
        try:
            import ipaddress
            addr = ipaddress.ip_address(ip)
            
            # Reject invalid IPs
            if ip.startswith(('0.', '127.', '169.254.', '224.', '225.', '226.', '227.', 
                             '228.', '229.', '230.', '231.', '232.', '233.', '234.',
                             '235.', '236.', '237.', '238.', '239.', '240.', '241.',
                             '242.', '243.', '244.', '245.', '246.', '247.', '248.',
                             '249.', '250.', '251.', '252.', '253.', '254.', '255.')):
                logger.warning(f"[SKIP] Invalid IP range: {ip}")
                return False
                
            # Reject private networks (optional - remove if needed)
            if addr.is_private or addr.is_loopback or addr.is_multicast:
                logger.warning(f"[SKIP] Private/loopback/multicast IP: {ip}")
                return False
                
            return addr.is_global
            
        except Exception as e:
            logger.error(f"IP validation failed for {ip}: {e}")
            return False
    
    def _get_nodes_from_db(self) -> List[Dict]:
        """Get active nodes from database"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            # Get nodes with speed_ok or ready status
            cursor.execute("""
                SELECT id, ip, user, password, status, ppp_iface, socks_port
                FROM nodes
                WHERE (status = 'speed_ok' OR status = 'ready' OR status LIKE 'speed%')
                AND ip IS NOT NULL
                ORDER BY id
            """)
            
            nodes = [dict(row) for row in cursor.fetchall()]
            conn.close()
            
            logger.info(f"Found {len(nodes)} nodes in database")
            return nodes
            
        except Exception as e:
            logger.error(f"Failed to get nodes from database: {e}")
            return []
    
    def _update_node_status(self, node_id: int, status: str):
        """Update node status in database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("UPDATE nodes SET status = ? WHERE id = ?", (status, node_id))
            conn.commit()
            conn.close()
            logger.info(f"Node {node_id} status updated to: {status}")
        except Exception as e:
            logger.error(f"Failed to update node {node_id} status: {e}")
    
    def _create_peer_config(self, node: Dict) -> str:
        """Generate PPP peer configuration with proper MS-CHAP-V2 settings"""
        node_id = node['id']
        ip = node['ip']
        username = node['user'] or 'admin'
        
        peer_config = f"""# CONNEXA Node {node_id} - {ip}
# Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}

name {username}
remotename connexa

# Authentication - MS-CHAP-V2 only
require-mschap-v2
require-mppe-128
refuse-pap
refuse-chap
refuse-mschap
refuse-eap

# Network settings
mtu 1400
mru 1400
nodefaultroute
usepeerdns

# Connection behavior
persist
holdoff 5
maxfail 0

# Compression
nopcomp
noaccomp
nobsdcomp
nodeflate

# Other options
lock
noauth
debug

# PPTP plugin
plugin pptp.so
pptp_server {ip}
"""
        return peer_config
    
    def _create_chap_secrets(self, nodes: List[Dict]):
        """Create chap-secrets file with all node credentials"""
        try:
            chap_lines = ["# CONNEXA CHAP Secrets - Auto-generated\n"]
            chap_lines.append("# Format: username remotename password ip\n\n")
            
            for node in nodes:
                username = node['user'] or 'admin'
                password = node['password'] or 'admin'
                ip = node['ip']
                
                # Add entry: "username" connexa "password" *
                chap_lines.append(f'"{username}" connexa "{password}" *\n')
            
            # Write file
            with open(self.chap_secrets, 'w') as f:
                f.writelines(chap_lines)
            
            # Set permissions
            os.chmod(self.chap_secrets, 0o600)
            
            logger.info(f"Created chap-secrets with {len(nodes)} entries")
            
        except Exception as e:
            logger.error(f"Failed to create chap-secrets: {e}")
            raise
    
    def _write_peer_file(self, node_id: int, config: str):
        """Write peer configuration file"""
        try:
            peer_file = self.peers_dir / f"connexa-node-{node_id}"
            with open(peer_file, 'w') as f:
                f.write(config)
            os.chmod(peer_file, 0o600)
            logger.info(f"Created peer file: {peer_file}")
        except Exception as e:
            logger.error(f"Failed to write peer file for node {node_id}: {e}")
            raise
    
    def _check_ppp_interface(self, expected_iface: str, timeout: int = 10) -> bool:
        """Check if PPP interface is up"""
        for _ in range(timeout):
            try:
                result = subprocess.run(
                    ['ip', 'addr', 'show', expected_iface],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                if result.returncode == 0 and 'UP' in result.stdout:
                    return True
            except Exception:
                pass
            time.sleep(1)
        return False
    
    def _check_auth_failure(self, node_id: int) -> bool:
        """Check if authentication failed by examining logs"""
        log_file = Path(LOG_DIR) / f"pptp_node_{node_id}.log"
        if not log_file.exists():
            return False
            
        try:
            with open(log_file, 'r') as f:
                content = f.read()
                if "peer refused to authenticate" in content:
                    return True
                if "No auth is possible" in content:
                    return True
        except Exception:
            pass
        return False
    
    def _start_pppd(self, node_id: int) -> bool:
        """Start pppd for a specific node"""
        try:
            peer_name = f"connexa-node-{node_id}"
            log_file = Path(LOG_DIR) / f"pptp_node_{node_id}.log"
            
            # Remove old log
            if log_file.exists():
                log_file.unlink()
            
            # Start pppd
            cmd = ['pppd', 'call', peer_name]
            
            # Redirect output to log file
            with open(log_file, 'w') as log:
                subprocess.Popen(
                    cmd,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True
                )
            
            logger.info(f"Started pppd for node {node_id}, logging to {log_file}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start pppd for node {node_id}: {e}")
            return False
    
    def _stop_pppd(self, node_id: int):
        """Stop pppd for a specific node"""
        try:
            # Kill pppd process for this node
            subprocess.run(['pkill', '-f', f'connexa-node-{node_id}'], timeout=5)
            time.sleep(2)
            logger.info(f"Stopped pppd for node {node_id}")
        except Exception as e:
            logger.warning(f"Error stopping pppd for node {node_id}: {e}")
    
    def setup_tunnel(self, node: Dict, attempt: int = 1) -> bool:
        """Setup PPTP tunnel for a node with retry logic"""
        node_id = node['id']
        ip = node['ip']
        
        logger.info(f"Setting up tunnel for node {node_id} ({ip}) - Attempt {attempt}/{MAX_RETRIES}")
        
        # Validate IP
        if not self._validate_ip(ip):
            logger.warning(f"[SKIP] Node {node_id}: invalid IP {ip}")
            self._update_node_status(node_id, 'ping_invalid_ip')
            return False
        
        # Create peer configuration
        try:
            config = self._create_peer_config(node)
            self._write_peer_file(node_id, config)
        except Exception as e:
            logger.error(f"Failed to create peer config for node {node_id}: {e}")
            return False
        
        # Start pppd
        if not self._start_pppd(node_id):
            return False
        
        # Wait for interface to come up
        time.sleep(10)
        
        # Determine expected interface name (ppp0, ppp1, etc.)
        expected_iface = node.get('ppp_iface', f'ppp{node_id}')
        
        # Check if interface is up
        if self._check_ppp_interface(expected_iface):
            logger.info(f"✅ Tunnel established: {expected_iface} for node {node_id}")
            self._update_node_status(node_id, 'tunnel_active')
            self.active_tunnels[node_id] = {
                'iface': expected_iface,
                'ip': ip,
                'status': 'active'
            }
            return True
        
        # Check for authentication failure
        if self._check_auth_failure(node_id):
            logger.warning(f"Authentication failed for node {node_id}")
            
            # Retry if attempts remaining
            if attempt < MAX_RETRIES:
                logger.info(f"Retrying node {node_id} in {RETRY_DELAY} seconds...")
                self._stop_pppd(node_id)
                time.sleep(RETRY_DELAY)
                return self.setup_tunnel(node, attempt + 1)
            else:
                logger.error(f"[FAIL] Node {node_id} failed authentication after {MAX_RETRIES} attempts")
                self._update_node_status(node_id, 'ping_auth_failed')
                self._stop_pppd(node_id)
                return False
        
        # Unknown failure
        logger.warning(f"[FAIL] Node {node_id} tunnel failed (unknown reason)")
        self._stop_pppd(node_id)
        return False
    
    def setup_all_tunnels(self):
        """Setup tunnels for all active nodes"""
        logger.info("=" * 70)
        logger.info("CONNEXA PPTP Tunnel Manager v7.9 - Starting")
        logger.info("=" * 70)
        
        # Get nodes from database
        nodes = self._get_nodes_from_db()
        
        if not nodes:
            logger.warning("No nodes found in database")
            return
        
        # Create chap-secrets for all nodes
        self._create_chap_secrets(nodes)
        
        # Setup each tunnel
        success_count = 0
        for node in nodes:
            if self.setup_tunnel(node):
                success_count += 1
        
        logger.info("=" * 70)
        logger.info(f"Tunnel setup complete: {success_count}/{len(nodes)} successful")
        logger.info(f"Active tunnels: {list(self.active_tunnels.keys())}")
        logger.info("=" * 70)
    
    def get_status(self) -> Dict:
        """Get current status of all tunnels"""
        return {
            'active_tunnels': len(self.active_tunnels),
            'tunnels': self.active_tunnels
        }


def main():
    """Main entry point"""
    try:
        manager = PPTPTunnelManager()
        manager.setup_all_tunnels()
        
        # Print status
        status = manager.get_status()
        logger.info(f"Final status: {status}")
        
        return 0 if status['active_tunnels'] > 0 else 1
        
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
