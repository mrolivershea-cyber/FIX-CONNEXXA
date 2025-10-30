# Systemd/Supervisor Port Conflict Resolution

## Problem (FIX #1)

Both systemd and supervisor try to bind port 8001 simultaneously, causing:

```
[Errno 98] address already in use
```

## Root Cause

- **systemd** has a unit file `connexa-backend.service` that starts the backend on port 8001
- **supervisor** also manages the backend service and tries to bind the same port
- Both services attempt to start simultaneously on system boot
- This creates a race condition and port conflict

## Solution

Choose ONE service manager and disable the other. We recommend using **supervisor** for the backend service.

### Option A: Use Supervisor (Recommended)

1. **Disable systemd unit:**
   ```bash
   systemctl disable --now connexa-backend.service
   ```

2. **Verify systemd is disabled:**
   ```bash
   systemctl status connexa-backend.service
   # Should show: "disabled" and "inactive"
   ```

3. **Ensure supervisor is managing the backend:**
   ```bash
   supervisorctl status backend
   # Should show: "RUNNING"
   ```

4. **Verify only ONE process on port 8001:**
   ```bash
   ss -lntp | grep 8001
   # Should show only ONE process
   ```

### Option B: Use Systemd (Alternative)

1. **Stop and disable supervisor for backend:**
   ```bash
   supervisorctl stop backend
   # Edit /etc/supervisor/conf.d/backend.conf and set autostart=false
   supervisorctl reread
   supervisorctl update
   ```

2. **Enable and start systemd unit:**
   ```bash
   systemctl enable --now connexa-backend.service
   ```

3. **Verify only systemd is running:**
   ```bash
   systemctl status connexa-backend.service
   # Should show: "active (running)"
   
   supervisorctl status backend
   # Should show: "STOPPED" or not exist
   ```

## Prevention Check Script

Create a startup check to prevent conflicts:

```bash
#!/bin/bash
# /usr/local/bin/check-backend-manager.sh

if systemctl is-enabled connexa-backend.service 2>/dev/null; then
    echo "Systemd unit is enabled"
    if supervisorctl status backend 2>/dev/null | grep -q RUNNING; then
        echo "ERROR: Both systemd and supervisor are managing backend!"
        echo "Disabling systemd unit..."
        systemctl disable --now connexa-backend.service
    fi
fi
```

## Verification

After resolving the conflict, verify:

1. **Only one backend process:**
   ```bash
   ps aux | grep "uvicorn.*8001" | grep -v grep
   # Should show exactly ONE process
   ```

2. **Port is bound correctly:**
   ```bash
   ss -lntp | grep 8001
   # Should show ONE listener
   ```

3. **Backend is accessible:**
   ```bash
   curl http://localhost:8001/service/status
   # Should return valid JSON
   ```

## Recommended Configuration

For CONNEXA v7.4.6, use **supervisor** only:

- ✅ Supervisor manages: backend, watchdog
- ❌ Systemd disabled: connexa-backend.service
- ✅ Firewall: Allow port 8001 only from trusted networks

## Troubleshooting

### Issue: Port still in use after disabling

```bash
# Find process using port
lsof -i :8001

# Kill the process
pkill -9 -f "uvicorn.*8001"

# Or force kill by port
fuser -k 8001/tcp
```

### Issue: Systemd re-enables itself

```bash
# Mask the unit to prevent re-enabling
systemctl mask connexa-backend.service
```

### Issue: Supervisor doesn't start backend

```bash
# Check supervisor logs
tail -f /var/log/supervisor/supervisord.log
tail -f /var/log/supervisor/backend.err.log
tail -f /var/log/supervisor/backend.out.log

# Restart supervisor
supervisorctl reload
```

## Related Files

- `/etc/systemd/system/connexa-backend.service` - Systemd unit file
- `/etc/supervisor/conf.d/backend.conf` - Supervisor configuration
- `/var/log/supervisor/backend.err.log` - Backend error logs

---

**Version:** v7.4.6  
**Date:** 2025-10-30  
**Fix:** #1 - systemd/supervisor port conflict
