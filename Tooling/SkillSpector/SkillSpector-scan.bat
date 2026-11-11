@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM SkillSpector - scan a skill and print the report to the console.
REM
REM Usage: SkillSpector-scan.bat <skill-path-or-git-url> [skillspector scan options]
REM   <skill-path>  A skill folder, a SKILL.md file, a .zip, or a git URL.
REM                 Windows paths are translated to the container's /scan mount.
REM   options       Passed through, e.g. --recursive, -f json, -V, --fail-on-findings.
REM
REM Static-only (--no-llm) is added automatically when no LLM provider is configured.
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

REM Collect the options after the path.
set "EXTRA="
:collect
shift
if "%~1"=="" goto scan
set EXTRA=%EXTRA% %1
goto collect

:scan
echo %EXTRA% | findstr /I /C:"--no-llm" >nul && set "SS_LLM_FLAG="
echo Scanning %SS_TARGET% %SS_LLM_FLAG%%EXTRA%
call "%COMMON%" :run scan "%SS_TARGET%" %SS_LLM_FLAG%%EXTRA%
exit /b %ERRORLEVEL%
