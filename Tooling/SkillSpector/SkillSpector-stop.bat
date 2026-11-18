@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM SkillSpector - stop the local-skillspector container. Nothing is deleted.

docker stop local-skillspector
exit /b %ERRORLEVEL%
