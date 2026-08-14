# Docker - Setup - PostgreSQL

Install and set up PostgreSQL on Docker using Docker Compose.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.
  
```
cd PostgreSQL
```

When this process is complete, change the directory back to the main directory.
  
```
cd ..
```

## Database

The Northwind database used in this process originally came from:
https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/northwind-pubs

The downloaded SQL in this repository has been adjusted for PostgreSQL.

## Primary Script

Use:

```
Docker-PostgreSQL-builder.bat
```

This script uses:

- `docker-compose.postgresql.yml` for container lifecycle
- Docker CLI only where needed (`docker exec` for SQL execution)

## Required Secrets File

Create a local secrets file:

```
copy ..\secrets\postgresql.env.example secrets\postgresql.env
```

Then replace values in `..\secrets\postgresql.env`:

- `DEV_USER_PASSWORD=<dev-user-password>`

## Processing Steps (Compose-first)

1. Pull the current image: `docker pull postgres:latest`.
2. Stop prior stack: `docker compose -f docker-compose.postgresql.yml down --remove-orphans`.
3. Start container: `docker compose -f docker-compose.postgresql.yml up -d --force-recreate`.
4. Recreate database `northwind` (drop/create).
5. Load [northwind.sql](northwind.sql).
6. Validate pilot tables were loaded.
7. Load [customobjects.sql](customobjects.sql).

## Manual Commands (Equivalent)

```bat
set "IMAGE_FILE=postgres:latest"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "DEV_USER_PASSWORD=replace-me"
docker pull "%IMAGE_FILE%"
docker compose -f docker-compose.postgresql.yml -p local-postgres up -d --force-recreate
docker exec local-postgres psql -U DevUser -d postgres -c "DROP DATABASE IF EXISTS northwind;"
docker exec local-postgres psql -U DevUser -d postgres -c "CREATE DATABASE northwind;"
docker exec -i local-postgres psql -U DevUser -d northwind < northwind.sql
docker exec -i local-postgres psql -U DevUser -d northwind < customobjects.sql
```

## Connection Info

- Host: `localhost`
- Port: `5432`
- Username: `DevUser`
- Password: value of `DEV_USER_PASSWORD`
- Database: `northwind`

## Additional Notes

- The compose service is named `local-postgres` to preserve existing references from API configs.
- Data is persisted in named volume `postgres_data`.
- Re-running the script intentionally reloads database objects for a deterministic local state.
- Script loads secrets from `..\secrets\postgresql.env` and stops with a clear error when the file is missing or placeholders are unchanged.

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.postgresql.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.postgresql.yml down
```

3. List databases:

```
docker exec local-postgres psql -U DevUser -d devDb -l
```

## Troubleshooting

If an error similar to `ERROR: duplicate key value violates unique constraint "suppliers_pkey"` occurs, it may be necessary to reset primary key sequences.
Run the SQL in the file: reset-primary-keys.sql
