@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds - API images (cloud-api-<lang>-<db>:1.0)
REM Builds the 6 API images used by every cloud. The images carry NO database or
REM security settings (no appsettings.Production.json, no .env, no DB build args);
REM each cloud injects them as container env vars (see terraform\modules\api-env).

pushd "%~dp0"

set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "CLOUD_WORK=%WORKING_DIR_WIN%\clouds"
set "REPO_DIR=%~dp0.."
set "PILOT_DOTNET_DIR=%~dp0..\..\PilotApiDotNet"
set "PILOT_JAVA_DIR=%~dp0..\..\PilotApiJava"
set "PILOT_PYTHON_DIR=%~dp0..\..\PilotApiPython"
set "SECRETS_FILE=%~dp0..\secrets\clouds-db.env"
set "APP_PORT=8080"

REM 0. Check Docker and load the secrets (used only for the D7 history check).
docker info >nul 2>&1
if errorlevel 1 (
	echo Docker is not running or not available.
	goto failed
)
call :load_env_file "%SECRETS_FILE%" || goto failed

FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 1. Pull base images.
docker pull mcr.microsoft.com/dotnet/aspnet:10.0 || goto failed
docker pull eclipse-temurin:25-jre-alpine || goto failed
docker pull python:3.12-slim || goto failed

REM 2. Prepare isolated build contexts (only the clouds subfolder is wiped).
if exist "%CLOUD_WORK%" rmdir /S /Q "%CLOUD_WORK%"
for %%D in (api-dotnet-publish api-dotnet-mssql api-dotnet-postgres api-java-mssql api-java-postgres api-python-publish api-python-mssql api-python-postgres) do mkdir "%CLOUD_WORK%\%%D"

REM 3. DotNet: test + publish.
if not exist "%PILOT_DOTNET_DIR%\PilotApi.sln" (
	echo PilotApiDotNet project path not found: "%PILOT_DOTNET_DIR%"
	goto failed
)
pushd "%PILOT_DOTNET_DIR%"
dotnet test --configuration Release --verbosity minimal
if errorlevel 1 (
	echo DotNet unit tests failed.
	popd
	goto failed
)
dotnet publish --configuration Release --os linux --arch x64 --output "%CLOUD_WORK%\api-dotnet-publish"
if errorlevel 1 (
	echo dotnet publish failed.
	popd
	goto failed
)
popd
if not exist "%CLOUD_WORK%\api-dotnet-publish\PilotApi.Web.dll" (
	echo Publish output is missing PilotApi.Web.dll.
	goto failed
)
REM Never ship a settings file with secrets (D7).
if exist "%CLOUD_WORK%\api-dotnet-publish\appsettings.Production.json" del /Q "%CLOUD_WORK%\api-dotnet-publish\appsettings.Production.json"
xcopy /E /I /Y /Q "%CLOUD_WORK%\api-dotnet-publish\*" "%CLOUD_WORK%\api-dotnet-mssql\" >nul || goto failed
xcopy /E /I /Y /Q "%CLOUD_WORK%\api-dotnet-publish\*" "%CLOUD_WORK%\api-dotnet-postgres\" >nul || goto failed

REM 4. Java: package.
if not exist "%PILOT_JAVA_DIR%\pom.xml" (
	echo PilotApiJava project path not found: "%PILOT_JAVA_DIR%"
	goto failed
)
pushd "%PILOT_JAVA_DIR%"
call mvn -q clean package
if errorlevel 1 (
	echo Maven build failed.
	popd
	goto failed
)
set "JAR_SOURCE="
for %%F in (target\*.jar) do if not defined JAR_SOURCE set "JAR_SOURCE=%%~fF"
popd
if not defined JAR_SOURCE (
	echo No jar file found in PilotApiJava\target.
	goto failed
)
copy /Y "%JAR_SOURCE%" "%CLOUD_WORK%\api-java-mssql\pilot-api.jar" >nul || goto failed
copy /Y "%JAR_SOURCE%" "%CLOUD_WORK%\api-java-postgres\pilot-api.jar" >nul || goto failed

