#!/usr/bin/env bash
#
# CONNEXA v8.0 - Restore Admin Panel Fix
# Restores correct backend on port 8001 and fixes admin panel accessibility
#

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v8.0 - Admin Panel Restore"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Configuration
APP_DIR="/app/backend"
BACKEND_PORT=8001
FRONTEND_PORT=3000

echo "[Step 1/6] Stopping incorrect backend services..."
supervisorctl stop backend 2>/dev/null || true
supervisorctl stop watchdog 2>/dev/null || true
systemctl stop connexa-backend.service 2>/dev/null || true
echo "✅ Services stopped"

echo ""
echo "[Step 2/6] Removing incorrect backend files..."
rm -f /usr/local/bin/connexa_backend_server.py
rm -f /usr/local/bin/connexa_watchdog.py
rm -f /etc/supervisor/conf.d/connexa-backend.conf
rm -f /etc/supervisor/conf.d/connexa-watchdog.conf
echo "✅ Incorrect files removed"

echo ""
echo "[Step 3/6] Creating proper FastAPI backend server..."
mkdir -p $APP_DIR

cat > $APP_DIR/server.py <<'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import sys
import os

# Add service_manager to path
sys.path.insert(0, os.path.dirname(__file__))

app = FastAPI(title="Connexa Backend API", version="8.0")

# Enable CORS for frontend on port 3000
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Import service manager
try:
    from service_manager import start_service, stop_service, service_status
except ImportError:
    # Fallback if service_manager not available
    async def start_service():
        return {"ok": False, "error": "service_manager not found"}
    
    async def stop_service():
        return {"ok": False, "error": "service_manager not found"}
    
    async def service_status():
        return {"ok": False, "error": "service_manager not found"}

@app.get("/")
async def root():
    return {"status": "ok", "service": "Connexa Backend API", "version": "8.0", "port": 8001}

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "backend", "port": 8001}

@app.post("/service/start")
async def start():
    """Start PPTP tunnel and SOCKS proxy"""
    return await start_service()

@app.post("/service/stop")
async def stop():
    """Stop PPTP tunnel and SOCKS proxy"""
    return await stop_service()

@app.get("/service/status")
async def status():
    """Get service status"""
    return await service_status()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF

echo "✅ FastAPI backend created at $APP_DIR/server.py"

echo ""
echo "[Step 4/6] Ensuring service_manager.py is correct..."
if [ ! -f "$APP_DIR/service_manager.py" ]; then
    echo "⚠️  service_manager.py not found, copying from repository..."
    if [ -f "backend/service_manager.py" ]; then
        cp backend/service_manager.py $APP_DIR/
        echo "✅ service_manager.py copied"
    else
        echo "❌ ERROR: service_manager.py not found in repository!"
        exit 1
    fi
else
    echo "✅ service_manager.py exists"
fi

echo ""
echo "[Step 5/6] Configuring systemd service for backend on port 8001..."
cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend API (FastAPI/Uvicorn)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/app/backend
ExecStart=/usr/bin/python3 -m uvicorn server:app --host 0.0.0.0 --port 8001 --workers 1
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable connexa-backend.service
echo "✅ Systemd service configured"

echo ""
echo "[Step 6/6] Starting backend service..."
systemctl start connexa-backend.service
sleep 3

# Check if backend is running
if systemctl is-active --quiet connexa-backend.service; then
    echo "✅ Backend service is RUNNING"
    
    # Test API endpoint
    echo ""
    echo "Testing API endpoint..."
    API_RESPONSE=$(curl -s http://localhost:8001/ 2>/dev/null || echo '{"error":"timeout"}')
    if echo "$API_RESPONSE" | grep -q '"status":"ok"'; then
        echo "✅ API is responding on port 8001"
        echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$API_RESPONSE"
    else
        echo "⚠️  API not responding properly"
        echo "$API_RESPONSE"
    fi
else
    echo "❌ Backend service failed to start"
    echo "Check logs with: journalctl -u connexa-backend.service -n 50"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v8.0 - Installation Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "✅ Admin panel should now be accessible:"
echo "   - Frontend:  http://YOUR_SERVER_IP:3000"
echo "   - Backend:   http://YOUR_SERVER_IP:8001"
echo ""
echo "📋 Verification commands:"
echo "   systemctl status connexa-backend"
echo "   curl http://localhost:8001/"
echo "   curl http://localhost:8001/service/status"
echo ""
echo "📝 Logs:"
echo "   journalctl -u connexa-backend.service -f"
echo "════════════════════════════════════════════════════════════════"
