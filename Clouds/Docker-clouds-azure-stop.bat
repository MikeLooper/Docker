@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Stop - Clouds - Azure emulator (local-azure), its databases and APIs
REM Usage: Docker-clouds-azure-stop.bat
REM   Stops local-azure, then every container it manages (databases, APIs, console).
REM   Nothing is deleted: data, images and Terraform state are kept.
REM   local-keycloak and the OTEL stack keep running (the local APIs use them too).

call "%~dp0scripts\cloud-lifecycle.bat" :stop azure
exit /b %errorlevel%
