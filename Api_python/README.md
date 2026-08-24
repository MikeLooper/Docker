# Docker - Setup - API (Python)

Build and run both Python API containers (SQL Server and PostgreSQL variants) using Docker Compose.

The application is the FastAPI project `PilotApiPython`, deployed twice: once configured for
SQL Server and once configured for PostgreSQL.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.

```
cd Api_python
```

When this process is complete, change the directory back to the main directory.

```
cd ..
```

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- Python 3.12 or later on `PATH` (used to build the wheel)
- The shared `pilot-net` Docker network, plus the running `local-mssql` and `local-postgres` containers
- Local clone of `PilotApiPython` at a sibling path:

```
C:\Working\Storage\Dev\GitHub\PilotApiPython
```

## Files

| File | Purpose |
| --- | --- |
| `Docker-Api-python-builder.bat` | Primary script: pulls, builds, publishes, and starts both containers |
| `docker-compose.api-python.yml` | Compose definition for both API services |
| `dockerfile_mssql` | Image definition for the SQL Server variant (installs ODBC Driver 18) |
| `dockerfile_postgres` | Image definition for the PostgreSQL variant |
| `../secrets/appsettings-api-python-sqlserver.env` | Settings copied into the SQL Server container as `.env` |
| `../secrets/appsettings-api-python-postgresql.env` | Settings copied into the PostgreSQL container as `.env` |

Each secrets file has a matching `.example` template. Create the real file from the template and
replace the placeholder password before running the script.

## Primary Script

Use:

```
Docker-Api-python-builder.bat
```

## What The Script Does

1. Resolves available host ports and validates both settings files.
2. Pulls the `python:3.12-slim` base image.
3. Captures the current date into `CURRENT_DATE` (published to each image as `APP_DEPLOY_DATE`).
4. Stops the prior stack with `docker compose down` and force-removes the containers
   `pilot-api-python-mssql` and `pilot-api-python-postgres`.
5. Builds (publishes) the Python application as a wheel with `python -m pip wheel`.
6. Creates isolated build contexts under:
   - `C:\Working\Storage\Dev\GitHub\Working\api-python-mssql`
   - `C:\Working\Storage\Dev\GitHub\Working\api-python-postgres`
7. Copies the wheel and the database-specific settings file (as `.env`) into each context.
8. Runs `docker compose -p pilot-api-python up -d --build --force-recreate`.
9. Opens both healthcheck URLs in the system browser.

Before compose startup, the script probes host ports in two separate ranges:

- SQL Server variant: `55501-54599`
- PostgreSQL variant: `55601-54699`

If the preferred start port is blocked, reserved, or in use on Windows, the script picks the first
open port within that range and prints the replacement.

## Images And Containers

| Variant | Image | Container | Default Host Port |
| --- | --- | --- | --- |
| SQL Server | `pilot-api-python-sqlserver` | `pilot-api-python-mssql` | 55501 |
| PostgreSQL | `pilot-api-python-postgres` | `pilot-api-python-postgres` | 55601 |

Both images receive `APP_DEPLOY_DATE` (build date) and `APP_PORT` (listening port) as environment
variables. Uvicorn listens on `APP_PORT` inside the container, and the same port is published on
the host.

## Manual Commands (Equivalent)

Run from this repository folder:

```bat
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "CURRENT_DATE=2026-08-16 00:00:00Z"
set "PYTHON_MSSQL_PORT=55501"
set "PYTHON_POSTGRES_PORT=55601"
docker compose -f docker-compose.api-python.yml -p pilot-api-python up -d --build --force-recreate
```

You can override host ports explicitly with `PYTHON_MSSQL_PORT` and `PYTHON_POSTGRES_PORT`.

## Endpoints

### SQL Server Variant

```
http://localhost:55501/healthcheck
http://localhost:55501/docs
```

### PostgreSQL Variant

```
http://localhost:55601/healthcheck
http://localhost:55601/docs
```

## Additional Notes

- The SQL Server image installs `msodbcsql18` and `unixodbc`, required by `pyodbc`.
- The PostgreSQL image needs no extra system packages because `psycopg[binary]` bundles `libpq`.
- Both containers run as the non-root user `appuser`.
- Database hosts inside the settings files use the shared network container names
  (`local-mssql`, `local-postgres`), not `localhost`.
- If one of the API containers fails to start, inspect logs with:

```
docker compose -f docker-compose.api-python.yml logs --tail 200
```

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.api-python.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.api-python.yml down
```
