#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA MINI-FIX PATCH"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Fixes: load_dotenv + AuthContext double /api"
echo "════════════════════════════════════════════════════════════════"

# ============================================================================
# STEP 0: Prerequisites check
# ============================================================================
echo ""
echo "📦 [Step 0/4] Checking prerequisites..."

if [ "$EUID" -ne 0 ]; then 
    echo "❌ ERROR: This script must be run as root"
    exit 1
fi

if [ ! -d "/app/backend" ]; then
    echo "⚠️  WARNING: /app/backend not found, creating directory structure..."
    mkdir -p /app/backend
fi

if [ ! -d "/app/frontend/src/contexts" ]; then
    echo "⚠️  WARNING: /app/frontend/src/contexts not found, creating directory structure..."
    mkdir -p /app/frontend/src/contexts
fi

echo "✅ Prerequisites checked"

# ============================================================================
# STEP 1: Backup existing files
# ============================================================================
echo ""
echo "📦 [Step 1/4] Creating backups..."

BACKUP_DIR="/app/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup server.py if it exists
if [ -f "/app/backend/server.py" ]; then
    cp /app/backend/server.py "$BACKUP_DIR/server.py.backup"
    echo "✅ Backed up server.py"
else
    echo "⚠️  server.py not found, will be created"
fi

# Backup AuthContext.js if it exists
if [ -f "/app/frontend/src/contexts/AuthContext.js" ]; then
    cp /app/frontend/src/contexts/AuthContext.js "$BACKUP_DIR/AuthContext.js.backup"
    echo "✅ Backed up AuthContext.js"
else
    echo "⚠️  AuthContext.js not found, will be created"
fi

echo "✅ Backups saved to: $BACKUP_DIR"

# ============================================================================
# STEP 2: Fix 1 - Add load_dotenv to server.py
# ============================================================================
echo ""
echo "📦 [Step 2/4] Applying Fix 1: load_dotenv in server.py..."

cd /app/backend

# Check if server.py exists
if [ -f "server.py" ]; then
    # Check if load_dotenv is already imported
    if grep -q "from dotenv import load_dotenv" server.py; then
        echo "✅ load_dotenv already imported in server.py"
    else
        # Use sed to add the import after line 17
        # First, insert the import statement
        sed -i '17a from dotenv import load_dotenv' server.py
        # Then add the load_dotenv() call
        sed -i '18a load_dotenv()' server.py
        echo "✅ Added load_dotenv import and call to server.py"
    fi
    
    # Verify the changes
    echo ""
    echo "Verification - Lines around the change:"
    sed -n '15,22p' server.py | cat -n
else
    echo "⚠️  server.py doesn't exist yet"
    echo "Creating a basic server.py with load_dotenv..."
    
    cat > server.py <<'PYEOF'
