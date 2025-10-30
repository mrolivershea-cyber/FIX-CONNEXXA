#!/bin/bash

# Check for root permissions
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Verify /app/backend directory
if [ ! -d "/app/backend" ]; then
    echo "Directory /app/backend does not exist."
    exit 1
fi

# Create backup
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_file="/app/backend/server.py.bak.$timestamp"
cp /app/backend/server.py "$backup_file"
echo "Backup created at $backup_file"

# Download service_manager.py
curl -o /app/backend/service_manager.py https://raw.githubusercontent.com/yourusername/yourrepo/main/service_manager.py

# Cleanup server.py
sed -i '/^import .*$/!b;N;/\nimport .*$/!b; s/\nimport .*//g' /app/backend/server.py # Remove duplicate imports
sed -i '/@app.route(.*)\/api\//!d' /app/backend/server.py # Remove wrong endpoints
sed -i '/if __name__ == "__main__":/!b;N;d' /app/backend/server.py # Remove old patches

# Add import at the beginning
sed -i '1i from service_manager import start_service, stop_service, get_service_status' /app/backend/server.py

# Add new API endpoints
sed -i '/if __name__ == "__main__":/i \
@app.route("/api/service/start", methods=["POST"])\

def start_service():\
    return start_service()\
\
@app.route("/api/service/stop", methods=["POST"])\

def stop_service():\
    return stop_service()\
\
@app.route("/api/service/status", methods=["GET"])\

def get_service_status():\
    return get_service_status()' /app/backend/server.py

# Install system packages
apt-get update
apt-get install -y pptp-linux ppp dante-server

# Restart backend via supervisorctl
supervisorctl restart backend

# Verify installation
curl -s http://localhost/health
curl -s http://localhost/api/service/status

# Display summary
echo "Installation Summary:"
echo "Backup location: $backup_file"
echo "API Endpoints:"
echo "POST /api/service/start"
echo "POST /api/service/stop"
echo "GET /api/service/status"
echo "Swagger UI URL: http://localhost/swagger"
echo "Testing commands:"
echo "curl -X POST http://localhost/api/service/start"
echo "curl -X POST http://localhost/api/service/stop"
echo "curl http://localhost/api/service/status"
echo "Logs location: /var/log/backend.log"
echo "Rollback instructions: Restore from $backup_file"