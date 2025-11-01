# Connexa-Shell Package Manifest

## Overview

Complete Shell-based solution for installing and managing CONNEXA Admin Panel from the Connexa-UPGRATE-fix repository.

## Package Contents

### 1. connexa-installer.sh (14.5 KB, 456 lines)

**Purpose**: Automated installer that downloads and installs the complete CONNEXA stack

**Features**:
- Downloads from Connexa-UPGRATE-fix repository
- Installs all system dependencies (Python, Node.js, PPTP, SOCKS, etc.)
- Sets up backend (FastAPI) and frontend (React)
- Initializes database with default admin user
- Configures Supervisor for service management
- Creates configuration files (.env)
- Runs comprehensive verification tests
- Creates backups of existing installations

**Installation Steps** (12 steps):
1. Root access check
2. System packages installation
3. PPTP setup (/dev/ppp)
4. Clone repository from GitHub
5. Backend Python dependencies
6. Frontend Node.js dependencies
7. Database initialization
8. Configuration files
9. Supervisor setup
10. Download management scripts
11. Start services
12. Verification

**Usage**:
```bash
# One-line install
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh | sudo bash

# Or manual
wget https://... && chmod +x connexa-installer.sh && sudo ./connexa-installer.sh
```

### 2. connexa-manager.sh (11.5 KB, 437 lines)

**Purpose**: Complete service management tool

**Commands**:
- `start` - Start all services
- `stop` - Stop all services
- `restart` - Restart all services
- `status` - Show detailed status (processes, ports, database)
- `logs [backend|frontend|all] [lines]` - View logs
- `health` - Run comprehensive health checks (5 tests)
- `config` - Display current configuration
- `help` - Show usage information

**Features**:
- Color-coded output
- Service control via Supervisor
- Port status checking
- Database statistics
- Log viewing
- Health checks (process, API, database, PPTP, disk space)
- Configuration display (hides secrets)
- Process cleanup

**Usage**:
```bash
sudo ./connexa-manager.sh start
./connexa-manager.sh status
./connexa-manager.sh logs backend 100
./connexa-manager.sh health
```

### 3. connexa-config.sh (10.4 KB, 370 lines)

**Purpose**: Interactive configuration tool

**Features**:
- Menu-driven interface
- Backend configuration (port, host, CORS origins)
- Frontend configuration (API URLs)
- Database operations:
  - Backup database
  - Reset admin password
  - Clear all nodes
  - Vacuum database
  - Export nodes to CSV
- Live service restart after changes
- Configuration viewing

**Usage**:
```bash
sudo ./connexa-config.sh
# Interactive menu appears
```

### 4. CONNEXA_SHELL_COMPLETE_README.md (14.2 KB)

**Purpose**: Comprehensive documentation

**Sections**:
- Overview and features
- Quick installation guide
- Directory structure
- Management scripts documentation
- Usage examples
- Configuration instructions
- Database management
- Troubleshooting guide
- Log locations
- Update procedures
- Uninstallation
- Security considerations
- Development guide
- Support information

## Installation Flow

```
┌─────────────────────────────────────────┐
│  connexa-installer.sh                   │
│  (One-time installation)                │
└──────────────┬──────────────────────────┘
               │
               ├─► Install system packages
               ├─► Clone Connexa-UPGRATE-fix
               ├─► Setup Python environment
               ├─► Setup Node.js environment
               ├─► Initialize database
               ├─► Create config files
               ├─► Configure Supervisor
               └─► Start services
                    │
                    ▼
          ┌──────────────────────┐
          │  CONNEXA Running     │
          └──────────┬───────────┘
                     │
      ┌──────────────┼──────────────┐
      │              │              │
      ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│ manager  │  │ config   │  │  logs    │
│ (control)│  │ (setup)  │  │ (debug)  │
└──────────┘  └──────────┘  └──────────┘
```

## Repository Setup

### For Connexa-Shell Repository

Create repository with these files:

```
Connexa-Shell/
├── README.md                     (rename from CONNEXA_SHELL_COMPLETE_README.md)
├── connexa-installer.sh          (main installer)
├── connexa-manager.sh            (service manager)
├── connexa-config.sh             (config tool)
├── .gitignore                    (from CONNEXA_SHELL_GITIGNORE)
└── LICENSE                       (add appropriate license)
```

### Quick Setup Commands

