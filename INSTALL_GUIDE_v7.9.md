# CONNEXA v7.9 Installation Guide

## Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-connexa-issues/install_connexa_v7_9_patch.sh | bash
```

### Manual Installation

```bash
# Clone repository
git clone https://github.com/mrolivershea-cyber/FIX-CONNEXXA.git
cd FIX-CONNEXXA

# Checkout the patch branch
git checkout copilot/fix-connexa-issues

# Run installer
bash install_connexa_v7_9_patch.sh
```

## What Gets Installed

The installer performs the following steps automatically:

### 1. Dependencies (Step 1/10)
- pptp-linux
- ppp
- sqlite3
- curl
- lsof
- supervisor
- python3
- python3-pip
- iptables
- iptables-persistent

### 2. Directory Structure (Step 2/10)
```
/app/backend/                  # Application directory
/root/FIX-CONNEXXA/           # Self-test location
/etc/ppp/peers/               # PPP peer configurations
/etc/ppp/ip-up.d/             # PPP up scripts
/etc/ppp/ip-down.d/           # PPP down scripts
/var/log/                     # Log directory
```

### 3. Core Components (Steps 3-6)
- **PPTP Tunnel Manager**: Python script for managing PPTP connections
- **PPP Scripts**: Routing configuration (ip-up, ip-down)
- **Watchdog**: Monitoring service
- **Self-Test**: Automated validation script

### 4. System Configuration (Steps 7-8)
- **Firewall**: Opens GRE (protocol 47) and TCP/1723
- **Cron**: Adds @reboot job for automatic testing

### 5. Service Management (Step 9)
- Reloads supervisor configuration
- Restarts backend service (if exists)
- Starts/restarts watchdog service

### 6. Validation (Step 10)
- Runs comprehensive self-test
- Displays results with color-coded PASS/FAIL

## Post-Installation

### Verify Installation

```bash
# Run self-test
bash /root/FIX-CONNEXXA/selftest.sh

# Check supervisor status
supervisorctl status

# View PPP interfaces
ip addr show | grep ppp

# Check watchdog logs
tail -f /var/log/connexa-watchdog.log
```

### Expected Results

After successful installation, you should see:

✅ **Supervisor Services**
```
backend    RUNNING   pid 1234, uptime 0:01:00
watchdog   RUNNING   pid 1235, uptime 0:00:50
```

✅ **PPP Interfaces**
```
ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>
```

✅ **Self-Test Summary**
```
✅ Connexa selftest passed — All systems operational!
Tests passed: 10/10
```

## Manual Setup (Alternative)

If you prefer to set up components individually:

### 1. Install Dependencies

```bash
apt-get update
apt-get install -y pptp-linux ppp sqlite3 curl lsof supervisor \
                   python3 python3-pip iptables iptables-persistent
```

### 2. Copy Files

```bash
# Create directories
mkdir -p /app/backend
mkdir -p /root/FIX-CONNEXXA

# Copy tunnel manager
cp backend/pptp_tunnel_manager.py /app/backend/
chmod +x /app/backend/pptp_tunnel_manager.py

# Copy PPP scripts
cp backend/ppp-ip-up /etc/ppp/ip-up
cp backend/ppp-ip-down /etc/ppp/ip-down
chmod +x /etc/ppp/ip-up /etc/ppp/ip-down

# Copy watchdog
cp backend/connexa-watchdog.sh /usr/local/bin/
chmod +x /usr/local/bin/connexa-watchdog.sh

# Copy self-test
cp backend/selftest.sh /root/FIX-CONNEXXA/
chmod +x /root/FIX-CONNEXXA/selftest.sh
```

### 3. Configure Supervisor

Create `/etc/supervisor/conf.d/connexa-watchdog.conf`:

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

Reload supervisor:
```bash
supervisorctl reread
supervisorctl update
supervisorctl start watchdog
```

### 4. Configure Firewall

```bash
# Allow GRE protocol
iptables -A INPUT -p gre -j ACCEPT
iptables -A OUTPUT -p gre -j ACCEPT

# Allow PPTP port
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 1723 -j ACCEPT

# Save rules
netfilter-persistent save
```

### 5. Add Cron Job

```bash
# Add @reboot test
(crontab -l 2>/dev/null; echo "@reboot /bin/bash /root/FIX-CONNEXXA/selftest.sh >> /var/log/selftest.log 2>&1") | crontab -
```

### 6. Run Tunnel Manager

```bash
cd /app/backend
python3 pptp_tunnel_manager.py
```

## Troubleshooting Installation

### Installation Fails at Dependencies

**Problem**: Package installation fails

**Solution**:
```bash
# Update package list
apt-get update

# Try installing packages individually
apt-get install -y pptp-linux
apt-get install -y ppp
apt-get install -y sqlite3
# ... etc
```

### Permission Denied Errors

**Problem**: Cannot write files or execute scripts

**Solution**:
```bash
# Ensure running as root
sudo bash install_connexa_v7_9_patch.sh

# Or switch to root
su -
bash install_connexa_v7_9_patch.sh
```

### Supervisor Not Found

**Problem**: supervisorctl command not found

**Solution**:
```bash
# Install supervisor
apt-get install -y supervisor

