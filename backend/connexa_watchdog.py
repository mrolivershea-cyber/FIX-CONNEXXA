#!/usr/bin/env python3
"""
CONNEXA Watchdog v7.9 (Python version)
Monitors PPP interfaces and backend service with robust error handling
"""

import subprocess
import time
import sys
import logging
import re
from datetime import datetime

# Configuration
LOGFILE = "/var/log/connexa-watchdog.log"
BACKEND_URL = "http://localhost:8001"
CHECK_INTERVAL = 30
MAX_WAIT_BACKEND = 120

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [Watchdog] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(LOGFILE),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)


def log(message):
    """Log message to file and stdout"""
    logger.info(message)


def run_command(cmd, shell=True, timeout=10):
    """
    Run command with error handling
    Returns (success, output, error)
    """
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return (result.returncode == 0, result.stdout, result.stderr)
    except subprocess.TimeoutExpired:
        return (False, "", "Command timeout")
    except Exception as e:
        return (False, "", str(e))


def count_ppp_interfaces():
    """
    Count active PPP interfaces using ip a | grep -E "ppp[0-9].*UP"
    Returns interface count (0 on error)
    """
    try:
        success, output, error = run_command("ip a")
        if not success:
            log(f"⚠️ Error getting interfaces: {error}")
            return 0
        
        # Count lines matching ppp[0-9].*UP pattern
        count = len([line for line in output.split('\n') 
                     if re.search(r'ppp\d+.*UP', line)])
        return count
    except Exception as e:
        log(f"⚠️ Exception counting PPP interfaces: {e}")
        return 0


def check_backend(url):
    """
    Check if backend is responding
    Returns True if backend is up, False otherwise
    """
    try:
        # Try health endpoint
        success, _, _ = run_command(f"curl -sf {url}/health", timeout=5)
        if success:
            return True
        
        # Try metrics endpoint
        success, _, _ = run_command(f"curl -sf {url}/metrics", timeout=5)
        return success
    except Exception as e:
        log(f"⚠️ Exception checking backend: {e}")
        return False


def count_socks_ports():
    """
    Count active SOCKS ports (1080-1089)
    Returns port count (0 on error)
    """
    try:
        count = 0
        for port in range(1080, 1090):
            success, _, _ = run_command(f"lsof -i :{port}", timeout=2)
            if success:
                count += 1
        return count
    except Exception as e:
        log(f"⚠️ Exception counting SOCKS ports: {e}")
        return 0


def get_active_ppp_interfaces():
    """
    Get list of active PPP interface names
    Returns list of interface names
    """
    try:
        success, output, _ = run_command("ip a")
        if not success:
            return []
        
        interfaces = []
        for line in output.split('\n'):
            match = re.search(r'(ppp\d+).*UP', line)
            if match:
                interfaces.append(match.group(1))
        return interfaces
    except Exception as e:
        log(f"⚠️ Exception getting PPP interface list: {e}")
        return []


def wait_for_backend(url, max_wait):
    """
    Wait for backend to become available
    Returns True if backend is up, False if timeout
    """
    log(f"Waiting for backend at {url}...")
    waited = 0
    
    while waited < max_wait:
        try:
            if check_backend(url):
                log(f"✅ Backend reachable after {waited}s")
                return True
            
            log(f"Waiting for backend... ({waited}s/{max_wait}s)")
            time.sleep(3)
            waited += 3
        except KeyboardInterrupt:
            log("Interrupted while waiting for backend")
            return False
        except Exception as e:
            log(f"⚠️ Exception while waiting for backend: {e}")
            time.sleep(3)
            waited += 3
    
    log(f"⚠️ Backend did not become available after {max_wait}s")
    return False


def main():
    """Main watchdog loop"""
    log("=" * 50)
    log("CONNEXA Watchdog v7.9 (Python) starting")
    log("=" * 50)
    
    # Initial delay for system startup (reduced to avoid supervisor timeout)
    log("Initial startup delay (3 seconds)...")
    time.sleep(3)
    
    # Don't wait for backend - start monitoring immediately
    # Backend will show as DOWN until it's ready, that's fine
    log("Starting monitoring loop (backend will be checked continuously)")
    backend_ready = False  # Will be checked in loop
    
    # Main monitoring loop
    log(f"Entering monitoring loop (check interval: {CHECK_INTERVAL}s)")
    log("=" * 50)
    
    while True:
        try:
            # Count PPP interfaces
            ppp_count = count_ppp_interfaces()
            
            # Check backend status (always check)
            backend_status = "UP" if check_backend(BACKEND_URL) else "DOWN"
            if backend_status == "DOWN":
                log("⚠️ Backend is not responding")
            
            # Count SOCKS ports
            socks_count = count_socks_ports()
            
            # Log status
            log(f"Status: PPP interfaces={ppp_count}, Backend={backend_status}, SOCKS ports={socks_count}")
            
            # Check for issues
            if ppp_count == 0:
                log("⚠️ WARNING: No PPP interfaces detected!")
            
            if backend_status == "DOWN":
                log("⚠️ WARNING: Backend service is not responding!")
            
            # Show active PPP interfaces
            if ppp_count > 0:
                interfaces = get_active_ppp_interfaces()
                if interfaces:
                    log(f"Active PPP interfaces: {', '.join(interfaces)}")
            
        except KeyboardInterrupt:
            log("Received shutdown signal, exiting gracefully")
            break
        except Exception as e:
            log(f"⚠️ Error in monitoring loop: {e}")
            # Continue monitoring even if there's an error
        
        # Sleep until next check
        try:
            time.sleep(CHECK_INTERVAL)
        except KeyboardInterrupt:
            log("Received shutdown signal during sleep, exiting gracefully")
            break

    log("Watchdog stopped")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"❌ Fatal error: {e}")
        sys.exit(1)
