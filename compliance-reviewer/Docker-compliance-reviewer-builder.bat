@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Compliance Reviewer (skills, API and Web UI) - Compose-first
REM
REM Deploys ..\AIAssistants\compliance-reviewer_any-ai (reviewer skills and scripts, testers and sample apps,
REM comp-review-api and comp-review-ui) to the container "local-compliance-reviewer" as a testing
REM environment (Environment = development).
REM
REM Usage: compliance-reviewer\Docker-compliance-reviewer-builder.bat [-skiptests]
REM   -skiptests  Skip the API (pytest) and Web UI (Vitest) unit tests during the image build.

pushd "%~dp0"

set "RUN_TESTS=true"
:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="-skiptests" (
	set "RUN_TESTS=false"
	shift
	goto :parse_args
)
echo Unknown option: %~1
echo Usage: %~nx0 [-skiptests]
popd
exit /b 1
:args_done

REM GitHub root = the folder that holds this repository and its sibling repositories.
for %%I in ("%~dp0..\..") do set "GITHUB_ROOT=%%~fI"
set "WORKING_DIR_WIN=%GITHUB_ROOT%\Working"
set "SOURCE_DIR=%GITHUB_ROOT%\AIAssistants\compliance-reviewer_any-ai"
set "STACK_DIR_WIN=%WORKING_DIR_WIN%\compliance-reviewer"
set "BUILD_CONTEXT_WIN=%STACK_DIR_WIN%\build"
set "COMPOSE_FILE=%~dp0docker-compose.compliance-reviewer.yml"
set "COMPOSE_PROJECT=compliance-reviewer"
set "CONTAINER_NAME=local-compliance-reviewer"
set "SECRETS_FILE=%~dp0..\secrets\compliance-reviewer.env"
set "CR_API_PORT=12001"
set "CR_UI_PORT=12101"

REM Forward-slash paths for Compose.
set "CR_BUILD_CONTEXT=%BUILD_CONTEXT_WIN:\=/%"
set "CR_DATA_DIR=%STACK_DIR_WIN:\=/%"
set "CR_RUN_TESTS=%RUN_TESTS%"

REM 0. Prerequisites.
where docker >nul 2>&1 || (echo Docker was not found on PATH. & popd & exit /b 1)
docker info >nul 2>&1 || (echo Docker is not running. Start Docker Desktop and retry. & popd & exit /b 1)

if not exist "%SOURCE_DIR%\api\run.py" (
	echo Compliance Reviewer source not found: "%SOURCE_DIR%"
	echo Clone the AIAssistants repository into "%GITHUB_ROOT%".
	popd
	exit /b 1
)

call :require_secrets_file "%SECRETS_FILE%"
if errorlevel 1 (popd & exit /b 1)

REM 1. Shared network (if not already existing).
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net
if errorlevel 1 (
	echo Unable to create the pilot-net network.
	popd
	exit /b 1
)

REM 2. Build arg used only for deployment metadata.
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 3. Stop any prior compose services and containers for this stack (frees their ports before probing).
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% down --remove-orphans
docker rm -f %CONTAINER_NAME% >nul 2>&1

REM 4. Resolve the host ports so Windows reserved/in-use ports do not break compose startup.
call :resolve_open_port %CR_API_PORT% CR_API_PORT
if errorlevel 1 (popd & exit /b 1)
call :resolve_open_port %CR_UI_PORT% CR_UI_PORT
if errorlevel 1 (popd & exit /b 1)
if "%CR_API_PORT%"=="%CR_UI_PORT%" (
	echo The API and Web UI resolved to the same port %CR_API_PORT%. Free port 12001 or 12101 and retry.
	popd
	exit /b 1
)
echo API port=%CR_API_PORT%  Web UI port=%CR_UI_PORT%

REM 5. Prepare an isolated build context: a copy of the reviewer workspace without build output,
REM    dependencies, run output or caches, plus this folder's Docker files.
if exist "%BUILD_CONTEXT_WIN%" rmdir /S /Q "%BUILD_CONTEXT_WIN%"
mkdir "%BUILD_CONTEXT_WIN%\docker"
robocopy "%SOURCE_DIR%" "%BUILD_CONTEXT_WIN%\reviewer" /E /NFL /NDL /NJH /NJS /NP ^
	/XD .git .vscode node_modules .angular dist coverage .venv __pycache__ .pytest_cache htmlcov bin obj target .build-output results transitions reports ^
	/XF *.pyc .coverage *.log
if errorlevel 8 (
	echo Copying the Compliance Reviewer source failed.
	popd
	exit /b 1
)
for %%F in (dockerfile entrypoint.sh spa_server.py) do (
	copy /Y "%~dp0%%F" "%BUILD_CONTEXT_WIN%\docker\" >nul
	if errorlevel 1 (
		echo Failed to copy %%F to the build context.
		popd
		exit /b 1
	)
)

REM 6. Host folders for reports, transition files and tester results (kept across rebuilds).
for %%D in (reports transitions test-results) do if not exist "%STACK_DIR_WIN%\%%D" mkdir "%STACK_DIR_WIN%\%%D"

REM 7. Build (runs the API and Web UI unit tests unless -skiptests) and start the container with Compose.
if /I "%RUN_TESTS%"=="false" echo Unit tests are skipped for this build.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% build --pull
if errorlevel 1 (
	echo Image build failed. If a unit test failed, its output is shown above.
	popd
	exit /b 1
)
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% up -d --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	popd
	exit /b 1
)

REM 8. Remove older, now untagged images of this stack.
docker image prune -f --filter "label=local.stack=compliance-reviewer" >nul 2>&1

REM 9. Wait for the API, then open its About endpoint and the Web UI.
echo Waiting for the API on port %CR_API_PORT% ...
powershell -NoProfile -Command "$u='http://localhost:%CR_API_PORT%/api/health'; for ($i=0; $i -lt 60; $i++) { try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 $u; Write-Output ('API health: ' + ($r.Content | ConvertFrom-Json).status); exit 0 } catch { Start-Sleep -Seconds 2 } }; exit 1"
if errorlevel 1 (
	echo The API did not answer within 2 minutes. Check the logs: docker logs %CONTAINER_NAME%
	popd
	exit /b 1
)

popd

echo.
echo Compliance Reviewer is running in "%CONTAINER_NAME%":
echo   API About:  http://localhost:%CR_API_PORT%/api/about
echo   API docs:   http://localhost:%CR_API_PORT%/swagger
echo   Web UI:     http://localhost:%CR_UI_PORT%/
echo   Host data:  %STACK_DIR_WIN%\{reports,transitions,test-results}

start "" http://localhost:%CR_API_PORT%/swagger
start "" http://localhost:%CR_UI_PORT%/

goto :eof

:require_secrets_file
if not exist "%~1" (
	echo Missing secrets file: "%~1"
	echo Create it from the matching ".example" template in the secrets folder.
	exit /b 1
)

set "HAS_CREDENTIAL="
for %%K in (ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN) do (
	findstr /R /B /C:"%%K=[^< ]" "%~1" >nul && set "HAS_CREDENTIAL=1"
)
if not defined HAS_CREDENTIAL (
	echo No AI tool credential is set in "%~1".
	echo Uncomment ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN or COPILOT_GITHUB_TOKEN and replace its placeholder value.
	exit /b 1
)
exit /b 0

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
