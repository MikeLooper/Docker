@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Stop - Clouds - GCP emulator (local-gcp), its databases and APIs
REM Usage: Docker-clouds-gcp-stop.bat
REM   Stops local-gcp, then every container it manages (databases, APIs, console).
REM   Nothing is deleted: data, images and Terraform state are kept.
REM   local-keycloak and the OTEL stack keep running (the local APIs use them too).

call "%~dp0scripts\cloud-lifecycle.bat" :stop gcp
exit /b %errorlevel%
