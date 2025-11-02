#!/bin/bash
#
# CONNEXA v7.9 Self-Test Script
# Automatically verifies system health after installation or restart
#

set -e

LOGFILE="/var/log/connexa-selftest.log"
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=10

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# Test result function
test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC} - $test_name" | tee -a "$LOGFILE"
        [ -n "$details" ] && log "       $details"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}❌ FAIL${NC} - $test_name" | tee -a "$LOGFILE"
        [ -n "$details" ] && log "       $details"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

log "=========================================="
log "CONNEXA v7.9 SELF-TEST START"
log "=========================================="

# Test 1: Check if supervisor is running
log ""
log "[Test 1/10] Checking supervisor service..."
if systemctl is-active --quiet supervisor || supervisorctl status > /dev/null 2>&1; then
    test_result "Supervisor service" "PASS" "Supervisor is running"
else
    test_result "Supervisor service" "FAIL" "Supervisor is not running"
fi

# Test 2: Check backend process
log ""
log "[Test 2/10] Checking backend service..."
if supervisorctl status backend 2>/dev/null | grep -q "RUNNING"; then
    BACKEND_PID=$(supervisorctl status backend | awk '{print $NF}' | tr -d ',')
    test_result "Backend service" "PASS" "Backend is RUNNING (PID: $BACKEND_PID)"
else
    test_result "Backend service" "FAIL" "Backend is not running"
fi

# Test 3: Check backend port
log ""
log "[Test 3/10] Checking backend port 8081..."
sleep 2
if lsof -i :8081 > /dev/null 2>&1 || curl -sf http://localhost:8081/metrics > /dev/null 2>&1; then
    test_result "Backend port 8081" "PASS" "Port 8081 is listening"
else
    test_result "Backend port 8081" "FAIL" "Port 8081 is not accessible"
fi

# Test 4: Check watchdog
log ""
log "[Test 4/10] Checking watchdog service..."
if supervisorctl status watchdog 2>/dev/null | grep -q "RUNNING"; then
    test_result "Watchdog service" "PASS" "Watchdog is RUNNING"
else
    test_result "Watchdog service" "FAIL" "Watchdog is not running"
fi

# Test 5: Check PPP interfaces
log ""
log "[Test 5/10] Checking PPP interfaces..."
PPP_COUNT=$(ip addr show | grep -c "ppp[0-9]:" || echo "0")
if [ $PPP_COUNT -ge 1 ]; then
    test_result "PPP interfaces" "PASS" "Found $PPP_COUNT PPP interface(s)"
    ip addr show | grep "ppp[0-9]:" | awk '{print "       - " $2}' | tee -a "$LOGFILE"
else
    test_result "PPP interfaces" "FAIL" "No PPP interfaces found (expected >= 1)"
fi

# Test 6: Check for authentication errors
log ""
log "[Test 6/10] Checking for authentication errors..."
if ls /tmp/pptp_node*.log > /dev/null 2>&1; then
    AUTH_ERRORS=$(grep -l "peer refused to authenticate" /tmp/pptp_node*.log 2>/dev/null || true)
    if [ -z "$AUTH_ERRORS" ]; then
        test_result "Authentication" "PASS" "No authentication errors found"
    else
        ERROR_COUNT=$(echo "$AUTH_ERRORS" | wc -l)
        test_result "Authentication" "FAIL" "Found authentication errors in $ERROR_COUNT log file(s)"
        echo "$AUTH_ERRORS" | sed 's/^/       - /' | tee -a "$LOGFILE"
    fi
else
    test_result "Authentication" "PASS" "No PPTP logs found (no tunnels attempted yet)"
fi

# Test 7: Check for routing errors
log ""
log "[Test 7/10] Checking for routing errors..."
if [ -f /var/log/ppp-up.log ]; then
    ROUTE_ERRORS=$(grep -c "Nexthop has invalid gateway" /var/log/ppp-up.log 2>/dev/null || echo "0")
    if [ $ROUTE_ERRORS -eq 0 ]; then
        test_result "Routing" "PASS" "No 'Nexthop has invalid gateway' errors"
    else
        test_result "Routing" "FAIL" "Found $ROUTE_ERRORS routing error(s)"
    fi
else
    test_result "Routing" "PASS" "No routing log found yet"
fi

# Test 8: Check for invalid IP attempts
log ""
log "[Test 8/10] Checking for invalid IP attempts..."
if [ -f /var/log/connexa-tunnel-manager.log ]; then
    INVALID_IP=$(grep -c "invalid IP\|0\.0\.0\.2" /var/log/connexa-tunnel-manager.log 2>/dev/null || echo "0")
    if [ $INVALID_IP -eq 0 ]; then
        test_result "IP validation" "PASS" "No invalid IP attempts (0.0.0.x)"
    else
        test_result "IP validation" "FAIL" "Found $INVALID_IP invalid IP attempt(s)"
    fi
else
    test_result "IP validation" "PASS" "No tunnel manager log found yet"
fi

# Test 9: Check metrics endpoint
log ""
log "[Test 9/10] Checking metrics endpoint..."
if curl -sf http://localhost:8081/metrics > /dev/null 2>&1; then
    METRICS=$(curl -s http://localhost:8081/metrics 2>/dev/null || echo "")
    if echo "$METRICS" | grep -q "connexa"; then
        test_result "Metrics endpoint" "PASS" "Metrics endpoint is accessible"
        # Show relevant metrics
        echo "$METRICS" | grep "connexa_ppp" | sed 's/^/       /' | tee -a "$LOGFILE"
    else
        test_result "Metrics endpoint" "FAIL" "Metrics found but no connexa metrics"
    fi
else
    test_result "Metrics endpoint" "FAIL" "Metrics endpoint not accessible"
fi

# Test 10: Check SOCKS proxies
log ""
log "[Test 10/10] Checking SOCKS proxy ports..."
SOCKS_COUNT=0
for port in 1080 1081 1082 1083 1084 1085; do
    if lsof -i ":$port" > /dev/null 2>&1; then
        SOCKS_COUNT=$((SOCKS_COUNT + 1))
    fi
done
if [ $SOCKS_COUNT -ge 1 ]; then
    test_result "SOCKS proxies" "PASS" "Found $SOCKS_COUNT active SOCKS port(s)"
else
    test_result "SOCKS proxies" "FAIL" "No SOCKS proxies detected"
fi

# Summary
log ""
log "=========================================="
log "SELF-TEST SUMMARY"
log "=========================================="
log "Tests passed: $PASS_COUNT/$TOTAL_TESTS"
log "Tests failed: $FAIL_COUNT/$TOTAL_TESTS"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ Connexa selftest passed — All systems operational!${NC}" | tee -a "$LOGFILE"
    EXIT_CODE=0
elif [ $PASS_COUNT -ge 7 ]; then
    echo -e "${YELLOW}⚠️ Connexa selftest partial — Some issues detected but system is mostly functional${NC}" | tee -a "$LOGFILE"
    EXIT_CODE=0
else
    echo -e "${RED}❌ Connexa selftest failed — Critical issues detected${NC}" | tee -a "$LOGFILE"
    EXIT_CODE=1
fi

log "=========================================="
log "SELF-TEST COMPLETE"
log "=========================================="

exit $EXIT_CODE
