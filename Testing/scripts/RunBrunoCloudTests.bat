@echo off
rem ===========================================================================
rem  scripts\RunBrunoCloudTests.bat
rem
rem  Shared code for RunBrunoCloudTests-aws.bat, RunBrunoCloudTests-azure.bat
rem  and RunBrunoCloudTests-gcp.bat. Runs the Bruno test collections of the
rem  Pilot APIs (DotNet, Java, Python) against the six APIs deployed in one
rem  cloud emulator, and writes a combined HTML report (plus per-run
rem  HTML/JSON/JUnit reports).
rem
rem  Steps:
rem    1. Start the cloud emulator: Clouds\Docker-clouds-<cloud>-start.bat
rem       (this checks every API and, unless -norebuild, re-runs the cloud's
rem       dbapi builder when one does not answer).
rem    2. Run the collections against the emulator, in this order:
rem         <Cloud> - SQL Server  (cloud-api-<lang>-mssql)
rem         <Cloud> - PostgreSQL  (cloud-api-<lang>-postgres)
rem    3. Stop the cloud emulator: Clouds\Docker-clouds-<cloud>-stop.bat
rem       (always, also when step 1 or 2 failed).
rem
rem  Usage:
rem    call scripts\RunBrunoCloudTests.bat <cloud> [<Collection>] [-norebuild]
rem      <cloud>       aws | azure | gcp
rem      <Collection>  PilotApiDotNet | PilotApiJava | PilotApiPython
rem                    (default: all three)
rem      -norebuild    passed to the start script: report unhealthy APIs
rem                    instead of re-running the dbapi builder
rem
rem  The API base URLs change when an API is redeployed (AWS API ids, Azure
rem  environment hash, GCP Cloud Run token), so they are read from the
rem  Terraform state (Clouds\terraform\<cloud>\20-apis\terraform.tfstate,
rem  output api_base_urls) and passed to Bruno with --env-var Host=<url>/.
rem  The Host values in the collections' "<Cloud> - ..." environment files are
rem  only the last known URLs, for use in the Bruno app.
rem
rem  The summary report is built by the #==POWERSHELL==# block of
rem  ..\RunBrunoTests.bat (read, not changed), so both scripts produce the
rem  same report layout.
rem
rem  Requires Node.js. Uses the Bruno CLI ("bru") if installed globally,
rem  otherwise runs it through npx (@usebruno/cli).
rem  Secrets (IDP_HOST_PASSWORD) are read by Bruno from the .env file in each
rem  collection folder. The cloud APIs use the same local-keycloak as the
rem  Docker APIs, so no other secret is needed.
rem ===========================================================================
setlocal EnableExtensions DisableDelayedExpansion

set "CLOUD=%~1"
set "CLOUD_LABEL="
if /i "%CLOUD%"=="aws"   set "CLOUD_LABEL=AWS"
if /i "%CLOUD%"=="azure" set "CLOUD_LABEL=Azure"
if /i "%CLOUD%"=="gcp"   set "CLOUD_LABEL=GCP"
if not defined CLOUD_LABEL (
    echo ERROR: Unknown cloud "%CLOUD%". Use aws, azure or gcp.
    exit /b 2
)

rem Resolved before the argument loop: "shift" also shifts %0.
for %%I in ("%~dp0..") do set "TESTING_DIR=%%~fI"
for %%I in ("%TESTING_DIR%\..") do set "DOCKER_ROOT=%%~fI"
for %%I in ("%DOCKER_ROOT%\..") do set "GITHUB_ROOT=%%~fI"

set "FILTER_NAME="
set "START_OPT="
:ParseArgs
shift
if "%~1"=="" goto ArgsDone
if /i "%~1"=="-norebuild" (
    set "START_OPT=-norebuild"
) else if /i "%~1"=="PilotApiDotNet" (
    set "FILTER_NAME=%~1"
) else if /i "%~1"=="PilotApiJava" (
    set "FILTER_NAME=%~1"
) else if /i "%~1"=="PilotApiPython" (
    set "FILTER_NAME=%~1"
) else (
    echo ERROR: Unknown argument "%~1". Use PilotApiDotNet, PilotApiJava, PilotApiPython or -norebuild.
    exit /b 2
)
goto ParseArgs
:ArgsDone

set "CLOUDS_DIR=%DOCKER_ROOT%\Clouds"
set "STATE_FILE=%CLOUDS_DIR%\terraform\%CLOUD%\20-apis\terraform.tfstate"
set "SUMMARY_SCRIPT=%TESTING_DIR%\RunBrunoTests.bat"
set "WRAPPER=RunBrunoCloudTests-%CLOUD%.bat"

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"`) do set "STAMP=%%T"
set "REPORT_DIR=%TESTING_DIR%\BrunoReports\%STAMP%_%CLOUD%"
set "MANIFEST=%REPORT_DIR%\runs.txt"
set "URL_FILE=%REPORT_DIR%\api-urls.txt"
mkdir "%REPORT_DIR%" >nul 2>&1

