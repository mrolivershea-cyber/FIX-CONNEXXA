# CONNEXA - Changelog

All notable changes to this project will be documented in this file.

## [7.4.8] - 2025-10-30

### 🎯 Multi-Tunnel Authentication Fix

Based on production diagnostics showing ppp1/ppp2 authentication failures.

### Added
- 🧩 **Base peers template** - `/etc/ppp/peers/connexa` now auto-created on initialization
- 🔧 **Multi-tunnel support** - Proper MSCHAP-V2 configuration for all tunnel instances
- 🛡️ **Graceful error handling** - Permission errors logged as warnings in test environments

### Fixed
- 🧩 **Multi-tunnel authentication** - ppp1, ppp2, etc. now authenticate properly
- 🔐 **LCP termination** - "peer refused to authenticate" resolved for secondary tunnels
- 📋 **Base template missing** - `pppd call connexa` now has proper default configuration

### Changed
- 📦 Updated all version strings from v7.4.7 to v7.4.8
- 🏗️ Base peers template created during PPTPTunnelManager initialization
- ⚙️ Individual node configs (connexa-node-{id}) now override base template settings

### Technical Details

The base `/etc/ppp/peers/connexa` template includes:
- `require-mschap-v2` - Enforce MSCHAP-V2 authentication
- `refuse-pap`, `refuse-eap`, `refuse-chap` - Disable weaker auth methods
- `noauth` - Don't require peer authentication
- `persist`, `holdoff 5`, `maxfail 3` - Auto-reconnect behavior
- `mtu 1400`, `mru 1400` - Proper MTU/MRU for PPTP
- `defaultroute`, `usepeerdns` - Network configuration

Individual tunnel configs (connexa-node-{id}) supplement with:
- `name {username}` - Local username
- `remotename connexa-node-{node_id}` - Remote identifier
- `connect "/usr/sbin/pptp {node_ip} --nolaunchpppd"` - Connection command
- `user {username}` - Authentication username

### Installation
```bash
bash install_connexa_v7_4_8_patch.sh
```

### Verification
```bash
# Check base template exists
ls -la /etc/ppp/peers/connexa

# Verify authentication works for all tunnels
pppd call connexa-node-1 &
pppd call connexa-node-2 &
pppd call connexa-node-3 &

# Check all interfaces are UP
ip link show | grep ppp
```

---

## [7.4.7] - 2025-10-30

### 🎯 Stability and PPTP Authentication Fixes

Based on production testing feedback and server diagnostics.

### Added
- 🧩 Automatic generation of `/etc/ppp/peers/{node}` with full MSCHAP-V2 support
- 🧱 GRE firewall rules automatically configured during installation
- 🧠 Enhanced peer configuration with proper MTU/MRU settings (1400)
- 🔧 Version tracking in PPTPTunnelManager and WatchdogMonitor classes

### Fixed
- 🧩 **CHAP authentication failures** - "peer refused to authenticate" resolved
- ⚙️ **chap-secrets quoting** - Now uses proper quoted format for MS server compatibility
- 🧱 **Missing GRE rules** - iptables rules for protocol 47 (GRE) now added automatically
- 🧩 **SQL syntax error** - Added parentheses around OR conditions in diagnostic queries
- 🔕 **Nexthop gateway warnings** - Reclassified as info-level, not error
- 🚫 **Port 8001 conflicts** - Systemd backend unit now disabled during installation
- 🧩 **Watchdog recovery** - Now properly restarts backend after 3 cycles with 0 PPP interfaces

### Changed
- 📦 Updated all version strings from v7.4.6 to v7.4.7
- 🩺 Improved logging with version information in status messages
- 🧠 Enhanced peer file generation with additional PPTP parameters:
  - `holdoff 5` - Wait 5 seconds between reconnection attempts
  - `maxfail 3` - Maximum 3 consecutive failures before giving up
  - `lock` - Use UUCP-style locking
  - `noipdefault` - Don't use default IP
  - `defaultroute` - Add default route through PPP link
  - `usepeerdns` - Use DNS servers from peer

### Installation
```bash
# Full installation
bash install_connexa_v7_4_7_patch.sh

# Minimal installation
bash install_minimal.sh
```

### Verification
After installation, verify the deployment:
```bash
# Restart services
supervisorctl restart backend
supervisorctl restart watchdog

# Check metrics
curl -s http://localhost:8001/service/status-v2

# Expected output indicators:
# - connexa_ppp_interfaces > 0
# - connexa_socks_ports >= 1
# - connexa_backend_up: true
```

### Compatibility
- ✅ Compatible with CONNEXA v7.4.x database schema
- ✅ Works with supervisor and systemd service managers
- ✅ Tested on Ubuntu 20.04/22.04 and Debian 11/12

---

## [7.4.6] - 2025-10-30

### Initial Release - Critical Fixes

### Added
- ✅ PPTP Tunnel Manager module
- ✅ Watchdog Monitor with auto-restart capability
- ✅ Complete installation scripts (full and minimal)
- ✅ Comprehensive documentation

### Fixed
- FIX #1: Systemd/Supervisor port 8001 conflict
- FIX #2: Missing /etc/ppp/peers/connexa-node-{id} files
- FIX #3: Incorrect chap-secrets format (missing quotes)
- FIX #4: Gateway warnings logged as errors
- FIX #5: Watchdog not restarting backend on zero PPP
- FIX #6: SQL syntax errors with OR conditions
- FIX #7: PPTP firewall rules documentation

### Documentation
- Complete QUICKSTART.md guide
- Security analysis (SECURITY.md)
- Firewall configuration guide
- Systemd/Supervisor conflict resolution

---

## Format

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Types of changes
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes
