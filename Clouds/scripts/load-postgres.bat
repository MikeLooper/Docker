@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Clouds - loader - PostgreSQL
REM Usage: load-postgres.bat <host> <port> <mode>
REM   mode = managed  (AWS RDS / Azure Flexible Server / GCP Cloud SQL)
REM          local    (Phase 0 test against local-postgres; DevUser is not changed)
REM Reads from the environment (never from the command line):
REM   CLOUD_DB_ADMIN_USER, CLOUD_DB_ADMIN_PASSWORD, CLOUD_DB_DEVUSER_PASSWORD
REM   CLOUD_DB_NAME_OVERRIDE (optional; replaces northwind)
REM The loader owns the northwind database and the "DevUser" role (D9).

set "DB_HOST=%~1"
set "DB_PORT=%~2"
set "LOAD_MODE=%~3"
if "%LOAD_MODE%"=="" (
	echo Usage: load-postgres.bat ^<host^> ^<port^> ^<managed^|local^>
	exit /b 1
)
if /I not "%LOAD_MODE%"=="managed" if /I not "%LOAD_MODE%"=="local" (
	echo Unknown mode "%LOAD_MODE%".
	exit /b 1
)
if not defined CLOUD_DB_ADMIN_USER (
	echo CLOUD_DB_ADMIN_USER is not set.
	exit /b 1
)
if not defined CLOUD_DB_ADMIN_PASSWORD (
	echo CLOUD_DB_ADMIN_PASSWORD is not set.
	exit /b 1
)
if not defined CLOUD_DB_DEVUSER_PASSWORD (
	echo CLOUD_DB_DEVUSER_PASSWORD is not set.
	exit /b 1
)

set "DB_NAME=northwind"
if defined CLOUD_DB_NAME_OVERRIDE set "DB_NAME=%CLOUD_DB_NAME_OVERRIDE%"
set "SQL_DIR=%~dp0..\..\PostgreSQL"
set "TOOL_IMAGE=postgres:latest"
set "PSQL=docker run --rm -i --network pilot-net -e PGPASSWORD -e CLOUD_DEVPW -e PGCONNECT_TIMEOUT=10 %TOOL_IMAGE% psql -h %DB_HOST% -p %DB_PORT% -v ON_ERROR_STOP=1 -q"
set "CLOUD_DEVPW=%CLOUD_DB_DEVUSER_PASSWORD%"
set "TMP_SQL=%TEMP%\cloud-load-postgres-%RANDOM%.sql"

echo [postgres] Target %DB_HOST%:%DB_PORT% (mode %LOAD_MODE%, database %DB_NAME%)

REM 1. Wait for the server to accept the admin login (60 x 5 s).
set "PGPASSWORD=%CLOUD_DB_ADMIN_PASSWORD%"
for /L %%I in (1,1,60) do (
	%PSQL% -U %CLOUD_DB_ADMIN_USER% -d postgres -c "SELECT 1;" >nul 2>&1 && goto ready
	echo [postgres] Waiting for PostgreSQL ... %%I/60
	ping -n 6 127.0.0.1 >nul
)
echo [postgres] PostgreSQL at %DB_HOST%:%DB_PORT% did not accept the admin login in time.
exit /b 1
:ready
echo [postgres] PostgreSQL is ready.

REM 2. "DevUser" role: create if missing, reset the password otherwise.
REM    psql reads the password with \getenv, so it is never on a command line.
if /I "%LOAD_MODE%"=="local" goto skip_role
> "%TMP_SQL%" echo \getenv devpw CLOUD_DEVPW
>>"%TMP_SQL%" echo SELECT format('CREATE ROLE %%I LOGIN CREATEDB PASSWORD %%L', 'DevUser', :'devpw') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'DevUser') \gexec
>>"%TMP_SQL%" echo SELECT format('ALTER ROLE %%I WITH LOGIN CREATEDB PASSWORD %%L', 'DevUser', :'devpw') \gexec
>>"%TMP_SQL%" echo SELECT format('GRANT %%I TO %%I', 'DevUser', current_user) WHERE NOT pg_has_role(current_user, 'DevUser', 'MEMBER') \gexec
%PSQL% -U %CLOUD_DB_ADMIN_USER% -d postgres < "%TMP_SQL%"
set "RC=%errorlevel%"
del /Q "%TMP_SQL%" >nul 2>&1
if not "%RC%"=="0" (
	echo [postgres] Creating the DevUser role failed.
	exit /b 1
)
:skip_role

REM 3. Recreate the database, owned by DevUser.
%PSQL% -U %CLOUD_DB_ADMIN_USER% -d postgres -c "DROP DATABASE IF EXISTS %DB_NAME% WITH (FORCE);"
if errorlevel 1 (
	echo [postgres] Dropping %DB_NAME% failed.
	exit /b 1
)
%PSQL% -U %CLOUD_DB_ADMIN_USER% -d postgres -c "CREATE DATABASE %DB_NAME% OWNER \"DevUser\";"
if errorlevel 1 (
	echo [postgres] Creating %DB_NAME% failed.
	exit /b 1
)

REM 4. Load schema and data as DevUser, then validate the tables.
set "PGPASSWORD=%CLOUD_DB_DEVUSER_PASSWORD%"
echo [postgres] Loading northwind.sql ...
%PSQL% -U DevUser -d %DB_NAME% < "%SQL_DIR%\northwind.sql" >nul
if errorlevel 1 (
	echo [postgres] Loading northwind.sql failed.
	exit /b 1
)
set "TABLE_COUNT="
set "COUNT_FILE=%TEMP%\cloud-load-postgres-%RANDOM%.txt"
%PSQL% -U DevUser -d %DB_NAME% -t -A -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'pilot' AND table_type = 'BASE TABLE';" > "%COUNT_FILE%"
for /f "usebackq tokens=1" %%C in ("%COUNT_FILE%") do if not defined TABLE_COUNT set "TABLE_COUNT=%%C"
del /Q "%COUNT_FILE%" >nul 2>&1
echo [postgres] Base tables in schema pilot: %TABLE_COUNT%
if not defined TABLE_COUNT goto bad_tables
echo %TABLE_COUNT%| findstr /R /X /C:"[0-9][0-9]*" >nul || goto bad_tables
if %TABLE_COUNT% LSS 13 goto bad_tables

REM 5. Custom objects, then reset the primary-key sequences.
echo [postgres] Loading customobjects.sql ...
%PSQL% -U DevUser -d %DB_NAME% < "%SQL_DIR%\customobjects.sql" >nul
if errorlevel 1 (
	echo [postgres] Loading customobjects.sql failed.
	exit /b 1
)
echo [postgres] Loading reset-primary-keys.sql ...
%PSQL% -U DevUser -d %DB_NAME% < "%SQL_DIR%\reset-primary-keys.sql" >nul
if errorlevel 1 (
	echo [postgres] Loading reset-primary-keys.sql failed.
	exit /b 1
)

echo [postgres] Load complete.
exit /b 0

:bad_tables
echo [postgres] Table validation failed (expected at least 13 base tables in schema pilot).
exit /b 1
