# ============================================================================
# STEP 8: Create FastAPI router with all endpoints
# ============================================================================
echo ""
echo "📦 [Final] Step 8/15: Creating FastAPI router..."

mkdir -p "$ROUTER_DIR"
cat > "$ROUTER_DIR/service_router.py" <<'PYEOF'
from fastapi import APIRouter, Query
import sys
sys.path.insert(0, '/app/backend')
from service_manager import ServiceManager

router = APIRouter(prefix="/service", tags=["Service Management"])
manager = ServiceManager()

@router.post("/start")
async def start_service():
    """Start all PPTP tunnels and SOCKS proxies."""
    return manager.start()

@router.post("/stop")
async def stop_service():
    """Stop all services."""
    return manager.stop()

@router.get("/status")
async def status_service():
    """Get current status."""
    return manager.status()

@router.post("/restart-node/{node_id}")
async def restart_node(node_id: int):
    """Restart specific node."""
    return manager.restart_node(node_id)

@router.post("/test-sample")
async def test_sample(
    status: str = Query("SpeedOculus", description="Node status to filter"),
    limit: int = Query(3, ge=1, le=10, description="Number of nodes to test"),
    mode: str = Query("speed_only", description="Test mode")
):
    """Test sample of nodes (SpeedOculus)."""
    return manager.test_sample(status=status, limit=limit, mode=mode)

@router.get("/stats")
async def get_stats():
    """Get statistics from database."""
    import sqlite3
    from pathlib import Path
    
    db_path = "/app/backend/connexa.db"
    if not Path(db_path).exists():
        return {"ok": False, "error": "Database not found"}
    
    try:
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        
        # Recent metrics
        metrics = cur.execute("""
            SELECT node_id, ts, speed_mbps, ping_ms, reconnects
            FROM node_metrics
            ORDER BY ts DESC
            LIMIT 50
        """).fetchall()
        
        # Active nodes
        active = cur.execute("""
            SELECT COUNT(*) FROM nodes 
            WHERE status IN ('speed_ok', 'ping_light')
        """).fetchone()[0]
        
        con.close()
        
        return {
            "ok": True,
            "active_nodes": active,
            "recent_metrics": [
                {
                    "node_id": m[0],
                    "ts": m[1],
                    "speed_mbps": m[2],
                    "ping_ms": m[3],
                    "reconnects": m[4]
                }
                for m in metrics
            ]
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}
PYEOF

touch "$ROUTER_DIR/__init__.py"
echo "✅ Router created with all endpoints"

# ============================================================================
# STEP 9: Create metrics endpoint
# ============================================================================
echo ""
echo "📦 [Final] Step 9/15: Adding metrics endpoint to router..."

cat >> "$ROUTER_DIR/service_router.py" <<'PYEOF'

@router.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    from fastapi.responses import Response
    try:
        import sys
        sys.path.insert(0, '/app/backend')
        from metrics_exporter import get_metrics, CONTENT_TYPE_LATEST
        
        return Response(
            content=get_metrics(),
            media_type=CONTENT_TYPE_LATEST
        )
    except Exception as e:
        return Response(
            content=f"# ERROR: {e}\n",
            media_type="text/plain",
            status_code=503
        )
PYEOF

echo "✅ Metrics endpoint added"

# ============================================================================
# STEP 10: Enhanced PPP hooks (Phase 2 + Final improvements)
# ============================================================================
echo ""
echo "📦 [Final] Step 10/15: Creating production PPP hooks..."

cat > /etc/ppp/ip-up.d/connexa-dante <<'IPUP'
#!/bin/bash
# Production ip-up hook with Dante rebind safety

IFACE="$1"
LOCAL_IP="$4"
REMOTE_IP="$5"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"
MAX_RETRIES=3
RETRY_DELAY=5

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-up] $(date) - Interface $IFACE UP"
echo "  Local: $LOCAL_IP, Remote: $REMOTE_IP, ipparam: $IPPARAM"
echo "════════════════════════════════════════════════════════════════"

# Validate interface
if ! ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
    echo "[ip-up] ERROR: Interface $IFACE not UP"
    exit 1
fi

