@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - OTEL

pushd "%~dp0"

set "PARTITION_NAME=local-otel"
set "COMPOSE_FILE=%~dp0docker-compose.otel.yml"
set "IMAGE_FILE_OTEL_COLL=otel/opentelemetry-collector-contrib:latest"
set "IMAGE_FILE_TEMPO=grafana/tempo:latest"
set "IMAGE_FILE_MIMIR=grafana/mimir:latest"
set "IMAGE_FILE_LOKI=grafana/loki:latest"
set "IMAGE_FILE_GRAFANA=grafana/grafana:latest"
set "GRAFANA_PORT=3000"
set "GRAFANA_URL=http://localhost:%GRAFANA_PORT%"

REM 1. Download the images:
docker pull "%IMAGE_FILE_OTEL_COLL%"
docker pull "%IMAGE_FILE_TEMPO%"
docker pull "%IMAGE_FILE_MIMIR%"
docker pull "%IMAGE_FILE_LOKI%"
docker pull "%IMAGE_FILE_GRAFANA%"
    
REM 2. Stop any prior compose services for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans

REM 3. Build and start containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

REM 4. Wait for Grafana API to be ready.
for /L %%I in (1,1,60) do (
	curl -sSf "%GRAFANA_URL%/api/health" >nul 2>nul && goto grafana_ready
	timeout /t 2 /nobreak >nul
)
echo Grafana API did not become ready in time.
exit /b 1

:grafana_ready

REM 5. create a limited-access credential inside Grafana, to allow dashboard access.
set "GRAFANA_USER_RESPONSE=%TEMP%\grafana-user-response.json"
set "GRAFANA_LOOKUP_RESPONSE=%TEMP%\grafana-user-lookup.json"
set "GRAFANA_PERM_RESPONSE=%TEMP%\grafana-perm-response.json"
set "GRAFANA_AUTH="

REM Resolve working admin credentials. Existing Grafana volumes may keep old admin users/passwords.
curl.exe -sSf -u "my_admin:my_admin_password" "%GRAFANA_URL%/api/user" >nul 2>nul && set "GRAFANA_AUTH=my_admin:my_admin_password"
if not defined GRAFANA_AUTH (
	curl.exe -sSf -u "admin:my_admin_password" "%GRAFANA_URL%/api/user" >nul 2>nul && set "GRAFANA_AUTH=admin:my_admin_password"
)
if not defined GRAFANA_AUTH (
	curl.exe -sSf -u "admin:admin" "%GRAFANA_URL%/api/user" >nul 2>nul && set "GRAFANA_AUTH=admin:admin"
)
if not defined GRAFANA_AUTH (
	docker exec local-grafana grafana cli admin reset-admin-password my_admin_password >nul 2>nul
	curl.exe -sSf -u "admin:my_admin_password" "%GRAFANA_URL%/api/user" >nul 2>nul && set "GRAFANA_AUTH=admin:my_admin_password"
)
if not defined GRAFANA_AUTH (
	echo Unable to authenticate to Grafana admin API. Skipping Grafana user/role provisioning.
	goto grafana_user_setup_done
)

curl.exe --fail-with-body -sS -X POST -H "Content-Type: application/json" -u "%GRAFANA_AUTH%" -d "{""name"":""Limited User"", ""email"":""user@example.com"", ""login"":""limited_user"", ""password"":""user_secure_password""}" "%GRAFANA_URL%/api/admin/users" > "%GRAFANA_USER_RESPONSE%" 2>&1
if errorlevel 1 (
	rem Best-effort provisioning failed; continue without limited user setup.
)

REM 6. Grant limited_user Grafana admin permissions (includes server stats read access).
curl.exe -sS -u "%GRAFANA_AUTH%" "%GRAFANA_URL%/api/users/lookup?loginOrEmail=limited_user" > "%GRAFANA_LOOKUP_RESPONSE%" 2>nul
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$r=Get-Content -Raw '%GRAFANA_LOOKUP_RESPONSE%' ^| ConvertFrom-Json; $r.id"`) do set "GRAFANA_USER_ID=%%I"

if defined GRAFANA_USER_ID (
	curl.exe --fail-with-body -sS -X PUT -H "Content-Type: application/json" -u "%GRAFANA_AUTH%" -d "{""isGrafanaAdmin"":true}" "%GRAFANA_URL%/api/admin/users/%GRAFANA_USER_ID%/permissions" > "%GRAFANA_PERM_RESPONSE%" 2>nul
)

REM 7. User provisioning is best-effort only.
:grafana_user_setup_done

popd

REM 8. Launch UI as a health check.
start http://localhost:%GRAFANA_PORT%
