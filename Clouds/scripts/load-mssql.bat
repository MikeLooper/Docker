@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Clouds - loader - SQL Server
REM Usage: load-mssql.bat <host> <port> <mode>
REM   mode = managed  (AWS RDS / Azure SQL: admin is CLOUD_DB_ADMIN_USER, or sa - see step 1)
REM          gce      (GCP Compute Engine container: admin is sa; sa is disabled at the end)
REM          local    (Phase 0 test against local-mssql; admin is CLOUD_DB_ADMIN_USER, DevUser is not changed)
REM Reads from the environment (never from the command line):
REM   CLOUD_DB_ADMIN_USER, CLOUD_DB_ADMIN_PASSWORD, CLOUD_DB_DEVUSER_PASSWORD
REM   CLOUD_DB_NAME_OVERRIDE (optional; replaces NorthWind)
REM The loader owns the NorthWind database and the DevUser login (D9).

set "DB_HOST=%~1"
set "DB_PORT=%~2"
set "LOAD_MODE=%~3"
if "%LOAD_MODE%"=="" (
	echo Usage: load-mssql.bat ^<host^> ^<port^> ^<managed^|gce^|local^>
	exit /b 1
)
if /I not "%LOAD_MODE%"=="managed" if /I not "%LOAD_MODE%"=="gce" if /I not "%LOAD_MODE%"=="local" (
	echo Unknown mode "%LOAD_MODE%".
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

set "ADMIN_USER=%CLOUD_DB_ADMIN_USER%"
if /I "%LOAD_MODE%"=="gce" set "ADMIN_USER=sa"
set "DB_NAME=NorthWind"
if defined CLOUD_DB_NAME_OVERRIDE set "DB_NAME=%CLOUD_DB_NAME_OVERRIDE%"
set "SQL_DIR=%~dp0..\..\SqlServer"
set "TOOL_IMAGE=mcr.microsoft.com/mssql/server:2025-latest"
set "SQLCMD=docker run --rm -i --network pilot-net -e SQLCMDPASSWORD -e CLOUD_DEVPW --entrypoint /opt/mssql-tools18/bin/sqlcmd %TOOL_IMAGE% -S %DB_HOST%,%DB_PORT% -C -l 30"
REM sqlcmd reads $(CLOUD_DEVPW) from the container env, so the password is never on a command line.
set "CLOUD_DEVPW=%CLOUD_DB_DEVUSER_PASSWORD%"

echo [mssql] Target %DB_HOST%:%DB_PORT% (mode %LOAD_MODE%, database %DB_NAME%)

REM 1. Wait until a sysadmin login works (60 x 5 s). Candidates, in order:
REM      managed: CLOUD_DB_ADMIN_USER, then sa with the same password. Both Floci
REM               emulators apply the admin password to the engine's sa login;
REM               the master login itself has no server rights there.
REM      gce:     sa, then DevUser (sa is disabled after the first load).
REM      local:   CLOUD_DB_ADMIN_USER.
for /L %%I in (1,1,60) do (
	call :try_admin %ADMIN_USER% "%CLOUD_DB_ADMIN_PASSWORD%" && goto ready
	if /I "%LOAD_MODE%"=="managed" call :try_admin sa "%CLOUD_DB_ADMIN_PASSWORD%" && goto ready
	if /I "%LOAD_MODE%"=="gce" call :try_admin DevUser "%CLOUD_DB_DEVUSER_PASSWORD%" && goto ready
	echo [mssql] Waiting for SQL Server ... %%I/60
	ping -n 6 127.0.0.1 >nul
)
echo [mssql] SQL Server at %DB_HOST%:%DB_PORT% did not accept a sysadmin login in time.
exit /b 1
:ready
echo [mssql] SQL Server is ready (admin login: %ADMIN_USER%).

REM 2. DevUser login (create if missing, reset password otherwise) + sysadmin.
if /I "%LOAD_MODE%"=="local" goto skip_login
%SQLCMD% -U %ADMIN_USER% -b -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DevUser') CREATE LOGIN [DevUser] WITH PASSWORD = N'$(CLOUD_DEVPW)', CHECK_POLICY = OFF; ELSE ALTER LOGIN [DevUser] WITH PASSWORD = N'$(CLOUD_DEVPW)'; IF IS_SRVROLEMEMBER('sysadmin','DevUser') = 0 ALTER SERVER ROLE [sysadmin] ADD MEMBER [DevUser];"
if errorlevel 1 (
	echo [mssql] Creating the DevUser login failed.
	exit /b 1
)
:skip_login

REM 3+. Everything else runs as DevUser.
set "SQLCMDPASSWORD=%CLOUD_DB_DEVUSER_PASSWORD%"

REM 3. Recreate the database.
%SQLCMD% -U DevUser -b -Q "IF DB_ID('%DB_NAME%') IS NOT NULL BEGIN ALTER DATABASE [%DB_NAME%] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [%DB_NAME%]; END; CREATE DATABASE [%DB_NAME%];"
if errorlevel 1 (
	echo [mssql] Recreating %DB_NAME% failed.
	exit /b 1
)

REM 4. Load schema and data.
echo [mssql] Loading Northwind.sql ...
%SQLCMD% -U DevUser -d %DB_NAME% < "%SQL_DIR%\Northwind.sql" >nul
if errorlevel 1 (
	echo [mssql] Loading Northwind.sql failed.
	exit /b 1
)

REM 5. Validate the tables.
set "TABLE_COUNT="
set "COUNT_FILE=%TEMP%\cloud-load-mssql-%RANDOM%.txt"
%SQLCMD% -U DevUser -d %DB_NAME% -b -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';" > "%COUNT_FILE%"
for /f "usebackq tokens=1" %%C in ("%COUNT_FILE%") do if not defined TABLE_COUNT set "TABLE_COUNT=%%C"
del /Q "%COUNT_FILE%" >nul 2>&1
echo [mssql] Base tables: %TABLE_COUNT%
if not defined TABLE_COUNT goto bad_tables
echo %TABLE_COUNT%| findstr /R /X /C:"[0-9][0-9]*" >nul || goto bad_tables
if %TABLE_COUNT% LSS 13 goto bad_tables

REM 6. Custom objects.
echo [mssql] Loading customobjects.sql ...
%SQLCMD% -U DevUser -d %DB_NAME% -b < "%SQL_DIR%\customobjects.sql" >nul
if errorlevel 1 (
	echo [mssql] Loading customobjects.sql failed.
	exit /b 1
)

REM 7. GCE only: disable sa, as the local builder does.
if /I not "%LOAD_MODE%"=="gce" goto done
%SQLCMD% -U DevUser -b -Q "ALTER LOGIN [sa] DISABLE;"
if errorlevel 1 (
	echo [mssql] Disabling sa failed.
	exit /b 1
)

:done
echo [mssql] Load complete.
exit /b 0

:bad_tables
echo [mssql] Table validation failed (expected at least 13 base tables).
exit /b 1

REM :try_admin <user> <password>
REM   On success (login works and is sysadmin) sets ADMIN_USER and SQLCMDPASSWORD.
:try_admin
set "SQLCMDPASSWORD=%~2"
%SQLCMD% -U %~1 -b -h -1 -Q "SET NOCOUNT ON; IF IS_SRVROLEMEMBER('sysadmin') = 1 SELECT 1; ELSE RAISERROR('not sysadmin', 16, 1);" >nul 2>&1
if errorlevel 1 exit /b 1
set "ADMIN_USER=%~1"
exit /b 0