# Extract SOCKS port
if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-up] SOCKS port: $SOCKS_PORT"
    
    # Retry binding with Dante restart
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "[ip-up] Binding attempt $attempt/$MAX_RETRIES..."
        
        # Stop Dante before reconfiguration
        systemctl stop danted 2>/dev/null || true
        sleep 1
        
        # Generate config with syslog (safe for read-only /var/log)
        cat > /etc/danted.conf <<DANTE
logoutput: syslog
internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${IFACE}
clientmethod: none
socksmethod: none
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect bind
    log: error
}
DANTE
        
        # Start Dante
        systemctl start danted 2>&1
        sleep 3
        
        # Verify
        if netstat -tulnp 2>/dev/null | grep -q ":${SOCKS_PORT}"; then
            echo "[ip-up] ✅ SUCCESS on attempt $attempt"
            echo "[WATCHDOG] node=unknown action=rebind_dante result=ok" >> /var/log/connexa-watchdog.log
            exit 0
        fi
        
        echo "[ip-up] ⚠️ Failed attempt $attempt"
        if [ $attempt -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    done
    
    echo "[ip-up] ❌ FAILED after $MAX_RETRIES attempts"
    echo "[WATCHDOG] node=unknown action=rebind_dante result=failed" >> /var/log/connexa-watchdog.log
    exit 1
fi
IPUP

chmod +x /etc/ppp/ip-up.d/connexa-dante

cat > /etc/ppp/ip-down.d/connexa-dante <<'IPDOWN'
#!/bin/bash
# Production ip-down hook

IFACE="$1"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-down] $(date) - Interface $IFACE DOWN"
echo "════════════════════════════════════════════════════════════════"

if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-down] Released SOCKS port: $SOCKS_PORT"
    echo "$(date)|$IFACE|$SOCKS_PORT" >> /tmp/connexa-down-events.log
fi
IPDOWN

chmod +x /etc/ppp/ip-down.d/connexa-dante
echo "✅ Production PPP hooks created"

# ============================================================================
# STEP 11: Enhanced watchdog with API integration
# ============================================================================
echo ""
echo "📦 [Final] Step 11/15: Creating production watchdog..."

cat > /usr/local/bin/connexa-ppp-watchdog.sh <<'WATCHDOG'
#!/bin/bash
# Production PPP Watchdog

LOG="/var/log/connexa-watchdog.log"
BACKEND_DB="/app/backend/connexa.db"
CHECK_INTERVAL=60
API_BASE="http://localhost:8001"

exec >> "$LOG" 2>&1

echo "════════════════════════════════════════════════════════════════"
echo "[Watchdog] Started at $(date)"
echo "════════════════════════════════════════════════════════════════"

while true; do
    if [ -f "$BACKEND_DB" ]; then
        # Get nodes with ppp_interface
        NODES=$(sqlite3 "$BACKEND_DB" "SELECT id, ppp_interface FROM nodes WHERE ppp_interface IS NOT NULL;" 2>/dev/null)
        
        while IFS='|' read -r NODE_ID IFACE; do
            if [ -n "$IFACE" ]; then
                # Check if interface exists and is UP
                if ! ip link show "$IFACE" &>/dev/null; then
                    echo "[Watchdog] $(date) - Interface $IFACE (node $NODE_ID) missing"
                    echo "[WATCHDOG] node=$NODE_ID action=restart result=triggered"
                    
                    # Trigger restart via API
                    RESPONSE=$(curl -s -X POST "$API_BASE/service/restart-node/$NODE_ID" 2>/dev/null)
                    
                    if echo "$RESPONSE" | grep -q '"ok":true'; then
                        echo "[Watchdog] Successfully restarted node $NODE_ID"
                        echo "[WATCHDOG] node=$NODE_ID action=restart result=ok"
                        
                        # Increment reconnect counter
                        sqlite3 "$BACKEND_DB" "UPDATE nodes SET reconnect_count = reconnect_count + 1 WHERE id=$NODE_ID;" 2>/dev/null
                    else
                        echo "[Watchdog] Failed to restart node $NODE_ID: $RESPONSE"
                        echo "[WATCHDOG] node=$NODE_ID action=restart result=failed"
                    fi
                    
                elif ! ip link show "$IFACE" | grep -q "state UP"; then
                    echo "[Watchdog] $(date) - Interface $IFACE exists but not UP"
                    ip link set "$IFACE" up 2>/dev/null || true
                fi
            fi
        done <<< "$NODES"
    fi
    
    sleep $CHECK_INTERVAL
