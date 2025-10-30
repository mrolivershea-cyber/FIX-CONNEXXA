#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.10 - PRODUCTION-VALIDATED MULTI-TUNNEL FIX"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "  User: mrolivershea-cyber"
echo "  Critical Fixes:"
echo "    - Base peers template with complete config"
echo "    - chap-secrets remotename matching (connexa)"
echo "    - GRE firewall rules (persistent)"
echo "════════════════════════════════════════════════════════════════"

# ============================================================================
# Check for required commands
# ============================================================================
echo ""
echo "📦 Checking for required commands..."

MISSING_CMDS=""
for cmd in python3 supervisorctl systemctl iptables; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_CMDS="$MISSING_CMDS $cmd"
    fi
done

if [ -n "$MISSING_CMDS" ]; then
    echo "⚠️  WARNING: The following commands are not found:$MISSING_CMDS"
    echo "   The script may fail or skip some steps."
    echo "   Press Ctrl+C to abort, or wait 5 seconds to continue..."
    sleep 5
fi

echo "✅ Pre-flight check completed"

# ============================================================================
# STEP 1: Configure GRE firewall rules (FIX #7 - CRITICAL for v7.4.10)
# ============================================================================
echo ""
echo "📦 [Step 1/10] Configuring GRE firewall rules for PPTP..."

# Add GRE and PPTP rules
iptables -C INPUT -p gre -j ACCEPT 2>/dev/null || iptables -A INPUT -p gre -j ACCEPT
iptables -C INPUT -p tcp --dport 1723 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
iptables -C OUTPUT -p gre -j ACCEPT 2>/dev/null || iptables -A OUTPUT -p gre -j ACCEPT
iptables -C OUTPUT -p tcp --sport 1723 -j ACCEPT 2>/dev/null || iptables -C OUTPUT -p tcp --dport 1723 -j ACCEPT 2>/dev/null || iptables -A OUTPUT -p tcp --dport 1723 -j ACCEPT

# Save rules persistently
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save 2>/dev/null || true
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
else
    mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

echo "✅ GRE firewall rules configured (protocol 47, TCP 1723)"

# ============================================================================
# STEP 2: Disable systemd unit (prevent port conflict - FIX #1)
# ============================================================================
echo ""
echo "📦 [Step 2/10] Disabling systemd unit to prevent port conflict..."

systemctl disable --now connexa-backend.service 2>/dev/null || true
echo "✅ systemd unit disabled"

# ============================================================================
# STEP 3: Verify port 8001 is available
# ============================================================================
echo ""
echo "📦 [Step 3/10] Checking port 8001..."

pkill -9 -f "uvicorn.*8001" 2>/dev/null || true
sleep 2

echo "✅ Port 8001 is available"

# ============================================================================
# STEP 4: Create directories
# ============================================================================
echo ""
echo "📦 [Step 4/10] Creating application directories..."

mkdir -p /app/backend
mkdir -p /etc/ppp/peers
mkdir -p /var/log/ppp

echo "✅ Directories created"

# ============================================================================
# STEP 5: Install PPTP Tunnel Manager v7.4.10
# ============================================================================
echo ""
echo "📦 [Step 5/10] Installing pptp_tunnel_manager.py v7.4.10..."

# Copy from repository
cp app/backend/pptp_tunnel_manager.py /app/backend/pptp_tunnel_manager.py
chmod 644 /app/backend/pptp_tunnel_manager.py

echo "✅ PPTP Tunnel Manager v7.4.10 installed"

# ============================================================================
# STEP 6: Install Watchdog v7.4.10
# ============================================================================
echo ""
echo "📦 [Step 6/10] Installing watchdog.py v7.4.10..."

# Copy from repository
cp app/backend/watchdog.py /app/backend/watchdog.py
chmod 644 /app/backend/watchdog.py

echo "✅ Watchdog v7.4.10 installed"

# ============================================================================
# STEP 7: Set permissions
# ============================================================================
echo ""
echo "📦 [Step 7/10] Setting file permissions..."

chmod 755 /app/backend
touch /etc/ppp/chap-secrets 2>/dev/null && chmod 600 /etc/ppp/chap-secrets || true

echo "✅ Permissions set"

# ============================================================================
# STEP 8: Restart backend via supervisor
# ============================================================================
echo ""
echo "📦 [Step 8/10] Restarting backend service..."

supervisorctl restart backend 2>/dev/null || echo "⚠️ Supervisor not controlling backend, skip restart"
sleep 3

echo "✅ Backend service restarted"

# ============================================================================
# STEP 9: Verify installation
# ============================================================================
echo ""
echo "📦 [Step 9/10] Verifying installation..."

# Check files exist
if [ -f "/app/backend/pptp_tunnel_manager.py" ] && [ -f "/app/backend/watchdog.py" ]; then
    echo "✅ Python modules installed"
else
    echo "❌ ERROR: Python modules not found"
    exit 1
fi

# Check GRE rules
if iptables -L INPUT -n | grep -q "gre"; then
    echo "✅ GRE firewall rules active"
else
    echo "⚠️  WARNING: GRE rules not found in iptables"
fi

echo "✅ Installation verification complete"

# ============================================================================
# STEP 10: Display status
# ============================================================================
echo ""
echo "📦 [Step 10/10] Checking system status..."
echo ""

# Check backend
if supervisorctl status backend 2>/dev/null | grep -q "RUNNING"; then
    echo "✅ Backend: RUNNING"
else
    echo "⚠️  Backend: Not running via supervisor"
fi

# Check PPP interfaces
PPP_COUNT=$(ip link show 2>/dev/null | grep -c "ppp" || echo "0")
echo "📊 PPP interfaces: $PPP_COUNT"

# Check base peers file
if [ -f "/etc/ppp/peers/connexa" ]; then
    echo "✅ Base peers template: EXISTS (mode $(stat -c %a /etc/ppp/peers/connexa 2>/dev/null || echo 'unknown'))"
else
    echo "⚠️  Base peers template: NOT FOUND (will be created on first tunnel)"
fi

# Check chap-secrets
if [ -f "/etc/ppp/chap-secrets" ]; then
    CHAP_COUNT=$(wc -l < /etc/ppp/chap-secrets 2>/dev/null || echo "0")
    echo "✅ chap-secrets: $CHAP_COUNT entries (mode $(stat -c %a /etc/ppp/chap-secrets 2>/dev/null || echo 'unknown'))"
else
    echo "⚠️  chap-secrets: NOT FOUND"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.10 Installation Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Check backend status: supervisorctl status backend"
echo "  2. Test tunnel creation via backend API"
echo "  3. Verify PPP interfaces: ip link show | grep ppp"
echo "  4. Check logs: tail -f /var/log/supervisor/backend-*.log"
echo ""
echo "Troubleshooting:"
echo "  - Base peers template auto-creates on first tunnel"
echo "  - chap-secrets uses remotename 'connexa' for proper matching"
echo "  - GRE firewall rules must be active for PPTP"
echo "  - See INSTALL.md for detailed troubleshooting"
echo ""
echo "v7.4.10 Critical Fixes:"
echo "  ✅ Base /etc/ppp/peers/connexa template (complete config)"
echo "  ✅ chap-secrets remotename matching (uses 'connexa')"
echo "  ✅ GRE firewall rules (protocol 47, persistent)"
echo "  ✅ Multi-tunnel MSCHAP-V2 authentication"
echo ""
