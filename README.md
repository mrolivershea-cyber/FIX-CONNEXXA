# FIX-CONNEXXA - Service Manager Module

## Features
- Auto node selection
- PPTP tunnel
- SOCKS proxy
- Idempotent
- Diagnostics

## One-Command Installation
To install the Service Manager module, run the following command:

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