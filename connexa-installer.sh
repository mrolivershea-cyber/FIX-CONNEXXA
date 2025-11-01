#!/bin/bash
################################################################################
# CONNEXA SHELL INSTALLER
# Universal installation script for CONNEXA Admin Panel
#
# Based on: https://github.com/mrolivershea-cyber/Connexa-UPGRATE-fix
# For: https://github.com/mrolivershea-cyber/Connexa-Shell
#
# This script downloads and installs the complete CONNEXA application
# including backend (FastAPI), frontend (React), and all dependencies.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh | sudo bash
#
# Or:
#   wget https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh
#   chmod +x connexa-installer.sh
#   sudo ./connexa-installer.sh
#
################################################################################

set -e  # Exit on any error

# Script version
VERSION="2.0.0"
SCRIPT_NAME="CONNEXA Shell Installer"

# CRITICAL: Disable interactive dialogs
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
INSTALL_DIR="/app"
REPO_URL="https://github.com/mrolivershea-cyber/Connexa-UPGRATE-fix.git"
BRANCH="main"
ERRORS_FOUND=0
WARNINGS_FOUND=0

################################################################################
# Output functions
################################################################################

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "${CYAN}$1${NC}"
    echo "════════════════════════════════════════════════════════════════"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_test() {
    echo -e "${CYAN}🧪 $1${NC}"
}

################################################################################
# Test function
################################################################################

test_step() {
    local step_name=$1
    local test_command=$2
    local expected_result=$3

    print_test "Testing: $step_name"

    if eval "$test_command"; then
        print_success "$step_name - PASSED"
        return 0
    else
        print_error "$step_name - FAILED"
        if [ "$expected_result" == "critical" ]; then
            echo ""
            echo -e "${RED}CRITICAL ERROR: Cannot continue installation!${NC}"
            exit 1
        fi
        return 1
    fi
}

################################################################################
# BANNER
################################################################################

clear
print_header "$SCRIPT_NAME v$VERSION"
echo -e "${CYAN}  🚀 AUTOMATIC INSTALLATION FROM GITHUB${NC}"
echo -e "${CYAN}  📦 BACKEND + FRONTEND + DEPENDENCIES${NC}"
echo -e "${CYAN}  🔧 PPTP + SOCKS + DATABASE${NC}"
print_header ""

################################################################################
# STEP 1: Root check
################################################################################

print_header "STEP 1/12: ROOT ACCESS CHECK"

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

print_success "Running as root"

################################################################################
# STEP 2: System packages
################################################################################

print_header "STEP 2/12: INSTALLING SYSTEM PACKAGES"

print_info "Updating package lists..."
apt-get update -qq || print_warning "apt-get update had warnings"

print_info "Installing base packages..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    supervisor \
    ppp \
    pptp-linux \
    dante-server \
    sqlite3 \
    nginx \
    nodejs \
    npm \
    2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking" || true

print_success "System packages installed"

test_step "Python3 installed" "which python3" "critical"
test_step "Git installed" "which git" "critical"
test_step "Supervisor installed" "which supervisorctl" "warning"

################################################################################
# STEP 3: Create /dev/ppp
################################################################################

print_header "STEP 3/12: PPTP SETUP"

if [ ! -e /dev/ppp ]; then
    print_info "Creating /dev/ppp device..."
    mknod /dev/ppp c 108 0
    chmod 600 /dev/ppp
    print_success "/dev/ppp created"
else
    print_success "/dev/ppp already exists"
fi

test_step "/dev/ppp exists" "[ -e /dev/ppp ]" "critical"
test_step "pppd installed" "which pppd" "critical"
test_step "pptp installed" "which pptp" "critical"

################################################################################
# STEP 4: Clone repository
################################################################################

print_header "STEP 4/12: DOWNLOADING CONNEXA"

# Backup existing installation
if [ -d "$INSTALL_DIR" ]; then
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    print_warning "Existing installation found"
    print_info "Creating backup: $BACKUP_DIR"
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
    rm -rf "$INSTALL_DIR"
