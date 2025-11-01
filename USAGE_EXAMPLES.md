# CONNEXA MINIFIX - Usage Examples

This document provides practical examples of how to use the MINIFIX_PATCH.sh script in various scenarios.

## Quick Start

### Scenario 1: Fresh Installation

If you're setting up CONNEXA for the first time:

```bash
# Step 1: Install main CONNEXA service
curl -O https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/install_service_manager.sh
bash install_service_manager.sh

# Step 2: Apply mini-fix patch
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | sudo bash
```

### Scenario 2: Existing Installation

If you already have CONNEXA running:

```bash
# Apply the patch (safe - creates backups automatically)
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | sudo bash
```

### Scenario 3: Development/Testing Environment

For testing before production:

```bash
# Download the script
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh

# Review the script
less MINIFIX_PATCH.sh

# Make it executable
chmod +x MINIFIX_PATCH.sh

# Run with verbose output
sudo ./MINIFIX_PATCH.sh 2>&1 | tee minifix_install.log
```

## Detailed Examples

### Example 1: Backend Only Fix

If you only need the backend fix (load_dotenv):

```bash
# Run the full script (it's safe and handles missing frontend gracefully)
sudo ./MINIFIX_PATCH.sh

# Or manually apply just the backend fix:
cd /app/backend
sudo sed -i '17a from dotenv import load_dotenv\nload_dotenv()' server.py
sudo supervisorctl restart backend
```

### Example 2: Frontend Only Fix

If you only need the frontend fix (double /api):

```bash
# Run the full script (it's safe and handles missing backend gracefully)
sudo ./MINIFIX_PATCH.sh

# Or manually apply just the frontend fix:
cd /app/frontend/src/contexts
sudo sed -i 's|const API = `${BACKEND_URL}/api`;|const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;|g' AuthContext.js
sudo supervisorctl restart frontend
```

### Example 3: Installing python-dotenv

The backend fix requires the `python-dotenv` package:

```bash
# Install for the system Python
sudo pip3 install python-dotenv

# Or install in a virtual environment
cd /app/backend
source venv/bin/activate  # if you use a venv
pip install python-dotenv

# Apply the patch
sudo /path/to/MINIFIX_PATCH.sh
```

### Example 4: Verifying Environment Variables

After applying the backend fix, test that .env files are being loaded:

```bash
# Create a test .env file
cat > /app/backend/.env <<EOF
TEST_VAR=hello_world
PORT=8001
EOF

# Add a test endpoint to verify (in server.py)
# @app.get("/test-env")
# def test_env():
#     return {"TEST_VAR": os.getenv("TEST_VAR")}

# Restart and test
sudo supervisorctl restart backend
curl http://localhost:8001/test-env
# Should return: {"TEST_VAR": "hello_world"}
```

### Example 5: Testing the Double /api Fix

After applying the frontend fix, test different BACKEND_URL scenarios:

```bash
# Test case 1: BACKEND_URL without /api
export REACT_APP_BACKEND_URL="http://localhost:8001"
# Expected API: http://localhost:8001/api ✅

# Test case 2: BACKEND_URL with /api
export REACT_APP_BACKEND_URL="http://localhost:8001/api"
# Expected API: http://localhost:8001/api ✅ (no double /api)

# Rebuild frontend to apply environment variable
cd /app/frontend
npm run build
sudo supervisorctl restart frontend
```

## Troubleshooting Examples

### Example 6: Permission Denied

```bash
# Error: Permission denied
# Solution: Run with sudo
sudo ./MINIFIX_PATCH.sh

# Or change ownership
sudo chown -R $USER:$USER /app
./MINIFIX_PATCH.sh
```

### Example 7: Port Already in Use

```bash
# Check what's using port 8001
sudo lsof -i :8001

# Kill the process
sudo fuser -k 8001/tcp

# Or change the port in .env
echo "PORT=8002" | sudo tee -a /app/backend/.env

# Restart
sudo supervisorctl restart backend
```

### Example 8: Script Runs But No Changes

```bash
# The script is idempotent - if changes are already applied, it won't reapply them
# Check if fixes are already present:

# Backend check
grep -n "load_dotenv" /app/backend/server.py

# Frontend check
grep "BACKEND_URL.endsWith" /app/frontend/src/contexts/AuthContext.js

# If present, you'll see output. If not, investigate why script didn't apply them.
```

### Example 9: Rolling Back Changes

