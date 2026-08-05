@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - PostgreSQL - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=postgres:latest"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "COMPOSE_FILE=%~dp0docker-compose.postgresql.yml"
set "SECRETS_FILE=%~dp0..\secrets\postgresql.env"

REM Load runtime secrets from file.
call :load_env_file "%SECRETS_FILE%"
if errorlevel 1 exit /b 1

if not defined DEV_USER_PASSWORD (
	echo Missing required key DEV_USER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%DEV_USER_PASSWORD%"=="<dev-user-password>" (
	echo Replace placeholder DEV_USER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)

REM 1. Get the latest image:
docker pull "%IMAGE_FILE%"

REM 2. Stop any prior compose services for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans

REM 3. Start the PostgreSQL container with Compose.
docker compose -f "%COMPOSE_FILE%" -p local-postgres up -d --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

REM 4. Recreate the Northwind database.
docker exec local-postgres psql -U DevUser -d postgres -c "DROP DATABASE IF EXISTS northwind;"
docker exec local-postgres psql -U DevUser -d postgres -c "CREATE DATABASE northwind;"

REM 5. Load Northwind schema/data.
docker exec -i local-postgres psql -U DevUser -d northwind < "%~dp0northwind.sql"

REM 6. Validate table load.
docker exec local-postgres psql -U DevUser -d northwind -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'pilot' AND table_type = 'BASE TABLE';"

REM 7. Load custom objects.
docker exec -i local-postgres psql -U DevUser -d northwind < "%~dp0customobjects.sql"

popd

goto :eof

:load_env_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from "..\secrets\postgresql.env.example".
	exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`type "%~1" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
exit /b 0
