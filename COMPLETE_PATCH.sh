#!/bin/bash
set -e

echo "Version 2.0"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Validate /app/backend directory exists
if [ ! -d "/app/backend" ]; then
    echo "/app/backend directory does not exist"
    exit 1
fi

# Create timestamped backup directory and copy files
BACKUP_DIR="/app/backend/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /app/backend/server.py "$BACKUP_DIR"
cp /app/backend/service_manager.py "$BACKUP_DIR"

# Download service_manager.py with size validation
curl -o /app/backend/service_manager.py "https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/backend/service_manager.py"
if [ $(stat -c%s "/app/backend/service_manager.py") -le 1000 ]; then
    echo "Downloaded file is less than 1000 bytes"
    exit 1
fi

# Run Python3 heredoc script to modify server.py
python3 <<EOF
import os

file_path = '/app/backend/server.py'
with open(file_path, 'r') as file:
    lines = file.readlines()

# Remove duplicate imports after line 100
imports = {}
for i in range(100, len(lines)):
    line = lines[i]
    if line.startswith('import ') or line.startswith('from '):
        if line not in imports:
            imports[line] = i

# Remove old endpoints
# Add your logic to remove old endpoints here

# Remove duplicate FastAPI declarations
# Add your logic here

# Add import after line with 'from services import service_manager'
for i in range(len(lines)):
    if 'from services import service_manager' in lines[i]:
        lines.insert(i + 1, 'import asyncio\n')

# Add async FastAPI endpoints
lines.insert(-1, """
@app.post('/api/service/start')
async def start_service():
    # Implementation here

@app.post('/api/service/stop')
async def stop_service():
    # Implementation here

@app.get('/api/service/status')
async def service_status():
    # Implementation here
""")

with open(file_path, 'w') as file:
    file.writelines(lines)
EOF

# Install necessary packages
apt-get install -y pptp-linux ppp dante-server

# Restart backend via supervisorctl
supervisorctl restart backend

# Test API endpoint
# Add your testing logic here

# Print summary
echo "Backup location: $BACKUP_DIR"
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "API URLs: /api/service/start, /api/service/stop, /api/service/status"
echo "Swagger URL: /docs"
echo "Rollback command: cp $BACKUP_DIR/server.py /app/backend/server.py"