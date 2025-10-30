#!/bin/bash
# Minimal installation script for CONNEXA v7.4.6 fixes
# This script has minimal dependencies and can be used if the full script fails

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.6 - MINIMAL INSTALLATION"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "❌ ERROR: python3 is required but not found"
    echo "   Install with: apt-get install python3 (Debian/Ubuntu)"
    echo "            or: yum install python3 (CentOS/RHEL)"
    exit 1
fi

echo "✅ Python3 found: $(python3 --version)"

# Create directories
echo ""
echo "📦 Creating directories..."
mkdir -p /app/backend
mkdir -p /etc/ppp/peers
mkdir -p /var/log/ppp
echo "✅ Directories created"

# Check if we're in the repository directory
if [ ! -f "app/backend/pptp_tunnel_manager.py" ]; then
    echo ""
    echo "❌ ERROR: Not in repository directory"
    echo "   Please run this script from the FIX-CONNEXXA directory:"
    echo "   cd /path/to/FIX-CONNEXXA && bash install_minimal.sh"
    exit 1
fi

# Copy Python modules
echo ""
echo "📦 Installing Python modules..."

cp app/backend/pptp_tunnel_manager.py /app/backend/
cp app/backend/watchdog.py /app/backend/
cp app/backend/__init__.py /app/backend/ 2>/dev/null || true
cp app/__init__.py /app/ 2>/dev/null || true

echo "✅ Python modules copied to /app/backend/"

# Test Python modules
echo ""
echo "📦 Testing Python modules..."

if python3 -c "import sys; sys.path.insert(0, '/app'); from backend import pptp_tunnel_manager" 2>/dev/null; then
    echo "✅ pptp_tunnel_manager.py imports successfully"
else
    echo "❌ pptp_tunnel_manager.py import failed"
    python3 -c "import sys; sys.path.insert(0, '/app'); from backend import pptp_tunnel_manager"
    exit 1
fi

if python3 -c "import sys; sys.path.insert(0, '/app'); from backend import watchdog" 2>/dev/null; then
    echo "✅ watchdog.py imports successfully"
else
    echo "❌ watchdog.py import failed"
    python3 -c "import sys; sys.path.insert(0, '/app'); from backend import watchdog"
    exit 1
fi

# Compile Python modules
echo ""
echo "📦 Compiling Python modules..."
python3 -m py_compile /app/backend/pptp_tunnel_manager.py
python3 -m py_compile /app/backend/watchdog.py
echo "✅ Python modules compiled"

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ MINIMAL INSTALLATION COMPLETE"
echo "════════════════════════════════════════════════════════════════"

echo ""
echo "Installed files:"
echo "  - /app/backend/pptp_tunnel_manager.py"
echo "  - /app/backend/watchdog.py"

echo ""
echo "Next steps:"
echo "  1. If using supervisor, restart backend:"
echo "     supervisorctl restart backend"
echo ""
echo "  2. If using systemd, disable it first (to avoid port conflict):"
echo "     systemctl disable --now connexa-backend.service"
echo ""
echo "  3. Test the installation:"
echo "     python3 -c 'from app.backend.pptp_tunnel_manager import pptp_tunnel_manager; print(pptp_tunnel_manager)'"
echo ""
echo "  4. Run watchdog (optional):"
echo "     python3 -m app.backend.watchdog --once"
echo ""
echo "  5. See QUICKSTART.md for full usage instructions"

echo ""
echo "Note: This minimal script only installs Python modules."
echo "      For full setup (firewall, supervisor config), use:"
echo "      bash install_connexa_v7_4_6_patch.sh"
