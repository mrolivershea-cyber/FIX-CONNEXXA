#!/bin/bash
#
# CONNEXA Watchdog v7.9
# Monitors PPP interfaces and backend service
# Waits for backend to be ready before starting monitoring
#

LOGFILE="/var/log/connexa-watchdog.log"
BACKEND_URL="http://localhost:8001"
CHECK_INTERVAL=30

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Watchdog] $*" | tee -a "$LOGFILE"
}

# Trap signals for graceful shutdown
trap 'log "Received shutdown signal, exiting gracefully"; exit 0' SIGTERM SIGINT

log "=========================================="
log "CONNEXA Watchdog v7.9 starting"
log "=========================================="

# Initial delay to allow system startup
log "Initial startup delay (10 seconds)..."
sleep 10

# Wait for backend to become available
log "Waiting for backend to become available..."
BACKEND_READY=0
MAX_WAIT=120
WAITED=0

until curl -sf "${BACKEND_URL}/health" > /dev/null 2>&1 || curl -sf "${BACKEND_URL}/metrics" > /dev/null 2>&1; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        log "⚠️ Backend did not become available after ${MAX_WAIT}s, continuing anyway..."
        break
    fi
    
    log "Waiting for backend... (${WAITED}s/${MAX_WAIT}s)"
    sleep 3
    WAITED=$((WAITED + 3))
done

if [ $WAITED -lt $MAX_WAIT ]; then
    log "✅ Backend reachable. Starting monitoring loop."
    BACKEND_READY=1
else
    log "⚠️ Starting monitoring without backend confirmation"
fi

# Main monitoring loop
log "Entering monitoring loop (check interval: ${CHECK_INTERVAL}s)"
log "=========================================="

while true; do
    # Count PPP interfaces that are UP
    PPP_COUNT=$(ip a | grep -E "ppp[0-9].*UP" | wc -l || echo "0")
    
    # Check backend status
    if [ $BACKEND_READY -eq 1 ]; then
        if curl -sf "${BACKEND_URL}/health" > /dev/null 2>&1 || curl -sf "${BACKEND_URL}/metrics" > /dev/null 2>&1; then
            BACKEND_STATUS="UP"
        else
            BACKEND_STATUS="DOWN"
            log "⚠️ Backend is not responding"
        fi
    else
        BACKEND_STATUS="UNKNOWN"
    fi
    
    # Count SOCKS ports (common ports: 1080-1089)
    SOCKS_COUNT=0
    for port in {1080..1089}; do
        if lsof -i ":$port" > /dev/null 2>&1; then
            SOCKS_COUNT=$((SOCKS_COUNT + 1))
        fi
    done
    
    # Log status
    log "Status: PPP interfaces=$PPP_COUNT, Backend=$BACKEND_STATUS, SOCKS ports=$SOCKS_COUNT"
    
    # Check for issues
    if [ $PPP_COUNT -eq 0 ]; then
        log "⚠️ WARNING: No PPP interfaces detected!"
    fi
    
    if [ "$BACKEND_STATUS" = "DOWN" ]; then
        log "⚠️ WARNING: Backend service is not responding!"
    fi
    
    # Show active PPP interfaces
    if [ $PPP_COUNT -gt 0 ]; then
        log "Active PPP interfaces:"
        ip addr show | grep "ppp[0-9]:" | awk '{print "  - " $2}' | tee -a "$LOGFILE"
    fi
    
    # Sleep until next check
    sleep $CHECK_INTERVAL
done
