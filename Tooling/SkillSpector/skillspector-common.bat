@echo off
REM SkillSpector - shared subroutines for the Tooling\SkillSpector\*.bat helpers.
REM Usage: call "%~dp0skillspector-common.bat" :<routine> [args]
REM No setlocal here on purpose: the routines set variables for the caller.
goto %~1

REM ---------------------------------------------------------------------------
REM :init  - sets the shared names and paths (keep in line with the builder).
REM ---------------------------------------------------------------------------
:init
set "CONTAINER_NAME=local-skillspector"
set "IMAGE_NAME=local-skillspector:latest"
REM SCAN_ROOT = the folder that holds this repository and its sibling repositories.
for %%I in ("%~dp0..\..\..") do set "SCAN_ROOT=%%~fI"
set "REPORTS_DIR=%SCAN_ROOT%\Working\skillspector-reports"
set "BUILDER=%~dp0..\Docker-SkillSpector-builder.bat"
set "SECRETS_FILE=%~dp0..\..\secrets\skillspector.env"
exit /b 0

REM ---------------------------------------------------------------------------
REM :ensure_running  - starts the container if stopped; fails if it does not exist.
REM ---------------------------------------------------------------------------
:ensure_running
set "SS_STATE="
for /f "usebackq delims=" %%S in (`docker inspect -f "{{.State.Running}}" %CONTAINER_NAME% 2^>nul`) do set "SS_STATE=%%S"
if not defined SS_STATE (
	echo Container %CONTAINER_NAME% does not exist. Run "Tooling\Docker-SkillSpector-builder.bat" first.
	exit /b 1
)
if /I "%SS_STATE%"=="true" exit /b 0
echo Starting %CONTAINER_NAME% ...
docker start %CONTAINER_NAME% >nul || exit /b 1
exit /b 0

REM ---------------------------------------------------------------------------
REM :llm_flag  - sets SS_LLM_FLAG=--no-llm when the container has no LLM provider.
REM ---------------------------------------------------------------------------
:llm_flag
set "SS_LLM_FLAG=--no-llm"
for /f "usebackq delims=" %%P in (`docker exec %CONTAINER_NAME% printenv SKILLSPECTOR_PROVIDER 2^>nul`) do set "SS_LLM_FLAG="
exit /b 0

REM ---------------------------------------------------------------------------
REM :resolve_target <path-or-url>   (args start at %%2: %%1 is the label)
REM   Sets SS_TARGET (the scan argument) and SS_MODE:
REM     exec   - path is under SCAN_ROOT (or a URL); scan in the running container.
REM     adhoc  - path is outside SCAN_ROOT; scan in a throwaway container that
REM              mounts the path's parent folder at /adhoc. SS_ADHOC_DIR is set.
REM ---------------------------------------------------------------------------
:resolve_target
set "SS_TARGET="
set "SS_MODE=exec"
set "SS_ADHOC_DIR="
set "SS_INPUT=%~2"
if "%SS_INPUT%"=="" (
	echo No skill path given.
	exit /b 1
)
REM Git URLs and other remote sources are passed through unchanged.
echo(%SS_INPUT%| findstr /I /R /C:"^https*://" /C:"^git@" >nul
if not errorlevel 1 (
	set "SS_TARGET=%SS_INPUT%"
	exit /b 0
)
if not exist "%SS_INPUT%" (
	echo Path not found: "%SS_INPUT%"
	exit /b 1
)
for %%F in ("%SS_INPUT%") do set "SS_FULL=%%~fF"
if "%SS_FULL:~-1%"=="\" set "SS_FULL=%SS_FULL:~0,-1%"
setlocal EnableDelayedExpansion
set "SS_REL=!SS_FULL:%SCAN_ROOT%\=!"
set "SS_CHECK=%SCAN_ROOT%\!SS_REL!"
if /I "!SS_CHECK!"=="!SS_FULL!" if /I not "!SS_REL!"=="!SS_FULL!" (
	set "SS_REL=!SS_REL:\=/!"
	for /f "delims=" %%T in ("/scan/!SS_REL!") do endlocal & set "SS_TARGET=%%T"
	exit /b 0
)
endlocal
REM Outside SCAN_ROOT: mount the parent folder for a one-off scan.
for %%F in ("%SS_FULL%") do (
	set "SS_PARENT=%%~dpF"
	set "SS_NAME=%%~nxF"
)
set "SS_ADHOC_DIR=%SS_PARENT:~0,-1%"
if "%SS_ADHOC_DIR:~-1%"==":" set "SS_ADHOC_DIR=%SS_ADHOC_DIR%\"
set "SS_TARGET=/adhoc/%SS_NAME%"
set "SS_MODE=adhoc"
exit /b 0

REM ---------------------------------------------------------------------------
REM :run <skillspector-args...>  - runs SkillSpector for the resolved target mode.
REM ---------------------------------------------------------------------------
:run
shift
set "SS_ARGS="
:run_args
if "%~1"=="" goto run_exec
set SS_ARGS=%SS_ARGS% %1
shift
goto run_args
:run_exec
if /I "%SS_MODE%"=="adhoc" goto run_adhoc
docker exec %CONTAINER_NAME% skillspector%SS_ARGS%
exit /b %ERRORLEVEL%
:run_adhoc
set "SS_ENV_ARG="
for /f "usebackq delims=" %%E in (`docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" %CONTAINER_NAME% ^| findstr /B "SKILLSPECTOR_PROVIDER="`) do set "SS_ENV_ARG=--env-file "%SECRETS_FILE%""
docker run --rm -v "%SS_ADHOC_DIR%:/adhoc:ro" -v "%REPORTS_DIR%:/reports" %SS_ENV_ARG% %IMAGE_NAME%%SS_ARGS%
exit /b %ERRORLEVEL%