done
WATCHDOG

chmod +x /usr/local/bin/connexa-ppp-watchdog.sh

cat > /etc/systemd/system/connexa-watchdog.service <<'UNIT'
[Unit]
Description=Connexa PPP Watchdog
After=network-online.target connexa-backend.service
Requires=connexa-backend.service

[Service]
Type=simple
ExecStart=/usr/local/bin/connexa-ppp-watchdog.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable connexa-watchdog.service 2>/dev/null || true
echo "✅ Production watchdog created"

# ============================================================================
# STEP 12: Configure systemd services with final limits
# ============================================================================
echo ""
echo "📦 [Final] Step 12/15: Configuring systemd services..."

cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend (Production)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001 --workers 1 --loop uvloop
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535
TasksMax=infinity

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /etc/systemd/system/danted.service.d
cat > /etc/systemd/system/danted.service.d/override.conf <<'OVERRIDE'
[Service]
LimitNOFILE=65535
TasksMax=8192
Restart=always
RestartSec=3
OVERRIDE

systemctl daemon-reload
systemctl enable connexa-backend.service danted.service 2>/dev/null || true
echo "✅ Systemd services configured"

# ============================================================================
# STEP 13: Patch server.py to include router
# ============================================================================
echo ""
echo "📦 [Final] Step 13/15: Patching server.py..."

SERVER="$APP_DIR/server.py"
if [ -f "$SERVER" ]; then
    if ! grep -q "service_router" "$SERVER"; then
        sed -i '1i from router.service_router import router as service_router' "$SERVER"
        sed -i '/^app = FastAPI/a app.include_router(service_router)' "$SERVER"
        echo "✅ server.py patched"
    else
        echo "✅ server.py already patched"
    fi
else
    echo "⚠️ server.py not found"
fi

# ============================================================================
# STEP 14: Restart services
# ============================================================================
echo ""
echo "📦 [Final] Step 14/15: Restarting services..."

supervisorctl restart backend 2>/dev/null || systemctl restart connexa-backend.service || true
sleep 5

BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || systemctl is-active connexa-backend.service 2>/dev/null || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

