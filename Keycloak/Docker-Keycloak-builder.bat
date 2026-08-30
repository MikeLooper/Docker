@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Keycloak

set "IMAGE_FILE=quay.io/keycloak/keycloak:latest"
set "KEYCLOAK_PORT=55001"
set "SECRETS_FILE=%~dp0..\secrets\keycloak.env"

REM Load runtime secrets from file.
call :load_env_file "%SECRETS_FILE%"
if errorlevel 1 exit /b 1

if not defined ADMIN_USERID (
	echo Missing required key ADMIN_USERID in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%ADMIN_USERID%"=="<admin-userid>" (
	echo Replace placeholder ADMIN_USERID in "%SECRETS_FILE%".
	exit /b 1
)

if not defined ADMIN_PASSWORD (
	echo Missing required key ADMIN_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%ADMIN_PASSWORD%"=="<admin-password>" (
	echo Replace placeholder ADMIN_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)

if not defined WORKING_USERID (
	echo Missing required key WORKING_USERID in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%WORKING_USERID%"=="<working-userid>" (
	echo Replace placeholder WORKING_USERID in "%SECRETS_FILE%".
	exit /b 1
)

if not defined WORKING_PASSWORD (
	echo Missing required key WORKING_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%WORKING_PASSWORD%"=="<working-password>" (
	echo Replace placeholder WORKING_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)

pushd "%~dp0"

REM 1. Remove a previously existing partition, if any is present:
docker rm -f local-keycloak

REM 2. Download the image:
docker pull "%IMAGE_FILE%"

REM 3. Build and start the Keycloak container.
docker run -d --name local-keycloak -m 1g -p %KEYCLOAK_PORT%:8080 --restart=always -v keycloak_data:/opt/keycloak/data -e KC_BOOTSTRAP_ADMIN_USERNAME=%ADMIN_USERID% -e KC_BOOTSTRAP_ADMIN_PASSWORD=%ADMIN_PASSWORD% %IMAGE_FILE% start-dev
if errorlevel 1 (
	echo docker run failed.
	exit /b 1
)

popd

REM 4. Wait for Keycloak to finish starting before using the CLI.
call :wait_for_keycloak
if errorlevel 1 exit /b 1

REM 5. Authenticate the CLI tool using your master admin credentials
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user %ADMIN_USERID% --password %ADMIN_PASSWORD%
if errorlevel 1 (
	echo Keycloak authenticate failed.
	exit /b 1
)

REM 6. create a realm, if it does not already exist
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get realms/local-realm >nul 2>&1
if not errorlevel 1 (
	echo Realm "local-realm" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=local-realm -s enabled=true
	if errorlevel 1 (
		echo Keycloak create realm failed.
		exit /b 1
	)
)

REM 7. create a role, if it does not already exist
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get roles/standard-user -r local-realm >nul 2>&1
if not errorlevel 1 (
	echo Role "standard-user" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create roles -r local-realm -s name=standard-user -s description="Standard user role with basic permissions"
	if errorlevel 1 (
		echo Keycloak create role failed.
		exit /b 1
	)
)

REM 8. Create the user inside your specific realm, if it does not already exist
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get users -r local-realm -q username=%WORKING_USERID% 2>nul | findstr /C:"\"username\" : \"%WORKING_USERID%\"" >nul
if not errorlevel 1 (
	echo User "%WORKING_USERID%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create users -r local-realm -s username=%WORKING_USERID% -s enabled=true -s "credentials=[{\"type\":\"password\",\"value\":\"%WORKING_PASSWORD%\",\"temporary\":false}]" -s email=%WORKING_USERID%@local.com -s firstName=John -s lastName=Doe
	if errorlevel 1 (
		echo Keycloak create user failed.
		exit /b 1
	)
)

REM 9. Assign Role to user, if not already assigned
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get-roles -r local-realm --uusername %WORKING_USERID% 2>nul | findstr /C:"\"name\" : \"standard-user\"" >nul
if not errorlevel 1 (
	echo Role "standard-user" already assigned to "%WORKING_USERID%", skipping assignment.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh add-roles -r local-realm --uusername %WORKING_USERID% --rolename standard-user
	if errorlevel 1 (
		echo Keycloak add role failed.
		exit /b 1
	)
)

REM 10. Launch admin to validate
start http://localhost:%KEYCLOAK_PORT%/admin

goto :eof

:wait_for_keycloak
ECHO .
ECHO Waiting for Keycloak to start...
setlocal
set "RETRY_COUNT=0"
set "MAX_RETRIES=120"
:wait_for_keycloak_loop
docker logs local-keycloak 2>&1 | findstr /C:"started in" >nul
if not errorlevel 1 (
	endlocal
	exit /b 0
)
set /a RETRY_COUNT+=1
if %RETRY_COUNT% GEQ %MAX_RETRIES% (
	echo Timed out waiting for Keycloak to start.
	endlocal
	exit /b 1
)
timeout /t 2 /nobreak >nul
goto :wait_for_keycloak_loop

:load_env_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from "..\secrets\keycloak.env.example".
	exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`type "%~1" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
exit /b 0
