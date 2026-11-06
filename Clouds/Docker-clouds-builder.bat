@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds (AWS / Azure / GCP emulators)
REM Usage: Docker-clouds-builder.bat [-platform all|aws|azure|gcp]     (default: all)
REM A single platform destroys the other clouds' deployments, stops their emulators,
REM and starts only the selected one. The choice is saved in Clouds\.platform.

pushd "%~dp0"

set "PARTITION_NAME=local-clouds"
set "COMPOSE_FILE=%~dp0docker-compose.clouds.yml"
set "PLATFORM_FILE=%~dp0.platform"
set "IMAGE_FILE_AWS=floci/floci:latest"
set "IMAGE_FILE_AZURE=floci/floci-az:latest"
set "IMAGE_FILE_GCP=floci/floci-gcp:latest"
set "AWS_PORT=4566"
set "AZURE_PORT=4577"
set "GCP_PORT=4588"

REM 0. Parse and validate the arguments.
set "PLATFORM=all"
if "%~1"=="" goto args_done
if /I not "%~1"=="-platform" goto usage
if "%~2"=="" goto usage
set "PLATFORM=%~2"
if not "%~3"=="" goto usage
:args_done
if /I "%PLATFORM%"=="all" goto platform_ok
if /I "%PLATFORM%"=="aws" goto platform_ok
if /I "%PLATFORM%"=="azure" goto platform_ok
if /I "%PLATFORM%"=="gcp" goto platform_ok
goto usage
:platform_ok
for %%P in (all aws azure gcp) do if /I "%PLATFORM%"=="%%P" set "PLATFORM=%%P"
echo Platform: %PLATFORM%

docker info >nul 2>&1
if errorlevel 1 (
	echo Docker is not running or not available.
	goto failed
)

REM 1. Ensure the shared network exists.
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net

REM 2. Download the selected images.
if "%PLATFORM%"=="all" (
	docker pull "%IMAGE_FILE_AWS%"
	docker pull "%IMAGE_FILE_AZURE%"
	docker pull "%IMAGE_FILE_GCP%"
)
if "%PLATFORM%"=="aws" docker pull "%IMAGE_FILE_AWS%"
if "%PLATFORM%"=="azure" docker pull "%IMAGE_FILE_AZURE%"
if "%PLATFORM%"=="gcp" docker pull "%IMAGE_FILE_GCP%"

REM 3. Single platform: tear down every other cloud while its emulator can still clean up.
if "%PLATFORM%"=="all" goto full_restart
for %%C in (aws azure gcp) do if not "%%C"=="%PLATFORM%" call :retire_cloud %%C
goto start_selected

:full_restart
REM 3. Stop any prior compose services for this stack, and remove stale console sidecars.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" down --remove-orphans
docker rm -f floci-aws-ui floci-az-local-azure-ui >nul 2>&1

:start_selected
REM 4. Start the selected emulators with Compose.
set "SERVICE_NAME="
if not "%PLATFORM%"=="all" set "SERVICE_NAME=local-%PLATFORM%"
if not "%PLATFORM%"=="all" call :sidecar_name %PLATFORM%
if defined SIDECAR docker rm -f %SIDECAR% >nul 2>&1
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" up -d --force-recreate %SERVICE_NAME%
if errorlevel 1 (
	echo docker compose up failed.
	goto failed
)

REM 5. Wait for each selected emulator to become ready.
if "%PLATFORM%"=="all" goto wait_all
if "%PLATFORM%"=="aws" call :wait_aws || goto failed
if "%PLATFORM%"=="azure" call :wait_azure || goto failed
if "%PLATFORM%"=="gcp" call :wait_gcp || goto failed
goto waited
:wait_all
call :wait_aws || goto failed
call :wait_azure || goto failed
call :wait_gcp || goto failed
:waited

REM 6. Save the selection for the other scripts.
> "%PLATFORM_FILE%" echo %PLATFORM%

popd

REM 7. Display the consoles of the selected emulators in the browser.
if "%PLATFORM%"=="all" goto open_all
if "%PLATFORM%"=="aws" start http://localhost:%AWS_PORT%/_floci/ui
if "%PLATFORM%"=="azure" start http://localhost:%AZURE_PORT%/_floci/ui
if "%PLATFORM%"=="gcp" start http://localhost:%GCP_PORT%/_floci-gcp/info
goto :eof
:open_all
start http://localhost:%AWS_PORT%/_floci/ui
start http://localhost:%AZURE_PORT%/_floci/ui
start http://localhost:%GCP_PORT%/_floci-gcp/info
goto :eof

