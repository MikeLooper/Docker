@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds (AWS / Azure / GCP emulators)

pushd "%~dp0"

set "PARTITION_NAME=local-clouds"
set "COMPOSE_FILE=%~dp0docker-compose.clouds.yml"
set "IMAGE_FILE_AWS=floci/floci:latest"
set "IMAGE_FILE_AZURE=floci/floci-az:latest"
set "IMAGE_FILE_GCP=floci/floci-gcp:latest"
set "AWS_PORT=4566"
set "AZURE_PORT=4577"
set "GCP_PORT=4588"

REM 1. Ensure the shared network exists.
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net

REM 2. Download the images.
docker pull "%IMAGE_FILE_AWS%"
docker pull "%IMAGE_FILE_AZURE%"
docker pull "%IMAGE_FILE_GCP%"

REM 3. Stop any prior compose services for this stack, and remove stale console sidecars.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" down --remove-orphans
docker rm -f floci-aws-ui floci-az-local-azure-ui >nul 2>&1

REM 4. Start containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" up -d --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	popd
	exit /b 1
)

REM 5. Wait for each emulator to become ready.
call :wait_for_url "AWS" "http://localhost:%AWS_PORT%/_localstack/health" strict || goto failed
call :wait_for_url "Azure" "http://localhost:%AZURE_PORT%/_floci/health" strict || goto failed
call :wait_for_url "GCP" "http://localhost:%GCP_PORT%/health" strict || goto failed

popd

REM 6. Display the consoles in the browser.
start http://localhost:%AWS_PORT%/_floci/ui
start http://localhost:%AZURE_PORT%/_floci/ui
start http://localhost:%GCP_PORT%/_floci-gcp/info

goto :eof

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :wait_for_url <name> <url> <mode>
REM   strict = curl -sSf (HTTP 2xx/3xx required)
REM   any    = curl -s -o nul (any HTTP response is accepted)
REM ---------------------------------------------------------------------------
:wait_for_url
set "WAIT_NAME=%~1"
set "WAIT_URL=%~2"
set "WAIT_MODE=%~3"
echo Waiting for %WAIT_NAME% at %WAIT_URL% ...
for /L %%I in (1,1,60) do (
	if /I "%WAIT_MODE%"=="strict" (
		curl.exe -sSf "%WAIT_URL%" >nul 2>nul && goto wait_ready
	) else (
		curl.exe -s -o nul "%WAIT_URL%" >nul 2>nul && goto wait_ready
	)
	timeout /t 2 /nobreak >nul
)
echo %WAIT_NAME% did not become ready in time.
exit /b 1

:wait_ready
echo %WAIT_NAME% is ready.
exit /b 0
