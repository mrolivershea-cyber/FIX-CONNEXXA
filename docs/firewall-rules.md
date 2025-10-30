# PPTP Firewall Rules (FIX #7)

## Overview

PPTP (Point-to-Point Tunneling Protocol) requires specific firewall rules to allow proper tunnel establishment. This document provides the necessary iptables rules for CONNEXA v7.4.6.

## Required Protocols

PPTP uses two protocols:
1. **TCP port 1723** - Control connection
2. **GRE (protocol 47)** - Data tunnel

## Firewall Rules

### Add PPTP Rules

```bash
#!/bin/bash
# Add PPTP firewall rules

# Allow incoming PPTP control connection
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT

# Allow incoming GRE (PPTP data tunnel)
iptables -A INPUT -p gre -j ACCEPT

# Allow outgoing PPTP control connection
iptables -A OUTPUT -p tcp --sport 1723 -j ACCEPT

# Allow outgoing GRE (PPTP data tunnel)
iptables -A OUTPUT -p gre -j ACCEPT

echo "✅ PPTP firewall rules added"
```

### For PPTP Client (CONNEXA Use Case)

When CONNEXA acts as a PPTP client connecting to remote servers:

```bash
#!/bin/bash
# PPTP Client firewall rules

# Allow outgoing PPTP control connection to remote servers
iptables -A OUTPUT -p tcp --dport 1723 -j ACCEPT

# Allow incoming PPTP control responses
iptables -A INPUT -p tcp --sport 1723 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outgoing GRE packets
iptables -A OUTPUT -p gre -j ACCEPT

# Allow incoming GRE packets
iptables -A INPUT -p gre -j ACCEPT

echo "✅ PPTP client firewall rules added"
```

## Installation Script

Save as `/usr/local/bin/setup-pptp-firewall.sh`:

```bash
#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  CONNEXA v7.4.6 - PPTP Firewall Setup"
echo "════════════════════════════════════════════════════════════════"

# Check if iptables is installed
if ! command -v iptables &> /dev/null; then
    echo "❌ iptables not found. Installing..."
    apt-get update -qq
    apt-get install -y iptables
fi

echo ""
echo "Adding PPTP firewall rules..."

# INPUT rules for PPTP
if ! iptables -C INPUT -p gre -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p gre -j ACCEPT
    echo "✅ Added INPUT rule for GRE"
else
    echo "ℹ️  INPUT GRE rule already exists"
fi

if ! iptables -C INPUT -p tcp --dport 1723 -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
    echo "✅ Added INPUT rule for TCP 1723"
else
    echo "ℹ️  INPUT TCP 1723 rule already exists"
fi

# OUTPUT rules for PPTP
if ! iptables -C OUTPUT -p gre -j ACCEPT 2>/dev/null; then
    iptables -A OUTPUT -p gre -j ACCEPT
    echo "✅ Added OUTPUT rule for GRE"
else
    echo "ℹ️  OUTPUT GRE rule already exists"
fi

if ! iptables -C OUTPUT -p tcp --sport 1723 -j ACCEPT 2>/dev/null; then
    iptables -A OUTPUT -p tcp --sport 1723 -j ACCEPT
    echo "✅ Added OUTPUT rule for TCP 1723"
else
    echo "ℹ️  OUTPUT TCP 1723 rule already exists"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Current PPTP-related iptables rules:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "INPUT rules:"
iptables -L INPUT -n -v | grep -E "gre|1723" || echo "No PPTP INPUT rules"
echo ""
echo "OUTPUT rules:"
iptables -L OUTPUT -n -v | grep -E "gre|1723" || echo "No PPTP OUTPUT rules"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Saving rules..."
echo "════════════════════════════════════════════════════════════════"

# Save rules to persist across reboots
if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || \
    echo "⚠️  Could not save iptables rules to file"
    
    echo "✅ iptables rules saved"
else
    echo "⚠️  iptables-save not available, install iptables-persistent package"
fi

echo ""
echo "✅ PPTP firewall setup complete!"
```