```bash
# Create directory
mkdir -p /tmp/connexa-shell && cd /tmp/connexa-shell

# Initialize git
git init && git branch -M main

# Copy files from FIX-CONNEXXA
cp /path/to/FIX-CONNEXXA/connexa-installer.sh .
cp /path/to/FIX-CONNEXXA/connexa-manager.sh .
cp /path/to/FIX-CONNEXXA/connexa-config.sh .
cp /path/to/FIX-CONNEXXA/CONNEXA_SHELL_COMPLETE_README.md README.md
cp /path/to/FIX-CONNEXXA/CONNEXA_SHELL_GITIGNORE .gitignore

# Ensure executables
chmod +x connexa-installer.sh connexa-manager.sh connexa-config.sh

# Commit
git add .
git commit -m "Initial commit: Shell-based CONNEXA installer and management tools v2.0.0"

# Push to GitHub
git remote add origin https://github.com/mrolivershea-cyber/Connexa-Shell.git
git push -u origin main
```

## Technical Details

### What Gets Installed

From **Connexa-UPGRATE-fix** repository:
- Backend: FastAPI application (5356 lines of Python)
- Frontend: React application
- Database: SQLite with predefined schema
- Services: PPTP tunnel manager, SOCKS proxy server
- Test files: Comprehensive testing suite

System packages:
- Python 3 + pip + venv
- Node.js + npm
- Git, curl, wget
- Supervisor (process manager)
- ppp + pptp-linux (PPTP support)
- dante-server (SOCKS proxy)
- SQLite
- Nginx

### Default Configuration

**Backend** (`/app/backend/.env`):
- PORT=8001
- HOST=0.0.0.0
- ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
- DATABASE_URL=sqlite:////app/backend/connexa.db
- SECRET_KEY=(auto-generated)

**Frontend** (`/app/frontend/.env`):
- REACT_APP_BACKEND_URL=http://localhost:8001
- REACT_APP_API_URL=http://localhost:8001/api

**Database**:
- Location: /app/backend/connexa.db
- Default user: admin / admin
- Tables: users, nodes

### Service Management

**Supervisor configs**:
- `/etc/supervisor/conf.d/connexa-backend.conf`
- `/etc/supervisor/conf.d/connexa-frontend.conf`

**Commands**:
```bash
supervisorctl start connexa-backend
supervisorctl stop connexa-backend
supervisorctl restart connexa-backend
supervisorctl status connexa-backend
```

## File Statistics

| File | Size | Lines | Type |
|------|------|-------|------|
| connexa-installer.sh | 14.5 KB | 456 | Shell script |
| connexa-manager.sh | 11.5 KB | 437 | Shell script |
| connexa-config.sh | 10.4 KB | 370 | Shell script |
| CONNEXA_SHELL_COMPLETE_README.md | 14.2 KB | 582 | Documentation |
| **Total** | **50.6 KB** | **1,845** | - |

## Comparison with Original

### Original MINIFIX Approach
- Focus: Two specific fixes (load_dotenv, double /api)
- Size: 16 KB installer
- Purpose: Patch existing installation

### New Connexa-Shell Approach
- Focus: Complete installation and management
- Size: 50.6 KB (3 scripts + docs)
- Purpose: Install from scratch + full lifecycle management
- Based on: Connexa-UPGRATE-fix (complete application)

## Testing

### Installer Validation
```bash
# Syntax check
bash -n connexa-installer.sh

# Dry-run (requires root)
sudo bash -x connexa-installer.sh 2>&1 | tee install.log
```

### Manager Validation
```bash
# Syntax check
bash -n connexa-manager.sh

# Test commands
./connexa-manager.sh help
./connexa-manager.sh status  # (no root required)
sudo ./connexa-manager.sh health
```

### Config Validation
```bash
# Syntax check
bash -n connexa-config.sh

# Test (interactive)
sudo ./connexa-config.sh
```

## Version History

### v2.0.0 (2024-11-01)
- Complete Shell-based solution
- Installer from Connexa-UPGRATE-fix
- Service manager script
- Configuration tool
- Comprehensive documentation
- Based on user requirements from FIX-CONNEXXA PR

## Support

**Related Repositories**:
- Connexa-Shell: Installation and management scripts
- Connexa-UPGRATE-fix: Source application
- FIX-CONNEXXA: Development and patches

**Documentation**:
- README.md: Complete user guide
- This file: Package manifest and technical details

---

**Status**: ✅ Ready for deployment to Connexa-Shell repository
**Version**: 2.0.0
**Date**: 2024-11-01
**Author**: @copilot for @mrolivershea-cyber
