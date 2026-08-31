@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Keycloak

set "IMAGE_FILE=quay.io/keycloak/keycloak:latest"
set "KEYCLOAK_PORT=55001"
set "SECRETS_FILE=%~dp0..\secrets\keycloak.env"
set "KEYCLOAK_INTERNAL_URL=http://localhost:8080"
set "REALM_NAME=local-realm"
set "ROLE_NAME=standard-user"
set "CLIENT_ID=local-client"

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

if not defined READER_USERID (
	echo Missing required key READER_USERID in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%READER_USERID%"=="<reader-userid>" (
	echo Replace placeholder READER_USERID in "%SECRETS_FILE%".
	exit /b 1
)

if not defined READER_PASSWORD (
	echo Missing required key READER_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%READER_PASSWORD%"=="<reader-password>" (
	echo Replace placeholder READER_PASSWORD in "%SECRETS_FILE%".
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

if not defined WORKING_ADMIN_USERID (
	echo Missing required key WORKING_ADMIN_USERID in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%WORKING_ADMIN_USERID%"=="<working-admin-userid>" (
	echo Replace placeholder WORKING_ADMIN_USERID in "%SECRETS_FILE%".
	exit /b 1
)

if not defined WORKING_ADMIN_PASSWORD (
	echo Missing required key WORKING_ADMIN_PASSWORD in "%SECRETS_FILE%".
	exit /b 1
)
if /I "%WORKING_ADMIN_PASSWORD%"=="<working-admin-password>" (
	echo Replace placeholder WORKING_ADMIN_PASSWORD in "%SECRETS_FILE%".
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
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh config credentials --server %KEYCLOAK_INTERNAL_URL% --realm master --user %ADMIN_USERID% --password %ADMIN_PASSWORD%
if errorlevel 1 (
	echo Keycloak authenticate failed.
	exit /b 1
)

REM 6. create a realm, if it does not already exist
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get realms/%REALM_NAME% >nul 2>&1
if not errorlevel 1 (
	echo Realm "%REALM_NAME%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=%REALM_NAME% -s enabled=true
	if errorlevel 1 (
		echo Keycloak create realm failed.
		exit /b 1
	)
)

REM 7. create a role, if it does not already exist
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get roles/%ROLE_NAME% -r %REALM_NAME% >nul 2>&1
if not errorlevel 1 (
	echo Role "%ROLE_NAME%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create roles -r %REALM_NAME% -s name=%ROLE_NAME% -s description="Standard user role with basic permissions"
	if errorlevel 1 (
		echo Keycloak create role failed.
		exit /b 1
	)
)

REM 8. Create users inside your specific realm, if not already existing
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get users -r %REALM_NAME% -q username=%READER_USERID% 2>nul | findstr /C:"\"username\" : \"%READER_USERID%\"" >nul
if not errorlevel 1 (
	echo User "%READER_USERID%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create users -r %REALM_NAME% -s username=%READER_USERID% -s enabled=true -s "credentials=[{\"type\":\"password\",\"value\":\"%READER_PASSWORD%\",\"temporary\":false}]" -s email=%READER_USERID%@local.com -s firstName=John -s lastName=Reader
	if errorlevel 1 (
		echo Keycloak create Reader user failed.
		exit /b 1
	)
)

docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get users -r %REALM_NAME% -q username=%WORKING_USERID% 2>nul | findstr /C:"\"username\" : \"%WORKING_USERID%\"" >nul
if not errorlevel 1 (
	echo User "%WORKING_USERID%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create users -r %REALM_NAME% -s username=%WORKING_USERID% -s enabled=true -s "credentials=[{\"type\":\"password\",\"value\":\"%WORKING_PASSWORD%\",\"temporary\":false}]" -s email=%WORKING_USERID%@local.com -s firstName=John -s lastName=Worker
	if errorlevel 1 (
		echo Keycloak create Worker user failed.
		exit /b 1
	)
)

docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get users -r %REALM_NAME% -q username=%WORKING_ADMIN_USERID% 2>nul | findstr /C:"\"username\" : \"%WORKING_ADMIN_USERID%\"" >nul
if not errorlevel 1 (
	echo User "%WORKING_ADMIN_USERID%" already exists, skipping creation.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create users -r %REALM_NAME% -s username=%WORKING_ADMIN_USERID% -s enabled=true -s "credentials=[{\"type\":\"password\",\"value\":\"%WORKING_ADMIN_PASSWORD%\",\"temporary\":false}]" -s email=%WORKING_ADMIN_USERID%@local.com -s firstName=John -s lastName=Adm
	if errorlevel 1 (
		echo Keycloak create Admin user failed.
		exit /b 1
	)
)

REM 9. Assign Role to users, if not already assigned
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get-roles -r %REALM_NAME% --uusername %READER_USERID% 2>nul | findstr /C:"\"name\" : \"%ROLE_NAME%\"" >nul
if not errorlevel 1 (
	echo Role "%ROLE_NAME%" already assigned to "%READER_USERID%", skipping assignment.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh add-roles -r %REALM_NAME% --uusername %READER_USERID% --rolename %ROLE_NAME%
	if errorlevel 1 (
		echo Keycloak add role to Reader failed.
		exit /b 1
	)
)

docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get-roles -r %REALM_NAME% --uusername %WORKING_USERID% 2>nul | findstr /C:"\"name\" : \"%ROLE_NAME%\"" >nul
if not errorlevel 1 (
	echo Role "%ROLE_NAME%" already assigned to "%WORKING_USERID%", skipping assignment.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh add-roles -r %REALM_NAME% --uusername %WORKING_USERID% --rolename %ROLE_NAME%
	if errorlevel 1 (
		echo Keycloak add role to Worker failed.
		exit /b 1
	)
)

docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get-roles -r %REALM_NAME% --uusername %WORKING_ADMIN_USERID% 2>nul | findstr /C:"\"name\" : \"%ROLE_NAME%\"" >nul
if not errorlevel 1 (
	echo Role "%ROLE_NAME%" already assigned to "%WORKING_ADMIN_USERID%", skipping assignment.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh add-roles -r %REALM_NAME% --uusername %WORKING_ADMIN_USERID% --rolename %ROLE_NAME%
	if errorlevel 1 (
		echo Keycloak add role to Admin failed.
		exit /b 1
	)
)

REM 10. Create a client Id, if not already created
docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh get clients -r %REALM_NAME% -q clientId=%CLIENT_ID% 2>nul | findstr /C:"\"clientId\" : \"%CLIENT_ID%\"" >nul
if not errorlevel 1 (
	echo Client ID "%CLIENT_ID%" already created, skipping create.
) else (
	docker exec -i local-keycloak /opt/keycloak/bin/kcadm.sh create clients -r %REALM_NAME% -s clientId=%CLIENT_ID% -s name="Local Client" -s description="Default local application client" -s enabled=true -s publicClient=true
	if errorlevel 1 (
		echo Keycloak add client ID failed.
		exit /b 1
	)
)

REM 11. Launch admin to validate
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
