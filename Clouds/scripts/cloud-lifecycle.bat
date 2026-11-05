@echo off
REM Clouds - start / stop one cloud emulator and the components its builders created.
REM Usage: call "%~dp0scripts\cloud-lifecycle.bat" :start <cloud> [-norebuild]
REM        call "%~dp0scripts\cloud-lifecycle.bat" :stop  <cloud>
REM   <cloud> = aws | azure | gcp
REM Nothing is created or destroyed by :stop; :start re-runs the cloud's dbapi builder
REM only when the deployed APIs do not answer (the emulators do not restart every
REM database container themselves; see docs\CloudEmulatorsDbAndApi.md, D12).
setlocal EnableExtensions DisableDelayedExpansion
set "CL_ROOT=%~dp0.."
set "COMMON=%~dp0dbapi-common.bat"
set "COMPOSE_FILE=%CL_ROOT%\docker-compose.clouds.yml"
set "PARTITION_NAME=local-clouds"
set "CL_CLOUD=%~2"
set "CL_OPT=%~3"
if /I not "%CL_CLOUD%"=="aws" if /I not "%CL_CLOUD%"=="azure" if /I not "%CL_CLOUD%"=="gcp" (
	echo Unknown cloud "%CL_CLOUD%".
	exit /b 1
)
call :names %CL_CLOUD%
docker info >nul 2>&1
if errorlevel 1 (
	echo Docker is not running or not available.
	exit /b 1
)
goto %~1

REM ---------------------------------------------------------------------------
REM :names <cloud>  - emulator health URL and the name prefixes of its managed containers.
REM ---------------------------------------------------------------------------
:names
if /I "%~1"=="aws" (
	set "CL_HEALTH=http://localhost:4566/_localstack/health"
	set "CL_PREFIXES=floci-aws-"
	set "CL_LABEL=AWS"
)
if /I "%~1"=="azure" (
	set "CL_HEALTH=https://localhost:4577/_floci/health"
	set "CL_PREFIXES=floci-az-local-azure-"
	set "CL_LABEL=Azure"
)
if /I "%~1"=="gcp" (
	set "CL_HEALTH=http://localhost:4588/health"
	set "CL_PREFIXES=floci-gcp-local-gcp-"
	set "CL_LABEL=GCP"
)
exit /b 0

REM ===========================================================================
REM :start <cloud> [-norebuild]
REM ===========================================================================
:start
echo === Start %CL_LABEL% emulator, databases and APIs ===

REM 1. The platform selection must allow this cloud.
call "%COMMON%" :check_platform %CL_CLOUD% || exit /b 1

REM 2. Shared services the APIs need (they are not stopped by :stop).
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net >nul
for %%N in (local-keycloak local-loki local-mimir local-tempo otel-collector local-grafana) do call :start_if_exists %%N

REM 3. The emulator (created by Docker-clouds-builder.bat if it does not exist yet).
docker inspect local-%CL_CLOUD% >nul 2>&1
if errorlevel 1 (
	echo Container local-%CL_CLOUD% does not exist. Creating it with Compose ...
	docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" up -d local-%CL_CLOUD% || exit /b 1
) else (
	docker start local-%CL_CLOUD% >nul || exit /b 1
)
call :wait_health || exit /b 1
if /I "%CL_CLOUD%"=="azure" (
	if not exist "%CL_ROOT%\terraform\tls" mkdir "%CL_ROOT%\terraform\tls"
	curl.exe -sfk "https://localhost:4577/_floci/tls-cert" -o "%CL_ROOT%\terraform\tls\floci-az.pem"
)

REM 4. Restart the managed containers that are still stopped (databases first, then
REM    APIs). The emulators restart or recreate some of them on their own.
call :start_managed

REM 5. Nothing deployed yet: done.
call :has_state %CL_CLOUD% || (
	echo No %CL_LABEL% databases or APIs are deployed.
	echo Run Clouds\Docker-clouds-%CL_CLOUD%-dbapi-builder.bat to create them.
	exit /b 0
)

REM 6. Check the APIs (health + authenticated data probe). If they do not answer,
REM    re-run the dbapi builder: it repairs the databases and reloads Northwind.
call "%COMMON%" :load_secrets || exit /b 1
set "WFU_TRIES=40"
call "%COMMON%" :verify_apis %CL_CLOUD% 20-apis && goto started
set "WFU_TRIES="
if /I "%CL_OPT%"=="-norebuild" (
	echo The %CL_LABEL% APIs are not healthy. Run Clouds\Docker-clouds-%CL_CLOUD%-dbapi-builder.bat to repair them.
	exit /b 1
)
echo The %CL_LABEL% APIs are not healthy; re-running Docker-clouds-%CL_CLOUD%-dbapi-builder.bat ...
endlocal & call "%~dp0..\Docker-clouds-%~2-dbapi-builder.bat"
exit /b %errorlevel%

:started
echo %CL_LABEL% is running. API base URLs:
type "%TEMP%\cloud-%CL_CLOUD%-api-urls.txt"
exit /b 0

REM ===========================================================================
REM :stop <cloud>
REM ===========================================================================
:stop
echo === Stop %CL_LABEL% emulator, databases and APIs ===
REM The emulator is stopped first, so it cannot replace the containers stopped next.
docker inspect local-%CL_CLOUD% >nul 2>&1 && docker stop local-%CL_CLOUD% >nul
set "CL_COUNT=0"
for %%P in (%CL_PREFIXES%) do (
	for /f "usebackq tokens=*" %%C in (`docker ps --format "{{.Names}}" --filter "name=^%%P"`) do (
		echo Stopping %%C
		docker stop %%C >nul
		set /a CL_COUNT+=1
	)
)
echo %CL_LABEL% stopped (emulator and %CL_COUNT% managed containers). Data and Terraform state are kept.
echo Start it again with Clouds\Docker-clouds-%CL_CLOUD%-start.bat
exit /b 0

REM ---------------------------------------------------------------------------
REM helpers
REM ---------------------------------------------------------------------------
:start_if_exists
docker inspect %~1 >nul 2>&1 || (
	echo WARNING: %~1 does not exist; the APIs need it. Run its builder first.
	exit /b 0
)
docker start %~1 >nul
exit /b 0

:wait_health
echo Waiting for %CL_LABEL% at %CL_HEALTH% ...
for /L %%I in (1,1,60) do (
	curl.exe -sSfk -o nul "%CL_HEALTH%" >nul 2>nul && goto wh_ready
	ping -n 3 127.0.0.1 >nul
)
echo %CL_LABEL% did not become ready in time.
exit /b 1
:wh_ready
echo %CL_LABEL% is ready.
exit /b 0

:start_managed
REM Give the emulator a moment to reconcile its own containers first.
REM Sorted by name, so a GCP VM container starts before its <vm>_klt container.
ping -n 11 127.0.0.1 >nul
for %%P in (%CL_PREFIXES%) do (
	for /f "usebackq tokens=*" %%C in (`docker ps -a --format "{{.Names}}" --filter "status=exited" --filter "name=^%%P" ^| sort`) do (
		echo Starting %%C
		docker start %%C >nul 2>&1 || echo WARNING: could not start %%C
	)
)
exit /b 0

REM :has_state <cloud>  - true when 20-apis has resources in its Terraform state.
:has_state
findstr /C:"\"mode\":" "%CL_ROOT%\terraform\%~1\20-apis\terraform.tfstate" >nul 2>&1
exit /b %errorlevel%
