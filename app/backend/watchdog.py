"""
CONNEXA v7.5.3 - Watchdog Monitor
Monitors PPP interfaces and auto-restarts backend on failures

FIX #5: Watchdog auto-restart on zero PPP interfaces
v7.4.7: Enhanced monitoring and recovery logic
v7.4.8: Improved stability for multi-tunnel scenarios
v7.4.9: Production-validated multi-tunnel monitoring
v7.4.10: Updated version tracking for consistency
v7.5.0: Added startup delay and backend readiness check
v7.5.1: Improved startup sequence with configurable delay
v7.5.3: Enhanced startup delay, backend port verification before monitoring
"""
import os
import time
import logging
import subprocess
import socket
from pathlib import Path
from typing import Dict, Any

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class WatchdogMonitor:
    """
    Monitor PPP interfaces and auto-restart backend when necessary.
    
    FIX #5: If connexa_ppp_interfaces == 0 for 3 consecutive checks,
    restart the backend via supervisorctl.
    """
    
    def __init__(self, check_interval: int = 30, startup_delay: int = 10):
        """
        Initialize watchdog monitor.
        
        Args:
            check_interval: Seconds between checks (default: 30)
            startup_delay: Seconds to wait before first check (default: 10)
        """
        self.check_interval = check_interval
        self.startup_delay = startup_delay
        self.zero_ppp_count = 0
        self.consecutive_threshold = 3
        self.version = "7.5.3"
        self.backend_port = 8001
        logger.info(f"WatchdogMonitor v{self.version} initialized (check_interval={check_interval}s, startup_delay={startup_delay}s)")
    
    def count_ppp_interfaces(self) -> int:
        """
        Count active PPP interfaces that are UP.
        
        Returns:
            Number of PPP interfaces in UP state
        """
        try:
            result = subprocess.run(
                ["ip", "link", "show"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                ppp_up_count = 0
                
                for line in lines:
                    # Look for lines like: "5: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>"
                    if 'ppp' in line.lower() and 'state UP' in line.upper():
                        ppp_up_count += 1
                
                return ppp_up_count
            else:
                logger.error(f"Failed to get interface list: {result.stderr}")
                return 0
                
        except subprocess.TimeoutExpired:
            logger.error("Timeout getting interface list")
            return 0
        except Exception as e:
            logger.error(f"Error counting PPP interfaces: {e}")
            return 0
    
    def restart_backend(self) -> bool:
        """
        Restart backend service via supervisorctl.
        
        Returns:
            True if restart command executed successfully
        """
        try:
            logger.warning("🔄 Restarting backend due to 3 consecutive zero PPP interfaces")
            
            result = subprocess.run(
                ["supervisorctl", "restart", "backend"],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                logger.info(f"✅ Backend restart initiated: {result.stdout}")
                self.zero_ppp_count = 0  # Reset counter after restart
                return True
            else:
                logger.error(f"❌ Backend restart failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("Timeout restarting backend")
            return False
        except Exception as e:
            logger.error(f"Error restarting backend: {e}")
            return False
    
    def check_and_recover(self) -> Dict[str, Any]:
        """
        Perform a single check and recovery action if needed.
        
        Returns:
            Status dictionary with check results
        """
        connexa_ppp_interfaces = self.count_ppp_interfaces()
        
        logger.info(f"Watchdog check: {connexa_ppp_interfaces} PPP interface(s) UP")
        
        if connexa_ppp_interfaces == 0:
            self.zero_ppp_count += 1
            logger.warning(f"⚠️ Zero PPP interfaces detected ({self.zero_ppp_count}/{self.consecutive_threshold})")
            
            if self.zero_ppp_count >= self.consecutive_threshold:
                # Trigger restart
                restart_success = self.restart_backend()
                
                return {
                    "ppp_count": connexa_ppp_interfaces,
                    "zero_count": self.zero_ppp_count,
                    "action": "restart_triggered",
                    "restart_success": restart_success,
                    "threshold_reached": True
                }
            else:
                return {
                    "ppp_count": connexa_ppp_interfaces,
                    "zero_count": self.zero_ppp_count,
                    "action": "monitoring",
                    "threshold_reached": False
                }
        else:
            # PPP interfaces are active, reset counter
            if self.zero_ppp_count > 0:
                logger.info(f"✅ PPP interfaces recovered, resetting zero count from {self.zero_ppp_count}")
            self.zero_ppp_count = 0
            
            return {
                "ppp_count": connexa_ppp_interfaces,
                "zero_count": self.zero_ppp_count,
                "action": "healthy",
                "threshold_reached": False
            }
    
    def check_backend_ready(self) -> bool:
        """
        Check if backend is ready by attempting to connect to port 8001.
        
        Returns:
            True if backend is responsive on port 8001
        """
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex(('127.0.0.1', self.backend_port))
            sock.close()
            return result == 0
        except Exception as e:
            logger.debug(f"Backend readiness check failed: {e}")
            return False
    
    def wait_for_backend(self, max_wait: int = 30) -> bool:
        """
        Wait for backend to become ready.
        
        Args:
            max_wait: Maximum seconds to wait for backend
            
        Returns:
            True if backend became ready within max_wait
        """
        logger.info(f"Waiting up to {max_wait}s for backend to be ready on port {self.backend_port}...")
        
        start_time = time.time()
        while time.time() - start_time < max_wait:
            if self.check_backend_ready():
                elapsed = int(time.time() - start_time)
                logger.info(f"✅ Backend is ready after {elapsed}s")
                return True
            time.sleep(1)
        
        logger.warning(f"⚠️ Backend not ready after {max_wait}s, proceeding anyway")
        return False
    
    def run_forever(self):
        """
        Run watchdog monitor in continuous loop.
        
        This method runs indefinitely, checking PPP interfaces
        at regular intervals and auto-recovering when needed.
        
        v7.5.3: Added startup delay and backend readiness check
        """
        logger.info(f"Watchdog starting with {self.startup_delay}s startup delay...")
        
        # Wait for backend to initialize
        if self.startup_delay > 0:
            time.sleep(self.startup_delay)
        
        # Verify backend is ready before monitoring
        self.wait_for_backend(max_wait=30)
        
        logger.info("Starting watchdog monitor loop...")
        
        try:
            while True:
                try:
                    status = self.check_and_recover()
                    
                    if status.get("threshold_reached"):
                        # After restart, wait longer before next check
                        logger.info(f"Waiting {self.check_interval * 2}s after restart...")
                        time.sleep(self.check_interval * 2)
                    else:
                        # Normal check interval
                        time.sleep(self.check_interval)
                        
                except KeyboardInterrupt:
                    logger.info("Watchdog monitor stopped by user")
                    break
                except Exception as e:
                    logger.error(f"Error in watchdog loop: {e}")
                    time.sleep(self.check_interval)
                    
        except Exception as e:
            logger.error(f"Fatal error in watchdog: {e}")
    
    def get_status(self) -> Dict[str, Any]:
        """
        Get current watchdog status without performing actions.
        
        Returns:
            Status dictionary
        """
        ppp_count = self.count_ppp_interfaces()
        
        return {
            "ppp_interfaces": ppp_count,
            "zero_ppp_count": self.zero_ppp_count,
            "consecutive_threshold": self.consecutive_threshold,
            "check_interval": self.check_interval,
            "is_healthy": ppp_count > 0
        }


# Create singleton
watchdog_monitor = WatchdogMonitor()


def main():
    """Main entry point for running watchdog as standalone script."""
    import argparse
    
    parser = argparse.ArgumentParser(description='CONNEXA Watchdog Monitor v7.5.3')
    parser.add_argument(
        '--interval',
        type=int,
        default=30,
        help='Check interval in seconds (default: 30)'
    )
    parser.add_argument(
        '--startup-delay',
        type=int,
        default=10,
        help='Startup delay in seconds before first check (default: 10)'
    )
    parser.add_argument(
        '--once',
        action='store_true',
        help='Run a single check instead of continuous monitoring'
    )
    
    args = parser.parse_args()
    
    monitor = WatchdogMonitor(check_interval=args.interval, startup_delay=args.startup_delay)
    
    if args.once:
        status = monitor.check_and_recover()
        logger.info(f"Single check result: {status}")
    else:
        monitor.run_forever()


if __name__ == "__main__":
    main()
