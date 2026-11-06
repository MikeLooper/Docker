@echo off
REM Clouds - shared subroutines for Docker-clouds-<cloud>-dbapi-builder.bat
REM Usage: call "%~dp0scripts\dbapi-common.bat" :<routine> [args]
REM No setlocal here on purpose: the routines set variables for the caller.
goto %~1

REM ---------------------------------------------------------------------------
REM :load_secrets  - loads secrets\clouds-db.env, validates it, sets TF_VAR_*.
REM ---------------------------------------------------------------------------
:load_secrets
set "SECRETS_FILE=%~dp0..\..\secrets\clouds-db.env"
if not exist "%SECRETS_FILE%" (
	echo Missing secrets file: "%SECRETS_FILE%"
	echo Create it from "secrets\clouds-db.env.example".
	exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%A in (`type "%SECRETS_FILE%" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
for %%K in (CLOUD_DB_ADMIN_USER CLOUD_DB_ADMIN_PASSWORD CLOUD_DB_DEVUSER_PASSWORD) do (
	if not defined %%K (
		echo Missing required key %%K in "%SECRETS_FILE%".
		exit /b 1
	)
)
if /I "%CLOUD_DB_ADMIN_PASSWORD%"=="<cloud-db-admin-password>" (
	echo Replace placeholder CLOUD_DB_ADMIN_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%CLOUD_DB_DEVUSER_PASSWORD%"=="<cloud-db-devuser-password>" (
	echo Replace placeholder CLOUD_DB_DEVUSER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
set "CLOUD_PROBE=1"
if not defined CLOUD_TEST_USER set "CLOUD_PROBE="
if not defined CLOUD_TEST_PASSWORD set "CLOUD_PROBE="
if /I "%CLOUD_TEST_USER%"=="<keycloak-test-user>" set "CLOUD_PROBE="
if /I "%CLOUD_TEST_PASSWORD%"=="<keycloak-test-user-password>" set "CLOUD_PROBE="
set "TF_VAR_db_admin_user=%CLOUD_DB_ADMIN_USER%"
set "TF_VAR_db_admin_password=%CLOUD_DB_ADMIN_PASSWORD%"
set "TF_VAR_db_devuser_password=%CLOUD_DB_DEVUSER_PASSWORD%"
exit /b 0

REM ---------------------------------------------------------------------------
REM :check_platform <cloud>  - Clouds\.platform must be "all" or <cloud>.
REM ---------------------------------------------------------------------------
:check_platform
set "CUR_PLATFORM=all"
if exist "%~dp0..\.platform" set /p CUR_PLATFORM=<"%~dp0..\.platform"
for /f "tokens=1" %%P in ("%CUR_PLATFORM%") do set "CUR_PLATFORM=%%P"
if /I "%CUR_PLATFORM%"=="all" exit /b 0
if /I "%CUR_PLATFORM%"=="%~2" exit /b 0
echo Platform is set to %CUR_PLATFORM%. Run Clouds\Docker-clouds-builder.bat -platform %~2 first.
exit /b 1

REM ---------------------------------------------------------------------------
REM :check_running <cloud>  - local-<cloud>, local-keycloak and otel-collector.
REM ---------------------------------------------------------------------------
:check_running
set "CR_OK=1"
for %%N in (local-%~2 local-keycloak otel-collector) do call "%~f0" :is_running %%N || set "CR_OK="
if defined CR_OK exit /b 0
echo Start the missing services first (local-%~2: Clouds\Docker-clouds-builder.bat -platform %~2).
exit /b 1

:is_running
set "IR_STATE="
for /f "usebackq tokens=*" %%S in (`docker inspect -f "{{.State.Running}}" %~2 2^>nul`) do set "IR_STATE=%%S"
if "%IR_STATE%"=="true" exit /b 0
echo Container %~2 is not running.
exit /b 1

REM ---------------------------------------------------------------------------
REM :check_images  - the 6 cloud-api-* images from apis.json must exist.
REM ---------------------------------------------------------------------------
:check_images
set "CI_OK=1"
for /f "usebackq tokens=*" %%N in (`powershell -NoProfile -Command "(Get-Content '%~dp0..\terraform\apis.json' -Raw | ConvertFrom-Json).name"`) do (
	docker image inspect "%%N:1.0" >nul 2>&1 || (
		echo Image %%N:1.0 is missing.
		set "CI_OK="
	)
)
if defined CI_OK exit /b 0
echo Run Clouds\Docker-clouds-api-images-builder.bat first.
exit /b 1

REM ---------------------------------------------------------------------------
REM :tf <cloud> <root> "<terraform args>"  (one quoted argument: cmd splits on =)
REM   Runs hashicorp/terraform inside local-<cloud>'s network namespace.
REM   Secrets are passed by name only (-e NAME).
REM ---------------------------------------------------------------------------
:tf
set "TF_CLOUD=%~2"
set "TF_ROOT=%~3"
set "TF_ARGS=%~4"
for %%I in ("%~dp0..\terraform") do set "TF_DIR=%%~fI"
set "TF_EXTRA="
if /I "%TF_CLOUD%"=="azure" set "TF_EXTRA=-e SSL_CERT_FILE=/workspace/tls/ca-bundle.pem"
docker run --rm --network container:local-%TF_CLOUD% -v "%TF_DIR%:/workspace" -w /workspace/%TF_CLOUD%/%TF_ROOT% -e TF_VAR_db_admin_user -e TF_VAR_db_admin_password -e TF_VAR_db_devuser_password -e TF_IN_AUTOMATION=1 %TF_EXTRA% %TF_TERRAFORM_ENV% hashicorp/terraform:latest %TF_ARGS%
exit /b %errorlevel%

REM ---------------------------------------------------------------------------
REM :tf_apply <cloud> <root>  - init + apply -auto-approve.
REM ---------------------------------------------------------------------------
:tf_apply
echo === Terraform %~2\%~3: init + apply ===
call "%~f0" :tf %~2 %~3 "init -input=false -no-color" >nul || (
	echo terraform init failed for %~2\%~3.
	exit /b 1
)
call "%~f0" :tf %~2 %~3 "apply -auto-approve -input=false -no-color"
if errorlevel 1 (
	echo terraform apply failed for %~2\%~3.
	exit /b 1
)
exit /b 0

REM ---------------------------------------------------------------------------
REM :tf_destroy <cloud> <root>  - destroy (skipped when the root has no state).
REM ---------------------------------------------------------------------------
:tf_destroy
if not exist "%~dp0..\terraform\%~2\%~3\terraform.tfstate" (
	echo No Terraform state in %~2\%~3; nothing to destroy.
	exit /b 0
)
echo === Terraform %~2\%~3: destroy ===
call "%~f0" :tf %~2 %~3 "init -input=false -no-color" >nul
call "%~f0" :tf %~2 %~3 "destroy -auto-approve -input=false -no-color"
exit /b %errorlevel%

REM ---------------------------------------------------------------------------
REM :tf_output <cloud> <root> <output-name> <variable>  - raw output into a variable.
REM ---------------------------------------------------------------------------
:tf_output
set "%~5="
set "TFO_FILE=%TEMP%\cloud-tf-output-%RANDOM%.txt"
call "%~f0" :tf %~2 %~3 "output -raw -no-color %~4" > "%TFO_FILE%" 2>nul
set "TFO_RC=%errorlevel%"
if "%TFO_RC%"=="0" set /p %~5=<"%TFO_FILE%"
del /Q "%TFO_FILE%" >nul 2>&1
if not "%TFO_RC%"=="0" (
	echo Could not read output %~4 from %~2\%~3.
	exit /b 1
)
exit /b 0

REM ---------------------------------------------------------------------------
REM :tf_output_map <cloud> <root> <output-name> <file>
REM   Writes "key url" lines for a map(string) output to <file>.
REM ---------------------------------------------------------------------------
:tf_output_map
set "TFM_JSON=%TEMP%\cloud-tf-map-%RANDOM%.json"
call "%~f0" :tf %~2 %~3 "output -json -no-color %~4" > "%TFM_JSON%" 2>nul
if errorlevel 1 (
	del /Q "%TFM_JSON%" >nul 2>&1
	echo Could not read output %~4 from %~2\%~3.
	exit /b 1
)
powershell -NoProfile -Command "$m = Get-Content '%TFM_JSON%' -Raw | ConvertFrom-Json; $m.PSObject.Properties | ForEach-Object { '{0} {1}' -f $_.Name, $_.Value } | Set-Content -Encoding ascii '%~5'"
set "TFM_RC=%errorlevel%"
del /Q "%TFM_JSON%" >nul 2>&1
exit /b %TFM_RC%

REM ---------------------------------------------------------------------------
REM :verify_apis <cloud> <root>
REM   For each api_base_urls entry: wait for /healthcheck, then (when
REM   CLOUD_TEST_* are set) call /v1/customers/get-all with a Keycloak token
REM   and expect 200 with a non-empty array, and 401 without a token.
REM ---------------------------------------------------------------------------
:verify_apis
set "VA_FILE=%TEMP%\cloud-api-urls-%RANDOM%.txt"
call "%~f0" :tf_output_map %~2 %~3 api_base_urls "%VA_FILE%" || exit /b 1
set "VA_FAILED="
set "CLOUD_TOKEN="
if not defined CLOUD_PROBE (
	echo WARNING: CLOUD_TEST_USER / CLOUD_TEST_PASSWORD are not set; skipping the authenticated data probe.
) else (
	call "%~f0" :get_token || set "VA_FAILED=1"
)
for /f "usebackq tokens=1,2" %%A in ("%VA_FILE%") do call "%~f0" :verify_one %%A %%B || set "VA_FAILED=1"
copy /Y "%VA_FILE%" "%TEMP%\cloud-%~2-api-urls.txt" >nul
del /Q "%VA_FILE%" >nul 2>&1
if defined VA_FAILED (
	echo One or more API checks failed.
	exit /b 1
)
echo All API checks passed.
exit /b 0

:verify_one
set "VO_NAME=%~2"
set "VO_BASE=%~3"
call "%~f0" :wait_for_url "%VO_NAME%" "%VO_BASE%/healthcheck" || exit /b 1
if not defined CLOUD_TOKEN exit /b 0
set "VO_CODE="
for /f "usebackq tokens=*" %%C in (`curl.exe -sk -o nul -w "%%{http_code}" "%VO_BASE%/v1/customers/get-all"`) do set "VO_CODE=%%C"
if not "%VO_CODE%"=="401" (
	echo [%VO_NAME%] Expected 401 without a token, got %VO_CODE%.
	exit /b 1
)
REM The first calls after a DB reload can fail on stale pooled connections, so retry.
set "VO_TRY=0"
:vo_probe
set /a VO_TRY+=1
set "VO_BODY=%TEMP%\cloud-probe-%RANDOM%.json"
set "VO_CODE="
for /f "usebackq tokens=*" %%C in (`curl.exe -sk -o "%VO_BODY%" -w "%%{http_code}" -H "Authorization: Bearer %CLOUD_TOKEN%" "%VO_BASE%/v1/customers/get-all"`) do set "VO_CODE=%%C"
set "VO_ROWS="
for /f "usebackq tokens=*" %%R in (`powershell -NoProfile -Command "try { (Get-Content '%VO_BODY%' -Raw | ConvertFrom-Json).Count } catch { 0 }"`) do set "VO_ROWS=%%R"
del /Q "%VO_BODY%" >nul 2>&1
if not "%VO_CODE%"=="200" if %VO_TRY% LSS 5 (
	ping -n 3 127.0.0.1 >nul
	goto vo_probe
)
if not "%VO_CODE%"=="200" (
	echo [%VO_NAME%] Data probe returned HTTP %VO_CODE%.
	exit /b 1
)
if "%VO_ROWS%"=="0" (
	echo [%VO_NAME%] Data probe returned no rows.
	exit /b 1
)
echo [%VO_NAME%] Data probe OK: %VO_ROWS% customers.
exit /b 0

REM :get_token  - password grant against local-keycloak; the password is read from a temp file.
:get_token
set "GT_PW=%TEMP%\cloud-kc-%RANDOM%.txt"
set "GT_OUT=%TEMP%\cloud-kc-%RANDOM%.json"
<nul set /p "=%CLOUD_TEST_PASSWORD%" > "%GT_PW%"
curl.exe -s -o "%GT_OUT%" -X POST "http://localhost:11141/realms/local-realm/protocol/openid-connect/token" -d grant_type=password -d client_id=local-client --data-urlencode "username=%CLOUD_TEST_USER%" --data-urlencode "password@%GT_PW%"
del /Q "%GT_PW%" >nul 2>&1
for /f "usebackq tokens=*" %%T in (`powershell -NoProfile -Command "try { (Get-Content '%GT_OUT%' -Raw | ConvertFrom-Json).access_token } catch { '' }"`) do set "CLOUD_TOKEN=%%T"
del /Q "%GT_OUT%" >nul 2>&1
if defined CLOUD_TOKEN exit /b 0
echo Could not get a token from local-keycloak for CLOUD_TEST_USER.
exit /b 1

REM ---------------------------------------------------------------------------
REM :open_healthchecks <cloud>  - opens each healthcheck URL in the browser.
REM ---------------------------------------------------------------------------
:open_healthchecks
if not exist "%TEMP%\cloud-%~2-api-urls.txt" exit /b 0
for /f "usebackq tokens=1,2" %%A in ("%TEMP%\cloud-%~2-api-urls.txt") do start "" "%%B/healthcheck"
exit /b 0

REM ---------------------------------------------------------------------------
REM :remove_leftovers <name-prefix> [<name-prefix> ...]
REM   Removes emulator-managed containers whose names start with a prefix.
REM ---------------------------------------------------------------------------
:remove_leftovers
shift
:rl_next
if "%~1"=="" exit /b 0
for /f "usebackq tokens=*" %%C in (`docker ps -a --format "{{.Names}}" --filter "name=^%~1"`) do (
	echo Removing leftover container %%C
	docker rm -f %%C >nul
)
shift
goto rl_next

REM ---------------------------------------------------------------------------
REM :wait_for_url <name> <url>  - up to WFU_TRIES (default 120) x 3 s for HTTP 200.
REM ---------------------------------------------------------------------------
:wait_for_url
echo Waiting for %~2 at %~3 ...
if not defined WFU_TRIES set "WFU_TRIES=120"
for /L %%I in (1,1,%WFU_TRIES%) do (
	curl.exe -sSfk -o nul "%~3" >nul 2>nul && goto wfu_ready
	ping -n 4 127.0.0.1 >nul
)
echo %~2 did not become ready in time.
exit /b 1
:wfu_ready
echo %~2 is ready.
exit /b 0
