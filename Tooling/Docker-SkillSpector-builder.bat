@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - SkillSpector (NVIDIA security scanner for AI agent skills)
REM Source: https://github.com/NVIDIA/SkillSpector
REM
REM Builds the SkillSpector image from source and creates the long-running
REM container "local-skillspector". Scans are run inside it with docker exec
REM (see Tooling\SkillSpector\*.bat).
REM
REM Usage: Tooling\Docker-SkillSpector-builder.bat [git-ref]
REM   git-ref  Optional tag or branch to build (default below).

set "SKILLSPECTOR_REPO=https://github.com/NVIDIA/SkillSpector.git"
set "SKILLSPECTOR_REF=v2.13.4"
if not "%~1"=="" set "SKILLSPECTOR_REF=%~1"

set "CONTAINER_NAME=local-skillspector"
set "IMAGE_NAME=local-skillspector"
set "IMAGE_LABEL=local.tool=skillspector"
REM GitHub root = the folder that holds this repository and its sibling repositories.
for %%I in ("%~dp0..\..") do set "GITHUB_ROOT=%%~fI"
set "WORKING_DIR_WIN=%GITHUB_ROOT%\Working"
set "SOURCE_DIR=%WORKING_DIR_WIN%\skillspector-src"
set "REPORTS_DIR=%WORKING_DIR_WIN%\skillspector-reports"
REM Host folder mounted read-only at /scan; skills under it can be scanned by path.
set "SCAN_ROOT=%GITHUB_ROOT%"
set "SECRETS_FILE=%~dp0..\secrets\skillspector.env"

REM 0. Prerequisites.
where docker >nul 2>&1 || (echo Docker was not found on PATH. & exit /b 1)
where git >nul 2>&1 || (echo Git was not found on PATH. & exit /b 1)
docker info >nul 2>&1 || (echo Docker is not running. Start Docker Desktop and retry. & exit /b 1)

REM 1. Remove a previously existing container, if any is present.
docker rm -f %CONTAINER_NAME% >nul 2>&1

REM 2. Fetch the source (shallow clone of the selected ref) into a clean folder.
if not exist "%WORKING_DIR_WIN%" mkdir "%WORKING_DIR_WIN%"
if exist "%SOURCE_DIR%" rmdir /S /Q "%SOURCE_DIR%"
echo Cloning SkillSpector %SKILLSPECTOR_REF% ...
git clone --depth 1 --branch "%SKILLSPECTOR_REF%" "%SKILLSPECTOR_REPO%" "%SOURCE_DIR%"
if errorlevel 1 (
	echo git clone failed for ref "%SKILLSPECTOR_REF%".
	exit /b 1
)

REM 3. Build the image with the repository's own Dockerfile.
echo Building image %IMAGE_NAME% ...
docker build --label %IMAGE_LABEL% -t %IMAGE_NAME%:%SKILLSPECTOR_REF:/=-% -t %IMAGE_NAME%:latest "%SOURCE_DIR%"
set "BUILD_RC=%ERRORLEVEL%"

REM 4. Cleanup: the source clone is only needed for the build.
if exist "%SOURCE_DIR%" rmdir /S /Q "%SOURCE_DIR%"
if not "%BUILD_RC%"=="0" (
	echo docker build failed.
	exit /b 1
)
REM Remove older SkillSpector images left untagged by this rebuild (only images with this label).
docker image prune -f --filter "label=%IMAGE_LABEL%" >nul

REM 5. LLM settings are optional. Without them, scans run static-only (--no-llm).
set "ENV_FILE_ARG="
if exist "%SECRETS_FILE%" (
	findstr /C:"<anthropic-api-key>" "%SECRETS_FILE%" >nul 2>&1
	if errorlevel 1 (
		set "ENV_FILE_ARG=--env-file "%SECRETS_FILE%""
		echo Using LLM settings from "%SECRETS_FILE%".
	) else (
		echo "%SECRETS_FILE%" still has a placeholder; scans will be static-only.
	)
) else (
	echo No "%SECRETS_FILE%" found; scans will be static-only.
	echo To enable LLM analysis, create it from "secrets\skillspector.env.example" and rerun this builder.
)

REM 6. Create the container. The image entrypoint is the one-shot CLI, so the container
REM    is kept alive with "sleep infinity" and scans run through docker exec.
if not exist "%REPORTS_DIR%" mkdir "%REPORTS_DIR%"
docker run -d --name %CONTAINER_NAME% -m 1g ^
	--entrypoint sleep ^
	-v "%SCAN_ROOT%:/scan:ro" ^
	-v "%REPORTS_DIR%:/reports" ^
	%ENV_FILE_ARG% ^
	%IMAGE_NAME%:latest infinity
if errorlevel 1 (
	echo docker run failed for %CONTAINER_NAME%.
	exit /b 1
)

REM 7. Health check.
docker exec %CONTAINER_NAME% skillspector --version
if errorlevel 1 (
	echo SkillSpector did not respond inside %CONTAINER_NAME%.
	exit /b 1
)

echo.
echo SkillSpector is ready in container %CONTAINER_NAME%.
echo   Scan a skill:   Tooling\SkillSpector\SkillSpector-scan.bat ^<path-to-skill^>
echo   Write reports:  Tooling\SkillSpector\SkillSpector-report.bat ^<path-to-skill^>
echo   Reports folder: %REPORTS_DIR%
exit /b 0
