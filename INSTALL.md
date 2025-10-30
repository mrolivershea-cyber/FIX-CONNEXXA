# CONNEXA v7.4.7 - Installation Guide

## Quick Installation

### Method 1: Clone Repository (Recommended)

```bash
# Clone repository
git clone https://github.com/mrolivershea-cyber/FIX-CONNEXXA.git

# Navigate to directory
cd FIX-CONNEXXA

# Switch to the fix branch
git checkout copilot/fix-pptp-tunnel-issues

# Verify files exist
ls -la install_connexa_v7_4_7_patch.sh

# Run installation
bash install_connexa_v7_4_7_patch.sh
```

### Method 2: Direct Download (No Git Required)

```bash
# Download the installation script directly
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/install_connexa_v7_4_7_patch.sh

# OR use curl
curl -O https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/install_connexa_v7_4_7_patch.sh

# Make it executable
chmod +x install_connexa_v7_4_7_patch.sh

# Run installation
bash install_connexa_v7_4_7_patch.sh
```

### Method 3: Minimal Installation

If you have issues with dependencies:

```bash
# Clone and switch branch (same as Method 1)
git clone https://github.com/mrolivershea-cyber/FIX-CONNEXXA.git
cd FIX-CONNEXXA
git checkout copilot/fix-pptp-tunnel-issues

# Run minimal installation (requires only python3)
bash install_minimal.sh
```

## Troubleshooting

### Error: "File not found"

**Problem:** Terminal says the file doesn't exist.

**Solution:**
1. Make sure you're in the correct directory:
   ```bash
   pwd
   # Should show: .../FIX-CONNEXXA
   ```

2. Verify you're on the correct branch:
   ```bash
   git branch
   # Should show: * copilot/fix-pptp-tunnel-issues
   ```

3. List files to confirm:
   ```bash
   ls -la install*.sh
   # Should show install_connexa_v7_4_7_patch.sh
   ```

4. If file is missing, fetch latest:
   ```bash
   git fetch origin
   git checkout copilot/fix-pptp-tunnel-issues
   git pull origin copilot/fix-pptp-tunnel-issues
   ```

### Error: "Command not found"

**Problem:** Missing system commands (ss, lsof, etc.)

**Solution:**
```bash
# Install dependencies
apt-get update
apt-get install -y python3 supervisor systemd iproute2

# Or use minimal installation
bash install_minimal.sh
```

### Error: "Permission denied"

**Problem:** Script is not executable.

**Solution:**
```bash
chmod +x install_connexa_v7_4_7_patch.sh
bash install_connexa_v7_4_7_patch.sh
```

## Available Installation Scripts

- `install_connexa_v7_4_7_patch.sh` - **Latest** full installation (v7.4.7)
- `install_connexa_v7_4_6_patch.sh` - Legacy full installation (v7.4.6)
- `install_minimal.sh` - Minimal installation (only Python modules)

## Verification

After installation, verify:

```bash
# Check services
supervisorctl status backend
supervisorctl status watchdog

# Check port
ss -lntp | grep 8001

# Test API
curl -s http://localhost:8001/service/status-v2

# Check logs
tail -f /var/log/supervisor/backend.out.log
```

## Support

If you still have issues:

1. Show current directory: `pwd`
2. Show branch: `git branch`
3. List files: `ls -la install*.sh`
4. Show git status: `git status`

Include this information when asking for help.

---

**Version:** v7.4.7  
**Branch:** copilot/fix-pptp-tunnel-issues  
**Repository:** https://github.com/mrolivershea-cyber/FIX-CONNEXXA
