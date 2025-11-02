#!/bin/bash
# CONNEXA v7.9 - PPP IP-UP Script
# Called when PPP interface comes up

PPP_IFACE=$1
LOCAL IP=$4
REMOTEIP=$5
LOG="/var/log/ppp-up.log"

echo "$(date): [PPP-UP] Interface=$PPP_IFACE Local=$LOCALIP Remote=$REMOTEIP" >> $LOG

# Add route only for remote address
if [ -n "$REMOTEIP" ]; then
  ip route replace $REMOTEIP/32 dev $PPP_IFACE
  echo "$(date): ✅ Added route for $REMOTEIP via $PPP_IFACE" >> $LOG
else
  echo "$(date): ⚠️ No remote IP detected for $PPP_IFACE" >> $LOG
fi

# Start SOCKS if script exists
if [ -f /usr/local/bin/socks_start.sh ]; then
  /usr/local/bin/socks_start.sh $PPP_IFACE $LOCALIP >> $LOG 2>&1
fi

exit 0
