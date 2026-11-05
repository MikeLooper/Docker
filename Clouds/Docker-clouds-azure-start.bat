@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Start - Clouds - Azure emulator (local-azure), its databases and APIs
REM Usage: Docker-clouds-azure-start.bat [-norebuild]
REM   Starts local-keycloak and the OTEL stack if needed, then local-azure and the containers
REM   created by Docker-clouds-azure-dbapi-builder.bat, and checks the APIs. If they do not
REM   answer, the dbapi builder is re-run (unless -norebuild).

call "%~dp0scripts\cloud-lifecycle.bat" :start azure %1
exit /b %errorlevel%
