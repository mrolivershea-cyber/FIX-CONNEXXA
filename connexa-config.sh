#!/bin/bash
################################################################################
# CONNEXA CONFIGURATION HELPER
# Interactive configuration tool for CONNEXA Admin Panel
#
# Repository: https://github.com/mrolivershea-cyber/Connexa-Shell
#
# This script helps configure CONNEXA settings interactively
#
# Usage:
#   ./connexa-config.sh
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
BACKEND_ENV="$INSTALL_DIR/backend/.env"
FRONTEND_ENV="$INSTALL_DIR/frontend/.env"

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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

################################################################################
# Configuration functions
################################################################################

configure_backend() {
    print_header "BACKEND CONFIGURATION"
    
    echo ""
    print_info "Current backend settings:"
    
    if [ -f "$BACKEND_ENV" ]; then
        echo ""
        # Show current settings (hide secrets)
        grep -v "SECRET_KEY\|PASSWORD" "$BACKEND_ENV" | grep "=" | while read line; do
            echo "  $line"
        done
    else
        print_error "Backend .env not found at: $BACKEND_ENV"
        return 1
    fi
    
    echo ""
    read -p "Do you want to modify backend settings? (y/N): " modify
    
    if [[ $modify =~ ^[Yy]$ ]]; then
        # Get current values
        CURRENT_PORT=$(grep "^PORT=" "$BACKEND_ENV" | cut -d= -f2)
        CURRENT_HOST=$(grep "^HOST=" "$BACKEND_ENV" | cut -d= -f2)
        CURRENT_ORIGINS=$(grep "^ALLOWED_ORIGINS=" "$BACKEND_ENV" | cut -d= -f2)
        
        # Port
        echo ""
        read -p "Backend port [$CURRENT_PORT]: " NEW_PORT
        NEW_PORT=${NEW_PORT:-$CURRENT_PORT}
        
        # Host
        echo ""
        echo "Host binding:"
        echo "  0.0.0.0 - Listen on all interfaces (public access)"
        echo "  127.0.0.1 - Listen only on localhost (secure)"
        read -p "Host [$CURRENT_HOST]: " NEW_HOST
        NEW_HOST=${NEW_HOST:-$CURRENT_HOST}
        
        # CORS Origins
        echo ""
        echo "Allowed CORS origins (comma-separated):"
        read -p "Origins [$CURRENT_ORIGINS]: " NEW_ORIGINS
        NEW_ORIGINS=${NEW_ORIGINS:-$CURRENT_ORIGINS}
        
        # Update .env file
        sed -i "s|^PORT=.*|PORT=$NEW_PORT|" "$BACKEND_ENV"
        sed -i "s|^HOST=.*|HOST=$NEW_HOST|" "$BACKEND_ENV"
        sed -i "s|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=$NEW_ORIGINS|" "$BACKEND_ENV"
        
        print_success "Backend configuration updated"
        
        # Restart services
        echo ""
        read -p "Restart backend now? (Y/n): " restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            print_info "Restarting backend..."
            supervisorctl restart connexa-backend 2>/dev/null || print_error "Failed to restart"
            print_success "Backend restarted"
        fi
    fi
}

configure_frontend() {
    print_header "FRONTEND CONFIGURATION"
    
    echo ""
    print_info "Current frontend settings:"
    
    if [ -f "$FRONTEND_ENV" ]; then
        echo ""
        cat "$FRONTEND_ENV" | grep "=" | while read line; do
            echo "  $line"
        done
    else
        print_error "Frontend .env not found at: $FRONTEND_ENV"
        return 1
    fi
    
    echo ""
    read -p "Do you want to modify frontend settings? (y/N): " modify
    
    if [[ $modify =~ ^[Yy]$ ]]; then
        # Get current values
        CURRENT_BACKEND_URL=$(grep "^REACT_APP_BACKEND_URL=" "$FRONTEND_ENV" | cut -d= -f2)
        CURRENT_API_URL=$(grep "^REACT_APP_API_URL=" "$FRONTEND_ENV" | cut -d= -f2)
        
        # Backend URL
        echo ""
        read -p "Backend URL [$CURRENT_BACKEND_URL]: " NEW_BACKEND_URL
        NEW_BACKEND_URL=${NEW_BACKEND_URL:-$CURRENT_BACKEND_URL}
        
        # API URL
        echo ""
        read -p "API URL [$CURRENT_API_URL]: " NEW_API_URL
        NEW_API_URL=${NEW_API_URL:-$CURRENT_API_URL}
        
        # Update .env file
        sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=$NEW_BACKEND_URL|" "$FRONTEND_ENV"
        sed -i "s|^REACT_APP_API_URL=.*|REACT_APP_API_URL=$NEW_API_URL|" "$FRONTEND_ENV"
        
        print_success "Frontend configuration updated"
        
        # Rebuild frontend
        echo ""
        read -p "Rebuild and restart frontend now? (Y/n): " rebuild
        if [[ ! $rebuild =~ ^[Nn]$ ]]; then
            print_info "Rebuilding frontend..."
            cd "$INSTALL_DIR/frontend"
            npm run build --silent 2>&1 || print_error "Build failed"
            
            print_info "Restarting frontend..."
            supervisorctl restart connexa-frontend 2>/dev/null || print_error "Failed to restart"
            print_success "Frontend rebuilt and restarted"
        fi
    fi
}

