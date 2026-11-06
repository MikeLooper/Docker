@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds - Azure databases and APIs (Terraform)
REM Usage: Docker-clouds-azure-dbapi-builder.bat [-destroy]
REM   Azure SQL + PostgreSQL Flexible Server loaded with Northwind, the 6 APIs as
REM   Container Apps (ingress as the front door). See docs\CloudEmulatorsDbAndApi.md.

pushd "%~dp0"

set "CLOUD=azure"
set "COMMON=%~dp0scripts\dbapi-common.bat"
set "TLS_DIR=%~dp0terraform\tls"

set "DESTROY="
if /I "%~1"=="-destroy" set "DESTROY=1"
if not "%~1"=="" if not defined DESTROY (
	echo Usage: Docker-clouds-azure-dbapi-builder.bat [-destroy]
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

REM 3. Terraform image, and the CA bundle that trusts the floci-az certificate.
docker pull -q hashicorp/terraform:latest || goto failed
call :ca_bundle || goto failed

REM 4. Databases (Azure SQL + PostgreSQL Flexible Server).
REM    After a local-azure restart, floci-az keeps the servers in ARM but does not
REM    restart their data-plane containers, so those servers are replaced.
call :heal_data_plane || goto failed
call "%COMMON%" :tf_apply %CLOUD% 10-databases || goto failed

REM 5. Endpoints (from the emulator's /connect API, via Terraform outputs).
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_host MSSQL_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_port MSSQL_PORT || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_host POSTGRES_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_port POSTGRES_PORT || goto failed
echo SQL Server: %MSSQL_HOST%:%MSSQL_PORT%   PostgreSQL: %POSTGRES_HOST%:%POSTGRES_PORT%

REM 6. Load Northwind.
call "%~dp0scripts\load-mssql.bat" %MSSQL_HOST% %MSSQL_PORT% managed || goto failed
call "%~dp0scripts\load-postgres.bat" %POSTGRES_HOST% %POSTGRES_PORT% managed || goto failed

REM 7. No image step: Container Apps run the local cloud-api-* images as-is.

REM 8. APIs (Container Apps; their ingress is the front door).
call "%COMMON%" :tf_apply %CLOUD% 20-apis || goto failed

REM 9. Health checks and the authenticated data probe (Container Apps ingress).
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
call :ca_bundle || goto failed
set "DESTROY_FAILED="
call "%COMMON%" :tf_destroy %CLOUD% 20-apis || set "DESTROY_FAILED=1"
call "%COMMON%" :tf_destroy %CLOUD% 10-databases || set "DESTROY_FAILED=1"
call "%COMMON%" :remove_leftovers floci-az-local-azure-ca- floci-az-local-azure-sql- floci-az-local-azure-pg-
popd
if defined DESTROY_FAILED exit /b 1
echo Azure databases and APIs destroyed.
goto :eof

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :heal_data_plane
REM   When 10-databases has state but a server's /connect does not report a
REM   running data plane (SQL: not HTTP 200; PostgreSQL: port 0), applies with
REM   -replace for that server so floci-az starts a fresh container.
REM ---------------------------------------------------------------------------
:heal_data_plane
if not exist "%~dp0terraform\azure\10-databases\terraform.tfstate" exit /b 0
set "HDP_REPLACE="
set "HDP_CODE="
for /f "usebackq tokens=*" %%C in (`curl.exe -sk -o nul -w "%%{http_code}" "https://localhost:4577/devstoreaccount1-sql/servers/cloud-mssql/connect"`) do set "HDP_CODE=%%C"
if "%HDP_CODE%"=="409" set "HDP_REPLACE=%HDP_REPLACE% -replace=azurerm_mssql_server.mssql"
set "HDP_FILE=%TEMP%\cloud-az-connect-%RANDOM%.json"
curl.exe -sk -o "%HDP_FILE%" "https://localhost:4577/devstoreaccount1-postgres/flexibleServers/cloud-postgres/connect"
findstr /C:"\"port\":0," "%HDP_FILE%" >nul && set "HDP_REPLACE=%HDP_REPLACE% -replace=azurerm_postgresql_flexible_server.postgres"
del /Q "%HDP_FILE%" >nul 2>&1
if not defined HDP_REPLACE exit /b 0
echo Database data plane not running (local-azure was restarted); replacing:%HDP_REPLACE%
docker rm -f floci-az-local-azure-sql-cloud-mssql floci-az-local-azure-pg-cloud-postgres >nul 2>&1
call "%COMMON%" :tf %CLOUD% 10-databases "init -input=false -no-color" >nul
call "%COMMON%" :tf %CLOUD% 10-databases "apply -auto-approve -input=false -no-color%HDP_REPLACE%"
exit /b %errorlevel%

REM ---------------------------------------------------------------------------
REM :ca_bundle  - terraform\tls\ca-bundle.pem = Terraform image's system CAs + floci-az CA.
REM ---------------------------------------------------------------------------
:ca_bundle
if not exist "%TLS_DIR%" mkdir "%TLS_DIR%"
curl.exe -sfk "https://localhost:4577/_floci/tls-cert" -o "%TLS_DIR%\floci-az.pem"
if errorlevel 1 (
	echo Could not fetch the floci-az certificate. Is FLOCI_AZ_TLS_ENABLED=true set on local-azure?
	exit /b 1
)
if not exist "%TLS_DIR%\system-ca.pem" (
	docker run --rm --entrypoint cat hashicorp/terraform:latest /etc/ssl/certs/ca-certificates.crt > "%TLS_DIR%\system-ca.pem"
	if errorlevel 1 exit /b 1
)
copy /Y /B "%TLS_DIR%\system-ca.pem" + "%TLS_DIR%\floci-az.pem" "%TLS_DIR%\ca-bundle.pem" >nul
exit /b %errorlevel%