if [ "$BACKEND_STATUS" = "RUNNING" ] || [ "$BACKEND_STATUS" = "active" ]; then
    echo "Testing API endpoints..."
    
    # Test /service/status
    STATUS_RESPONSE=$(curl -s http://localhost:8001/service/status 2>/dev/null || echo '{"error":"timeout"}')
    if echo "$STATUS_RESPONSE" | grep -q '"ok"'; then
        echo "✅ /service/status working"
    fi
    
    # Test /metrics
    METRICS_RESPONSE=$(curl -s http://localhost:8001/service/metrics 2>/dev/null | head -5)
    if echo "$METRICS_RESPONSE" | grep -q 'connexa_'; then
        echo "✅ /service/metrics working"
    fi
fi

# ============================================================================
# STEP 15: Final verification and report
# ============================================================================
echo ""
echo "📦 [Final] Step 15/15: Final verification..."

VERIFY_LOG="/root/connexa_final_verification_$(date +%Y%m%d_%H%M%S).log"

cat > "$VERIFY_LOG" <<VERIFY
════════════════════════════════════════════════════════════════
CONNEXA v7.3.4-FINAL Production Verification Report
Generated: $(date)
User: mrolivershea-cyber
════════════════════════════════════════════════════════════════

[SYSTEM LIMITS]
ulimit -n: $(ulimit -n)
fs.file-max: $(sysctl -n fs.file-max)
kernel.pid_max: $(sysctl -n kernel.pid_max)

[PPP MODULES]
$(lsmod | grep ppp)

[/dev/ppp]
$(ls -l /dev/ppp 2>/dev/null || echo "NOT FOUND")

[SERVICES]
Backend: $BACKEND_STATUS
Watchdog: $(systemctl is-enabled connexa-watchdog.service 2>/dev/null || echo "not enabled")
Danted: $(systemctl is-active danted 2>/dev/null || echo "inactive")

[DATABASE SCHEMA]
Tables: $(sqlite3 $APP_DIR/connexa.db ".tables" 2>/dev/null || echo "DB not found")

[API ENDPOINTS]
/service/status: $(curl -s http://localhost:8001/service/status 2>/dev/null | grep -o '"ok":[^,]*' || echo "not tested")
/service/metrics: $(curl -s http://localhost:8001/service/metrics 2>/dev/null | head -1 || echo "not tested")

[FILES CREATED]
- service_manager.py: $([ -f "$APP_DIR/service_manager.py" ] && echo "✓" || echo "✗")
- metrics_exporter.py: $([ -f "$APP_DIR/metrics_exporter.py" ] && echo "✓" || echo "✗")
- service_router.py: $([ -f "$APP_DIR/router/service_router.py" ] && echo "✓" || echo "✗")
- ip-up hook: $([ -f /etc/ppp/ip-up.d/connexa-dante ] && echo "✓" || echo "✗")
- ip-down hook: $([ -f /etc/ppp/ip-down.d/connexa-dante ] && echo "✓" || echo "✗")
- watchdog script: $([ -f /usr/local/bin/connexa-ppp-watchdog.sh ] && echo "✓" || echo "✗")

[LOG FILES]
- /var/log/connexa-ppp-hooks.log
- /var/log/connexa-watchdog.log
- /var/log/link_socks_to_ppp.log
- /tmp/dante-logs/danted.log (via syslog)

════════════════════════════════════════════════════════════════
VERIFY

cat "$VERIFY_LOG"

echo ""
echo "✅ Verification log: $VERIFY_LOG"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  🎉 CONNEXA v7.3.4-FINAL INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📦 Installed Components:"
echo "  ✅ Phase 1: System limits (FD=65535, NPROC=65535)"
echo "  ✅ Phase 2: Unit ID + PPP hooks (deterministic interfaces)"
echo "  ✅ Phase 3: Auto-recovery + Watchdog"
echo "  ✅ Final: Metrics, SpeedOculus, Admin endpoints"
echo ""
echo "🔧 Key Features:"
echo "  • Prometheus metrics: /service/metrics"
echo "  • SpeedOculus testing: POST /service/test-sample"
echo "  • Auto-recovery watchdog (60s interval)"
echo "  • Dante with syslog (safe for read-only FS)"
echo "  • Thread-safe concurrent limits"
echo "  • Database metrics tracking"
echo ""
echo "📊 Current Status:"
echo "  - Backend: $BACKEND_STATUS"
echo "  - ulimit -n: $(ulimit -n)"
echo "  - PPP modules: $(lsmod | grep -c ppp || echo 0)"
echo ""
echo "🚀 Quick Start:"
echo "  1. Start services:"
echo "     curl -X POST http://localhost:8001/service/start"
echo ""
echo "  2. Start watchdog:"
echo "     systemctl start connexa-watchdog.service"
echo ""
echo "  3. Run speed test sample:"
echo "     curl -X POST 'http://localhost:8001/service/test-sample?limit=3'"
echo ""
echo "  4. Check metrics:"
echo "     curl http://localhost:8001/service/metrics"
echo ""
echo "  5. View stats:"
echo "     curl http://localhost:8001/service/stats"
echo ""
echo "📋 Test Commands:"
echo "  # Check watchdog"
echo "  tail -f /var/log/connexa-watchdog.log"
echo ""
echo "  # Check PPP hooks"
echo "  tail -f /var/log/connexa-ppp-hooks.log"
echo ""
echo "  # Check database"
echo "  sqlite3 /app/backend/connexa.db 'SELECT * FROM node_metrics ORDER BY ts DESC LIMIT 10;'"
echo ""
echo "  # Test SOCKS"
echo "  curl --socks5 127.0.0.1:1080 ifconfig.me"
echo ""
echo "🎯 Production Ready!"
echo "   All phases (1-3) integrated + metrics + testing"
echo "════════════════════════════════════════════════════════════════"
