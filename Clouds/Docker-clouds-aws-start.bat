@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Start - Clouds - AWS emulator (local-aws), its databases and APIs
REM Usage: Docker-clouds-aws-start.bat [-norebuild]
REM   Starts local-keycloak and the OTEL stack if needed, then local-aws and the containers
REM   created by Docker-clouds-aws-dbapi-builder.bat, and checks the APIs. If they do not
REM   answer, the dbapi builder is re-run (unless -norebuild).

call "%~dp0scripts\cloud-lifecycle.bat" :start aws %1
exit /b %errorlevel%
