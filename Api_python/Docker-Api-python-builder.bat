@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - API (Python) - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=python:3.12-slim"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "COMPOSE_FILE=%~dp0docker-compose.api-python.yml"
set "PILOT_PYTHON_DIR=%~dp0..\..\PilotApiPython"
set "MSSQL_SECRETS_FILE=%~dp0..\secrets\appsettings-api-python-sqlserver.env"
set "POSTGRES_SECRETS_FILE=%~dp0..\secrets\appsettings-api-python-postgresql.env"
set "PYTHON_MSSQL_PORT=55501"
set "PYTHON_POSTGRES_PORT=55601"

REM Resolve host ports so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port %PYTHON_MSSQL_PORT% PYTHON_MSSQL_PORT
if errorlevel 1 exit /b 1
call :resolve_open_port %PYTHON_POSTGRES_PORT% PYTHON_POSTGRES_PORT
if errorlevel 1 exit /b 1

REM Validate the environment files exist before doing any work.
call :require_secrets_file "%MSSQL_SECRETS_FILE%"
if errorlevel 1 exit /b 1
call :require_secrets_file "%POSTGRES_SECRETS_FILE%"
if errorlevel 1 exit /b 1

REM 1. Download the Python image:
docker pull "%IMAGE_FILE%"
if errorlevel 1 (
	echo docker pull failed for "%IMAGE_FILE%".
	exit /b 1
)

REM 2. Build arg used only for deployment metadata.
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 3. Stop any prior compose services and containers for this stack.
docker compose -f "%COMPOSE_FILE%" -p pilot-api-python down --remove-orphans
docker rm -f pilot-api-python-mssql >nul 2>&1
docker rm -f pilot-api-python-postgres >nul 2>&1

REM 4. Prepare isolated build contexts.
if exist "%WORKING_DIR_WIN%" rmdir /S /Q "%WORKING_DIR_WIN%"
mkdir "%WORKING_DIR_WIN%"

mkdir "%WORKING_DIR_WIN%\api-python-publish"
mkdir "%WORKING_DIR_WIN%\api-python-mssql"
mkdir "%WORKING_DIR_WIN%\api-python-postgres"

REM 5. Build (publish) the Python application as a wheel.
if not exist "%PILOT_PYTHON_DIR%\pyproject.toml" (
	echo PilotApiPython project path not found: "%PILOT_PYTHON_DIR%"
	echo Update PILOT_PYTHON_DIR in this script to your local PilotApiPython repository path.
	exit /b 1
)

where python >nul 2>&1
if errorlevel 1 (
	echo Python was not found on PATH. Install Python 3.12 or later and retry.
	exit /b 1
)

pushd "%PILOT_PYTHON_DIR%"
python -m pip wheel . --no-deps --wheel-dir "%WORKING_DIR_WIN%\api-python-publish"
if errorlevel 1 (
	echo Python wheel build failed.
	popd
	exit /b 1
)
popd

set "WHEEL_SOURCE="
for %%F in ("%WORKING_DIR_WIN%\api-python-publish\*.whl") do set "WHEEL_SOURCE=%%~fF"

if not defined WHEEL_SOURCE (
	echo No wheel file was produced in "%WORKING_DIR_WIN%\api-python-publish".
	exit /b 1
)
echo Wheel=%WHEEL_SOURCE%

REM 6. Copy the wheel into each build context.
copy /Y "%WHEEL_SOURCE%" "%WORKING_DIR_WIN%\api-python-mssql\" >nul
if errorlevel 1 (
	echo Failed to copy the wheel to the api-python-mssql build context.
	exit /b 1
)
copy /Y "%WHEEL_SOURCE%" "%WORKING_DIR_WIN%\api-python-postgres\" >nul
if errorlevel 1 (
	echo Failed to copy the wheel to the api-python-postgres build context.
	exit /b 1
)

REM 7. Copy database-specific settings into each context as the application .env file.
copy /Y "%MSSQL_SECRETS_FILE%" "%WORKING_DIR_WIN%\api-python-mssql\.env" >nul
if errorlevel 1 (
	echo Failed to copy "%MSSQL_SECRETS_FILE%".
	exit /b 1
)
copy /Y "%POSTGRES_SECRETS_FILE%" "%WORKING_DIR_WIN%\api-python-postgres\.env" >nul
if errorlevel 1 (
	echo Failed to copy "%POSTGRES_SECRETS_FILE%".
	exit /b 1
)

REM 8. Build and start both API containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p pilot-api-python up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

popd

REM 9. Launch health checks.
start http://localhost:%PYTHON_MSSQL_PORT%/healthcheck
start http://localhost:%PYTHON_POSTGRES_PORT%/healthcheck

goto :eof

:require_secrets_file
if not exist "%~1" (
	echo Missing settings file: "%~1"
	echo Create it from the matching ".example" template in the secrets folder.
	exit /b 1
)

findstr /C:"<mssql-dev-user-password>" /C:"<postgres-dev-user-password>" "%~1" >nul
if not errorlevel 1 (
	echo Replace the placeholder password in "%~1".
	exit /b 1
)
exit /b 0

:resolve_open_port
set "RESOLVED_PORT="
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "$start = [int]%~1; $end = [Math]::Min($start + 98, 65535); function Test-Port([int]$port){ $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port); try { $listener.Start(); return $true } catch { return $false } finally { if ($listener.Server -and $listener.Server.IsBound) { $listener.Stop() } } }; foreach ($p in $start..$end) { if (Test-Port $p) { Write-Output $p; exit 0 } }; exit 1"`) do set "RESOLVED_PORT=%%P"

if not defined RESOLVED_PORT (
	goto :no_open_port
)

if not "%RESOLVED_PORT%"=="%~1" (
	echo Port %~1 unavailable. Using %RESOLVED_PORT% instead.
)

set "%~2=%RESOLVED_PORT%"
exit /b 0

:no_open_port
set /a "RANGE_END=%~1+98"
if %RANGE_END% GTR 65535 set "RANGE_END=65535"
echo Unable to find an available host port in the range %~1-%RANGE_END%.
exit /b 1