where bru >nul 2>&1
if %ERRORLEVEL%==0 (
    set "BRU_CMD=bru"
) else (
    where npx >nul 2>&1 || (
        echo ERROR: Neither "bru" nor "npx" was found. Install Node.js, then run: npm install -g @usebruno/cli
        exit /b 2
    )
    set "BRU_CMD=npx --yes @usebruno/cli"
)

echo Cloud         : %CLOUD_LABEL%
echo Report folder : %REPORT_DIR%
if defined FILTER_NAME echo Collection    : %FILTER_NAME%
echo.

set "OVERALL=0"
set "RUN_COUNT=0"
set "CLOUD_ERROR="

rem ---------------------------------------------------------------------------
rem  1. Start the cloud emulator.
rem ---------------------------------------------------------------------------
echo ###########################################################################
echo  Step 1: start the %CLOUD_LABEL% emulator
echo ###########################################################################
call "%CLOUDS_DIR%\Docker-clouds-%CLOUD%-start.bat" %START_OPT%
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo ERROR: Docker-clouds-%CLOUD%-start.bat failed ^(exit code %RC%^). The tests are skipped.
    set "CLOUD_ERROR=CLOUD_START_FAILED"
) else (
    call :ReadApiUrls
)

rem ---------------------------------------------------------------------------
rem  2. Run the collections against the emulator.
rem ---------------------------------------------------------------------------
echo ###########################################################################
echo  Step 2: run the Bruno collections against %CLOUD_LABEL%
echo ###########################################################################
call :RunEnvironment "mssql"    "SQL Server" "SqlServer"
call :RunEnvironment "postgres" "PostgreSQL" "PostgreSQL"

rem ---------------------------------------------------------------------------
rem  3. Stop the cloud emulator.
rem ---------------------------------------------------------------------------
echo ###########################################################################
echo  Step 3: stop the %CLOUD_LABEL% emulator
echo ###########################################################################
call "%CLOUDS_DIR%\Docker-clouds-%CLOUD%-stop.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: Docker-clouds-%CLOUD%-stop.bat failed ^(exit code %RC%^). Stop the emulator by hand.
    set "OVERALL=1"
)

if "%RUN_COUNT%"=="0" (
    echo ERROR: No collections matched the requested filter.
    set "OVERALL=1"
)

