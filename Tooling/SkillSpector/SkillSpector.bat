@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM SkillSpector - run any SkillSpector command inside the local-skillspector container.
REM
REM Usage: SkillSpector.bat <command> [options]
REM Examples:
REM   SkillSpector.bat --help
REM   SkillSpector.bat scan --help
REM   SkillSpector.bat scan /scan/AI-Working/.claude/skills --recursive --no-llm
REM   SkillSpector.bat baseline /scan/AI-Working/.claude/skills/my-skill -o /reports/my-skill.baseline.json
REM
REM Paths are container paths: C:\Working\Storage\Dev\GitHub is mounted read-only at /scan,
REM and the reports folder (Working\skillspector-reports) is writable at /reports.

set "COMMON=%~dp0skillspector-common.bat"
call "%COMMON%" :init
call "%COMMON%" :ensure_running || exit /b 2
if "%~1"=="" (
	docker exec %CONTAINER_NAME% skillspector --help
	exit /b %ERRORLEVEL%
)
docker exec %CONTAINER_NAME% skillspector %*
exit /b %ERRORLEVEL%
