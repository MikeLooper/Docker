# Docker - Setup - API (Python with Claude)

Build and run the `PythonAPIWithClaude` FastAPI service (answers questions using Claude) as a
single container using Docker Compose.

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- Python 3.12 or later (the project's `.venv` is used when present; otherwise `python` on `PATH`)
- The shared `pilot-net` Docker network and, for telemetry, the running `otel-collector` container
  (see the [OTEL README](../Otel/README.md))
- Local clone of PythonAPIWithClaude at:

```
C:\Working\Storage\Dev\GitHub\PythonAPIWithClaude
```

## Files

| File | Purpose |
| --- | --- |
| `Docker-pythonapi-with-claude-builder.bat` | Primary script: tests, builds, and starts the container |
| `docker-compose.api-python-with-claude.yml` | Compose definition for the API service |
| `dockerfile` | Image definition |
| `../secrets/api-python-with-claude.env` | Holds `ANTHROPIC_API_KEY`; passed to the container at runtime |

Create `../secrets/api-python-with-claude.env` from its `.example` template and set your Claude API
key before running the script. The key is supplied through Compose `env_file` and is not copied
into the image.

## What The Script Does

1. Resolves an available host port (preferred `56601`, range `56601-56699`) and validates the secrets file.
2. Pulls the `python:3.14-slim` base image.
3. Stops the prior stack and force-removes the `python-api-with-claude` container.
4. Runs `pytest`, then builds the application wheel with `python -m pip wheel`.
5. Copies the wheel into `C:\Working\Storage\Dev\GitHub\Working\api-python-with-claude`.
6. Runs `docker compose -p python-api-with-claude up -d --build --force-recreate`.
7. Opens the health check URL in the system browser.

## Image And Container

| Image | Container | Default Host Port |
| --- | --- | --- |
| `python-api-with-claude` | `python-api-with-claude` | 56601 |

Compose overrides these settings for the container: `APP_HOST=0.0.0.0`, `APP_PORT`,
`OTEL_SERVICE_NAME=python-api-with-claude`, and
`OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`. Optional `CLAUDE_*` settings can be added
to the secrets file.

## Endpoints

```
http://localhost:56601/health
http://localhost:56601/docs
http://localhost:56601/api/v1/questions   (POST)
```

## Bruno Tests

The Bruno collection is in the application repository at
`C:\Working\Storage\Dev\GitHub\PythonAPIWithClaude\tests\Bruno\PythonAPIWithClaude`. Its `Docker`
environment targets `http://localhost:56601/`. No IDP token is needed, but the `Ask` and
`Ask_WithOverrides` requests call the Claude API and use tokens from your key.

The API does not use a database, so `RunBrunoTests.bat` runs it once (environment `Docker`) after the
PostgreSQL and SQL Server passes, and includes it in the combined HTML report under `Testing\BrunoReports`:

```
..\Testing\RunBrunoTests.bat
```

## Additional CLI Commands

```
docker compose -f docker-compose.api-python-with-claude.yml -p python-api-with-claude logs --tail 200
docker compose -f docker-compose.api-python-with-claude.yml -p python-api-with-claude restart
docker compose -f docker-compose.api-python-with-claude.yml -p python-api-with-claude down
```
