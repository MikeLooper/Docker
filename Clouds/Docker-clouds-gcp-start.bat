@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Start - Clouds - GCP emulator (local-gcp), its databases and APIs
REM Usage: Docker-clouds-gcp-start.bat [-norebuild]
REM   Starts local-keycloak and the OTEL stack if needed, then local-gcp and the containers
REM   created by Docker-clouds-gcp-dbapi-builder.bat, and checks the APIs. If they do not
REM   answer, the dbapi builder is re-run (unless -norebuild).

call "%~dp0scripts\cloud-lifecycle.bat" :start gcp %1
exit /b %errorlevel%
