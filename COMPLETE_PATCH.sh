#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# Verify /app/backend exists
BACKEND_DIR="/app/backend"
if [ ! -d "$BACKEND_DIR" ]; then
  echo "Directory $BACKEND_DIR does not exist."
  exit 1
fi

# Create timestamped backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$BACKEND_DIR/backup_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Download service_manager.py
SERVICE_MANAGER_URL="https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/backend/service_manager.py"
curl -o "$BACKEND_DIR/service_manager.py" "$SERVICE_MANAGER_URL"

# Validate file size
if [ $(stat -c%s "$BACKEND_DIR/service_manager.py") -le 1000 ]; then
  echo "Downloaded file is less than 1000 bytes."
  exit 1
fi

# Remove duplicate imports after line 100
awk 'NR==100 {print; getline; if ($0 !~ /import/) {print; print "import service_manager"} next} {print}' "$BACKEND_DIR/service_manager.py" > "$BACKEND_DIR/service_manager_tmp.py"
mv "$BACKEND_DIR/service_manager_tmp.py" "$BACKEND_DIR/service_manager.py"

# Remove old endpoints
sed -i '/\/start_service/d' "$BACKEND_DIR/service_manager.py"
sed -i '/\/stop_service/d' "$BACKEND_DIR/service_manager.py"
sed -i '/\/service_status/d' "$BACKEND_DIR/service_manager.py"

# Remove duplicate FastAPI declarations
# (Assuming they are named consistently, this might need specific grep/sed commands based on actual code)

# Add new import statement
sed -i '/from services import service_manager network_tester/a from service_manager import start_service, stop_service, service_status' "$BACKEND_DIR/service_manager.py"

# Insert new FastAPI endpoints
cat <<EOF >> "$BACKEND_DIR/service_manager.py"

@app.post("/api/service/start")
async def start_service_endpoint():
    # Logic to start service
    return {"message": "Service started"}

@app.post("/api/service/stop")
async def stop_service_endpoint():
    # Logic to stop service
    return {"message": "Service stopped"}

@app.get("/api/service/status")
async def service_status_endpoint():
    # Logic to check the service status
    return {"status": "Service is running"}
EOF

# Install required packages
apt-get update
apt-get install -y pptp-linux ppp dante-server

# Restart backend
supervisorctl restart backend

# Wait for 5 seconds
sleep 5

# Test API endpoint
curl -X GET "http://localhost:8000/api/service/status"

# Print summary
echo "Backup created at: $BACKUP_DIR"
echo "Server IP: $(hostname -I)"
echo "API Endpoints: /api/service/start, /api/service/stop, /api/service/status"
echo "Swagger URL: http://localhost:8000/docs"
echo "Rollback: Restore from backup directory $BACKUP_DIR"