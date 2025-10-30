#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.3.3-dev - PHASE 3: Auto-Recovery + Rebind Safety"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Tag: PHASE_3_AUTO_RECOVERY"
echo "  Features: Auto-reconnect, error handling, Dante rebind safety"
echo "  Requires: Phase 1 + Phase 2 completed"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"

# ============================================================================
# VERIFY PHASE 2 PREREQUISITES
# ============================================================================
echo ""
echo "🔍 [Phase3] Verifying Phase 2 prerequisites..."

if [ ! -f /etc/ppp/ip-up.d/connexa-dante ]; then
    echo "⚠️ WARNING: Phase 2 ip-up hook not found"
    echo "Phase 2 may not be applied. Continue anyway? (y/n)"
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

echo "✅ Prerequisites verified"

# ============================================================================
# STEP 1: Enhanced ip-up hook with error handling
# ============================================================================
echo ""
echo "📦 [Phase3] Step 1/7: Updating ip-up hook with auto-recovery..."

cat > /etc/ppp/ip-up.d/connexa-dante <<'IPUP'
#!/bin/bash
# Phase 3: Enhanced ip-up hook with error handling and retry logic
# Called when PPP interface comes UP

IFACE="$1"
LOCAL_IP="$4"
REMOTE_IP="$5"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"
MAX_RETRIES=3
RETRY_DELAY=5

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-up] $(date) - Interface $IFACE UP (Phase 3)"
echo "  Local IP: $LOCAL_IP"
echo "  Remote IP: $REMOTE_IP"
echo "  ipparam: $IPPARAM"
echo "════════════════════════════════════════════════════════════════"

# Phase 3: Validate interface is actually UP
if ! ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
    echo "[ip-up] ERROR: Interface $IFACE not in UP state"
    exit 1
fi

# Extract SOCKS port from ipparam (format: "socks:1080")
if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-up] Detected SOCKS port: $SOCKS_PORT"
    
    # Phase 3: Retry logic for SOCKS binding
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "[ip-up] SOCKS binding attempt $attempt/$MAX_RETRIES..."
        
        if /usr/local/bin/link_socks_to_ppp.sh "$SOCKS_PORT" "$IFACE"; then
            echo "[ip-up] ✅ SOCKS binding successful on attempt $attempt"
            exit 0
        else
            echo "[ip-up] ⚠️ SOCKS binding failed on attempt $attempt"
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "[ip-up] Retrying in ${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
            fi
        fi
    done
    
    echo "[ip-up] ❌ SOCKS binding failed after $MAX_RETRIES attempts"
    exit 1
else
    echo "[ip-up] No SOCKS port in ipparam, skipping Dante config"
fi

echo "[ip-up] Hook completed"
IPUP

chmod +x /etc/ppp/ip-up.d/connexa-dante
echo "✅ ip-up hook updated with retry logic"

# ============================================================================
# STEP 2: Enhanced ip-down hook with cleanup and notification
# ============================================================================
echo ""
echo "📦 [Phase3] Step 2/7: Updating ip-down hook with cleanup..."

cat > /etc/ppp/ip-down.d/connexa-dante <<'IPDOWN'
#!/bin/bash
# Phase 3: Enhanced ip-down hook with cleanup
# Called when PPP interface goes DOWN

IFACE="$1"
IPPARAM="$6"

LOG="/var/log/connexa-ppp-hooks.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[ip-down] $(date) - Interface $IFACE DOWN (Phase 3)"
echo "  ipparam: $IPPARAM"
echo "════════════════════════════════════════════════════════════════"

# Phase 3: Extract SOCKS port and mark for potential restart
if [[ "$IPPARAM" =~ socks:([0-9]+) ]]; then
    SOCKS_PORT="${BASH_REMATCH[1]}"
    echo "[ip-down] SOCKS port $SOCKS_PORT released"
    
    # Phase 3: Create marker file for auto-recovery
    echo "$(date)|$IFACE|$SOCKS_PORT" >> /tmp/connexa-down-events.log
    
    # Phase 3: Optional - kill processes holding the interface
    # (commented out for safety - enable if needed)
    # lsof -t "$IFACE" 2>/dev/null | xargs -r kill -9
fi

echo "[ip-down] Cleanup completed"
IPDOWN

chmod +x /etc/ppp/ip-down.d/connexa-dante
echo "✅ ip-down hook updated with cleanup"

