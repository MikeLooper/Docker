@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM SkillSpector - start the local-skillspector container (it must already exist).

set "COMMON=%~dp0skillspector-common.bat"
call "%COMMON%" :init
call "%COMMON%" :ensure_running || exit /b 1
docker exec %CONTAINER_NAME% skillspector --version
exit /b %ERRORLEVEL%
