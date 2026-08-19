@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - API (DotNet) - Compose-first

pushd "%~dp0"

set "IMAGE_FILE=mcr.microsoft.com/dotnet/aspnet:10.0"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "WORKING_DIR_WIN=C:\Working\Storage\Dev\GitHub\Working"
set "COMPOSE_FILE=%~dp0docker-compose.utility-dotnet.yml"
set "UTILITY_DOTNET_DIR=%~dp0..\..\PilotUtilityApi"
set "DOTNET_MSSQL_PORT=55701"
set "DOTNET_POSTGRES_PORT=55801"

REM Resolve host ports so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port %DOTNET_MSSQL_PORT% DOTNET_MSSQL_PORT
if errorlevel 1 exit /b 1
call :resolve_open_port %DOTNET_POSTGRES_PORT% DOTNET_POSTGRES_PORT
if errorlevel 1 exit /b 1

REM 1. Download the .NET image:
docker pull "%IMAGE_FILE%"

REM 2. Build arg used only for deployment metadata.
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 3. Stop any prior compose services for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans

REM 4. Prepare isolated build contexts.
if exist "%WORKING_DIR_WIN%" rmdir /S /Q "%WORKING_DIR_WIN%"
mkdir "%WORKING_DIR_WIN%"

mkdir "%WORKING_DIR_WIN%\utility-dotnet-publish"
mkdir "%WORKING_DIR_WIN%\utility-dotnet-mssql"
mkdir "%WORKING_DIR_WIN%\utility-dotnet-postgres"

REM 5. Publish the API for Linux runtime.
if not exist "%UTILITY_DOTNET_DIR%\*.sln" if not exist "%UTILITY_DOTNET_DIR%\*.csproj" (
	echo UtilityApiDotNet project path not found: "%UTILITY_DOTNET_DIR%"
	echo Update UTILITY_DOTNET_DIR in this script to your local UtilityApiDotNet repository path.
	exit /b 1
)

pushd "%UTILITY_DOTNET_DIR%"
dotnet publish --configuration Release --os linux --arch x64 --output "%WORKING_DIR_WIN%\utility-dotnet-publish"
if errorlevel 1 (
	echo dotnet publish failed.
	popd
	exit /b 1
)
popd

if not exist "%WORKING_DIR_WIN%\utility-dotnet-publish\PilotUtilityApi.Web.dll" (
	echo Publish output is missing PilotUtilityApi.Web.dll in "%WORKING_DIR_WIN%\utility-dotnet-publish".
	echo Verify the project publishes this assembly or update docker entrypoint accordingly.
	exit /b 1
)

REM 6. Copy published files into each context.
xcopy /E /I /Y "%WORKING_DIR_WIN%\utility-dotnet-publish\*" "%WORKING_DIR_WIN%\utility-dotnet-mssql\" >nul
if errorlevel 1 (
	echo Failed to copy published files to utility-dotnet-mssql build context.
	exit /b 1
)
xcopy /E /I /Y "%WORKING_DIR_WIN%\utility-dotnet-publish\*" "%WORKING_DIR_WIN%\utility-dotnet-postgres\" >nul
if errorlevel 1 (
	echo Failed to copy published files to utility-dotnet-postgres build context.
	exit /b 1
)

REM 7. Copy environment-specific appsettings into each context.
copy /Y "%~dp0..\secrets\appsettings-utility-dotnet-sqlserver.env" "%WORKING_DIR_WIN%\utility-dotnet-mssql\appsettings.Production.json" >nul
copy /Y "%~dp0..\secrets\appsettings-utility-dotnet-postgresql.env" "%WORKING_DIR_WIN%\utility-dotnet-postgres\appsettings.Production.json" >nul

REM 8. Build and start both API containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p utility-api-dotnet up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

popd

REM 9. Launch health checks.
start http://localhost:%DOTNET_MSSQL_PORT%/healthcheck
start http://localhost:%DOTNET_POSTGRES_PORT%/healthcheck

goto :eof

:resolve_open_port
set "RESOLVED_PORT="
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "$start = [int]%~1; $end = [Math]::Min($start + 98, 65535); function Test-Port([int]$port){ $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port); try { $listener.Start(); return $true } catch { return $false } finally { if ($listener.Server -and $listener.Server.IsBound) { $listener.Stop() } } }; foreach ($p in $start..$end) { if (Test-Port $p) { Write-Output $p; exit 0 } }; exit 1"`) do set "RESOLVED_PORT=%%P"

if not defined RESOLVED_PORT (
	goto :no_open_port
)

if not "%RESOLVED_PORT%"=="%~1" (
	echo Port %~1 unavailable. Using %RESOLVED_PORT% instead.
)

set "%~2=%RESOLVED_PORT%"
exit /b 0

:no_open_port
set /a "RANGE_END=%~1+98"
if %RANGE_END% GTR 65535 set "RANGE_END=65535"
echo Unable to find an available host port in the range %~1-%RANGE_END%.
exit /b 1
