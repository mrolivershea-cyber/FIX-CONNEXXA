# Connexa-Shell

**Complete Shell-based installer and management tools for CONNEXA Admin Panel**

Based on [Connexa-UPGRATE-fix](https://github.com/mrolivershea-cyber/Connexa-UPGRATE-fix)

## Overview

Connexa-Shell provides comprehensive Shell scripts to install and manage the CONNEXA Admin Panel - a powerful VPN node management system with PPTP tunneling, SOCKS proxy support, and automated testing capabilities.

### What is CONNEXA?

CONNEXA is an admin panel for managing VPN nodes (PPTP/SOCKS), featuring:
- 🚀 Automated node testing (ping, speed, connectivity)
- 🔐 PPTP tunnel management
- 🌐 SOCKS proxy server
- 📊 Real-time status monitoring
- 🗄️ SQLite database with web interface
- 📱 React frontend + FastAPI backend

### What is Connexa-Shell?

Connexa-Shell provides:
- ✅ **One-command installation** of the complete CONNEXA stack
- ✅ **Management scripts** for service control
- ✅ **Configuration tools** for easy setup
- ✅ **All in pure Shell** - no manual setup required

## Quick Install

### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh | sudo bash
```

### Manual Installation

```bash
# Download installer
wget https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh

# Make executable
chmod +x connexa-installer.sh

# Run as root
sudo ./connexa-installer.sh
```

## What Gets Installed

The installer will:

1. **System Packages**: Python3, Node.js, Git, Supervisor, PPTP tools, Dante SOCKS server
2. **CONNEXA Application**: Cloned from Connexa-UPGRATE-fix repository
3. **Backend**: FastAPI application with SQLite database
4. **Frontend**: React application
5. **Services**: Configured and started via Supervisor
6. **Configuration**: Auto-generated .env files with secure defaults

### Installation Directory Structure

```
/app/
├── backend/
│   ├── server.py           # FastAPI application
│   ├── database.py         # Database models
│   ├── services.py         # Business logic
│   ├── connexa.db          # SQLite database
│   ├── venv/               # Python virtual environment
│   └── .env                # Configuration
├── frontend/
│   ├── src/                # React source
│   ├── build/              # Production build
│   ├── package.json
│   └── .env                # Frontend config
└── ...
```

## Management Scripts

### 1. connexa-manager.sh - Service Management

Complete service control:

```bash
# Download manager
wget https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-manager.sh
chmod +x connexa-manager.sh

# Start services
sudo ./connexa-manager.sh start

# Stop services
sudo ./connexa-manager.sh stop

# Restart services
sudo ./connexa-manager.sh restart

# Check status
./connexa-manager.sh status

# View logs
./connexa-manager.sh logs backend
./connexa-manager.sh logs frontend
./connexa-manager.sh logs all

# Health check
./connexa-manager.sh health

# Show configuration
./connexa-manager.sh config

# Help
./connexa-manager.sh help
```

### 2. connexa-config.sh - Configuration Tool

Interactive configuration:

```bash
# Download config tool
wget https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-config.sh
chmod +x connexa-config.sh

# Run interactive configuration
sudo ./connexa-config.sh
```

Features:
- Backend configuration (ports, CORS, etc.)
- Frontend configuration (API URLs)
- Database operations (backup, reset password, vacuum)
- Export data to CSV

## Usage

### After Installation

1. **Access the application:**
   - Backend API: http://localhost:8001
   - API Documentation: http://localhost:8001/docs
   - Frontend: http://localhost:3000 (if configured)

2. **Default credentials:**
   - Username: `admin`
   - Password: `admin`

3. **Check status:**
   ```bash
   ./connexa-manager.sh status
   ```

4. **View logs:**
   ```bash
   ./connexa-manager.sh logs backend
   ```

### Managing Services

```bash
# Start everything
sudo ./connexa-manager.sh start

# Stop everything
sudo ./connexa-manager.sh stop

# Restart after config changes
sudo ./connexa-manager.sh restart

# Check if running
./connexa-manager.sh status

# Run health checks
./connexa-manager.sh health
```

### Configuration

#### Backend Configuration

Edit `/app/backend/.env`:

```bash
# Server
PORT=8001
HOST=0.0.0.0
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Database
DATABASE_URL=sqlite:////app/backend/connexa.db

# Security
SECRET_KEY=your-secret-key-here
ACCESS_TOKEN_EXPIRE_MINUTES=30

# PPTP
PPTP_ENABLED=true
PPTP_TIMEOUT=30

# SOCKS
SOCKS_BASE_PORT=1080
SOCKS_ENABLED=true
```

Or use interactive configuration:
```bash
sudo ./connexa-config.sh
```

#### Frontend Configuration

Edit `/app/frontend/.env`:

```bash
REACT_APP_BACKEND_URL=http://localhost:8001
REACT_APP_API_URL=http://localhost:8001/api
```

### Database Management

```bash
# Using the config tool
sudo ./connexa-config.sh
# Select option 3: Database Operations

# Or manually:

# Backup database
cp /app/backend/connexa.db /app/backend/connexa.db.backup

# Reset admin password
sqlite3 /app/backend/connexa.db "UPDATE users SET password_hash='\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/Lew52r7P/gE8p.B6i' WHERE username='admin';"

# Check node count
sqlite3 /app/backend/connexa.db "SELECT COUNT(*) FROM nodes;"

# Export nodes
sqlite3 -header -csv /app/backend/connexa.db "SELECT * FROM nodes;" > nodes.csv
```

## Features

### Installation Script (connexa-installer.sh)

- ✅ **Automated installation** - One command installs everything
- ✅ **Dependency management** - Installs all required packages
- ✅ **PPTP setup** - Creates /dev/ppp device
- ✅ **Database initialization** - Creates schema and admin user
- ✅ **Service configuration** - Sets up Supervisor
- ✅ **Verification** - Tests all components after installation
- ✅ **Backup** - Backs up existing installation
- ✅ **Error handling** - Comprehensive error checking

### Management Script (connexa-manager.sh)

- ✅ **Service control** - Start/stop/restart services
- ✅ **Status monitoring** - Check service and port status
- ✅ **Log viewing** - View backend/frontend logs
- ✅ **Health checks** - Comprehensive system tests
- ✅ **Configuration display** - Show current settings
- ✅ **Process cleanup** - Kill stray processes

### Configuration Tool (connexa-config.sh)

- ✅ **Interactive configuration** - Menu-driven interface
- ✅ **Backend settings** - Port, host, CORS configuration
- ✅ **Frontend settings** - API URL configuration
- ✅ **Database operations** - Backup, reset, export, vacuum
- ✅ **Live reload** - Restart services after changes

## Requirements

- **OS**: Ubuntu/Debian Linux (or similar)
- **Privileges**: Root access required
- **Network**: Internet connection for downloading packages
- **Disk**: At least 2GB free space
- **Memory**: At least 1GB RAM

## Architecture

### Technology Stack

- **Backend**: Python 3 + FastAPI + Uvicorn
- **Frontend**: React + Node.js
- **Database**: SQLite
- **Process Management**: Supervisor
- **VPN**: PPTP + pppd
- **Proxy**: Dante SOCKS server

### Service Architecture

```
┌─────────────────────────────────────────────────┐
│  Supervisor (Process Manager)                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌────────────────┐      ┌──────────────────┐  │
│  │ connexa-backend│      │ connexa-frontend │  │
│  │                │      │                  │  │
│  │ FastAPI:8001   │◄─────┤ React:3000       │  │
│  │                │      │                  │  │
│  └────────┬───────┘      └──────────────────┘  │
│           │                                     │
│           ▼                                     │
│  ┌────────────────┐                            │
│  │ SQLite Database│                            │
│  │ connexa.db     │                            │
│  └────────────────┘                            │
│                                                 │
└─────────────────────────────────────────────────┘
           │
           ▼
    ┌─────────────┐
    │ PPTP Tunnels│
    │ /dev/ppp    │
    └─────────────┘
           │
           ▼
    ┌─────────────┐
    │ SOCKS Proxy │
    │ port 1080+  │
    └─────────────┘
```

## Troubleshooting

### Installation Issues

**Error: "This script must be run as root"**
```bash
sudo ./connexa-installer.sh
```

**Error: "Failed to create /dev/ppp"**
```bash
# Check if running in Docker with proper capabilities
docker run --cap-add=NET_ADMIN your-image
```

**Error: "Port 8001 already in use"**
```bash
# Kill existing process
sudo fuser -k 8001/tcp

# Or change port in /app/backend/.env
```

### Service Issues

**Backend won't start**
```bash
# Check logs
./connexa-manager.sh logs backend

# Common issues:
# 1. Missing dependencies
cd /app/backend
source venv/bin/activate
pip install -r requirements.txt

# 2. Database locked
rm /app/backend/connexa.db-journal

# 3. Port in use
sudo fuser -k 8001/tcp
```

**Frontend won't start**
```bash
# Check logs
./connexa-manager.sh logs frontend

# Rebuild frontend
cd /app/frontend
npm install
npm run build
```

**PPTP not working**
```bash
# Check /dev/ppp
ls -la /dev/ppp

# Recreate if needed
sudo mknod /dev/ppp c 108 0
sudo chmod 600 /dev/ppp

# Check pppd
which pppd

# Install if missing
sudo apt-get install ppp pptp-linux
```

### Database Issues

**Database locked**
```bash
# Stop all services
sudo ./connexa-manager.sh stop

# Remove journal
rm /app/backend/connexa.db-journal

# Restart
sudo ./connexa-manager.sh start
```

**Reset admin password**
```bash
sudo ./connexa-config.sh
# Select option 3 → Reset admin password
```

**Corrupted database**
```bash
# Restore from backup
cp /app/backend/connexa.db.backup /app/backend/connexa.db

# Or reinitialize
rm /app/backend/connexa.db
sudo ./connexa-installer.sh  # Will recreate database
```

## Logs

### Log Locations

- Backend: `/var/log/supervisor/connexa-backend.log`
- Backend errors: `/var/log/supervisor/connexa-backend-error.log`
- Frontend: `/var/log/supervisor/connexa-frontend.log`
- Supervisor: `/var/log/supervisor/supervisord.log`

### Viewing Logs

```bash
# Using manager script
./connexa-manager.sh logs backend
./connexa-manager.sh logs frontend

# Or directly
tail -f /var/log/supervisor/connexa-backend.log
tail -f /var/log/supervisor/connexa-frontend-error.log

# Follow all logs
tail -f /var/log/supervisor/*.log
```

## Updating

### Update CONNEXA Application

```bash
# Backup current installation
sudo cp -r /app /app_backup_$(date +%Y%m%d)

# Pull latest changes
cd /app
sudo git pull origin main

# Update dependencies
cd /app/backend
source venv/bin/activate
pip install -r requirements.txt

cd /app/frontend
npm install
npm run build

# Restart services
sudo ./connexa-manager.sh restart
```

### Update Management Scripts

```bash
# Download latest scripts
wget -O connexa-manager.sh https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-manager.sh
wget -O connexa-config.sh https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-config.sh

chmod +x connexa-manager.sh connexa-config.sh
```

## Uninstallation

```bash
# Stop services
sudo ./connexa-manager.sh stop

# Remove supervisor configs
sudo rm /etc/supervisor/conf.d/connexa-*.conf
sudo supervisorctl reread
sudo supervisorctl update

# Remove application
sudo rm -rf /app

# Optional: Remove packages
sudo apt-get remove --purge ppp pptp-linux dante-server
sudo apt-get autoremove
```

## Security Considerations

### Production Deployment

1. **Change default password**
   ```bash
   sudo ./connexa-config.sh
   # Select: Database Operations → Reset admin password
   ```

2. **Configure firewall**
   ```bash
   # Allow only necessary ports
   sudo ufw allow 8001/tcp  # Backend API
   sudo ufw allow 3000/tcp  # Frontend (if public)
   sudo ufw enable
   ```

3. **Use HTTPS**
   - Set up nginx reverse proxy with SSL
   - Use Let's Encrypt for certificates

4. **Secure CORS**
   ```bash
   # Edit /app/backend/.env
   ALLOWED_ORIGINS=https://yourdomain.com
   ```

5. **Bind to localhost**
   ```bash
   # Edit /app/backend/.env
   HOST=127.0.0.1  # Only accessible via reverse proxy
   ```

## Development

### Running in Development Mode

```bash
# Backend
cd /app/backend
source venv/bin/activate
python -m uvicorn server:app --reload --port 8001

# Frontend
cd /app/frontend
npm start
```

### Making Changes

```bash
# Edit code
cd /app
git checkout -b my-feature

# Make changes
# ...

# Restart to test
sudo ./connexa-manager.sh restart

# View logs
./connexa-manager.sh logs backend
```

## Repository Structure

For Connexa-Shell repository:

```
Connexa-Shell/
├── connexa-installer.sh      # Main installation script
├── connexa-manager.sh         # Service management script
├── connexa-config.sh          # Configuration tool
├── README.md                  # This file
├── LICENSE                    # License file
└── .gitignore                 # Git ignore rules
```

## Support

### Getting Help

1. Check this README
2. View logs: `./connexa-manager.sh logs backend`
3. Run health check: `./connexa-manager.sh health`
4. Check [Connexa-UPGRATE-fix](https://github.com/mrolivershea-cyber/Connexa-UPGRATE-fix) documentation
5. Open an issue on GitHub

### Reporting Bugs

Please include:
- OS version (`cat /etc/os-release`)
- Error messages from logs
- Output of `./connexa-manager.sh health`
- Steps to reproduce

## License

This project follows the same license as Connexa-UPGRATE-fix.

## Credits

- **Based on**: [Connexa-UPGRATE-fix](https://github.com/mrolivershea-cyber/Connexa-UPGRATE-fix)
- **Author**: mrolivershea-cyber
- **Repository**: [Connexa-Shell](https://github.com/mrolivershea-cyber/Connexa-Shell)

## Version History

### v2.0.0 (2024-11-01)
- Complete rewrite in Shell
- Automated installer from Connexa-UPGRATE-fix
- Service management script
- Configuration tool
- Comprehensive documentation

---

**Quick Links:**
- [Install](#quick-install) | [Usage](#usage) | [Management](#management-scripts) | [Troubleshooting](#troubleshooting)