echo.
echo Building summary report...
if not exist "%SUMMARY_SCRIPT%" (
    echo ERROR: %SUMMARY_SCRIPT% was not found; it holds the summary report builder.
    set "OVERALL=1"
    goto Result
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath '%SUMMARY_SCRIPT%' -Raw; $s = $s.Substring($s.LastIndexOf('#==POWERSHELL==#')); & ([scriptblock]::Create($s)) -ReportDir '%REPORT_DIR%'; $f = Join-Path '%REPORT_DIR%' 'Summary.html'; if (Test-Path -LiteralPath $f) { $h = (Get-Content -LiteralPath $f -Raw).Replace('<title>Bruno Test Summary</title>', '<title>Bruno Test Summary - %CLOUD_LABEL%</title>').Replace('Docker Applications &middot; Automated API Tests', '%CLOUD_LABEL% Cloud Emulator &middot; Automated API Tests').Replace('Generated by RunBrunoTests.bat', 'Generated by %WRAPPER%'); Set-Content -LiteralPath $f -Value $h -Encoding UTF8 }"

echo.
echo Summary report: %REPORT_DIR%\Summary.html
if exist "%REPORT_DIR%\Summary.html" start "" "%REPORT_DIR%\Summary.html"

:Result
if "%OVERALL%"=="0" (echo RESULT: ALL COLLECTIONS PASSED) else (echo RESULT: ONE OR MORE COLLECTIONS FAILED)
endlocal & exit /b %OVERALL%

rem ---------------------------------------------------------------------------
rem  :ReadApiUrls
rem  Writes "<api-name> <base-url>" lines for the deployed APIs to URL_FILE,
rem  from the api_base_urls output in the Terraform state. Sets CLOUD_ERROR
rem  when no API is deployed.
rem ---------------------------------------------------------------------------
:ReadApiUrls
if not exist "%STATE_FILE%" (
    echo ERROR: No %CLOUD_LABEL% APIs are deployed ^(no Terraform state^).
    echo        Run Clouds\Docker-clouds-%CLOUD%-dbapi-builder.bat first.
    set "CLOUD_ERROR=NOT_DEPLOYED"
    goto :eof
)
powershell -NoProfile -Command "$m = (Get-Content -LiteralPath '%STATE_FILE%' -Raw | ConvertFrom-Json).outputs.api_base_urls.value; $lines = @(if ($m) { $m.PSObject.Properties | ForEach-Object { '{0} {1}' -f $_.Name, ([string]$_.Value).TrimEnd('/') } }); Set-Content -LiteralPath '%URL_FILE%' -Value $lines -Encoding ascii"
set "URL_COUNT=0"
if exist "%URL_FILE%" for /f "usebackq tokens=1,2" %%A in ("%URL_FILE%") do set /a URL_COUNT+=1
if "%URL_COUNT%"=="0" (
    echo ERROR: No %CLOUD_LABEL% APIs are deployed ^(api_base_urls is empty^).
    echo        Run Clouds\Docker-clouds-%CLOUD%-dbapi-builder.bat first.
    set "CLOUD_ERROR=NOT_DEPLOYED"
    goto :eof
)
echo API base URLs ^(from Terraform state^):
type "%URL_FILE%"
echo.
goto :eof

rem ---------------------------------------------------------------------------
rem  :RunEnvironment <db> <DbLabel> <DbTag>
rem  Bruno environment "<Cloud> - <DbLabel>", APIs cloud-api-<lang>-<db>.
rem ---------------------------------------------------------------------------
:RunEnvironment
set "BRU_ENV=%CLOUD_LABEL% - %~2"
set "TAG=%CLOUD_LABEL%-%~3"
echo ###########################################################################
echo  Environment: %BRU_ENV%
echo ###########################################################################
call :RunCollection "PilotApiDotNet" "%GITHUB_ROOT%\PilotApiDotNet\test\Bruno\PilotApiDotNet"  "cloud-api-dotnet-%~1"
call :RunCollection "PilotApiJava"   "%GITHUB_ROOT%\PilotApiJava\test\Bruno\PilotApiJava"      "cloud-api-java-%~1"
call :RunCollection "PilotApiPython" "%GITHUB_ROOT%\PilotApiPython\tests\Bruno\PilotApiPython" "cloud-api-python-%~1"
goto :eof

rem ---------------------------------------------------------------------------
rem  :RunCollection <Name> <CollectionPath> <ApiName>   (uses BRU_ENV and TAG)
rem  The manifest line format is the one RunBrunoTests.bat uses:
rem    <Tag>;<Environment>;<Collection>;<exit code or status>;<start>;<end>
rem ---------------------------------------------------------------------------
:RunCollection
if defined FILTER_NAME if /i not "%FILTER_NAME%"=="%~1" goto :eof
set /a RUN_COUNT+=1
set "NAME=%~1"
set "COLL=%~2"
set "API=%~3"
set "OUT=%REPORT_DIR%\%NAME%_%TAG%"
echo ===========================================================================
echo  %NAME%  [%BRU_ENV%]  %API%
echo  %COLL%
echo ===========================================================================
call :Now START_TS
if defined CLOUD_ERROR (
    echo SKIPPED: %CLOUD_ERROR%
    call :Fail "%CLOUD_ERROR%"
    goto :eof
)
if not exist "%COLL%\opencollection.yml" if not exist "%COLL%\bruno.json" (
    echo ERROR: Collection not found.
    call :Fail NOT_FOUND
    goto :eof
)
if not exist "%COLL%\environments\%BRU_ENV%.yml" (
    echo ERROR: Bruno environment "%BRU_ENV%" not found in the collection.
    call :Fail ENVIRONMENT_NOT_FOUND
    goto :eof
)
set "API_URL="
for /f "usebackq tokens=1,2" %%A in ("%URL_FILE%") do if /i "%%A"=="%API%" set "API_URL=%%B"
if not defined API_URL (
    echo ERROR: %API% is not deployed in %CLOUD_LABEL%.
    call :Fail API_NOT_DEPLOYED
    goto :eof
)
echo  Host: %API_URL%/
pushd "%COLL%"
call %BRU_CMD% run -r --env "%BRU_ENV%" --env-var "Host=%API_URL%/" ^
    --reporter-json  "%OUT%.json" ^
    --reporter-html  "%OUT%.html" ^
    --reporter-junit "%OUT%.xml"
set "RC=%ERRORLEVEL%"
popd
call :Now END_TS
>> "%MANIFEST%" echo %TAG%;%BRU_ENV%;%NAME%;%RC%;%START_TS%;%END_TS%
if not "%RC%"=="0" set "OVERALL=1"
echo.
goto :eof

rem ---------------------------------------------------------------------------
rem  :Fail <Status>   Records a collection that could not run (uses START_TS).
rem ---------------------------------------------------------------------------
:Fail
>> "%MANIFEST%" echo %TAG%;%BRU_ENV%;%NAME%;%~1;%START_TS%;%START_TS%
set "OVERALL=1"
echo.
goto :eof

rem ---------------------------------------------------------------------------
rem  :Now <VariableName>   Sets the variable to the current ISO 8601 timestamp.
rem ---------------------------------------------------------------------------
:Now
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format o"`) do set "%~1=%%T"
goto :eof
