# FIX-CONNEXXA - Service Manager Module

## Features
- Auto node selection
- PPTP tunnel
- SOCKS proxy
- Idempotent
- Diagnostics

## Installation Scripts

### Mini-Fix Patch (NEW!)
Quick patch for environment variables and API path fixes:

```bash
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/MINIFIX_PATCH.sh | sudo bash
```

**Fixes:**
- Backend: Adds `load_dotenv()` for environment variable support
- Frontend: Fixes double `/api` path in AuthContext.js
- Automatic service restart

See [MINIFIX_README.md](./MINIFIX_README.md) for detailed documentation.

### Complete Service Manager Installation
To install the complete Service Manager module, run:

```bash
curl -O https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/install_service_manager.sh && bash install_service_manager.sh
```

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