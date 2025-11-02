#!/bin/bash
# CONNEXA v7.9 - PPP IP-DOWN Script
# Called when PPP interface goes down

PPP_IFACE=$1
REMOTEIP=$5
LOG="/var/log/ppp-down.log"

echo "$(date): [PPP-DOWN] Interface=$PPP_IFACE Remote=$REMOTEIP" >> $LOG

if [ -n "$REMOTEIP" ]; then
  ip route del $REMOTEIP/32 dev $PPP_IFACE 2>/dev/null || true
  echo "$(date): ❌ Removed route for $REMOTEIP ($PPP_IFACE)" >> $LOG
fi

# Stop SOCKS if script exists
if [ -f /usr/local/bin/socks_stop.sh ]; then
  /usr/local/bin/socks_stop.sh $PPP_IFACE >> $LOG 2>&1
fi

exit 0
