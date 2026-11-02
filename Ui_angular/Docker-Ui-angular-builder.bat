@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - UI (Angular) - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=nginxinc/nginx-unprivileged:stable-alpine"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "COMPOSE_FILE=%~dp0docker-compose.ui-angular.yml"
set "COMPOSE_PROJECT=pilot-ui"
set "PILOT_ANGULAR_DIR=C:\Working\Storage\Dev\GitHub\PilotUiAngular"
set "ENVIRONMENT_FILE=%PILOT_ANGULAR_DIR%\src\environments\environment.ts"
set "ENVIRONMENT_BACKUP=%PILOT_ANGULAR_DIR%\src\environments\environment.ts.docker-backup"
set "SECRETS_FILE=%~dp0..\secrets\ui-angular.env"
set "UI_SECURITY_TOKEN_SECRETS_FILE=%~dp0..\secrets\ui-security-token-secrets.env"
set "UI_SECURITY_TOKEN_SECRETS_TARGET=%PILOT_ANGULAR_DIR%\public\security-token-secrets.json"
set "UI_ANGULAR_PORT=11801"
REM Dedicated Playwright dev server port; see PilotUiAngular\tests\playwright.config.ts.
set "E2E_SERVER_PORT=4201"

if not exist "%PILOT_ANGULAR_DIR%\package.json" (
	echo PilotUiAngular project path not found: "%PILOT_ANGULAR_DIR%"
	echo Update PILOT_ANGULAR_DIR in this script to your local PilotUiAngular repository path.
	exit /b 1
)

REM A test server left behind by an interrupted E2E run locks node_modules and would break npm ci.
call :stop_e2e_server

REM Install dependencies and run the tests before touching the running stack, so a failure leaves it deployed.
REM npm can exit with a negative code (e.g. EPERM is -4048), which "if errorlevel 1" does not catch.
pushd "%PILOT_ANGULAR_DIR%"
call npm ci
if %errorlevel% neq 0 (
	echo npm ci failed.
	popd
	exit /b 1
)

call npm test
if %errorlevel% neq 0 (
	echo Unit tests failed.
	popd
	exit /b 1
)

call npm run test:e2e
if %errorlevel% neq 0 (
	echo End-to-end tests failed.
	popd
	exit /b 1
)
popd

REM Stop any prior compose services for this stack first so its own ports are free to reuse.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% down --remove-orphans
docker rm -f pilot-ui >nul 2>&1

REM Resolve the host port so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port %UI_ANGULAR_PORT% UI_ANGULAR_PORT
if errorlevel 1 exit /b 1

REM 1. Download the Nginx image used to serve the Angular bundle:
docker pull "%IMAGE_FILE%"

REM 2. Build arg / runtime value used only for deployment metadata.
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 3. Prepare an isolated build context.
if exist "%WORKING_DIR_WIN%\ui-angular" rmdir /S /Q "%WORKING_DIR_WIN%\ui-angular"
mkdir "%WORKING_DIR_WIN%\ui-angular"

REM 4. Verify the UI security token secrets file exists, does not contain placeholder
REM    values, and publish it into the Angular project so the build picks it up.
if not exist "%UI_SECURITY_TOKEN_SECRETS_FILE%" (
	echo Secrets file not found: "%UI_SECURITY_TOKEN_SECRETS_FILE%"
	echo Copy ".\secrets\ui-security-token-secrets.env.example" to ".\secrets\ui-security-token-secrets.env" and update its contents with the correct secrets.
	exit /b 1
)

findstr /C:"<idp-host-user>" /C:"<idp-host-password>" "%UI_SECURITY_TOKEN_SECRETS_FILE%" >nul
if not errorlevel 1 (
	echo Placeholder values found in "%UI_SECURITY_TOKEN_SECRETS_FILE%".
	echo Update the "username" and "password" values with the correct secrets before continuing.
	exit /b 1
)

copy /Y "%UI_SECURITY_TOKEN_SECRETS_FILE%" "%UI_SECURITY_TOKEN_SECRETS_TARGET%" >nul
if errorlevel 1 (
	echo Failed to copy "%UI_SECURITY_TOKEN_SECRETS_FILE%" to "%UI_SECURITY_TOKEN_SECRETS_TARGET%".
	exit /b 1
)

REM 5. Publish the Angular application.
pushd "%PILOT_ANGULAR_DIR%"
call npm run build:prod
if %errorlevel% neq 0 (
	echo Angular production build failed.
	popd
	REM call :restore_environment
	exit /b 1
)
popd

REM call :restore_environment

if not exist "%PILOT_ANGULAR_DIR%\dist\PilotUiAngular\browser\index.html" (
	echo Build output is missing "dist\PilotUiAngular\browser\index.html".
	exit /b 1
)

REM 6. Copy the published bundle and server configuration into the build context.
xcopy /E /I /Y "%PILOT_ANGULAR_DIR%\dist\PilotUiAngular\browser\*" "%WORKING_DIR_WIN%\ui-angular\browser\" >nul
if errorlevel 1 (
	echo Failed to copy the Angular bundle to the ui-angular build context.
	exit /b 1
)

copy /Y "%~dp0nginx.conf" "%WORKING_DIR_WIN%\ui-angular\nginx.conf" >nul
if errorlevel 1 (
	echo Failed to copy nginx.conf to the ui-angular build context.
	exit /b 1
)

copy /Y "%~dp0pilot-proxy-headers.conf" "%WORKING_DIR_WIN%\ui-angular\pilot-proxy-headers.conf" >nul
if errorlevel 1 (
	echo Failed to copy pilot-proxy-headers.conf to the ui-angular build context.
	exit /b 1
)

REM 7. Build and start the UI container with Compose.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

popd

REM 8. Launch the application.
start http://localhost:%UI_ANGULAR_PORT%/

goto :eof

:stop_e2e_server
REM Match on the command line: the server's socket does not reliably appear as listening in netstat.
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -like '*ng.js* serve --port %E2E_SERVER_PORT%*' } | ForEach-Object { $_.ProcessId }"`) do (
	echo Stopping leftover E2E server, PID %%P.
	taskkill /PID %%P /T /F >nul 2>&1
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
