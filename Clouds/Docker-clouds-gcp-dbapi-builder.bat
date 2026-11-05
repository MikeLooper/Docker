@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds - GCP databases and APIs (Terraform)
REM Usage: Docker-clouds-gcp-dbapi-builder.bat [-destroy]
REM   Cloud SQL for PostgreSQL and SQL Server on Compute Engine, loaded with
REM   Northwind, and the 6 APIs on Cloud Run. See docs\CloudEmulatorsDbAndApi.md.

pushd "%~dp0"

set "CLOUD=gcp"
set "COMMON=%~dp0scripts\dbapi-common.bat"

set "DESTROY="
if /I "%~1"=="-destroy" set "DESTROY=1"
if not "%~1"=="" if not defined DESTROY (
	echo Usage: Docker-clouds-gcp-dbapi-builder.bat [-destroy]
	goto failed
)

docker info >nul 2>&1
if errorlevel 1 (
	echo Docker is not running or not available.
	goto failed
)

REM 0. Load and validate secrets\clouds-db.env.
call "%COMMON%" :load_secrets || goto failed

REM 1. Platform and running services.
if defined DESTROY goto destroy
call "%COMMON%" :check_platform %CLOUD% || goto failed
call "%COMMON%" :check_running %CLOUD% || goto failed

REM 2. The API images must exist.
call "%COMMON%" :check_images || goto failed

REM 3. Terraform image.
docker pull -q hashicorp/terraform:latest || goto failed

REM 4. Databases (Cloud SQL + Compute Engine).
REM    After a local-gcp restart, floci-gcp does not restart the VM's SQL Server
REM    container (<vm>_klt), so the VM is replaced.
call :heal_mssql_vm || goto failed
call "%COMMON%" :tf_apply %CLOUD% 10-databases || goto failed

REM 5. Endpoints.
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_host MSSQL_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_port MSSQL_PORT || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_host POSTGRES_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_port POSTGRES_PORT || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_admin_user POSTGRES_ADMIN_USER || goto failed
echo SQL Server: %MSSQL_HOST%:%MSSQL_PORT%   PostgreSQL: %POSTGRES_HOST%:%POSTGRES_PORT%

REM 6. Load Northwind. SQL Server on GCE uses sa (disabled at the end); floci-gcp keeps
REM    the Cloud SQL admin login fixed (postgres/postgres), whatever root password is sent.
call "%~dp0scripts\load-mssql.bat" %MSSQL_HOST% %MSSQL_PORT% gce || goto failed
setlocal
set "CLOUD_DB_ADMIN_USER=%POSTGRES_ADMIN_USER%"
set "CLOUD_DB_ADMIN_PASSWORD=postgres"
call "%~dp0scripts\load-postgres.bat" %POSTGRES_HOST% %POSTGRES_PORT% managed
endlocal & set "PG_RC=%errorlevel%"
if not "%PG_RC%"=="0" goto failed

REM 7. No image step: Cloud Run runs the local cloud-api-* images as-is.

REM 8. APIs (Cloud Run).
call "%COMMON%" :tf_apply %CLOUD% 20-apis || goto failed

REM 9. Health checks and the authenticated data probe (Cloud Run service URLs).
call "%COMMON%" :verify_apis %CLOUD% 20-apis || goto failed

popd

REM 10. Open the health checks in the browser.
call "%COMMON%" :open_healthchecks %CLOUD%
goto :eof

:destroy
call "%COMMON%" :is_running local-%CLOUD% || (
	echo local-%CLOUD% must be running to destroy its resources.
	goto failed
)
set "DESTROY_FAILED="
call "%COMMON%" :tf_destroy %CLOUD% 20-apis || set "DESTROY_FAILED=1"
call "%COMMON%" :tf_destroy %CLOUD% 10-databases || set "DESTROY_FAILED=1"
call "%COMMON%" :remove_leftovers floci-gcp-compute- floci-gcp-local-gcp-
popd
if defined DESTROY_FAILED exit /b 1
echo GCP databases and APIs destroyed.
goto :eof

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :heal_mssql_vm  - replaces the SQL Server VM when its _klt container is not running.
REM ---------------------------------------------------------------------------
:heal_mssql_vm
findstr /C:"google_compute_instance" "%~dp0terraform\gcp\10-databases\terraform.tfstate" >nul 2>&1 || exit /b 0
call "%COMMON%" :tf %CLOUD% 10-databases "init -input=false -no-color" >nul
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_host HMV_HOST >nul 2>&1 || exit /b 0
set "HMV_STATE="
for /f "usebackq tokens=*" %%S in (`docker inspect -f "{{.State.Running}}" %HMV_HOST%_klt 2^>nul`) do set "HMV_STATE=%%S"
if "%HMV_STATE%"=="true" exit /b 0
echo SQL Server container %HMV_HOST%_klt is not running (local-gcp was restarted); replacing the VM.
call "%COMMON%" :tf %CLOUD% 10-databases "apply -auto-approve -input=false -no-color -replace=google_compute_instance.mssql"
exit /b %errorlevel%
