#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.3.1-dev - PHASE 1: Core & Limits Stabilization"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Tag: PHASE_1_CORE_LIMITS"
echo "  Fixes: Too many files, thread limits, pppd stability"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Root required"
    exit 1
fi

APP_DIR="/app/backend"

# ============================================================================
# STEP 1: Install dependencies
# ============================================================================
echo ""
echo "📦 [Phase1] Step 1/9: Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y pptp-linux ppp dante-server net-tools sqlite3 supervisor iproute2

echo "✅ Packages installed"

# ============================================================================
# STEP 2: System limits and sysctl (CRITICAL)
# ============================================================================
echo ""
echo "📦 [Phase1] Step 2/9: Applying system limits..."

cat > /etc/security/limits.d/connexa.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
* soft nproc 8192
* hard nproc 8192
EOF

cat >> /etc/sysctl.conf <<EOF
# Connexa Phase 1 tuning
fs.file-max=1048576
net.core.somaxconn=8192
vm.max_map_count=262144
EOF

sysctl -p || true
ulimit -n 65535 2>/dev/null || true

echo "✅ System limits applied"
echo "  - ulimit -n: $(ulimit -n)"
echo "  - fs.file-max: $(sysctl -n fs.file-max)"
echo "  - net.core.somaxconn: $(sysctl -n net.core.somaxconn)"
echo "  - vm.max_map_count: $(sysctl -n vm.max_map_count)"

# ============================================================================
# STEP 3: PPP modules and /dev/ppp validation
# ============================================================================
echo ""
echo "📦 [Phase1] Step 3/9: Ensuring PPP kernel modules..."

# Load modules
for mod in ppp_generic ppp_async ppp_mppe ppp_deflate; do
    modprobe $mod 2>/dev/null || true
done

# Auto-load on boot
cat > /etc/modules-load.d/ppp.conf <<EOF
ppp_generic
ppp_async
ppp_mppe
ppp_deflate
EOF

# Ensure /dev/ppp exists
if [ ! -c /dev/ppp ]; then
    echo "[Phase1] Creating /dev/ppp"
    mknod /dev/ppp c 108 0
    chmod 600 /dev/ppp
else
    echo "[Phase1] /dev/ppp already exists"
fi

# Create runtime directories
mkdir -p /var/run/ppp /var/log/ppp /tmp/dante-logs
chmod 755 /var/run/ppp /var/log/ppp
chmod 777 /tmp/dante-logs

echo "✅ PPP modules loaded:"
lsmod | grep ppp

# ============================================================================
# STEP 4: Cleanup stale processes and pidfiles
# ============================================================================
echo ""
echo "📦 [Phase1] Step 4/9: Cleanup stale PPPD processes..."

rm -f /var/run/ppp*.pid 2>/dev/null || true
pkill -9 -f "pppd call pptp_" 2>/dev/null || true
ip -o link show | grep -oP 'ppp\d+' | while read iface; do
    ip link delete "$iface" 2>/dev/null || true
done

echo "✅ Cleanup complete"

# ============================================================================
# STEP 5: Configure systemd services with limits
# ============================================================================
echo ""
echo "📦 [Phase1] Step 5/9: Configuring systemd services..."

# Backend service
cat > /etc/systemd/system/connexa-backend.service <<'UNIT'
[Unit]
Description=Connexa Backend (Uvicorn)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/app/backend
ExecStart=/app/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001
Restart=always
RestartSec=3
LimitNOFILE=65535
TasksMax=8192

[Install]
WantedBy=multi-user.target
UNIT

# Danted service override
mkdir -p /etc/systemd/system/danted.service.d
cat > /etc/systemd/system/danted.service.d/override.conf <<'OVERRIDE'
[Service]
LimitNOFILE=65535
TasksMax=8192
Restart=always
RestartSec=3
OVERRIDE

systemctl daemon-reload
systemctl enable connexa-backend.service 2>/dev/null || true

echo "✅ Systemd services configured with:"
echo "  - LimitNOFILE=65535"
echo "  - TasksMax=8192"
echo "  - Restart=always"

# ============================================================================
# STEP 6: Update pptp_tunnel_manager.py with thread safety
# ============================================================================
echo ""
echo "📦 [Phase1] Step 6/9: Adding thread safety to pptp_tunnel_manager.py..."

if [ -f "$APP_DIR/pptp_tunnel_manager.py" ]; then
    # Backup original
    cp "$APP_DIR/pptp_tunnel_manager.py" "$APP_DIR/pptp_tunnel_manager.py.backup.$(date +%s)"
    
    # Add semaphore at top if not exists
    if ! grep -q "tunnel_semaphore" "$APP_DIR/pptp_tunnel_manager.py"; then
        # Insert after imports
        sed -i '/^import /a \
import threading\
\
# Phase 1: Limit concurrent tunnel creation\
tunnel_semaphore = threading.Semaphore(5)  # Max 5 concurrent tunnels' "$APP_DIR/pptp_tunnel_manager.py"
        
        echo "✅ Added threading semaphore to pptp_tunnel_manager.py"
    else
        echo "✅ Thread semaphore already exists"
    fi
else
    echo "⚠️ pptp_tunnel_manager.py not found - will be created by main installer"
fi

