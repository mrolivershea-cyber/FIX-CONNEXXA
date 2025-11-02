# CONNEXA v7.9 - Full Automation Patch

## Overview

CONNEXA v7.9 is a comprehensive patch that provides full automation for PPTP tunnel management with MS-CHAP-V2 authentication, automatic retry logic, and built-in self-testing capabilities.

## Features

### ✅ Core Features

- **MS-CHAP-V2 Authentication**: Proper authentication with MPPE-128 encryption
- **Dynamic Credential Management**: Automatic generation of chap-secrets from database
- **Intelligent Retry Logic**: Up to 3 automatic retry attempts for failed connections
- **IP Validation**: Filters out invalid IPs (0.0.0.x) before attempting connections
- **Routing Fix**: Eliminates "Nexthop has invalid gateway" errors
- **Watchdog Monitoring**: Continuous monitoring of PPP interfaces and backend health
- **Automated Self-Testing**: Runs automatically after installation and on reboot
- **Comprehensive Logging**: Detailed logs for debugging and monitoring

### 🆕 What's New in v7.9

1. **Full Automation**: No manual configuration required
2. **Self-Healing**: Automatic retry on authentication failures
3. **Built-in Diagnostics**: Comprehensive self-test validates system health
4. **Cron Integration**: Automatic testing on system reboot
5. **Enhanced Monitoring**: Real-time status of PPP, backend, and SOCKS services

## Components

### 1. PPTP Tunnel Manager (`pptp_tunnel_manager.py`)

The core component that manages PPTP tunnels:

- Reads node configuration from SQLite database
- Validates IP addresses
- Generates peer configurations with proper MS-CHAP-V2 settings
- Creates and manages chap-secrets
- Implements 3-attempt retry logic
- Logs all operations

**Key Features:**
- Rejects invalid IPs (0.0.0.x, private ranges)
- Auto-generates MPPE-128 encrypted connections
- Marks failed nodes as `ping_auth_failed` or `ping_invalid_ip`
- Comprehensive error logging

### 2. PPP Scripts

**ip-up script** (`/etc/ppp/ip-up`):
- Runs when PPP interface comes up
- Adds proper host routes
- Prevents "Nexthop has invalid gateway" errors
- Logs all routing operations

**ip-down script** (`/etc/ppp/ip-down`):
- Runs when PPP interface goes down
- Cleans up routes
- Logs connection statistics

### 3. Watchdog (`connexa-watchdog.sh`)

Monitors system health:
- Waits for backend to become available
- Monitors PPP interface count
- Checks backend status
- Counts active SOCKS ports
- Logs status every 30 seconds

**Features:**
- Graceful startup with backend verification
- Continuous monitoring loop
- Alerts on issues (no PPP interfaces, backend down)
- Supervisor integration for automatic restart

### 4. Self-Test Script (`selftest.sh`)

Comprehensive validation of system health:

**Tests Performed:**
1. Supervisor service status
2. Backend service status
3. Backend port availability (8001)
4. Watchdog service status
5. PPP interface count (expects >= 1)
6. Authentication error detection
7. Routing error detection
8. Invalid IP attempt detection
9. Metrics endpoint accessibility
10. SOCKS proxy availability

**Output:**
- Color-coded PASS/FAIL results
- Detailed logging to `/var/log/connexa-selftest.log`
- Summary with pass/fail counts
- Overall system health status

## Installation

### Quick Install

```bash
bash install_connexa_v7_9_patch.sh
```

### What the Installer Does

1. **Installs Dependencies**: pptp-linux, ppp, sqlite3, supervisor, etc.
2. **Creates Directories**: Sets up required directory structure
3. **Installs Tunnel Manager**: Copies pptp_tunnel_manager.py to /app/backend
4. **Installs PPP Scripts**: Sets up ip-up and ip-down scripts
5. **Installs Watchdog**: Creates watchdog service with supervisor config
6. **Installs Self-Test**: Copies selftest script to /root/FIX-CONNEXXA
7. **Configures Firewall**: Opens GRE (protocol 47) and TCP/1723
8. **Sets Up Cron**: Adds @reboot job for automatic testing
9. **Reloads Services**: Restarts backend and watchdog
10. **Runs Self-Test**: Validates installation

