#!/bin/bash
set -e

# Version 2.1 - Date: $(date +"%Y-%m-%d")

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Validate directory
DIR="/app/backend"
if [ ! -d "$DIR" ]; then
    echo "Directory $DIR does not exist."
    exit 1
fi

# Create a timestamped backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
cp /app/backend/server.py "/app/backend/backup_$TIMESTAMP_server.py"
cp /app/backend/service_manager.py "/app/backend/backup_$TIMESTAMP_service_manager.py"

# Download service_manager.py
wget -O /app/backend/service_manager.py "https://github.com/mrolivershea-cyber/FIX-CONNEXXA/raw/main/backend/service_manager.py"
if [[ $(stat -c%s "/app/backend/service_manager.py") -le 1000 ]]; then
    echo "Downloaded file is less than 1000 bytes."
    exit 1
fi

# Clean server.py
python3 <<'PYEOF'
import sys

def clean_server(file_path):
    with open(file_path, 'r+') as f:
        lines = f.readlines()
        # Remove duplicate imports after line 100 and old endpoints
        # Add import after 'from services import'
        # Insert async FastAPI endpoints
        # [Insert logic here]

if __name__ == "__main__":
    clean_server('/app/backend/server.py')
PYEOF

# Install necessary packages
apt-get update
apt-get install -y pptp-linux ppp dante-server

# Restart backend service
supervisorctl restart backend
sleep 5

# Test API
curl -s http://localhost:8001/api/service/status

# Print summary
echo "Backup location: /app/backend/backup_$TIMESTAMP_server.py"
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "API URLs: http://localhost:8001/api/service/{start|stop|status}"
echo "Swagger URL: http://localhost:8001/docs"
echo "Rollback command: cp /app/backend/backup_$TIMESTAMP_server.py /app/backend/server.py"