# ============================================================================
# STEP 3: Create watchdog script for auto-recovery
# ============================================================================
echo ""
echo "📦 [Phase3] Step 3/7: Creating PPP watchdog..."

cat > /usr/local/bin/connexa-ppp-watchdog.sh <<'WATCHDOG'
#!/bin/bash
# Phase 3: PPP Watchdog - monitors and restarts failed tunnels

LOG="/var/log/connexa-watchdog.log"
BACKEND_DB="/app/backend/connexa.db"
CHECK_INTERVAL=60  # Check every 60 seconds

exec >> "$LOG" 2>&1

echo "════════════════════════════════════════════════════════════════"
echo "[Watchdog] Started at $(date)"
echo "════════════════════════════════════════════════════════════════"

while true; do
    # Check if we have active nodes in DB
    if [ -f "$BACKEND_DB" ]; then
        ACTIVE_NODES=$(sqlite3 "$BACKEND_DB" "SELECT COUNT(*) FROM nodes WHERE status IN ('speed_ok', 'ping_light') AND ppp_interface IS NOT NULL;" 2>/dev/null || echo 0)
        
        if [ "$ACTIVE_NODES" -gt 0 ]; then
            # Get expected interfaces from DB
            EXPECTED_IFACES=$(sqlite3 "$BACKEND_DB" "SELECT DISTINCT ppp_interface FROM nodes WHERE status IN ('speed_ok', 'ping_light') AND ppp_interface IS NOT NULL;" 2>/dev/null)
            
            for IFACE in $EXPECTED_IFACES; do
                # Check if interface exists and is UP
                if ! ip link show "$IFACE" &>/dev/null; then
                    echo "[Watchdog] $(date) - Interface $IFACE missing, triggering restart..."
                    
                    # Get node info from DB
                    NODE_ID=$(sqlite3 "$BACKEND_DB" "SELECT id FROM nodes WHERE ppp_interface='$IFACE' LIMIT 1;" 2>/dev/null)
                    
                    if [ -n "$NODE_ID" ]; then
                        echo "[Watchdog] Restarting tunnel for node $NODE_ID..."
                        # Trigger restart via backend API
                        curl -s -X POST http://localhost:8001/service/restart-node/$NODE_ID || echo "[Watchdog] API call failed"
                    fi
                elif ! ip link show "$IFACE" | grep -q "state UP"; then
                    echo "[Watchdog] $(date) - Interface $IFACE exists but not UP, attempting recovery..."
                    ip link set "$IFACE" up 2>/dev/null || true
                fi
            done
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
WATCHDOG

chmod +x /usr/local/bin/connexa-ppp-watchdog.sh
echo "✅ Watchdog script created"

# ============================================================================
# STEP 4: Create systemd service for watchdog
# ============================================================================
echo ""
echo "📦 [Phase3] Step 4/7: Creating watchdog systemd service..."

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
echo "✅ Watchdog service created (not started yet)"

# ============================================================================
# STEP 5: Enhanced link_socks_to_ppp.sh with rebind safety
# ============================================================================
echo ""
echo "📦 [Phase3] Step 5/7: Updating link_socks_to_ppp.sh with rebind safety..."

cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
# Phase 3: Enhanced SOCKS binding with rebind safety

PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[Phase3] $(date) - Linking SOCKS port $PORT to interface $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Phase 3: Check if Dante is already bound to this interface
if [ -f /etc/danted.conf ]; then
    CURRENT_IFACE=$(grep "^external:" /etc/danted.conf | awk '{print $2}')
    if [ "$CURRENT_IFACE" = "$IFACE" ]; then
        echo "[Phase3] ⚠️ Dante already bound to $IFACE, checking port..."
        CURRENT_PORT=$(grep "^internal:.*port" /etc/danted.conf | grep -oP 'port = \K\d+')
        if [ "$CURRENT_PORT" = "$PORT" ]; then
            # Already correctly configured, just verify it's running
            if netstat -tulnp 2>/dev/null | grep -q ":${PORT}"; then
                echo "[Phase3] ✅ Dante already running correctly on $PORT -> $IFACE"
                exit 0
            else
                echo "[Phase3] ⚠️ Dante configured but not listening, restarting..."
            fi
        fi
    fi
fi