configure_database() {
    print_header "DATABASE CONFIGURATION"
    
    DB_FILE="$INSTALL_DIR/backend/connexa.db"
    
    echo ""
    if [ -f "$DB_FILE" ]; then
        DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
        print_success "Database exists: $DB_SIZE"
        
        # Get statistics
        NODE_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        USER_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
        
        echo ""
        echo "Statistics:"
        echo "  Nodes: $NODE_COUNT"
        echo "  Users: $USER_COUNT"
        
        echo ""
        echo "Database operations:"
        echo "  1. Backup database"
        echo "  2. Reset admin password"
        echo "  3. Clear all nodes"
        echo "  4. Vacuum database"
        echo "  5. Export nodes to CSV"
        echo "  6. Back to main menu"
        echo ""
        
        read -p "Choose operation (1-6): " choice
        
        case $choice in
            1)
                BACKUP_FILE="$DB_FILE.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$DB_FILE" "$BACKUP_FILE"
                print_success "Database backed up to: $BACKUP_FILE"
                ;;
            2)
                print_info "Resetting admin password to: admin"
                # Default bcrypt hash for 'admin'
                sqlite3 "$DB_FILE" "UPDATE users SET password_hash='\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/Lew52r7P/gE8p.B6i' WHERE username='admin';"
                print_success "Admin password reset"
                ;;
            3)
                read -p "Are you sure you want to delete all nodes? (yes/no): " confirm
                if [ "$confirm" == "yes" ]; then
                    sqlite3 "$DB_FILE" "DELETE FROM nodes;"
                    print_success "All nodes deleted"
                else
                    print_info "Operation cancelled"
                fi
                ;;
            4)
                print_info "Vacuuming database..."
                sqlite3 "$DB_FILE" "VACUUM;"
                NEW_SIZE=$(du -h "$DB_FILE" | cut -f1)
                print_success "Database vacuumed. New size: $NEW_SIZE"
                ;;
            5)
                EXPORT_FILE="/tmp/nodes_export_$(date +%Y%m%d_%H%M%S).csv"
                sqlite3 -header -csv "$DB_FILE" "SELECT * FROM nodes;" > "$EXPORT_FILE"
                print_success "Nodes exported to: $EXPORT_FILE"
                ;;
            6)
                return
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    else
        print_error "Database not found at: $DB_FILE"
    fi
}

show_menu() {
    clear
    print_header "CONNEXA CONFIGURATION TOOL v2.0.0"
    
    echo ""
    echo "Configuration options:"
    echo ""
    echo "  1. Configure Backend"
    echo "  2. Configure Frontend"
    echo "  3. Database Operations"
    echo "  4. View Current Configuration"
    echo "  5. Exit"
    echo ""
}

view_config() {
    print_header "CURRENT CONFIGURATION"
    
    echo ""
    echo "📁 Backend ($BACKEND_ENV):"
    echo "─────────────────────"
    if [ -f "$BACKEND_ENV" ]; then
        grep -v "SECRET_KEY\|PASSWORD" "$BACKEND_ENV" | grep "=" | while read line; do
            echo "  $line"
        done
    else
        print_error "Not found"
    fi
    
    echo ""
    echo "📁 Frontend ($FRONTEND_ENV):"
    echo "─────────────────────"
    if [ -f "$FRONTEND_ENV" ]; then
        cat "$FRONTEND_ENV" | grep "=" | while read line; do
            echo "  $line"
        done
    else
        print_error "Not found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

################################################################################
# Main
################################################################################

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script should be run as root for full functionality"
    echo "Some operations may fail without root privileges"
    echo ""
    read -p "Continue anyway? (y/N): " continue
    if [[ ! $continue =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Main loop
while true; do
    show_menu
    read -p "Choose option (1-5): " choice
    
    case $choice in
        1)
            configure_backend
            echo ""
            read -p "Press Enter to continue..."
            ;;
        2)
            configure_frontend
            echo ""
            read -p "Press Enter to continue..."
            ;;
        3)
            configure_database
            echo ""
            read -p "Press Enter to continue..."
            ;;
        4)
            view_config
            ;;
        5)
            print_success "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            sleep 1
            ;;
    esac
done
