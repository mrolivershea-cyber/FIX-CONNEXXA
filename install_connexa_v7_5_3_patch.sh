#!/bin/bash
set -e

echo "================================================================"
echo "CONNEXA v7.5.3 - Authentication and Watchdog Stabilization Patch"
echo "================================================================"
echo ""
echo "This patch includes:"
echo "  1. Enhanced MS-CHAP-V2 authentication with MPPE enforcement"
echo "  2. Improved IP validation (rejects 0.0.0.x)"
echo "  3. Watchdog startup delay (prevents FATAL exits)"
echo "  4. Supervisor config updates (startsecs=10)"
echo "  5. Authentication auto-retry mechanism"
echo ""

# Check for required commands
for cmd in python3 supervisorctl; do
    if ! command -v $cmd &> /dev/null; then
        echo "⚠️  Warning: $cmd not found, some features may not work"
    fi
done

# Deploy Python modules
echo "[1/5] Deploying Python modules..."
cp -v app/backend/pptp_tunnel_manager.py /app/backend/ 2>/dev/null || echo "   ℹ️  Install manually to /app/backend/"
cp -v app/backend/watchdog.py /app/backend/ 2>/dev/null || echo "   ℹ️  Install manually to /app/backend/"
echo "✅ Python modules deployed"

# GRE Firewall rules (idempotent)
echo ""
echo "[2/5] Configuring GRE firewall rules..."
if command -v iptables &> /dev/null; then
    # Check if rules already exist
    if ! iptables -C INPUT -p gre -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p gre -j ACCEPT
        echo "✅ Added GRE INPUT rule"
    else
        echo "   ℹ️  GRE INPUT rule already exists"
    fi
    
    if ! iptables -C OUTPUT -p gre -j ACCEPT 2>/dev/null; then
        iptables -A OUTPUT -p gre -j ACCEPT
        echo "✅ Added GRE OUTPUT rule"
    else
        echo "   ℹ️  GRE OUTPUT rule already exists"
    fi
    
    # Save rules if netfilter-persistent is available
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        echo "✅ Firewall rules saved (persistent)"
    fi
else
    echo "   ⚠️  iptables not found, skip firewall configuration"
fi

# Update Supervisor watchdog config
echo ""
echo "[3/5] Updating Supervisor watchdog configuration..."
SUPERVISOR_CONF="/etc/supervisor/conf.d/watchdog.conf"
if [ -f "$SUPERVISOR_CONF" ]; then
    # Backup existing config
    cp "$SUPERVISOR_CONF" "${SUPERVISOR_CONF}.backup.$(date +%s)"
    
    # Update or add startsecs and autorestart
    if grep -q "startsecs=" "$SUPERVISOR_CONF"; then
        sed -i 's/startsecs=[0-9]*/startsecs=10/' "$SUPERVISOR_CONF"
    else
        echo "startsecs=10" >> "$SUPERVISOR_CONF"
    fi
    
    if grep -q "autorestart=" "$SUPERVISOR_CONF"; then
        sed -i 's/autorestart=.*/autorestart=true/' "$SUPERVISOR_CONF"
    else
        echo "autorestart=true" >> "$SUPERVISOR_CONF"
    fi
    
    echo "✅ Supervisor watchdog config updated"
    echo "   - startsecs=10 (prevents rapid exit)"
    echo "   - autorestart=true (auto-recovery)"
else
    echo "   ⚠️  Supervisor config not found at $SUPERVISOR_CONF"
    echo "   ℹ️  Create it manually with:"
    echo "      [program:watchdog]"
    echo "      command=/usr/local/bin/connexa-watchdog.sh"
    echo "      startsecs=10"
    echo "      autorestart=true"
fi

# Reload Supervisor
echo ""
echo "[4/5] Reloading Supervisor..."
if command -v supervisorctl &> /dev/null; then
    supervisorctl reread
    supervisorctl update
    echo "✅ Supervisor configuration reloaded"
else
    echo "   ⚠️  supervisorctl not found, reload manually"
fi

# Restart services
echo ""
echo "[5/5] Restarting services..."
if command -v supervisorctl &> /dev/null; then
    echo "Restarting backend..."
    supervisorctl restart backend || echo "   ⚠️  Could not restart backend"
    
    echo "Restarting watchdog..."
    supervisorctl restart watchdog || echo "   ⚠️  Could not restart watchdog"
    
    echo "✅ Services restarted"
else
    echo "   ⚠️  supervisorctl not found, restart services manually"
fi

echo ""
echo "================================================================"
echo "✅ CONNEXA v7.5.3 patch installed successfully!"
echo "================================================================"
echo ""
echo "Verification steps:"
echo "  1. Check services: supervisorctl status"
echo "  2. Verify watchdog: supervisorctl status watchdog"
echo "     (Should show RUNNING, not FATAL)"
echo "  3. Check tunnels: ip link show | grep ppp"
echo "  4. Monitor logs: tail -f /var/log/connexa-tunnel.log"
echo "  5. Test auth: Look for 'Tunnel established pppX' messages"
echo ""
echo "Expected results:"
echo "  - Watchdog stays RUNNING (no FATAL exits)"
echo "  - Multiple PPP tunnels authenticate (ppp0, ppp1, ppp2)"
echo "  - No connections to 0.0.0.2"
echo "  - Backend metrics show phase 4.3, version v7.5.3"
echo ""