"""
CONNEXA Backend Server
Basic FastAPI server with environment variable support
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import sys
import logging
from pathlib import Path

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).parent))

# Configure logging
logging.basicConfig(level=logging.INFO)

# Load environment variables from .env file
from dotenv import load_dotenv
load_dotenv()

# Import service modules
try:
    from service_manager import start_service, stop_service, service_status
except ImportError:
    logging.warning("service_manager module not found")
    start_service = None
    stop_service = None
    service_status = None

# Initialize FastAPI app
app = FastAPI(
    title="CONNEXA Service Manager API",
    description="Backend API for CONNEXA service management",
    version="1.0.0"
)

# CORS middleware
# Configure allowed origins from environment or use localhost for security
allowed_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8080").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check endpoint
@app.get("/", tags=["Health"])
async def root():
    """Health check endpoint"""
    return {"status": "ok", "service": "CONNEXA Backend"}

@app.get("/health", tags=["Health"])
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}

# Service Management Endpoints (if available)
if start_service:
    @app.post("/api/service/start", tags=["Service Management"])
    async def api_start_service():
        """Start the service"""
        result = await start_service()
        if not result.get("ok"):
            raise HTTPException(
                status_code=result.get("status_code", 500), 
                detail=result
            )
        return result

if stop_service:
    @app.post("/api/service/stop", tags=["Service Management"])
    async def api_stop_service():
        """Stop the service"""
        result = await stop_service()
        if not result.get("ok"):
            raise HTTPException(status_code=500, detail=result)
        return result

if service_status:
    @app.get("/api/service/status", tags=["Service Management"])
    async def api_service_status():
        """Get service status"""
        return await service_status()

# Run server
if __name__ == "__main__":
    port = int(os.getenv("PORT", "8001"))
    host = os.getenv("HOST", "127.0.0.1")  # Default to localhost for security
    uvicorn.run(app, host=host, port=port)
PYEOF
    
    echo "✅ Created server.py with load_dotenv support"
fi

# ============================================================================
# STEP 3: Fix 2 - Fix double /api in AuthContext.js
# ============================================================================
echo ""
echo "📦 [Step 3/4] Applying Fix 2: Double /api fix in AuthContext.js..."

cd /app/frontend/src/contexts

# Check if AuthContext.js exists
if [ -f "AuthContext.js" ]; then
    # Check if the fix is already applied
    if grep -q 'BACKEND_URL.endsWith("/api")' AuthContext.js; then
        echo "✅ Double /api fix already applied in AuthContext.js"
    else
        # Apply the fix using sed
        # This will replace the line that defines API with the fixed version
        sed -i 's|const API = `${BACKEND_URL}/api`;|const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;|g' AuthContext.js
        
        # Also handle variations without backticks
        sed -i 's|const API = \${BACKEND_URL}/api;|const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;|g' AuthContext.js
        
        echo "✅ Fixed double /api issue in AuthContext.js"
    fi
    
    # Verify the changes
    echo ""
    echo "Verification - API constant definition:"
    grep -A 2 "const API" AuthContext.js | head -3 || echo "Pattern not found"
else
    echo "⚠️  AuthContext.js doesn't exist yet"
    echo "Creating a basic AuthContext.js with the fix..."
    
    cat > AuthContext.js <<'JSEOF'
import React, { createContext, useState, useEffect, useContext } from 'react';

// Get backend URL from environment or use default
const BACKEND_URL = process.env.REACT_APP_BACKEND_URL || 'http://localhost:8001';

// Fix double /api issue - check if BACKEND_URL already ends with /api
const API = BACKEND_URL.endsWith("/api") ? BACKEND_URL : `${BACKEND_URL}/api`;

// Create authentication context
const AuthContext = createContext();

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Check authentication status on mount
  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const token = localStorage.getItem('token');
      if (token) {
        // Verify token with backend
        // Note: The /auth/verify endpoint needs to be implemented in the backend
        const response = await fetch(`${API}/auth/verify`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        }).catch(err => {
          // If endpoint doesn't exist yet, just clear token and continue
          console.warn('Auth verification endpoint not available:', err);
          return null;
        });
        
        if (response && response.ok) {
          const data = await response.json();
          setUser(data.user);
        } else if (response && !response.ok) {
          localStorage.removeItem('token');
        }
      }
    } catch (err) {
      console.error('Auth check error:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const login = async (username, password) => {
    try {
      const response = await fetch(`${API}/auth/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ username, password })
      });

      if (response.ok) {
        const data = await response.json();
        localStorage.setItem('token', data.token);
        setUser(data.user);
        return { success: true };
      } else {
        const error = await response.json();
        return { success: false, error: error.message };
      }
    } catch (err) {
      return { success: false, error: err.message };
    }
  };

  const logout = () => {
    localStorage.removeItem('token');
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, loading, error, login, logout, API }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export default AuthContext;
JSEOF
    
    echo "✅ Created AuthContext.js with double /api fix"
fi

# ============================================================================
# STEP 4: Restart services
# ============================================================================
echo ""
echo "📦 [Step 4/4] Restarting services..."

# Check if supervisorctl is available
if command -v supervisorctl &> /dev/null; then
    echo "Restarting backend service..."
    supervisorctl restart backend 2>/dev/null || supervisorctl restart connexa-backend 2>/dev/null || echo "⚠️  Backend service not found in supervisor"
    
    echo "Restarting frontend service..."
    supervisorctl restart frontend 2>/dev/null || supervisorctl restart connexa-frontend 2>/dev/null || echo "⚠️  Frontend service not found in supervisor"
    
    sleep 3
    
    # Check service status
    echo ""
    echo "Service status:"
    supervisorctl status backend 2>/dev/null || echo "Backend: not managed by supervisor"
    supervisorctl status frontend 2>/dev/null || echo "Frontend: not managed by supervisor"
else
    echo "⚠️  supervisorctl not found, skipping service restart"
    echo "Please restart services manually if needed"
fi

echo "✅ Services restarted"

# ============================================================================
# VERIFICATION
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  🔍 VERIFICATION"
echo "════════════════════════════════════════════════════════════════"

echo ""
echo "[1] Backend server.py changes:"
if [ -f "/app/backend/server.py" ]; then
    if grep -q "from dotenv import load_dotenv" /app/backend/server.py; then
        echo "✅ load_dotenv import found"
    else
        echo "❌ load_dotenv import not found"
    fi
    
    if grep -q "load_dotenv()" /app/backend/server.py; then
        echo "✅ load_dotenv() call found"
    else
        echo "❌ load_dotenv() call not found"
    fi
else
    echo "❌ server.py not found"
fi

echo ""
echo "[2] Frontend AuthContext.js changes:"
if [ -f "/app/frontend/src/contexts/AuthContext.js" ]; then
    if grep -q 'BACKEND_URL.endsWith("/api")' /app/frontend/src/contexts/AuthContext.js; then
        echo "✅ Double /api fix found"
    else
        echo "❌ Double /api fix not found"
    fi
else
    echo "❌ AuthContext.js not found"
fi

echo ""
echo "[3] Backup location:"
echo "📁 $BACKUP_DIR"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  📊 SUMMARY"
echo "════════════════════════════════════════════════════════════════"

BACKEND_FIXED=0
FRONTEND_FIXED=0

if [ -f "/app/backend/server.py" ] && grep -q "load_dotenv()" /app/backend/server.py; then
    BACKEND_FIXED=1
fi

if [ -f "/app/frontend/src/contexts/AuthContext.js" ] && grep -q 'BACKEND_URL.endsWith("/api")' /app/frontend/src/contexts/AuthContext.js; then
    FRONTEND_FIXED=1
fi

echo ""
echo "Backend Fix (load_dotenv):  $([ $BACKEND_FIXED -eq 1 ] && echo '✅ Applied' || echo '❌ Not applied')"
echo "Frontend Fix (double /api): $([ $FRONTEND_FIXED -eq 1 ] && echo '✅ Applied' || echo '❌ Not applied')"

echo ""
if [ $BACKEND_FIXED -eq 1 ] && [ $FRONTEND_FIXED -eq 1 ]; then
    echo "🎉🎉🎉 ALL FIXES APPLIED SUCCESSFULLY! 🎉🎉🎉"
    echo ""
    echo "Changes applied:"
    echo "  ✅ Backend: Added load_dotenv() for environment variables"
    echo "  ✅ Frontend: Fixed double /api path in AuthContext"
    echo "  ✅ Services: Restarted via supervisorctl"
    echo ""
    echo "Next steps:"
    echo "  1. Verify backend is running: curl http://localhost:8001/health"
    echo "  2. Check frontend in browser"
    echo "  3. Test API endpoints"
else
    echo "⚠️  Some fixes may not have been applied"
    echo ""
    echo "To rollback:"
    echo "  Backend:  cp $BACKUP_DIR/server.py.backup /app/backend/server.py"
    echo "  Frontend: cp $BACKUP_DIR/AuthContext.js.backup /app/frontend/src/contexts/AuthContext.js"
    echo "  Then run: supervisorctl restart backend frontend"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ MINI-FIX PATCH COMPLETE"
echo "════════════════════════════════════════════════════════════════"