```bash
# List backups
ls -la /app/backup_*/

# Find the most recent backup
LATEST_BACKUP=$(ls -td /app/backup_*/ | head -1)

# Restore files
sudo cp "$LATEST_BACKUP/server.py.backup" /app/backend/server.py
sudo cp "$LATEST_BACKUP/AuthContext.js.backup" /app/frontend/src/contexts/AuthContext.js

# Restart services
sudo supervisorctl restart backend frontend
```

### Example 10: Debugging with Logs

```bash
# Run script with full logging
sudo ./MINIFIX_PATCH.sh 2>&1 | tee -a /tmp/minifix_debug.log

# Check backend logs
sudo tail -f /var/log/supervisor/backend.err.log

# Check frontend logs  
sudo tail -f /var/log/supervisor/frontend.err.log

# Check if services are running
sudo supervisorctl status

# Test API endpoint
curl -v http://localhost:8001/health
curl -v http://localhost:8001/api/service/status
```

## Integration Examples

### Example 11: With Docker

```bash
# If running in Docker, exec into container first
docker exec -it connexa-backend bash

# Then run the script inside container
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | bash

# Or copy script into container
docker cp MINIFIX_PATCH.sh connexa-backend:/tmp/
docker exec connexa-backend bash /tmp/MINIFIX_PATCH.sh
```

### Example 12: With CI/CD

```yaml
# .github/workflows/apply-minifix.yml
name: Apply MiniFix

on:
  workflow_dispatch:

jobs:
  apply-fix:
    runs-on: ubuntu-latest
    steps:
      - name: Download script
        run: |
          curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh -o minifix.sh
          chmod +x minifix.sh
      
      - name: Deploy to server
        run: |
          scp minifix.sh user@server:/tmp/
          ssh user@server 'sudo /tmp/minifix.sh'
```

### Example 13: Multiple Servers

```bash
# Apply to multiple servers at once
SERVERS="server1.example.com server2.example.com server3.example.com"

for server in $SERVERS; do
    echo "Applying patch to $server..."
    ssh root@$server 'curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | bash'
    echo "Done with $server"
done
```

## Advanced Examples

### Example 14: Custom Backend Directory

If your backend is not in `/app/backend`:

```bash
# Edit the script before running
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh

# Modify paths in the script
sed -i 's|/app/backend|/opt/connexa/backend|g' MINIFIX_PATCH.sh
sed -i 's|/app/frontend|/opt/connexa/frontend|g' MINIFIX_PATCH.sh

# Run modified script
sudo ./MINIFIX_PATCH.sh
```

### Example 15: Dry Run Mode

Create a dry-run version to see what would be changed:

```bash
# Create a test copy
cp MINIFIX_PATCH.sh MINIFIX_PATCH_DRYRUN.sh

# Modify to not actually change files (replace sed -i with sed and just print)
sed -i 's/sed -i/sed/g' MINIFIX_PATCH_DRYRUN.sh

# Run to see what would change
sudo ./MINIFIX_PATCH_DRYRUN.sh
```

### Example 16: Automated Health Check

```bash
# Apply patch with automatic health check
sudo ./MINIFIX_PATCH.sh

# Wait for services to stabilize
sleep 10

# Run health checks
check_health() {
    backend_status=$(curl -s http://localhost:8001/health | grep -o "healthy")
    
    if [ "$backend_status" = "healthy" ]; then
        echo "✅ Backend is healthy"
        return 0
    else
        echo "❌ Backend health check failed"
        return 1
    fi
}

# Check with retry
for i in {1..5}; do
    if check_health; then
        echo "🎉 Patch applied successfully and services are healthy!"
        exit 0
    fi
    echo "Retry $i/5..."
    sleep 5
done

echo "❌ Health check failed after 5 retries"
exit 1
```

## Best Practices

1. **Always backup before patching** (the script does this automatically)
2. **Test in development first** before applying to production
3. **Review logs** after applying the patch
4. **Verify both fixes** were applied using the verification section output
5. **Keep backups** for at least 7 days
6. **Document custom changes** if you modify the script
7. **Use version control** to track when patches were applied

## Need Help?

If you encounter issues:

1. Check the logs: `/var/log/supervisor/*.log`
2. Verify backups exist: `ls -la /app/backup_*/`
3. Review the script output for error messages
4. Check GitHub issues: https://github.com/mrolivershea-cyber/FIX-CONNEXXA/issues
5. See MINIFIX_README.md for detailed documentation