Make it executable:

```bash
chmod +x /usr/local/bin/setup-pptp-firewall.sh
```

Run it:

```bash
/usr/local/bin/setup-pptp-firewall.sh
```

## Verification

### Check if rules are applied:

```bash
# Check INPUT rules
iptables -L INPUT -n -v | grep -E "gre|1723"

# Check OUTPUT rules
iptables -L OUTPUT -n -v | grep -E "gre|1723"
```

Expected output:
```
    0     0 ACCEPT     gre  --  *      *       0.0.0.0/0            0.0.0.0/0
    0     0 ACCEPT     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:1723
```

### Test PPTP connectivity:

```bash
# Test TCP connection to PPTP server
nc -zv <pptp-server-ip> 1723

# Check if GRE is allowed (requires active connection)
tcpdump -i any proto gre
```

## Persistence Across Reboots

### Option A: Use iptables-persistent

```bash
# Install iptables-persistent
apt-get install -y iptables-persistent

# During installation, answer "Yes" to save current rules
# Or manually save:
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
```

### Option B: Add to rc.local

```bash
# Add to /etc/rc.local (before 'exit 0')
/usr/local/bin/setup-pptp-firewall.sh
```

### Option C: Create systemd service

Create `/etc/systemd/system/pptp-firewall.service`:

```ini
[Unit]
Description=PPTP Firewall Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-pptp-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
systemctl enable pptp-firewall.service
systemctl start pptp-firewall.service
```

## Troubleshooting

### Issue: PPTP connection hangs at "Sending PPTP Start Control Connection Request"

**Solution:** Check if GRE is allowed:
```bash
iptables -L INPUT -v | grep gre
iptables -L OUTPUT -v | grep gre
```

### Issue: "Connection refused" on port 1723

**Solution:** Check if TCP 1723 is allowed:
```bash
iptables -L INPUT -v | grep 1723
iptables -L OUTPUT -v | grep 1723
```

### Issue: Rules disappear after reboot

**Solution:** Install iptables-persistent or create systemd service (see Persistence section above)

## Cloud Provider Considerations

### AWS EC2
- Security Groups must allow:
  - TCP 1723 (inbound/outbound)
  - Protocol 47 (GRE) (inbound/outbound)

### Azure
- Network Security Group (NSG) must allow:
  - TCP 1723
  - Protocol 47 (GRE)

### Google Cloud
- Firewall rules must allow:
  - TCP 1723
  - Protocol 47 (GRE)

### DigitalOcean
- UFW/iptables rules as documented above

## Related Commands

```bash
# Remove PPTP rules
iptables -D INPUT -p gre -j ACCEPT
iptables -D INPUT -p tcp --dport 1723 -j ACCEPT
iptables -D OUTPUT -p gre -j ACCEPT
iptables -D OUTPUT -p tcp --sport 1723 -j ACCEPT

# List all rules with line numbers
iptables -L INPUT --line-numbers
iptables -L OUTPUT --line-numbers

# Flush all rules (CAUTION!)
iptables -F
```

## Security Considerations

1. **Limit source IPs:** For production, restrict PPTP access to known IPs:
   ```bash
   iptables -A INPUT -p tcp -s <trusted-ip> --dport 1723 -j ACCEPT
   iptables -A INPUT -p tcp --dport 1723 -j DROP
   ```

2. **Use VPN instead:** PPTP is considered less secure. Consider:
   - OpenVPN
   - WireGuard
   - IPSec/IKEv2

3. **Monitor logs:** Watch for failed PPTP attempts:
   ```bash
   tail -f /var/log/messages | grep -i pptp
   ```

---

**Version:** v7.4.6  
**Date:** 2025-10-30  
**Fix:** #7 - PPTP firewall rules  
**Optional:** This is a helper enhancement, not required for basic functionality
