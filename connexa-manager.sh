#!/bin/bash
################################################################################
# CONNEXA SERVICE MANAGER
# Shell-based service management for CONNEXA Admin Panel
#
# Repository: https://github.com/mrolivershea-cyber/Connexa-Shell
#
# This script provides comprehensive service management:
#   - Start/Stop/Restart services
#   - Check status
#   - View logs
#   - Configuration management
#   - Health checks
#
# Usage:
#   ./connexa-manager.sh [command] [options]
#
# Commands:
#   start           Start all services
#   stop            Stop all services
#   restart         Restart all services
#   status          Show service status
#   logs            View logs
#   health          Run health checks
#   config          Show configuration
#   help            Show this help
#
################################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/app"
BACKEND_LOG="/var/log/supervisor/connexa-backend.log"
FRONTEND_LOG="/var/log/supervisor/connexa-frontend.log"

################################################################################
# Helper functions
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
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This command requires root privileges"
        echo "Please run: sudo $0 $@"
        exit 1
    fi
}

################################################################################
# Service control functions
################################################################################

start_services() {
    print_header "STARTING CONNEXA SERVICES"
    
    check_root
    
    print_info "Starting backend..."
    if supervisorctl start connexa-backend 2>/dev/null; then
        print_success "Backend started"
    else
        print_error "Failed to start backend"
        print_info "Try: supervisorctl status connexa-backend"
    fi
    
    print_info "Starting frontend..."
    if supervisorctl start connexa-frontend 2>/dev/null; then
        print_success "Frontend started"
    else
        print_warning "Frontend not configured or failed to start"
    fi
    
    sleep 2
    show_status
}

stop_services() {
    print_header "STOPPING CONNEXA SERVICES"
    
    check_root
    
    print_info "Stopping backend..."
    if supervisorctl stop connexa-backend 2>/dev/null; then
        print_success "Backend stopped"
    else
        print_warning "Backend stop failed or not running"
    fi
    
    print_info "Stopping frontend..."
    if supervisorctl stop connexa-frontend 2>/dev/null; then
        print_success "Frontend stopped"
    else
        print_warning "Frontend not configured or already stopped"
    fi
    
    # Also kill any stray processes
    print_info "Cleaning up stray processes..."
    pkill -f "uvicorn.*connexa" 2>/dev/null || true
    pkill -f "npm.*start.*frontend" 2>/dev/null || true
    
    print_success "Services stopped"
}

restart_services() {
    print_header "RESTARTING CONNEXA SERVICES"
    
    check_root
    
    stop_services
    sleep 2
    start_services
}

show_status() {
    print_header "CONNEXA SERVICE STATUS"
    
    echo ""
    echo "📊 Supervisor Status:"
    echo "─────────────────────"
    supervisorctl status connexa-backend 2>/dev/null || echo "Backend: Not configured"
    supervisorctl status connexa-frontend 2>/dev/null || echo "Frontend: Not configured"
    
    echo ""
    echo "🔌 Port Status:"
    echo "─────────────────────"
    
    # Check backend port
    if ss -lntp 2>/dev/null | grep -q ":8001"; then
        print_success "Backend port 8001: LISTENING"
    else
        print_warning "Backend port 8001: NOT LISTENING"
    fi
    
    # Check frontend port
    if ss -lntp 2>/dev/null | grep -q ":3000"; then
        print_success "Frontend port 3000: LISTENING"
    else
        print_info "Frontend port 3000: NOT LISTENING"
    fi
    
    echo ""
    echo "💾 Database:"
    echo "─────────────────────"
    
    if [ -f "$INSTALL_DIR/backend/connexa.db" ]; then
        DB_SIZE=$(du -h "$INSTALL_DIR/backend/connexa.db" | cut -f1)
        print_success "Database exists: $DB_SIZE"
        
        # Count nodes
        NODE_COUNT=$(sqlite3 "$INSTALL_DIR/backend/connexa.db" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        echo "  Nodes in database: $NODE_COUNT"
    else
        print_warning "Database not found"
    fi
    
    echo ""
}

show_logs() {
    local service=${1:-backend}
    local lines=${2:-50}
    
    print_header "CONNEXA LOGS - $service"
    
    case $service in
        backend)
            if [ -f "$BACKEND_LOG" ]; then
                echo ""
                echo "Last $lines lines of backend log:"
                echo "─────────────────────────────────"
                tail -n "$lines" "$BACKEND_LOG"
            else
                print_error "Backend log not found: $BACKEND_LOG"
            fi
            ;;
        frontend)
            if [ -f "$FRONTEND_LOG" ]; then
                echo ""
                echo "Last $lines lines of frontend log:"
                echo "─────────────────────────────────"
                tail -n "$lines" "$FRONTEND_LOG"
            else
                print_error "Frontend log not found: $FRONTEND_LOG"
            fi
            ;;
        all)
            show_logs backend "$lines"
            echo ""
            show_logs frontend "$lines"
            ;;
        *)
            print_error "Unknown service: $service"
            print_info "Available: backend, frontend, all"
            ;;
    esac
}

