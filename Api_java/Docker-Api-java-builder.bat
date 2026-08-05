@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - API (Java) - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=eclipse-temurin:25-jre-alpine"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "COMPOSE_FILE=%~dp0docker-compose.api-java.yml"
set "PILOT_JAVA_DIR=%~dp0..\..\PilotApiJava"
set "SECRETS_FILE=%~dp0..\secrets\api-java.env"
set "JAVA_MSSQL_PORT=56601"
set "JAVA_POSTGRES_PORT=56701"

REM Resolve host ports so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port 56601 JAVA_MSSQL_PORT
if errorlevel 1 exit /b 1
call :resolve_open_port 56701 JAVA_POSTGRES_PORT
if errorlevel 1 exit /b 1

REM Load runtime secrets from file.
call :load_env_file "%SECRETS_FILE%"
if errorlevel 1 exit /b 1

if not defined MSSQL_DB_PASSWORD (
	echo Missing required key MSSQL_DB_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if not defined POSTGRES_DB_PASSWORD (
	echo Missing required key POSTGRES_DB_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%MSSQL_DB_PASSWORD%"=="<mssql-dev-user-password>" (
	echo Replace placeholder MSSQL_DB_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%POSTGRES_DB_PASSWORD%"=="<postgres-dev-user-password>" (
	echo Replace placeholder POSTGRES_DB_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)

REM 1. Download the Java image:
docker pull "%IMAGE_FILE%"

REM 1. Stop any prior compose services for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans

REM 2. Prepare isolated build contexts.
if exist "%WORKING_DIR_WIN%\api-java-mssql" rmdir /S /Q "%WORKING_DIR_WIN%\api-java-mssql"
if exist "%WORKING_DIR_WIN%\api-java-postgres" rmdir /S /Q "%WORKING_DIR_WIN%\api-java-postgres"

mkdir "%WORKING_DIR_WIN%\api-java-mssql"
mkdir "%WORKING_DIR_WIN%\api-java-postgres"

REM 3. Build the application jar when it does not already exist.
if not exist "%PILOT_JAVA_DIR%\pom.xml" (
	echo PilotApiJava project path not found: "%PILOT_JAVA_DIR%"
	echo Update PILOT_JAVA_DIR in this script to your local PilotApiJava repository path.
	exit /b 1
)

pushd "%PILOT_JAVA_DIR%"
call mvn clean package -DskipTests
if errorlevel 1 (
	echo Maven build failed.
	popd
	exit /b 1
)

set "JAR_SOURCE="
for %%F in (target\*.jar) do (
	set "JAR_SOURCE=%%F"
	goto :jarFound
)

echo No jar file found in target\.
popd
exit /b 1

:jarFound
copy /Y "%JAR_SOURCE%" "%WORKING_DIR_WIN%\api-java-mssql\pilot-api.jar" >nul
if errorlevel 1 (
	echo Failed to copy jar to api-java-mssql build context.
	popd
	exit /b 1
)
copy /Y "%JAR_SOURCE%" "%WORKING_DIR_WIN%\api-java-postgres\pilot-api.jar" >nul
if errorlevel 1 (
	echo Failed to copy jar to api-java-postgres build context.
	popd
	exit /b 1
)
popd

REM 4. Build arg used only for deployment metadata.
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 5. Build and start both API containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p pilot-api-java up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

popd

REM 6. Launch health checks.
start http://localhost:%JAVA_MSSQL_PORT%/healthcheck
start http://localhost:%JAVA_POSTGRES_PORT%/healthcheck

goto :eof

:load_env_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from "..\secrets\api-java.env.example".
	exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`type "%~1" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
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
