@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - SQL Server - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=mcr.microsoft.com/mssql/server:2025-latest"
set "COMPOSE_FILE=%~dp0docker-compose.sqlserver.yml"
set "SECRETS_FILE=%~dp0..\secrets\sqlserver.env"

REM Load runtime secrets from file.
call :load_env_file "%SECRETS_FILE%"
if errorlevel 1 exit /b 1

if not defined SA_PASSWORD (
	echo Missing required key SA_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if not defined DEV_USER_PASSWORD (
	echo Missing required key DEV_USER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%SA_PASSWORD%"=="<sa-password>" (
	echo Replace placeholder SA_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%DEV_USER_PASSWORD%"=="<dev-user-password>" (
	echo Replace placeholder DEV_USER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)

REM 1. Download the SQL Server image:
docker pull "%IMAGE_FILE%"

REM 2. Stop any prior compose services for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans

REM 3. Start SQL Server with Compose.
docker compose -f "%COMPOSE_FILE%" -p local-mssql up -d --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

REM 4. Validate SA password.
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%SA_PASSWORD%" -C -Q "SELECT 1;"
if errorlevel 1 (
	echo SA login validation failed. Check SA_PASSWORD complexity and value.
	exit /b 1
)

REM 5. Create/maintain DevUser and disable sa.
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%SA_PASSWORD%" -C -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DevUser') BEGIN CREATE LOGIN [DevUser] WITH PASSWORD = N'%DEV_USER_PASSWORD%'; END; IF IS_SRVROLEMEMBER('sysadmin','DevUser') = 0 BEGIN ALTER SERVER ROLE [sysadmin] ADD MEMBER [DevUser]; END;"
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -C -Q "ALTER LOGIN [sa] DISABLE;"

REM 6. Recreate NorthWind database.
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -C -Q "IF DB_ID('NorthWind') IS NOT NULL BEGIN ALTER DATABASE [NorthWind] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [NorthWind]; END; CREATE DATABASE [NorthWind];"

REM 7. Load NorthWind schema/data.
docker exec -i local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -d NorthWind -C < "%~dp0Northwind.sql"

REM 8. Validate table load.
docker exec local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -d NorthWind -C -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';"

REM 9. Load custom objects.
docker exec -i local-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "%DEV_USER_PASSWORD%" -d NorthWind -C < "%~dp0customobjects.sql"

popd

goto :eof

:load_env_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from "..\secrets\sqlserver.env.example".
	exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`type "%~1" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
exit /b 0