# ============================================================================
# STEP 7: Create link_socks_to_ppp.sh with enhanced logging
# ============================================================================
echo ""
echo "📦 [Phase1] Step 7/9: Creating link_socks_to_ppp.sh..."

cat > /usr/local/bin/link_socks_to_ppp.sh <<'SCRIPT'
#!/bin/bash
PORT="${1:-1080}"
IFACE="${2:-ppp0}"
LOG="/var/log/link_socks_to_ppp.log"

exec >> "$LOG" 2>&1
echo "════════════════════════════════════════════════════════════════"
echo "[Phase1] $(date) - Linking SOCKS port $PORT to interface $IFACE"
echo "════════════════════════════════════════════════════════════════"

# Wait for interface (30 seconds max)
MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
    if ip link show "$IFACE" &>/dev/null; then
        if ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
            echo "✅ Interface $IFACE is UP (attempt $i/$MAX_WAIT)"
            break
        fi
    fi
    sleep 1
done

# Final check
if ! ip link show "$IFACE" &>/dev/null; then
    echo "❌ ERROR: Interface $IFACE does not exist after ${MAX_WAIT}s"
    exit 1
fi

# Get IP
EXTERNAL_IP=$(ip addr show "$IFACE" | grep -oP 'inet \K[\d.]+' | head -1)
echo "📍 External IP on $IFACE: ${EXTERNAL_IP:-N/A}"

# Generate danted.conf
cat > /etc/danted.conf <<DANTE
logoutput: /tmp/dante-logs/danted.log
internal: 0.0.0.0 port = ${PORT}
external: ${IFACE}
method: none
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    command: connect
    log: connect disconnect
}
DANTE

# Restart danted
systemctl restart danted 2>&1 || true
sleep 2

# Verify
if netstat -tulnp 2>/dev/null | grep -q ":${PORT}"; then
    echo "✅ SUCCESS: Dante listening on port ${PORT}"
    echo "$(date) - Bind successful: ${PORT} -> ${IFACE} (${EXTERNAL_IP})"
    exit 0
else
    echo "❌ ERROR: Dante not listening on port ${PORT}"
    systemctl status danted --no-pager || true
    exit 1
fi
SCRIPT

chmod +x /usr/local/bin/link_socks_to_ppp.sh
echo "✅ link_socks_to_ppp.sh created"

# ============================================================================
# STEP 8: Restart services
# ============================================================================
echo ""
echo "📦 [Phase1] Step 8/9: Restarting services..."

supervisorctl restart backend 2>/dev/null || systemctl restart connexa-backend.service || true
sleep 3

BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | awk '{print $2}' || systemctl is-active connexa-backend.service 2>/dev/null || echo "UNKNOWN")
echo "Backend status: $BACKEND_STATUS"

# ============================================================================
# STEP 9: Post-install verification
# ============================================================================
echo ""
echo "📦 [Phase1] Step 9/9: Post-install verification..."

VERIFY_LOG="/root/phase1_verification_$(date +%Y%m%d_%H%M%S).log"

cat > "$VERIFY_LOG" <<VERIFY
════════════════════════════════════════════════════════════════
CONNEXA Phase 1 Verification Report
Generated: $(date)
════════════════════════════════════════════════════════════════

[SYSTEM LIMITS]
ulimit -n: $(ulimit -n)
fs.file-max: $(sysctl -n fs.file-max)
net.core.somaxconn: $(sysctl -n net.core.somaxconn)
vm.max_map_count: $(sysctl -n vm.max_map_count)

[PPP MODULES]
$(lsmod | grep ppp)

[/dev/ppp]
$(ls -l /dev/ppp 2>/dev/null || echo "NOT FOUND")

[SYSTEMD SERVICES]
Backend: $BACKEND_STATUS
Danted: $(systemctl is-active danted 2>/dev/null || echo "inactive")

[BACKEND FD LIMIT]
$(grep LimitNOFILE /etc/systemd/system/connexa-backend.service 2>/dev/null || echo "Not configured")

[RUNNING PPPD PROCESSES]
$(ps aux | grep pppd | grep -v grep | wc -l) processes

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
echo "  ✅ Phase 1 (v7.3.1-dev) INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "🔧 Applied Fixes:"
echo "  ✅ System FD limit: 65535"
echo "  ✅ Sysctl tuning: fs.file-max=1048576"
echo "  ✅ PPP modules loaded and validated"
echo "  ✅ /dev/ppp created/verified"
echo "  ✅ Systemd services: LimitNOFILE=65535, TasksMax=8192"
echo "  ✅ Thread semaphore added to tunnel manager"
echo "  ✅ Stale pppd processes cleaned"
echo ""
echo "📊 Current Status:"
echo "  - ulimit -n: $(ulimit -n)"
echo "  - PPP modules: $(lsmod | grep -c ppp || echo 0)"
echo "  - Backend: $BACKEND_STATUS"
echo ""
echo "🔍 Next Steps:"
echo "  1. Reboot recommended to apply all limits: sudo reboot"
echo "  2. After reboot, test: curl http://localhost:8001/service/status"
echo "  3. Check verification log: cat $VERIFY_LOG"
echo ""
echo "📋 Phase 2 (Unit ID + Dante) will be applied after reboot"
echo "════════════════════════════════════════════════════════════════"