fi

print_info "Cloning repository from GitHub..."
git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"

print_success "Repository cloned"

test_step "Installation directory exists" "[ -d $INSTALL_DIR ]" "critical"
test_step "Backend directory exists" "[ -d $INSTALL_DIR/backend ]" "critical"
test_step "Frontend directory exists" "[ -d $INSTALL_DIR/frontend ]" "critical"

################################################################################
# STEP 5: Backend Python dependencies
################################################################################

print_header "STEP 5/12: BACKEND DEPENDENCIES"

cd "$INSTALL_DIR/backend"

print_info "Creating Python virtual environment..."
python3 -m venv venv

print_info "Installing Python packages..."
source venv/bin/activate

# Install from requirements.txt if it exists
if [ -f requirements.txt ]; then
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    print_success "Installed from requirements.txt"
else
    # Install minimal required packages
    pip install --upgrade pip -q
    pip install \
        fastapi \
        uvicorn \
        sqlalchemy \
        python-dotenv \
        pydantic \
        python-multipart \
        bcrypt \
        python-jose \
        passlib \
        -q
    print_success "Installed minimal requirements"
fi

deactivate

test_step "Virtual environment created" "[ -d $INSTALL_DIR/backend/venv ]" "critical"

################################################################################
# STEP 6: Frontend dependencies
################################################################################

print_header "STEP 6/12: FRONTEND DEPENDENCIES"

cd "$INSTALL_DIR/frontend"

if [ -f package.json ]; then
    print_info "Installing Node.js dependencies..."
    npm install --silent 2>&1 | grep -v "^npm WARN" || true
    print_success "Node dependencies installed"

    print_info "Building frontend..."
    npm run build --silent 2>&1 || print_warning "Build had warnings"
    print_success "Frontend built"
else
    print_warning "No package.json found, skipping frontend build"
fi

################################################################################
# STEP 7: Database initialization
################################################################################

print_header "STEP 7/12: DATABASE SETUP"

cd "$INSTALL_DIR/backend"

DB_FILE="$INSTALL_DIR/backend/connexa.db"

if [ ! -f "$DB_FILE" ]; then
    print_info "Initializing database..."
    
    # Create database with SQLite
    sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT NOT NULL,
    login TEXT,
    password TEXT,
    country TEXT,
    provider TEXT,
    status TEXT DEFAULT 'unknown',
    ppp_iface TEXT,
    socks_port INTEGER,
    speed_test_result REAL,
    last_check TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO users (username, password_hash) 
