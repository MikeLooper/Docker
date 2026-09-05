# Docker - Setup - Pilot Utility API

Build and run both .NET API containers (SQL Server and PostgreSQL variants) using Docker Compose.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.
  
```
cd Api_dotnet
```

When this process is complete, change the directory back to the main directory.
  
```
cd ..
```

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- .NET SDK that can publish the `PilotUtilityApi` project
- Local clone of [PilotUtilityApi](https://github.com/MikeLooper/PilotUtilityApi) at a sibling path:

```
C:\Working\Storage\Dev\GitHub\PilotUtilityApi
```

## Primary Script

Use:

```
Docker-utility-dotnet-builder.bat
```

This script uses:

- `docker-compose.utility-dotnet.yml` for build/run
- Docker CLI only where needed (`dotnet publish`, shared network check)

## What The Script Does

1. Stops prior stack with `docker compose down`.
2. Publishes .NET API for Linux.
3. Creates isolated build contexts under:
   - `C:\Working\Storage\Dev\GitHub\Working\utility-dotnet-mssql`
   - `C:\Working\Storage\Dev\GitHub\Working\utility-dotnet-postgres`
4. Copies database-specific production settings `appsettings-utility-dotnet-*.env` as `appsettings.Production.json` into each context.
5. Runs `docker compose -p utility-api-dotnet up -d --build --force-recreate`.
6. Opens healthcheck URLs.

Before compose startup, the script probes host ports in two separate ranges:

- SQL Server variant: `55701-55799`
- PostgreSQL variant: `55801-55899`

If the preferred start port is blocked/reserved/in-use on Windows, the script picks the first open
port within that range and prints the replacement.

## Manual Commands (Equivalent)

Run from this repository folder:

```bat
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "CURRENT_DATE=2026-08-03 00:00:00Z"
set "DOTNET_MSSQL_PORT=55701"
set "DOTNET_POSTGRES_PORT=55801"
docker compose -f docker-compose.utility-dotnet.yml -p utility-api-dotnet up -d --build --force-recreate
```

You can override host ports explicitly with `DOTNET_MSSQL_PORT` and `DOTNET_POSTGRES_PORT`.

## Endpoints

### SQL Server Variant

```
http://localhost:<DOTNET_MSSQL_PORT>/healthcheck
```

### PostgreSQL Variant

```
http://localhost:<DOTNET_POSTGRES_PORT>/healthcheck
```

## Additional Notes

- The compose file still tags images as `utility-api-dotnet-mssql:1.0` and `utility-api-dotnet-postgres:1.0`.
- Keeping separate build contexts prevents appsettings collisions when both images are built in one compose run.
- Script validates `PILOT_DOTNET_DIR` and fails early if no `.sln` or `.csproj` is found.
- Script validates that `PilotUtilityApi.Web.dll` exists after publish before building Docker images.
- If one of the API projects fails to start, inspect logs with:

```
docker compose -f docker-compose.utility-dotnet.yml logs --tail 200
```

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.utility-dotnet.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.utility-dotnet.yml down
```


