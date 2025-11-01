# Connexa-Shell Installer

Standalone Shell installer for CONNEXA application fixes.

## Overview

This is a self-contained Shell script that applies critical fixes to the CONNEXA application:

1. **Backend Fix**: Adds `load_dotenv()` for environment variable support in `server.py`
2. **Frontend Fix**: Fixes double `/api` path issue in `AuthContext.js`
3. **Service Management**: Automatically restarts services

## Quick Install

### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash
```

### Download and Review

```bash
# Download the installer
wget https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh

# Make it executable
chmod +x connexa-shell-installer.sh

# Review the script (optional but recommended)
less connexa-shell-installer.sh

# Run the installer
sudo ./connexa-shell-installer.sh
```

## What It Does

### Backend Fix

Adds environment variable loading support to your FastAPI backend:

```python
# Added after line 17 in server.py
from dotenv import load_dotenv
load_dotenv()
```

**Benefits:**
- Load configuration from `.env` files
- Keep secrets out of code
- Easy environment-specific configuration

### Frontend Fix

Prevents double `/api` in URL paths:

```javascript
// Before (Problem)
const API = `${BACKEND_URL}/api`;
// If BACKEND_URL = "http://localhost:8001/api"
// Result: "http://localhost:8001/api/api" ❌

// After (Fixed)
const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;
// Result: "http://localhost:8001/api" ✅
```

**Benefits:**
- No more 404 errors from double `/api`
- Works with any `BACKEND_URL` configuration
- Automatic path normalization

## Features

✅ **Idempotent** - Safe to run multiple times
✅ **Automatic Backups** - Creates timestamped backups before changes
✅ **Self-Contained** - No dependencies on other scripts
✅ **Creates Missing Files** - Generates complete templates if files don't exist
✅ **Security Hardened** - Includes security best practices
✅ **Comprehensive Verification** - Validates all changes after application
✅ **Colored Output** - Clear, easy-to-read progress indicators

## Requirements

- Root/sudo access
- Linux/Unix system with bash
- (Optional) `supervisorctl` for automatic service restart

The script will create directories if they don't exist:
- `/app/backend`
- `/app/frontend/src/contexts`

## Installation Output

```
════════════════════════════════════════════════════════════════
  CONNEXA Shell Installer v1.0.0
  Date: 2024-11-01 12:00:00
  Fixes: load_dotenv + AuthContext double /api
════════════════════════════════════════════════════════════════

📦 [Step 0/4] Checking prerequisites...
✅ Prerequisites checked

📦 [Step 1/4] Creating backups...
✅ Backed up server.py
✅ Backups saved to: /app/backup_20241101_120000

📦 [Step 2/4] Applying Fix 1: load_dotenv in server.py...
✅ Added load_dotenv import and call to server.py

📦 [Step 3/4] Applying Fix 2: Double /api fix in AuthContext.js...
✅ Fixed double /api issue in AuthContext.js

📦 [Step 4/4] Restarting services...
✅ Services restarted

🎉 ALL FIXES APPLIED SUCCESSFULLY! 🎉
```

## Configuration

After installation, configure your backend by creating `/app/backend/.env`:

```bash
# Server configuration
PORT=8001
HOST=127.0.0.1

# Security - CORS allowed origins (comma-separated)
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com

# Database
DATABASE_URL=sqlite:///connexa.db

# Other settings
SECRET_KEY=your-secret-key-here
```

### Security Recommendations

1. **Host Binding**: Defaults to `127.0.0.1` (localhost)
   - Only set `HOST=0.0.0.0` if you need external access
   - Use a reverse proxy (nginx/Apache) for production

2. **CORS Origins**: Configure specific domains
   - Never use `*` in production
   - List only domains you control

3. **Secret Management**:
   ```bash
   # Generate a strong secret key
   python3 -c "import secrets; print(secrets.token_urlsafe(32))"
   ```

## Verification

After running the installer, verify the fixes:

### Check Backend

```bash
# Verify fix is applied
grep -n "load_dotenv" /app/backend/server.py

# Test the API
curl http://localhost:8001/health
# Expected: {"status":"healthy"}
```

### Check Frontend

```bash
# Verify fix is applied
grep "BACKEND_URL.endsWith" /app/frontend/src/contexts/AuthContext.js