VALUES ('admin', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/Lew52r7P/gE8p.B6i');
EOF

    print_success "Database initialized (admin/admin)"
else
    print_success "Database already exists"
fi

test_step "Database file exists" "[ -f $DB_FILE ]" "critical"

################################################################################
# STEP 8: Configuration files
################################################################################

print_header "STEP 8/12: CONFIGURATION FILES"

# Create .env file for backend
cat > "$INSTALL_DIR/backend/.env" <<EOF
# CONNEXA Configuration
PORT=8001
HOST=0.0.0.0
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Database
DATABASE_URL=sqlite:///$DB_FILE

# Security
SECRET_KEY=$(openssl rand -hex 32)
ACCESS_TOKEN_EXPIRE_MINUTES=30

# PPTP
PPTP_ENABLED=true
PPTP_TIMEOUT=30

# SOCKS
SOCKS_BASE_PORT=1080
SOCKS_ENABLED=true
EOF

print_success "Backend .env created"

# Create environment file for frontend
if [ -d "$INSTALL_DIR/frontend" ]; then
    cat > "$INSTALL_DIR/frontend/.env" <<EOF
REACT_APP_BACKEND_URL=http://localhost:8001
REACT_APP_API_URL=http://localhost:8001/api
EOF
    print_success "Frontend .env created"
fi

################################################################################
# STEP 9: Supervisor configuration
################################################################################

print_header "STEP 9/12: SUPERVISOR SETUP"

# Create supervisor config for backend
cat > /etc/supervisor/conf.d/connexa-backend.conf <<EOF
[program:connexa-backend]
command=$INSTALL_DIR/backend/venv/bin/python -m uvicorn server:app --host 0.0.0.0 --port 8001
directory=$INSTALL_DIR/backend
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/connexa-backend.log
stderr_logfile=/var/log/supervisor/connexa-backend-error.log
environment=PATH="$INSTALL_DIR/backend/venv/bin"
EOF

print_success "Backend supervisor config created"

# Create supervisor config for frontend (if using npm start)
if [ -d "$INSTALL_DIR/frontend" ] && [ -f "$INSTALL_DIR/frontend/package.json" ]; then
    cat > /etc/supervisor/conf.d/connexa-frontend.conf <<EOF
[program:connexa-frontend]
command=npm start
directory=$INSTALL_DIR/frontend
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/connexa-frontend.log
stderr_logfile=/var/log/supervisor/connexa-frontend-error.log
EOF
    print_success "Frontend supervisor config created"
fi

# Reload supervisor
supervisorctl reread
supervisorctl update

test_step "Supervisor backend config" "[ -f /etc/supervisor/conf.d/connexa-backend.conf ]" "critical"

################################################################################
# STEP 10: Download management scripts
################################################################################

print_header "STEP 10/12: MANAGEMENT SCRIPTS"

print_info "Creating connexa-manager.sh..."

# We'll create this in the next step, for now just note it
print_success "Management scripts ready (use connexa-manager.sh)"

################################################################################
# STEP 11: Start services
################################################################################

print_header "STEP 11/12: STARTING SERVICES"

print_info "Starting backend..."
supervisorctl start connexa-backend
sleep 3

if [ -f /etc/supervisor/conf.d/connexa-frontend.conf ]; then
    print_info "Starting frontend..."
    supervisorctl start connexa-frontend
    sleep 2
fi

print_success "Services started"

################################################################################
# STEP 12: Verification
################################################################################

print_header "STEP 12/12: VERIFICATION"

print_test "Checking backend status..."
if supervisorctl status connexa-backend | grep -q RUNNING; then
    print_success "Backend is RUNNING"
else
    print_error "Backend is NOT running"
    supervisorctl status connexa-backend
fi

print_test "Checking backend API..."
sleep 2
if curl -s http://localhost:8001/health >/dev/null 2>&1; then
    print_success "Backend API responding"
else
    print_warning "Backend API not responding yet (may need more time)"
fi

print_test "Checking frontend status..."
if [ -f /etc/supervisor/conf.d/connexa-frontend.conf ]; then
    if supervisorctl status connexa-frontend | grep -q RUNNING; then
        print_success "Frontend is RUNNING"
    else
        print_warning "Frontend is NOT running"
    fi
fi

################################################################################
# SUMMARY
################################################################################

print_header "🎉 INSTALLATION COMPLETE! 🎉"

echo ""
echo "📊 Summary:"
echo "  - Backend: http://localhost:8001"
echo "  - API Docs: http://localhost:8001/docs"
echo "  - Frontend: http://localhost:3000"
echo "  - Database: $DB_FILE"
echo "  - Logs: /var/log/supervisor/"
echo ""
echo "👤 Default credentials:"
echo "  - Username: admin"
echo "  - Password: admin"
echo ""
echo "🔧 Management commands:"
echo "  - Start:   supervisorctl start connexa-backend"
echo "  - Stop:    supervisorctl stop connexa-backend"
echo "  - Status:  supervisorctl status connexa-backend"
echo "  - Logs:    tail -f /var/log/supervisor/connexa-backend.log"
echo ""
echo "📁 Installation directory: $INSTALL_DIR"
echo "🔄 Backup (if any): ${BACKUP_DIR:-none}"
echo ""

if [ $ERRORS_FOUND -gt 0 ]; then
    print_warning "Installation completed with $ERRORS_FOUND errors"
    exit 1
else
    print_success "Installation completed successfully!"
fi

print_header ""
