# MINIFIX Quick Start Guide

## One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | sudo bash
```

## What Gets Fixed

| Fix | File | Change |
|-----|------|--------|
| **Backend** | `/app/backend/server.py` | Adds `load_dotenv()` for environment variables |
| **Frontend** | `/app/frontend/src/contexts/AuthContext.js` | Fixes double `/api` in URL paths |

## Before Running

✅ You have root/sudo access
✅ CONNEXA is installed (or directories exist)
✅ You want to fix environment variable loading
✅ You want to fix API path issues

## After Running

✅ Check output for green checkmarks
✅ Verify services are running: `supervisorctl status`
✅ Test API: `curl http://localhost:8001/health`
✅ Backup saved to: `/app/backup_[timestamp]/`

## Rollback

```bash
# Find your backup
BACKUP=$(ls -td /app/backup_*/ | head -1)

# Restore files
sudo cp $BACKUP/server.py.backup /app/backend/server.py
sudo cp $BACKUP/AuthContext.js.backup /app/frontend/src/contexts/AuthContext.js

# Restart
sudo supervisorctl restart backend frontend
```

## Common Issues

### "Permission denied"
```bash
sudo ./MINIFIX_PATCH.sh
```

### "Backend not starting"
```bash
# Check logs
tail -50 /var/log/supervisor/backend.err.log

# Install missing dependency
pip3 install python-dotenv
```

### "Files not found"
Script creates them automatically - this is normal for fresh installs.

## Need More Help?

- 📖 Full docs: [MINIFIX_README.md](./MINIFIX_README.md)
- 💡 Examples: [USAGE_EXAMPLES.md](./USAGE_EXAMPLES.md)
- 🐛 Issues: [GitHub Issues](https://github.com/mrolivershea-cyber/FIX-CONNEXXA/issues)

## Files Created

```
FIX-CONNEXXA/
├── MINIFIX_PATCH.sh      ← Main script
├── MINIFIX_README.md     ← Full documentation
├── USAGE_EXAMPLES.md     ← Usage examples
└── QUICKSTART.md         ← This file
```