# Check in browser console - no /api/api paths should appear
```

### Check Services

```bash
supervisorctl status
# or
supervisorctl status backend
supervisorctl status frontend
```

## Rollback

If you need to undo the changes:

```bash
# Find your backup (shown in installer output)
BACKUP=/app/backup_YYYYMMDD_HHMMSS

# Restore backend
sudo cp $BACKUP/server.py.backup /app/backend/server.py

# Restore frontend
sudo cp $BACKUP/AuthContext.js.backup /app/frontend/src/contexts/AuthContext.js

# Restart services
sudo supervisorctl restart backend frontend
```

## Troubleshooting

### "Permission denied"

```bash
# Solution: Run with sudo
sudo ./connexa-shell-installer.sh
```

### "Backend service not found"

The installer works without supervisorctl but won't restart services automatically.

**Manual restart:**
```bash
# If using systemd
sudo systemctl restart connexa-backend
sudo systemctl restart connexa-frontend

# If using docker
docker restart connexa-backend
docker restart connexa-frontend

# If running directly
pkill -f "uvicorn.*server:app"
cd /app/backend && python3 server.py &
```

### Backend won't start

```bash
# Check logs
tail -50 /var/log/supervisor/backend.err.log

# Common issue: Missing python-dotenv
pip3 install python-dotenv

# Restart
supervisorctl restart backend
```

### API still shows /api/api

```bash
# Frontend might need rebuild
cd /app/frontend
npm run build

# Or restart dev server
npm start
```

## Technical Details

### What Files Are Modified

| File | Location | Modification |
|------|----------|-------------|
| `server.py` | `/app/backend/` | Adds `load_dotenv()` after line 17 |
| `AuthContext.js` | `/app/frontend/src/contexts/` | Fixes API path construction |

### Implementation Methods

**Backend Fix:**
```bash
sed -i '17a from dotenv import load_dotenv' server.py
sed -i '18a load_dotenv()' server.py
```

**Frontend Fix:**
```bash
sed -i 's|const API = `${BACKEND_URL}/api`;|const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;|g' AuthContext.js
```

### Idempotency

The script checks if fixes are already applied before making changes:

```bash
# Backend check
if grep -q "from dotenv import load_dotenv" server.py; then
    echo "Already applied"
fi

# Frontend check
if grep -q 'BACKEND_URL.endsWith("/api")' AuthContext.js; then
    echo "Already applied"
fi
```

## Integration Examples

### With Docker

```dockerfile
# In your Dockerfile
RUN curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | bash
```

### With Ansible

```yaml
- name: Apply CONNEXA fixes
  shell: |
    curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | bash
  become: yes
```

### With Terraform

```hcl
resource "null_resource" "connexa_fixes" {
  provisioner "remote-exec" {
    inline = [
      "curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-shell-installer.sh | sudo bash"
    ]
  }
}
```

## Repository Structure

When used in the `Connexa-Shell` repository:

```
Connexa-Shell/
├── connexa-shell-installer.sh    # Main installer script
├── README.md                      # This file
├── LICENSE                        # License file
└── .gitignore                     # Git ignore file
```

## Version History

### v1.0.0 (2024-11-01)
- Initial release
- Backend: `load_dotenv()` support
- Frontend: Double `/api` fix
- Automatic backups
- Service restart
- Security hardening
- Comprehensive verification

## Support

### Documentation
- **Full Documentation**: [FIX-CONNEXXA Repository](https://github.com/mrolivershea-cyber/FIX-CONNEXXA)
- **Source Code**: This repository
- **Issues**: [Report Issues](https://github.com/mrolivershea-cyber/Connexa-Shell/issues)

### Getting Help

1. Check this README first
2. Review the [FIX-CONNEXXA documentation](https://github.com/mrolivershea-cyber/FIX-CONNEXXA)
3. Open an issue with:
   - Your operating system
   - Error messages
   - Steps to reproduce

## License

This project follows the same license as the main CONNEXA project.

## Author

**mrolivershea-cyber**

- GitHub: [@mrolivershea-cyber](https://github.com/mrolivershea-cyber)
- Main Project: [FIX-CONNEXXA](https://github.com/mrolivershea-cyber/FIX-CONNEXXA)

## Related Projects

- **FIX-CONNEXXA**: Complete documentation and additional scripts
- **Connexa-UPGRATE-fix**: Original upgrade fixes

---

**Note**: This is a standalone installer. For additional installation scripts and comprehensive documentation, see the [FIX-CONNEXXA repository](https://github.com/mrolivershea-cyber/FIX-CONNEXXA).
