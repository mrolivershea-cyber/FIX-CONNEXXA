# CONNEXA v7.9 - Quick Reference Card

## Installation

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-connexa-issues/install_connexa_v7_9_patch.sh | bash

# Or manual
git clone https://github.com/mrolivershea-cyber/FIX-CONNEXXA.git
cd FIX-CONNEXXA
git checkout copilot/fix-connexa-issues
bash install_connexa_v7_9_patch.sh
```

## Quick Commands

### Status Checks
```bash
# Run self-test
bash /root/FIX-CONNEXXA/selftest.sh

# Check services
supervisorctl status

# View PPP interfaces
ip addr show | grep ppp

# Count PPP interfaces
ip addr show | grep -c "ppp[0-9]:"
```

### Logs
```bash
# Watchdog (real-time)
tail -f /var/log/connexa-watchdog.log

# Tunnel manager
tail -f /var/log/connexa-tunnel-manager.log

# Individual tunnels
tail -f /tmp/pptp_node_*.log

# PPP routing
tail -f /var/log/ppp-up.log

# Self-test
tail -f /var/log/connexa-selftest.log
```

### Service Management
```bash
# Restart backend
supervisorctl restart backend

# Restart watchdog
supervisorctl restart watchdog

# Stop all
supervisorctl stop all

# View logs
supervisorctl tail -f watchdog
```

### Manual Tunnel Management
```bash
# Run tunnel manager
cd /app/backend
python3 pptp_tunnel_manager.py

# Check specific node logs
tail -f /tmp/pptp_node_2.log

# View peer configs
cat /etc/ppp/peers/connexa-node-*

# Check chap-secrets
cat /etc/ppp/chap-secrets
```

### Diagnostics
```bash
# Check backend
curl -s http://localhost:8001/metrics | grep connexa

# Check port 8001
lsof -i :8001

# Check firewall
iptables -L -n | grep -E "gre|1723"

# Check database
sqlite3 /app/backend/connexa.db "SELECT id, ip, status FROM nodes;"

# Check routes
ip route show | grep ppp
```

### Troubleshooting
```bash
# No PPP interfaces
grep "authentication\|invalid" /tmp/pptp_node_*.log

# Routing issues
grep "Nexthop\|gateway" /var/log/ppp-up.log

# Watchdog issues
grep "ERROR\|FAIL\|WARNING" /var/log/connexa-watchdog.log

# Backend not responding
journalctl -u supervisor -n 50
```

## File Locations

| Item | Path |
|------|------|
| Tunnel Manager | `/app/backend/pptp_tunnel_manager.py` |
| Self-Test | `/root/FIX-CONNEXXA/selftest.sh` |
| Watchdog | `/usr/local/bin/connexa-watchdog.sh` |
| ip-up Script | `/etc/ppp/ip-up` |
| ip-down Script | `/etc/ppp/ip-down` |
| Peer Configs | `/etc/ppp/peers/connexa-node-*` |
| CHAP Secrets | `/etc/ppp/chap-secrets` |
| Database | `/app/backend/connexa.db` |

## Expected Output

### Successful Self-Test
```
✅ PASS - Supervisor service
✅ PASS - Backend service
✅ PASS - Backend port 8001
✅ PASS - Watchdog service
✅ PASS - PPP interfaces (Found 2 PPP interface(s))
✅ PASS - Authentication (No authentication errors found)
✅ PASS - Routing (No 'Nexthop has invalid gateway' errors)
✅ PASS - IP validation (No invalid IP attempts)
✅ PASS - Metrics endpoint
✅ PASS - SOCKS proxies

✅ Connexa selftest passed — All systems operational!
Tests passed: 10/10
```

### Healthy Watchdog Log
```
[2024-10-31 14:30:00] [Watchdog] CONNEXA Watchdog v7.9 starting
[2024-10-31 14:30:10] [Watchdog] Initial delay (10 seconds)...
[2024-10-31 14:30:10] [Watchdog] Waiting for backend...
[2024-10-31 14:30:13] [Watchdog] ✅ Backend reachable. Starting monitoring.
[2024-10-31 14:30:13] [Watchdog] Status: PPP=2, Backend=UP, SOCKS=2
[2024-10-31 14:30:43] [Watchdog] Status: PPP=2, Backend=UP, SOCKS=2
```

### Active PPP Interfaces
```
3: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>
4: ppp1: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>
```

## Common Issues - Quick Fixes

### No PPP Interfaces
```bash
# Check for auth errors
grep "peer refused" /tmp/pptp_node_*.log

# Check IP validation
grep "SKIP\|invalid IP" /var/log/connexa-tunnel-manager.log

# Manually retry
cd /app/backend && python3 pptp_tunnel_manager.py
```

### Backend Not Responding
```bash
# Check if running
supervisorctl status backend

# Check port
lsof -i :8001

# Restart
supervisorctl restart backend
sleep 5
curl http://localhost:8001/metrics
```

### Watchdog FATAL
```bash
# Check logs
tail -50 /var/log/connexa-watchdog.log

# Restart
supervisorctl restart watchdog

# Manual test
/usr/local/bin/connexa-watchdog.sh
```

### Authentication Failures
```bash
# Check chap-secrets
cat /etc/ppp/chap-secrets

# Check peer config
cat /etc/ppp/peers/connexa-node-*

# Regenerate (run tunnel manager)
cd /app/backend && python3 pptp_tunnel_manager.py
```

## Success Criteria Checklist

- [ ] Supervisor: backend and watchdog RUNNING
- [ ] PPP: At least 1-2 interfaces UP
- [ ] Port 8001: Accessible
- [ ] Logs: No "peer refused to authenticate"
- [ ] Logs: No "Nexthop has invalid gateway"
- [ ] Logs: No 0.0.0.2 connection attempts
- [ ] Metrics: connexa_ppp_interfaces > 0
- [ ] Self-test: 10/10 PASS or 7+/10 PASS

## Key Features

✅ MS-CHAP-V2 with MPPE-128
✅ 3-attempt retry logic
✅ Dynamic chap-secrets
✅ IP validation (rejects 0.0.0.x)
✅ Routing fix (no invalid gateway)
✅ Watchdog monitoring
✅ Automated self-testing
✅ Cron @reboot testing
✅ Comprehensive logging

## Need Help?

1. **Run self-test**: `bash /root/FIX-CONNEXXA/selftest.sh`
2. **Check all logs**: See "Logs" section above
3. **Review troubleshooting**: See [README_v7.9.md](README_v7.9.md#troubleshooting)
4. **Check supervisor**: `supervisorctl status`

## Version Info

- **Version**: 7.9
- **Branch**: copilot/fix-connexa-issues
- **Components**: 7 files, ~1200 lines of code
- **Features**: Full automation, MS-CHAP-V2, self-testing

---

For detailed documentation, see:
- [README_v7.9.md](README_v7.9.md) - Complete documentation
- [INSTALL_GUIDE_v7.9.md](INSTALL_GUIDE_v7.9.md) - Installation guide
