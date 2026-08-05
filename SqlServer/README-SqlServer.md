# Docker - Setup - SQL Server

Install and set up SQL Server on Docker using Docker Compose.

## Preparation

Previous setup noted in the [Main README](.\README.md) should have already been accomplished.

Change to the current directory.
  
```
cd SqlServer
```

When this process is complete, change the directory back to the main directory.
  
```
cd ..
```

## Database

The Northwind database used in this process originally came from:
https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/northwind-pubs

The SQL in this repository has been modernized for local loading.

## Primary Script

Use:

```
Docker-SQLServer-builder.bat
```

This script uses:

- `docker-compose.sqlserver.yml` for container lifecycle
- Docker CLI only where needed (`docker exec` + `sqlcmd` for server/database configuration)

## Required Secrets File

Create a local secrets file:

```
copy ..\secrets\sqlserver.env.example secrets\sqlserver.env
```

Then replace values in `..\secrets\sqlserver.env`:

- `SA_PASSWORD=<sa-password>`
- `DEV_USER_PASSWORD=<dev-user-password>`

## Processing Steps (Compose-first)

1. Pull the current image: `docker pull mcr.microsoft.com/mssql/server:2025-latest`.
2. Stop prior stack: `docker compose -f docker-compose.sqlserver.yml down --remove-orphans`.
3. Start container: `docker compose -f docker-compose.sqlserver.yml up -d --force-recreate`.
4. Validate SA login with `sqlcmd`.
5. Create/maintain `DevUser`, grant sysadmin, disable `sa`.
6. Recreate `NorthWind` database.
7. Load [Northwind.sql](Northwind.sql).
8. Validate tables.
9. Load [customobjects.sql](customobjects.sql).

## Manual Commands (Equivalent)

```bat
set "IMAGE_FILE=mcr.microsoft.com/mssql/server:2025-latest"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "SA_PASSWORD=replace-me"
set "DEV_USER_PASSWORD=replace-me"
docker pull "%IMAGE_FILE%"
docker compose -f docker-compose.sqlserver.yml -p local-mssql up -d --force-recreate
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%SA_PASSWORD%" -C -Q "SELECT 1;"
docker exec -i local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -d NorthWind -C < Northwind.sql
docker exec -i local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -d NorthWind -C < customobjects.sql
```

## SQL Server Password Requirements

- At least 8 characters
- Three out of four categories: uppercase, lowercase, digits, symbols
- Must not contain account name

## Additional Notes

- The compose service is named `local-mssql` to preserve compatibility with API connection strings.
- Data is persisted in named volume `mssql_data`.
- Script is intentionally idempotent for local rebuilds: it recreates the `NorthWind` database each run.
- Script loads secrets from `..\secrets\sqlserver.env` and stops with a clear error when the file is missing or placeholders are unchanged.

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.sqlserver.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.sqlserver.yml down
```

3. List all databases:

```
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "<dev-user-password>" -C -Q "SELECT name FROM sys.databases;"
```

## Troubleshooting

1. If executing the script results in this error message: "Login failed for user 'sa'".
- Possibly the 'sa' user has already been disabled (complying with best practices), and cannot be used.
- In such a case, all of step 4 and the first command of step 5 ('sa' disable) in the batch file would have to be manually commented out to allow the batch file to continue.
