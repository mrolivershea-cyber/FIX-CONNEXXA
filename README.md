# CONNEXA v7.4.8 - PPTP Tunnel Fix

**Fix 7 critical bugs preventing PPTP tunnels from establishing and causing backend restart loops.**

## 🚀 Quick Install (One Command - RECOMMENDED)

**Having trouble downloading files? Use our universal installer:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/download_and_install.sh)
```

Or with wget:
```bash
bash <(wget -qO- https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/download_and_install.sh)
```

**What this does:**
- ✅ Auto-detects wget/curl
- ✅ Downloads latest v7.4.8 patch
- ✅ Handles all download errors
- ✅ Works without git

## 📋 What's Fixed in v7.4.8

- ✅ **Systemd/Supervisor port conflict** (port 8001)
- ✅ **PPTP peer configuration** with MSCHAP-V2
- ✅ **Multi-tunnel authentication** (ppp0, ppp1, ppp2, etc.) ⭐ NEW
- ✅ **Base template creation** `/etc/ppp/peers/connexa` ⭐ NEW  
- ✅ **CHAP-secrets format** with proper quoting
- ✅ **Watchdog auto-restart** on zero PPP interfaces
- ✅ **SQL syntax errors** in queries
- ✅ **Firewall rules** for PPTP (GRE + TCP 1723)

## 🔧 Alternative Installation Methods

### Method 1: Git Clone
```bash
git clone https://github.com/mrolivershea-cyber/FIX-CONNEXXA.git
cd FIX-CONNEXXA
git checkout copilot/fix-pptp-tunnel-issues
bash install_connexa_v7_4_8_patch.sh
```

### Method 2: Direct Download
```bash
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/install_connexa_v7_4_8_patch.sh
bash install_connexa_v7_4_8_patch.sh
```

### Method 3: Minimal Install
```bash
wget https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/copilot/fix-pptp-tunnel-issues/install_minimal.sh
bash install_minimal.sh
```

## 📖 Documentation

- **[INSTALL.md](INSTALL.md)** - Complete installation guide with troubleshooting
- **[QUICKSTART.md](QUICKSTART.md)** - 5-minute deployment
- **[CHANGELOG.md](CHANGELOG.md)** - Version history (v7.4.6 → v7.4.7 → v7.4.8)
- **[SECURITY.md](SECURITY.md)** - Security considerations

## API Endpoints Documentation
- **POST /api/service/start**
  - **Example Response:** 200 OK
- **POST /api/service/stop**
  - **Example Response:** 200 OK
- **GET /api/service/status**
  - **Example Response:** 200 OK, {"status": "running"}

## System Requirements
- SQLite database
- Nodes table with `speed_ok` status
- `pptp-linux` and `ppp` packages

## Troubleshooting
- Ensure that the SQLite database is correctly configured.
- Verify that the nodes table is populated with valid entries.
- Check the logs for any error messages.

## File Structure
- `/src`: Source code
- `/tests`: Test scripts
- `/docs`: Documentation

## Testing Commands
To run tests, use the following command:

```bash
pytest tests/
```

## Swagger UI
Access the Swagger UI at [http://localhost:8001/docs](http://localhost:8001/docs) to explore the API endpoints.