# Start supervisor service
systemctl start supervisor
systemctl enable supervisor
```

### Port 8001 Already in Use

**Problem**: Backend port is already occupied

**Solution**:
```bash
# Find process using port
lsof -i :8001

# Kill process (if safe to do so)
kill -9 $(lsof -t -i :8001)

# Or stop any existing backend
supervisorctl stop backend
pkill -f "uvicorn.*8001"
```

### Database Not Found

**Problem**: /app/backend/connexa.db doesn't exist

**Solution**:
```bash
# Check if database exists
ls -la /app/backend/*.db

# If database is in different location, create symlink
ln -s /path/to/actual/connexa.db /app/backend/connexa.db

# Or update DB_PATH in pptp_tunnel_manager.py
```

### Firewall Rules Fail

**Problem**: iptables commands fail

**Solution**:
```bash
# Check if iptables is installed
which iptables

# Install if missing
apt-get install -y iptables

# Check current rules
iptables -L -n

# Manually add rules
iptables -A INPUT -p 47 -j ACCEPT
iptables -A OUTPUT -p 47 -j ACCEPT
```

## Verification Steps

### 1. Check Installation Files

```bash
# Verify all files exist
ls -lh /app/backend/pptp_tunnel_manager.py
ls -lh /etc/ppp/ip-up
ls -lh /etc/ppp/ip-down
ls -lh /usr/local/bin/connexa-watchdog.sh
ls -lh /root/FIX-CONNEXXA/selftest.sh
```

### 2. Check Permissions

```bash
# All scripts should be executable
ls -l /app/backend/pptp_tunnel_manager.py    # Should show -rwxr-xr-x
ls -l /etc/ppp/ip-up                         # Should show -rwxr-xr-x
ls -l /usr/local/bin/connexa-watchdog.sh     # Should show -rwxr-xr-x
ls -l /root/FIX-CONNEXXA/selftest.sh        # Should show -rwxr-xr-x
```

### 3. Check Services

```bash
# Supervisor should be running
systemctl status supervisor

# Watchdog should be running
supervisorctl status watchdog

# Backend should be running (if configured)
supervisorctl status backend
```

### 4. Check Firewall

```bash
# Verify GRE and PPTP rules
iptables -L -n | grep -E "gre|1723"
```

### 5. Check Cron

```bash
# Verify cron job was added
crontab -l | grep selftest
```

### 6. Check Logs

```bash
# All log directories should exist
ls -la /var/log/connexa-*
ls -la /tmp/pptp_node_*.log
```

## Uninstall

To remove CONNEXA v7.9:

```bash
# Stop services
supervisorctl stop watchdog
supervisorctl stop backend

# Remove supervisor config
rm -f /etc/supervisor/conf.d/connexa-watchdog.conf
supervisorctl reread
supervisorctl update

# Remove files
rm -f /app/backend/pptp_tunnel_manager.py
rm -f /etc/ppp/ip-up
rm -f /etc/ppp/ip-down
rm -f /usr/local/bin/connexa-watchdog.sh
rm -rf /root/FIX-CONNEXXA

# Remove cron job
crontab -l | grep -v "selftest.sh" | crontab -

# Remove logs (optional)
rm -f /var/log/connexa-*
rm -f /tmp/pptp_node_*.log
```

## Getting Help

### Log Files to Check

1. **Installation Log**: Check terminal output during installation
2. **Tunnel Manager**: `/var/log/connexa-tunnel-manager.log`
3. **Individual Tunnels**: `/tmp/pptp_node_*.log`
4. **Watchdog**: `/var/log/connexa-watchdog.log`
5. **Self-Test**: `/var/log/connexa-selftest.log`
6. **PPP Routing**: `/var/log/ppp-up.log`
7. **Supervisor**: `/var/log/supervisor/*.log`

### Common Issues and Solutions

See the main [README_v7.9.md](README_v7.9.md#troubleshooting) for detailed troubleshooting.

### Support

1. Run self-test: `bash /root/FIX-CONNEXXA/selftest.sh`
2. Check all logs (see above)
3. Verify supervisor status: `supervisorctl status`
4. Check PPP interfaces: `ip addr show | grep ppp`

## Next Steps

After installation:

1. ✅ **Verify Installation**: Run self-test
2. 🔧 **Configure Database**: Ensure `/app/backend/connexa.db` has valid nodes
3. 🚀 **Start Tunnels**: Run tunnel manager
4. 📊 **Monitor Status**: Check watchdog logs
5. ✨ **Validate**: Ensure PPP interfaces are UP

## Advanced Configuration

### Customizing Retry Attempts

Edit `/app/backend/pptp_tunnel_manager.py`:

```python
MAX_RETRIES = 3  # Change to desired number
RETRY_DELAY = 5  # Change delay between retries (seconds)
```

### Customizing Watchdog Interval

Edit `/usr/local/bin/connexa-watchdog.sh`:

```bash
CHECK_INTERVAL=30  # Change to desired interval (seconds)
```

### Customizing Database Path

Edit `/app/backend/pptp_tunnel_manager.py`:

```python
DB_PATH = "/app/backend/connexa.db"  # Change to your database path
```

## License

This patch is part of the FIX-CONNEXXA project by mrolivershea-cyber.
