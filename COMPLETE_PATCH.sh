#!/bin/bash

# 1. Check root permissions
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# 2. Check /app/backend directory
BACKEND_DIR="/app/backend"
if [ ! -d "$BACKEND_DIR" ]; then
    echo "Directory $BACKEND_DIR does not exist."
    exit 1
fi

# 3. Create timestamped backup directory
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backup_$TIMESTAMP"
mkdir "$BACKUP_DIR"
cp "$BACKEND_DIR/server.py" "$BACKUP_DIR/"
cp "$BACKEND_DIR/service_manager.py" "$BACKUP_DIR/"

# 4. Download service_manager.py and validate file size
SERVICE_MANAGER_URL="https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/backend/service_manager.py"
curl -o "$BACKEND_DIR/service_manager.py" "$SERVICE_MANAGER_URL"

if [ $? -ne 0 ] || [ ! -f "$BACKEND_DIR/service_manager.py" ]; then
    echo "Failed to download service_manager.py"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$BACKEND_DIR/service_manager.py")
if [ "$FILE_SIZE" -le 1000 ]; then
    echo "service_manager.py is less than 1000 bytes, aborting."
    exit 1
fi

# 5. Clean server.py
python3 - <<EOF
import re

with open("$BACKEND_DIR/server.py", "r+") as f:
    content = f.readlines()

# Removing duplicate imports of service_manager after line 100
for i, line in enumerate(content[100:]):
    if "service_manager" in line:
        del content[i + 100]

# Removing old endpoints
content = [line for line in content if "/start_service" not in line and "/stop_service" not in line and "/service_status" not in line]

# Removing duplicate app = FastAPI() declarations after line 100
app_declarations = 0
for i, line in enumerate(content[100:]):
    if "app = FastAPI()" in line:
        app_declarations += 1
        if app_declarations > 1:
            del content[i + 100]

# Adding import statement
for i, line in enumerate(content):
    if "from services import service_manager, network_tester" in line:
        content.insert(i + 1, "from service_manager import start_service, stop_service, service_status\n")
        break

# Inserting FastAPI endpoints
endpoints = """
@app.post("/api/service/start")
async def start_service_endpoint():
    # Implementation here
    pass

@app.post("/api/service/stop")
async def stop_service_endpoint():
    # Implementation here
    pass

@app.get("/api/service/status")
async def service_status_endpoint():
    # Implementation here
    pass
"""

for i, line in enumerate(content):
    if "if __name__" in line or "if name ==" in line:
        content.insert(i, endpoints)
        break

with open("$BACKEND_DIR/server.py", "w") as f:
    f.writelines(content)
EOF

# 6. Install required packages
apt-get install -y pptp-linux ppp dante-server || { echo "Failed to install packages"; exit 1; }

# 7. Restart backend
supervisorctl restart backend || supervisorctl restart connexa-backend

# 8. Wait and test the endpoint
sleep 5
curl -s http://localhost:8001/api/service/status || { echo "Service is not running"; exit 1; }

# 9. Print summary
echo "Backup created at $BACKUP_DIR"
echo "API endpoints:"
echo " - POST /api/service/start"
echo " - POST /api/service/stop"
echo " - GET /api/service/status"
echo "Swagger UI URL: http://localhost:8001/docs"
echo "Test commands:"
echo " - curl -X POST http://localhost:8001/api/service/start"
echo "Rollback instructions: Restore from $BACKUP_DIR"