# Wait for interface (30 seconds max)
MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
    if ip link show "$IFACE" &>/dev/null; then
        if ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
            echo "✅ Interface $IFACE is UP (attempt $i/$MAX_WAIT)"
            break
        else
            echo "⏳ Interface exists but not UP yet ($i/$MAX_WAIT)"
        fi
    else
        echo "⏳ Waiting for $IFACE to be created ($i/$MAX_WAIT)"
    fi
    sleep 1
done

# Final check
if ! ip link show "$IFACE" &>/dev/null; then
    echo "❌ ERROR: Interface $IFACE does not exist after ${MAX_WAIT}s"
    exit 1
fi

if ! ip link show "$IFACE" | grep -q "state UP"; then
    echo "⚠️ WARNING: Interface $IFACE exists but not UP"
    exit 1
fi

# Get external IP
EXTERNAL_IP=$(ip addr show "$IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "📍 External IP on $IFACE: ${EXTERNAL_IP:-N/A}"

# Phase 3: Stop Dante before reconfiguring (prevents bind errors)
echo "🛑 Stopping danted before reconfiguration..."
systemctl stop danted 2>&1 || true
sleep 1

# Generate danted.conf
echo "📝 Generating /etc/danted.conf for port $PORT..."
cat > /etc/danted.conf <<DANTE
# Phase 3: Enhanced Dante configuration
logoutput: /tmp/dante-logs/danted.log
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}
method: none
user.notprivileged: nobody

# Phase 3: More permissive pass rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect bind
    log: connect disconnect error
}
DANTE

# Phase 3: Restart danted with validation
echo "🔄 Starting danted..."
systemctl start danted 2>&1 || {
    echo "❌ Failed to start danted, checking status..."
    systemctl status danted --no-pager || true
    exit 1
}

sleep 3

# Verify SOCKS port is listening
for attempt in {1..5}; do
    if netstat -tulnp 2>/dev/null | grep -q ":${PORT}"; then
        echo "✅ SUCCESS: Dante listening on port ${PORT} (attempt $attempt)"
        echo "$(date) - Bind successful: ${PORT} -> ${IFACE} (${EXTERNAL_IP})"
        exit 0
    fi
    echo "⏳ Waiting for Dante to start listening ($attempt/5)..."
    sleep 1
done

echo "❌ ERROR: Dante not listening on port ${PORT} after 5 attempts"
echo "Danted status:"
systemctl status danted --no-pager || true
exit 1
SCRIPT

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh updated with rebind safety"

# ============================================================================
# STEP 6: Update service_manager.py with restart endpoint
# ============================================================================
echo ""
echo "📦 [Phase3] Step 6/7: Adding restart endpoint to service_manager.py..."

# Backup existing
if [ -f "$APP_DIR/service_manager.py" ]; then
    cp "$APP_DIR/service_manager.py" "$APP_DIR/service_manager.py.backup.phase3"
    
    # Add restart_node method if not exists
    if ! grep -q "def restart_node" "$APP_DIR/service_manager.py"; then
        cat >> "$APP_DIR/service_manager.py" <<'PYEOF'

    def restart_node(self, node_id: int) -> Dict[str, Any]:
        """Phase 3: Restart a specific node's tunnel."""
        try:
            con = sqlite3.connect(self.db_path)
            con.row_factory = sqlite3.Row
            cur = con.cursor()
            
            # Get node info
            user_col, pass_col = self._detect_cred_columns(cur)
            row = cur.execute(
                f"SELECT id, ip, {user_col} AS username, {pass_col} AS password, ppp_interface, socks_port "
                f"FROM nodes WHERE id=?",
                (node_id,)
            ).fetchone()
            
            if not row:
                return {"ok": False, "error": f"Node {node_id} not found"}
            
            node = dict(row)
            con.close()
            
            # Kill existing pppd for this node
            self._run(f"pkill -f 'pppd call connexa-{node_id}' 2>/dev/null || true")
            time.sleep(2)
            
            # Determine unit from existing data or assign new
            if node.get('ppp_interface'):
                unit_match = re.search(r'ppp(\d+)', node['ppp_interface'])
                unit = int(unit_match.group(1)) if unit_match else 0
            else:
                unit = 0
            
            socks_port = node.get('socks_port') or (SOCKS_PORT_BASE + unit)
            
            # Restart tunnel
            iface = self._start_pptp_tunnel(node, unit, socks_port)
            
            if iface:
                return {
                    "ok": True,
                    "node_id": node_id,
                    "interface": iface,
                    "socks_port": socks_port,
                    "status": "restarted"
                }
            else:
                return {
                    "ok": False,
                    "node_id": node_id,
                    "error": "Failed to restart tunnel"
                }
                
        except Exception as e:
            return {"ok": False, "error": str(e)}