## Usage

### Manual Tunnel Setup

```bash
cd /app/backend
python3 pptp_tunnel_manager.py
```

### Run Self-Test

```bash
bash /root/FIX-CONNEXXA/selftest.sh
```

### Check Watchdog Status

```bash
supervisorctl status watchdog
tail -f /var/log/connexa-watchdog.log
```

### View PPP Interfaces

```bash
ip addr show | grep ppp
```

### Check Logs

```bash
# Tunnel manager logs
tail -f /var/log/connexa-tunnel-manager.log

# Individual tunnel logs
tail -f /tmp/pptp_node_*.log

# PPP routing logs
tail -f /var/log/ppp-up.log
tail -f /var/log/ppp-down.log

# Watchdog logs
tail -f /var/log/connexa-watchdog.log

# Self-test logs
tail -f /var/log/connexa-selftest.log
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│           CONNEXA v7.9 Architecture             │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐         ┌─────────────────┐  │
│  │   Database   │────────▶│ Tunnel Manager  │  │
│  │ (connexa.db) │         │  (Python)       │  │
│  └──────────────┘         └─────────────────┘  │
│         │                         │             │
│         │                         ▼             │
│         │                  ┌─────────────────┐  │
│         │                  │  chap-secrets   │  │
│         │                  │  peer configs   │  │
│         │                  └─────────────────┘  │
│         │                         │             │
│         │                         ▼             │
│         │                  ┌─────────────────┐  │
│         │                  │      pppd       │  │
│         │                  │   (PPTP call)   │  │
│         │                  └─────────────────┘  │
│         │                         │             │
│         │                         ▼             │
│         │                  ┌─────────────────┐  │
│         │                  │  PPP Interface  │  │
│         │                  │  (ppp0, ppp1)   │  │
│         │                  └─────────────────┘  │
│         │                         │             │
│         │                         ▼             │
│         │                  ┌─────────────────┐  │
│         │                  │   ip-up script  │  │
│         │                  │  (routing fix)  │  │
│         │                  └─────────────────┘  │
│         │                                       │
│         ▼                                       │
│  ┌──────────────────────────────────────────┐  │
│  │            Watchdog Monitor              │  │
│  │   (PPP + Backend + SOCKS monitoring)     │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Configuration Files

### Peer Configuration Template

Location: `/etc/ppp/peers/connexa-node-{id}`

```
name {username}
remotename connexa
require-mschap-v2
require-mppe-128
refuse-pap
refuse-chap
refuse-mschap
mtu 1400
mru 1400
nodefaultroute
usepeerdns
persist
lock
noauth
debug
plugin pptp.so
pptp_server {ip}
```

### CHAP Secrets Format

Location: `/etc/ppp/chap-secrets`

```
"username" connexa "password" *
```

### Supervisor Configuration

Location: `/etc/supervisor/conf.d/connexa-watchdog.conf`

```ini
[program:watchdog]
command=/usr/local/bin/connexa-watchdog.sh
autostart=true
autorestart=true
startsecs=10
startretries=999
stdout_logfile=/var/log/connexa-watchdog.log
stderr_logfile=/var/log/connexa-watchdog.log
user=root
```

## Troubleshooting

### No PPP Interfaces Created

1. Check tunnel manager logs:
   ```bash
   tail -50 /var/log/connexa-tunnel-manager.log
   ```

2. Check individual tunnel logs:
   ```bash
   tail -50 /tmp/pptp_node_*.log
   ```

3. Look for authentication errors:
   ```bash
   grep "peer refused to authenticate" /tmp/pptp_node_*.log
   ```

4. Check database for valid nodes:
   ```bash
   sqlite3 /app/backend/connexa.db "SELECT id, ip, status FROM nodes WHERE status LIKE 'speed%';"
   ```

### Authentication Failures

1. Verify chap-secrets:
   ```bash
   cat /etc/ppp/chap-secrets
   ```

2. Check peer configuration:
   ```bash
   cat /etc/ppp/peers/connexa-node-*
   ```

3. Verify MS-CHAP-V2 is configured:
   ```bash
   grep "require-mschap-v2" /etc/ppp/peers/connexa-node-*
   ```

### Routing Issues

1. Check routing logs:
   ```bash
   tail -50 /var/log/ppp-up.log
   ```

2. Look for "Nexthop" errors:
   ```bash
   grep "Nexthop" /var/log/ppp-up.log
   ```

3. Verify routes are added:
   ```bash
   ip route show
   ```

### Watchdog Not Starting

1. Check supervisor status:
   ```bash
   supervisorctl status watchdog
   ```

2. Check watchdog logs:
   ```bash
   tail -50 /var/log/connexa-watchdog.log
   ```

3. Manually test watchdog:
   ```bash
   /usr/local/bin/connexa-watchdog.sh
   ```

### Backend Not Responding

1. Check if backend is running:
   ```bash
   supervisorctl status backend
   ```

2. Check port 8001:
   ```bash
   lsof -i :8001
   curl http://localhost:8001/metrics
   ```

3. Check backend logs:
   ```bash
   tail -50 /var/log/supervisor/backend*.log
   ```

## Success Criteria

After installation, the self-test should show:

- ✅ **PPP Interfaces**: At least 1-2 PPP interfaces UP
- ✅ **Watchdog**: RUNNING status in supervisor
- ✅ **No Authentication Errors**: No "peer refused to authenticate" in logs
- ✅ **No Routing Errors**: No "Nexthop has invalid gateway" in logs
- ✅ **No Invalid IPs**: No connection attempts to 0.0.0.x addresses
- ✅ **Metrics Available**: `/metrics` endpoint showing connexa_ppp_interfaces > 0
- ✅ **Backend Running**: Port 8001 accessible
- ✅ **SOCKS Proxies**: At least 1 SOCKS port active

## File Locations

| Component | Location |
|-----------|----------|
| Tunnel Manager | `/app/backend/pptp_tunnel_manager.py` |
| Self-Test Script | `/root/FIX-CONNEXXA/selftest.sh` |
| Watchdog Script | `/usr/local/bin/connexa-watchdog.sh` |
| Watchdog Config | `/etc/supervisor/conf.d/connexa-watchdog.conf` |
| ip-up Script | `/etc/ppp/ip-up` |
| ip-down Script | `/etc/ppp/ip-down` |
| Peer Configs | `/etc/ppp/peers/connexa-node-*` |
| CHAP Secrets | `/etc/ppp/chap-secrets` |
| Database | `/app/backend/connexa.db` |

## Log Locations

| Log Type | Location |
|----------|----------|
| Tunnel Manager | `/var/log/connexa-tunnel-manager.log` |
| Individual Tunnels | `/tmp/pptp_node_{id}.log` |
| PPP Up Events | `/var/log/ppp-up.log` |
| PPP Down Events | `/var/log/ppp-down.log` |
| Watchdog | `/var/log/connexa-watchdog.log` |
| Self-Test | `/var/log/connexa-selftest.log` |
| Self-Test (cron) | `/var/log/selftest.log` |

## Version History

### v7.9 (Current)
- ✨ Full automation with MS-CHAP-V2
- ✨ 3-attempt retry logic
- ✨ Dynamic chap-secrets generation
- ✨ IP validation (reject 0.0.0.x)
- ✨ Routing fix (no invalid gateway)
- ✨ Watchdog with backend verification
- ✨ Automated self-testing
- ✨ Cron integration for reboot testing

### v7.4.6 (Previous)
- Single tunnel focus
- Manual configuration
- Basic MSCHAP-v2 support

## Support

For issues or questions:
1. Run the self-test: `bash /root/FIX-CONNEXXA/selftest.sh`
2. Check all logs (see Log Locations above)
3. Review troubleshooting section
4. Check supervisor status: `supervisorctl status`

## License

This patch is part of the FIX-CONNEXXA project by mrolivershea-cyber.

## Changelog

See version history above for detailed changes.