run_health_check() {
    print_header "CONNEXA HEALTH CHECK"
    
    local healthy=0
    local total=0
    
    # Check 1: Backend process
    total=$((total + 1))
    echo ""
    echo "Test 1/5: Backend process"
    if supervisorctl status connexa-backend 2>/dev/null | grep -q RUNNING; then
        print_success "Backend process is running"
        healthy=$((healthy + 1))
    else
        print_error "Backend process is not running"
    fi
    
    # Check 2: Backend API
    total=$((total + 1))
    echo ""
    echo "Test 2/5: Backend API"
    if curl -s http://localhost:8001/health >/dev/null 2>&1; then
        print_success "Backend API is responding"
        healthy=$((healthy + 1))
    else
        print_error "Backend API is not responding"
    fi
    
    # Check 3: Database
    total=$((total + 1))
    echo ""
    echo "Test 3/5: Database"
    if [ -f "$INSTALL_DIR/backend/connexa.db" ]; then
        if sqlite3 "$INSTALL_DIR/backend/connexa.db" "SELECT 1;" >/dev/null 2>&1; then
            print_success "Database is accessible"
            healthy=$((healthy + 1))
        else
            print_error "Database exists but is not accessible"
        fi
    else
        print_error "Database file not found"
    fi
    
    # Check 4: PPTP setup
    total=$((total + 1))
    echo ""
    echo "Test 4/5: PPTP setup"
    if [ -e /dev/ppp ]; then
        print_success "/dev/ppp exists"
        healthy=$((healthy + 1))
    else
        print_warning "/dev/ppp not found (PPTP may not work)"
    fi
    
    # Check 5: Disk space
    total=$((total + 1))
    echo ""
    echo "Test 5/5: Disk space"
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -lt 90 ]; then
        print_success "Disk usage: ${DISK_USAGE}%"
        healthy=$((healthy + 1))
    else
        print_warning "Disk usage high: ${DISK_USAGE}%"
    fi
    
    # Summary
    echo ""
    print_header "HEALTH CHECK SUMMARY"
    echo ""
    echo "Tests passed: $healthy/$total"
    
    if [ $healthy -eq $total ]; then
        print_success "All health checks passed!"
        return 0
    elif [ $healthy -gt 0 ]; then
        print_warning "Some health checks failed"
        return 1
    else
        print_error "All health checks failed"
        return 2
    fi
}

show_config() {
    print_header "CONNEXA CONFIGURATION"
    
    echo ""
    echo "📁 Installation:"
    echo "─────────────────────"
    echo "  Directory: $INSTALL_DIR"
    echo "  Backend:   $INSTALL_DIR/backend"
    echo "  Frontend:  $INSTALL_DIR/frontend"
    echo "  Database:  $INSTALL_DIR/backend/connexa.db"
    
    echo ""
    echo "🔧 Backend Configuration:"
    echo "─────────────────────"
    if [ -f "$INSTALL_DIR/backend/.env" ]; then
        # Show non-sensitive config
        grep -v "SECRET_KEY\|PASSWORD\|password" "$INSTALL_DIR/backend/.env" | grep -v "^#" | grep -v "^$"
    else
        print_warning "Backend .env not found"
    fi
    
    echo ""
    echo "🌐 Frontend Configuration:"
    echo "─────────────────────"
    if [ -f "$INSTALL_DIR/frontend/.env" ]; then
        cat "$INSTALL_DIR/frontend/.env" | grep -v "^#" | grep -v "^$"
    else
        print_warning "Frontend .env not found"
    fi
    
    echo ""
    echo "👥 Supervisor Configuration:"
    echo "─────────────────────"
    echo "  Backend:  /etc/supervisor/conf.d/connexa-backend.conf"
    echo "  Frontend: /etc/supervisor/conf.d/connexa-frontend.conf"
    
    echo ""
}

show_help() {
    cat <<EOF

CONNEXA Service Manager v2.0.0

USAGE:
    ./connexa-manager.sh [command] [options]

COMMANDS:
    start               Start all services
    stop                Stop all services
    restart             Restart all services
    status              Show service status
    logs [service]      View logs (backend/frontend/all)
    health              Run health checks
    config              Show configuration
    help                Show this help

EXAMPLES:
    # Start services
    sudo ./connexa-manager.sh start

    # Check status
    ./connexa-manager.sh status

    # View backend logs (last 50 lines)
    ./connexa-manager.sh logs backend

    # View all logs (last 100 lines)
    ./connexa-manager.sh logs all 100

    # Run health check
    ./connexa-manager.sh health

    # Show configuration
    ./connexa-manager.sh config

INSTALLATION:
    If CONNEXA is not installed, run:
    curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/Connexa-Shell/main/connexa-installer.sh | sudo bash

DOCUMENTATION:
    https://github.com/mrolivershea-cyber/Connexa-Shell

EOF
}

################################################################################
# Main
################################################################################

# Parse command
COMMAND=${1:-help}
shift || true

case $COMMAND in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "${1:-backend}" "${2:-50}"
        ;;
    health)
        run_health_check
        ;;
    config)
        show_config
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
