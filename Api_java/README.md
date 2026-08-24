# Docker - Setup - API (Java)

Build and run both Java API containers (SQL Server and PostgreSQL variants) using Docker Compose.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.
  
```
cd Api_java
```

When this process is complete, change the directory back to the main directory.
  
```
cd ..
```

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- Java/Maven build environment for `PilotApiJava`
- Local clone of `PilotApiJava` at a sibling path:

```
C:\Working\Storage\Dev\GitHub\PilotApiJava
```

## Primary Script

Use:

```
Docker-Api-java-builder.bat
```

This script uses:

- `docker-compose.api-java.yml` for build/run
- Docker CLI where needed (`mvn clean package -DskipTests`, shared network check)

## Required Secrets File

Create a local secrets file:

```
copy secrets\api-java.env.example secrets\api-java.env
```

Then replace values in `secrets\api-java.env`:

- `MSSQL_DB_PASSWORD=<mssql-dev-user-password>`
- `POSTGRES_DB_PASSWORD=<postgres-dev-user-password>`

## What The Script Does

1. Stops prior stack with `docker compose down`.
2. Creates isolated build contexts under:
	- `C:\Working\Storage\Dev\GitHub\Working\api-java-mssql`
	- `C:\Working\Storage\Dev\GitHub\Working\api-java-postgres`
3. Runs `mvn clean package -DskipTests` from `PilotApiJava`.
4. Copies jar to each context as `pilot-api.jar`.
5. Runs `docker compose -p pilot-api-java up -d --build --force-recreate`.
6. Opens healthcheck URLs.

Before compose startup, the script probes host ports in two separate ranges:

- SQL Server variant: `55301-55399`
- PostgreSQL variant: `55401-55499`

If the preferred start port is blocked/reserved/in-use on Windows, the script picks the first open
port within that range and prints the replacement.

## Manual Commands (Equivalent)

Run from this repository folder:

```bat
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "CURRENT_DATE=2026-08-03 00:00:00Z"
set "MSSQL_DB_PASSWORD=replace-me"
set "POSTGRES_DB_PASSWORD=replace-me"
set "JAVA_MSSQL_PORT=55301"
set "JAVA_POSTGRES_PORT=55401"
docker compose -f docker-compose.api-java.yml -p pilot-api-java up -d --build --force-recreate
```

You can override host/container ports explicitly with `JAVA_MSSQL_PORT` and `JAVA_POSTGRES_PORT`.

## Endpoints

### SQL Server Variant

```
http://localhost:<JAVA_MSSQL_PORT>/healthcheck
```

### PostgreSQL Variant

```
http://localhost:<JAVA_POSTGRES_PORT>/healthcheck
```

## Additional Notes

- Compose now injects database connection values at runtime (`environment`) instead of sending DB passwords through `docker build --build-arg`.
- Script loads secrets from `secrets\api-java.env` and stops with a clear error when the file is missing or placeholders are unchanged.
- Script validates `PILOT_JAVA_DIR` and fails early if `pom.xml` is not found.
- The `DEPLOY_DATE` build argument is still passed for deployment metadata.
- If startup fails, inspect logs with:

```
docker compose -f docker-compose.api-java.yml logs --tail 200
```

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.api-java.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.api-java.yml down
```