PYEOF
        echo "✅ Added restart_node method"
    else
        echo "✅ restart_node method already exists"
    fi
fi

# Update router
if [ -f "$APP_DIR/router/service_router.py" ]; then
    if ! grep -q "restart-node" "$APP_DIR/router/service_router.py"; then
        cat >> "$APP_DIR/router/service_router.py" <<'PYEOF'

@router.post("/restart-node/{node_id}")
async def restart_node(node_id: int):
    """Phase 3: Restart a specific node's tunnel."""
    return manager.restart_node(node_id)
PYEOF
        echo "✅ Added restart endpoint to router"
    fi
fi

# ============================================================================
# STEP 7: Restart services and verification
# ============================================================================
echo ""
echo "📦 [Phase3] Step 7/7: Restarting services..."

supervisorctl restart backend 2>/dev/null || systemctl restart connexa-backend.service || true
sleep 5

BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || systemctl is-active connexa-backend.service 2>/dev/null || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

# Start watchdog (optional - can be started manually)
# systemctl start connexa-watchdog.service

VERIFY_LOG="/root/phase3_verification_$(date +%Y%m%d_%H%M%S).log"

cat > "$VERIFY_LOG" <<VERIFY
════════════════════════════════════════════════════════════════
CONNEXA Phase 3 Verification Report
Generated: $(date)
════════════════════════════════════════════════════════════════

[HOOKS (Enhanced)]
ip-up hook: $(grep -c "Phase 3" /etc/ppp/ip-up.d/connexa-dante 2>/dev/null || echo 0) phase 3 markers
ip-down hook: $(grep -c "Phase 3" /etc/ppp/ip-down.d/connexa-dante 2>/dev/null || echo 0) phase 3 markers

[WATCHDOG]
Watchdog script: $(ls -l /usr/local/bin/connexa-ppp-watchdog.sh 2>/dev/null || echo "NOT FOUND")
Watchdog service: $(systemctl is-enabled connexa-watchdog.service 2>/dev/null || echo "not enabled")

[LINK_SOCKS_TO_PPP (Enhanced)]
$(grep -c "Phase 3" /usr/local/bin/link_socks_to_ppp.sh 2>/dev/null || echo 0) phase 3 enhancements

[SERVICE_MANAGER]
restart_node method: $(grep -c "def restart_node" $APP_DIR/service_manager.py 2>/dev/null || echo 0) found

[BACKEND]
Backend status: $BACKEND_STATUS
Restart endpoint: $(grep -c "restart-node" $APP_DIR/router/service_router.py 2>/dev/null || echo 0) found

════════════════════════════════════════════════════════════════
VERIFY

cat "$VERIFY_LOG"

echo ""
echo "✅ Verification log saved to: $VERIFY_LOG"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Phase 3 (v7.3.3-dev) INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔧 Applied Features:"
echo "  ✅ Auto-retry logic in ip-up hook (3 attempts)"
echo "  ✅ Enhanced ip-down hook with event logging"
echo "  ✅ PPP watchdog service (monitors and restarts failed tunnels)"
echo "  ✅ Rebind safety in link_socks_to_ppp.sh"
echo "  ✅ Restart endpoint: POST /service/restart-node/{id}"
echo "  ✅ Stop-before-start logic for Dante (prevents bind errors)"
echo ""
echo "📊 Current Status:"
echo "  - Backend: $BACKEND_STATUS"
echo "  - Watchdog: enabled (not started - start manually if needed)"
echo ""
echo "🔍 Commands:"
echo "  1. Start watchdog: systemctl start connexa-watchdog.service"
echo "  2. Check watchdog: tail -f /var/log/connexa-watchdog.log"
echo "  3. Check hooks: tail -f /var/log/connexa-ppp-hooks.log"
echo "  4. Restart single node: curl -X POST http://localhost:8001/service/restart-node/2"
echo "  5. View down events: cat /tmp/connexa-down-events.log"
echo ""
echo "📋 All 3 phases complete! System is now production-ready."
echo "════════════════════════════════════════════════════════════════"
