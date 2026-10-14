@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - API (Python with Claude) - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=python:3.14-slim"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "COMPOSE_FILE=%~dp0docker-compose.api-python-with-claude.yml"
set "COMPOSE_PROJECT=python-api-with-claude"
set "CONTAINER_NAME=python-api-with-claude"
set "BUILD_CONTEXT=%WORKING_DIR_WIN%\api-python-with-claude"
set "SOURCE_DIR=C:\Working\Storage\Dev\GitHub\PythonAPIWithClaude"
set "SECRETS_FILE=%~dp0..\secrets\api-python-with-claude.env"
set "PYTHON_CLAUDE_PORT=56601"

REM Resolve the host port so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port %PYTHON_CLAUDE_PORT% PYTHON_CLAUDE_PORT
if errorlevel 1 exit /b 1

REM Validate the secrets file exists before doing any work.
call :require_secrets_file "%SECRETS_FILE%"
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
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% down --remove-orphans
docker rm -f %CONTAINER_NAME% >nul 2>&1

REM 4. Prepare an isolated build context (only this stack's folders are replaced).
if exist "%WORKING_DIR_WIN%\api-python-with-claude-publish" rmdir /S /Q "%WORKING_DIR_WIN%\api-python-with-claude-publish"
if exist "%BUILD_CONTEXT%" rmdir /S /Q "%BUILD_CONTEXT%"
mkdir "%WORKING_DIR_WIN%\api-python-with-claude-publish"
mkdir "%BUILD_CONTEXT%"

REM 5. Test and build (publish) the Python application as a wheel.
if not exist "%SOURCE_DIR%\pyproject.toml" (
	echo PythonAPIWithClaude project path not found: "%SOURCE_DIR%"
	echo Update SOURCE_DIR in this script to your local PythonAPIWithClaude repository path.
	exit /b 1
)

REM Prefer the project's virtual environment (it has the dev/test dependencies); fall back to PATH.
set "PYTHON_EXE=%SOURCE_DIR%\.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
	where python >nul 2>&1
	if errorlevel 1 (
		echo Python was not found on PATH. Install Python 3.12 or later and retry.
		exit /b 1
	)
	set "PYTHON_EXE=python"
)
echo Python=%PYTHON_EXE%

pushd "%SOURCE_DIR%"

"%PYTHON_EXE%" -m pytest
if errorlevel 1 (
	echo Unit tests failed. Aborting Docker build process.
	popd
	exit /b 1
)

"%PYTHON_EXE%" -m pip wheel . --no-deps --wheel-dir "%WORKING_DIR_WIN%\api-python-with-claude-publish"
if errorlevel 1 (
	echo Python wheel build failed.
	popd
	exit /b 1
)
popd

set "WHEEL_SOURCE="
for %%F in ("%WORKING_DIR_WIN%\api-python-with-claude-publish\*.whl") do set "WHEEL_SOURCE=%%~fF"

if not defined WHEEL_SOURCE (
	echo No wheel file was produced in "%WORKING_DIR_WIN%\api-python-with-claude-publish".
	exit /b 1
)
echo Wheel=%WHEEL_SOURCE%

REM 6. Copy the wheel into the build context.
REM    The secrets file is NOT copied into the image; Compose passes it to the container at runtime.
copy /Y "%WHEEL_SOURCE%" "%BUILD_CONTEXT%\" >nul
if errorlevel 1 (
	echo Failed to copy the wheel to the api-python-with-claude build context.
	exit /b 1
)

REM 7. Build and start the API container with Compose.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

popd

REM 8. Launch the health check.
start http://localhost:%PYTHON_CLAUDE_PORT%/health

goto :eof

:require_secrets_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from the matching ".example" template in the secrets folder.
	exit /b 1
)

findstr /C:"<anthropic-api-key>" "%~1" >nul
if not errorlevel 1 (
	echo Replace the placeholder API key in "%~1".
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
