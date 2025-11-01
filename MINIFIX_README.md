# CONNEXA MINI-FIX PATCH

## Overview

This patch script applies two critical fixes to the CONNEXA application:

1. **Backend Fix**: Adds `load_dotenv()` support to `server.py` for proper environment variable handling
2. **Frontend Fix**: Fixes double `/api` path issue in `AuthContext.js`

## Features

- ✅ Idempotent - safe to run multiple times
- ✅ Creates automatic backups before making changes
- ✅ Comprehensive verification and validation
- ✅ Automatic service restart
- ✅ Rollback instructions included
- ✅ Creates missing files if they don't exist

## Prerequisites

- Root/sudo access
- `/app/backend` directory (or will be created)
- `/app/frontend/src/contexts` directory (or will be created)
- `supervisorctl` for service management (optional)

## Installation

### One-Command Install

```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | sudo bash
```

### Manual Install

```bash
# Download the script
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh

# Make executable
chmod +x MINIFIX_PATCH.sh

# Run as root
sudo ./MINIFIX_PATCH.sh
```

## What It Does

### Step 0: Prerequisites Check
- Verifies root access
- Checks/creates required directory structure

### Step 1: Backup
- Creates timestamped backup directory
- Backs up `server.py` and `AuthContext.js`

### Step 2: Backend Fix (load_dotenv)
- Adds `from dotenv import load_dotenv` after line 17 in `server.py`
- Adds `load_dotenv()` call
- Creates basic `server.py` if it doesn't exist

### Step 3: Frontend Fix (Double /api)
- Fixes the API path construction in `AuthContext.js`
- Changes: `const API = ${BACKEND_URL}/api;`
- To: `const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : ${BACKEND_URL}/api;`
- Creates basic `AuthContext.js` if it doesn't exist

### Step 4: Service Restart
- Restarts backend and frontend services via supervisorctl

## Technical Details

### Backend Fix Details

The backend fix adds environment variable support using `python-dotenv`:

```python
# Added after line 17 in server.py
from dotenv import load_dotenv
load_dotenv()
```

This allows the application to read configuration from `.env` files.

### Frontend Fix Details

The frontend fix prevents double `/api` when `BACKEND_URL` already includes it:

**Before:**
```javascript
const API = `${BACKEND_URL}/api`;
// If BACKEND_URL = "http://localhost:8001/api"
// Result: "http://localhost:8001/api/api" ❌
```

**After:**
```javascript
const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;
// If BACKEND_URL = "http://localhost:8001/api"
// Result: "http://localhost:8001/api" ✅
// If BACKEND_URL = "http://localhost:8001"
// Result: "http://localhost:8001/api" ✅
```

## Verification

The script performs automatic verification:

```bash
# Backend check
grep -q "from dotenv import load_dotenv" /app/backend/server.py
grep -q "load_dotenv()" /app/backend/server.py

# Frontend check
grep -q 'BACKEND_URL.endsWith("/api")' /app/frontend/src/contexts/AuthContext.js
```

## Testing

After running the patch:

### Test Backend
```bash
# Check if backend is running
curl http://localhost:8001/health

# Should return:
# {"status": "healthy"}
```

### Test Frontend
```bash
# Check frontend (adjust port as needed)
curl http://localhost:3000

# Or open in browser
```

### Test API Endpoints
```bash
# Test service status
curl http://localhost:8001/api/service/status

# Should not result in /api/api paths
```

## Rollback

If you need to rollback changes:

```bash
# The backup directory path is shown in the output
BACKUP_DIR="/app/backup_YYYYMMDD_HHMMSS"

# Restore backend
cp $BACKUP_DIR/server.py.backup /app/backend/server.py

# Restore frontend
cp $BACKUP_DIR/AuthContext.js.backup /app/frontend/src/contexts/AuthContext.js

# Restart services
supervisorctl restart backend frontend
```

## Troubleshooting

### Script fails with "Permission denied"
```bash
# Make sure you're running as root
sudo ./MINIFIX_PATCH.sh
```

### Backend service won't start
```bash
# Check backend logs
tail -50 /var/log/supervisor/backend.err.log

# Check if port is in use
lsof -i :8001

# Try manual restart
supervisorctl restart backend
```

### Frontend shows API errors
```bash
# Check browser console for errors
# Verify REACT_APP_BACKEND_URL is set correctly
# Check if backend is responding
curl http://localhost:8001/health
```

### Double /api still appearing
```bash
# Verify the fix was applied
grep 'BACKEND_URL.endsWith' /app/frontend/src/contexts/AuthContext.js

# Check environment variable
echo $REACT_APP_BACKEND_URL

# Make sure frontend was rebuilt/restarted
supervisorctl restart frontend
```

## File Locations

- **Patch Script**: `/home/runner/work/FIX-CONNEXXA/FIX-CONNEXXA/MINIFIX_PATCH.sh`
- **Backend**: `/app/backend/server.py`
- **Frontend**: `/app/frontend/src/contexts/AuthContext.js`
- **Backups**: `/app/backup_YYYYMMDD_HHMMSS/`

## Security Considerations

### Backend Security
The generated `server.py` includes security best practices:

- **Host Binding**: Defaults to `127.0.0.1` (localhost) for security. Set `HOST=0.0.0.0` in `.env` only if you need external access.
- **CORS Origins**: Configurable via `ALLOWED_ORIGINS` environment variable (comma-separated). Defaults to `http://localhost:3000,http://localhost:8080`.
- **Environment Variables**: All sensitive configuration should be in `.env` files, never hardcoded.

Example `.env` file:
```bash
PORT=8001
HOST=127.0.0.1
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com
```

### Frontend Security
- The authentication endpoint includes error handling for missing backend endpoints
- Tokens are stored in localStorage (consider upgrading to httpOnly cookies for production)
- API calls include proper error handling

## Dependencies

### Backend
- Python 3.x
- python-dotenv package (install with: `pip install python-dotenv`)
- FastAPI
- uvicorn

### Frontend
- Node.js
- React
- REACT_APP_BACKEND_URL environment variable

## Integration with Existing Scripts

This mini-fix patch can be integrated with other CONNEXA installation scripts:

```bash
# Run after main installation
bash install_connexa_v7_4_6_final_fix.sh
bash MINIFIX_PATCH.sh
```

## Version History

- **v1.0.0** (2024-11-01)
  - Initial release
  - Backend: load_dotenv support
  - Frontend: Double /api fix
  - Automatic backups
  - Service restart

## Support

For issues or questions:
- Repository: https://github.com/mrolivershea-cyber/FIX-CONNEXXA
- Check existing installation scripts for patterns
- Review logs in `/var/log/supervisor/`

## License

This script follows the same license as the FIX-CONNEXXA repository.

## Author

mrolivershea-cyber

## Related Scripts

- `COMPLETE_PATCH.sh` - Complete service manager installation
- `install_connexa_v7_4_6_final_fix.sh` - Full v7.4.6 installation
- `install_service_manager.sh` - Service manager module installation

---

**Note**: This patch is designed to be minimally invasive and only makes the specific changes needed to fix the two identified issues.