:usage
echo Usage: Docker-clouds-builder.bat [-platform all^|aws^|azure^|gcp]
echo   Default: all. A single platform stops the other emulators after destroying
echo   their databases and APIs.
popd
exit /b 1

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :retire_cloud <cloud>
REM   Destroys the cloud's Terraform deployments (if any) while its emulator is
REM   still running, then stops the emulator and removes its console sidecar.
REM ---------------------------------------------------------------------------
:retire_cloud
set "RC_CLOUD=%~1"
set "RC_RUNNING="
for /f "usebackq tokens=*" %%S in (`docker inspect -f "{{.State.Running}}" local-%RC_CLOUD% 2^>nul`) do set "RC_RUNNING=%%S"
set "RC_HAS_STATE="
REM A state file with no "mode" entries has no resources.
findstr /C:"\"mode\":" "%~dp0terraform\%RC_CLOUD%\20-apis\terraform.tfstate" >nul 2>&1 && set "RC_HAS_STATE=1"
findstr /C:"\"mode\":" "%~dp0terraform\%RC_CLOUD%\10-databases\terraform.tfstate" >nul 2>&1 && set "RC_HAS_STATE=1"
if "%RC_RUNNING%"=="true" if defined RC_HAS_STATE if exist "%~dp0Docker-clouds-%RC_CLOUD%-dbapi-builder.bat" (
	echo Destroying the %RC_CLOUD% databases and APIs ...
	call "%~dp0Docker-clouds-%RC_CLOUD%-dbapi-builder.bat" -destroy
	if errorlevel 1 echo WARNING: destroying the %RC_CLOUD% deployment reported an error.
)
if not "%RC_RUNNING%"=="true" if defined RC_HAS_STATE (
	echo WARNING: local-%RC_CLOUD% is not running, so its Terraform state was not destroyed.
	echo          Start it and run Docker-clouds-%RC_CLOUD%-dbapi-builder.bat -destroy to clean up.
)
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" stop local-%RC_CLOUD%
call :sidecar_name %RC_CLOUD%
if defined SIDECAR docker rm -f %SIDECAR% >nul 2>&1
exit /b 0

REM :sidecar_name <cloud>  - sets SIDECAR to the console sidecar container (if any).
:sidecar_name
set "SIDECAR="
if /I "%~1"=="aws" set "SIDECAR=floci-aws-ui floci-aws-ecr-registry"
if /I "%~1"=="azure" set "SIDECAR=floci-az-local-azure-ui"
exit /b 0

:wait_aws
call :wait_for_url "AWS" "http://localhost:%AWS_PORT%/_localstack/health" strict
exit /b %errorlevel%

:wait_azure
REM local-azure runs with TLS (self-signed). Save its CA certificate for Terraform.
call :wait_for_url "Azure" "https://localhost:%AZURE_PORT%/_floci/health" strict-insecure || exit /b 1
if not exist "%~dp0terraform\tls" mkdir "%~dp0terraform\tls"
curl.exe -sfk "https://localhost:%AZURE_PORT%/_floci/tls-cert" -o "%~dp0terraform\tls\floci-az.pem"
if errorlevel 1 echo WARNING: could not save the floci-az TLS certificate.
exit /b 0

:wait_gcp
call :wait_for_url "GCP" "http://localhost:%GCP_PORT%/health" strict
exit /b %errorlevel%

REM ---------------------------------------------------------------------------
REM :wait_for_url <name> <url> <mode>
REM   strict          = curl -sSf  (HTTP 2xx/3xx required)
REM   strict-insecure = curl -sSfk (as strict, self-signed TLS accepted)
REM   any             = curl -s -o nul (any HTTP response is accepted)
REM ---------------------------------------------------------------------------
:wait_for_url
set "WAIT_NAME=%~1"
set "WAIT_URL=%~2"
set "WAIT_MODE=%~3"
echo Waiting for %WAIT_NAME% at %WAIT_URL% ...
for /L %%I in (1,1,60) do (
	if /I "%WAIT_MODE%"=="strict" (
		curl.exe -sSf "%WAIT_URL%" >nul 2>nul && goto wait_ready
	) else if /I "%WAIT_MODE%"=="strict-insecure" (
		curl.exe -sSfk "%WAIT_URL%" >nul 2>nul && goto wait_ready
	) else (
		curl.exe -s -o nul "%WAIT_URL%" >nul 2>nul && goto wait_ready
	)
	ping -n 3 127.0.0.1 >nul
)
echo %WAIT_NAME% did not become ready in time.
exit /b 1

:wait_ready
echo %WAIT_NAME% is ready.
exit /b 0