REM 5. Python: test + wheel.
if not exist "%PILOT_PYTHON_DIR%\pyproject.toml" (
	echo PilotApiPython project path not found: "%PILOT_PYTHON_DIR%"
	goto failed
)
set "PYTHON_EXE=%PILOT_PYTHON_DIR%\.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=python"
pushd "%PILOT_PYTHON_DIR%"
"%PYTHON_EXE%" -m pytest -q
if errorlevel 1 (
	echo Python unit tests failed.
	popd
	goto failed
)
"%PYTHON_EXE%" -m pip wheel . --no-deps --quiet --wheel-dir "%CLOUD_WORK%\api-python-publish"
if errorlevel 1 (
	echo Python wheel build failed.
	popd
	goto failed
)
popd
set "WHEEL_SOURCE="
for %%F in ("%CLOUD_WORK%\api-python-publish\*.whl") do set "WHEEL_SOURCE=%%~fF"
if not defined WHEEL_SOURCE (
	echo No wheel file was produced.
	goto failed
)
copy /Y "%WHEEL_SOURCE%" "%CLOUD_WORK%\api-python-mssql\" >nul || goto failed
copy /Y "%WHEEL_SOURCE%" "%CLOUD_WORK%\api-python-postgres\" >nul || goto failed

REM 6. Build the images. Only DEPLOY_DATE and the port are passed as build args (D7).
call :build cloud-api-dotnet-mssql    "%REPO_DIR%\Api_dotnet\dockerfile_mssql"    api-dotnet-mssql    APP_PORT || goto failed
call :build cloud-api-dotnet-postgres "%REPO_DIR%\Api_dotnet\dockerfile_postgres" api-dotnet-postgres APP_PORT || goto failed
call :build cloud-api-java-mssql      "%REPO_DIR%\Api_java\dockerfile_mssql"      api-java-mssql      SERVER_PORT || goto failed
call :build cloud-api-java-postgres   "%REPO_DIR%\Api_java\dockerfile_postgres"   api-java-postgres   SERVER_PORT || goto failed
call :build cloud-api-python-mssql    "%REPO_DIR%\Api_python\dockerfile_mssql"    api-python-mssql    APP_PORT || goto failed
call :build cloud-api-python-postgres "%REPO_DIR%\Api_python\dockerfile_postgres" api-python-postgres APP_PORT || goto failed

REM 7. D7 checks: no baked DB settings or secrets in any image.
set "D7_FAILED="
for /f "usebackq tokens=*" %%N in (`powershell -NoProfile -Command "(Get-Content '%~dp0terraform\apis.json' -Raw | ConvertFrom-Json).name"`) do call :d7_check %%N
if defined D7_FAILED (
	echo D7 checks FAILED.
	goto failed
)
echo D7 checks passed for all images.

popd
echo Cloud API images built.
goto :eof

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :build <image-name> <dockerfile> <context-subfolder> <port-arg-name>
REM ---------------------------------------------------------------------------
:build
echo Building %~1:1.0 ...
docker build -q -f "%~2" -t "%~1:1.0" --build-arg "DEPLOY_DATE=%CURRENT_DATE%" --build-arg "%~4=%APP_PORT%" "%CLOUD_WORK%\%~3"
if errorlevel 1 (
	echo docker build failed for %~1.
	exit /b 1
)
exit /b 0

REM ---------------------------------------------------------------------------
REM :d7_check <image-name>
REM ---------------------------------------------------------------------------
:d7_check
set "IMG=%~1:1.0"
docker image inspect "%IMG%" >nul 2>&1
if errorlevel 1 (
	echo [D7] %IMG%: image missing.
	set "D7_FAILED=1"
	exit /b 0
)
docker image inspect --format "{{range .Config.Env}}{{println .}}{{end}}" "%IMG%" | findstr /R /C:"^DB_PASSWORD=." /C:"^DB_URL=." >nul
if not errorlevel 1 (
	echo [D7] %IMG%: DB_PASSWORD or DB_URL has a value in the image env.
	set "D7_FAILED=1"
)
if defined CLOUD_DB_DEVUSER_PASSWORD (
	docker history --no-trunc "%IMG%" | findstr /C:"%CLOUD_DB_DEVUSER_PASSWORD%" >nul
	if not errorlevel 1 (
		echo [D7] %IMG%: image history contains the DevUser password.
		set "D7_FAILED=1"
	)
)
docker run --rm --entrypoint sh "%IMG%" -c "ls -a /app" | findstr /X /C:"appsettings.Production.json" /C:".env" >nul
if not errorlevel 1 (
	echo [D7] %IMG%: appsettings.Production.json or .env found in /app.
	set "D7_FAILED=1"
)
echo [D7] %IMG%: checked.
exit /b 0

:load_env_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from "..\secrets\clouds-db.env.example".
	exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%A in (`type "%~1" ^| findstr /R /V /C:"^[ ]*#" /C:"^[ ]*$"`) do set "%%A=%%B"
exit /b 0
