@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM SkillSpector - scan a skill and save Markdown and JSON reports.
REM
REM Usage: SkillSpector-report.bat <skill-path-or-git-url> [skillspector scan options]
REM Reports are written to C:\Working\Storage\Dev\GitHub\Working\skillspector-reports
REM as <name>-<yyyyMMdd-HHmmss>.md and .json, and the folder is opened.
REM Exit code: 0 = score 50 or less, 1 = score above 50 (or a strict gate fired), 2 = error.

if "%~1"=="" (
	echo Usage: %~nx0 ^<skill-path-or-git-url^> [skillspector scan options]
	exit /b 2
)

set "COMMON=%~dp0skillspector-common.bat"
call "%COMMON%" :init
call "%COMMON%" :ensure_running || exit /b 2
call "%COMMON%" :resolve_target "%~1" || exit /b 2
call "%COMMON%" :llm_flag

REM Report name: the skill folder name (a SKILL.md file uses its parent folder's name).
for %%F in ("%~f1") do (
	set "REPORT_NAME=%%~nxF"
	if /I "%%~nxF"=="SKILL.md" for %%P in ("%%~dpF.") do set "REPORT_NAME=%%~nxP"
)
echo(%~1| findstr /I /R /C:"^https*://" /C:"^git@" >nul && set "REPORT_NAME=remote-skill"
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%D"
set "REPORT_BASE=%REPORT_NAME%-%STAMP%"

set "EXTRA="
:collect
shift
if "%~1"=="" goto scan
set EXTRA=%EXTRA% %1
goto collect

:scan
echo %EXTRA% | findstr /I /C:"--no-llm" >nul && set "SS_LLM_FLAG="
if not exist "%REPORTS_DIR%" mkdir "%REPORTS_DIR%"

echo Writing %REPORT_BASE%.json ...
call "%COMMON%" :run scan "%SS_TARGET%" %SS_LLM_FLAG%%EXTRA% -f json -o /reports/%REPORT_BASE%.json
if errorlevel 2 (
	echo JSON report failed.
	exit /b 2
)
echo Writing %REPORT_BASE%.md ...
call "%COMMON%" :run scan "%SS_TARGET%" %SS_LLM_FLAG%%EXTRA% -f markdown -o /reports/%REPORT_BASE%.md
set "RC=%ERRORLEVEL%"
if "%RC%"=="2" (
	echo Markdown report failed.
	exit /b 2
)

echo.
type "%REPORTS_DIR%\%REPORT_BASE%.md"
echo.
echo Reports saved in %REPORTS_DIR%:
dir /B "%REPORTS_DIR%\%REPORT_BASE%.*"
start "" "%REPORTS_DIR%"
exit /b %RC%
