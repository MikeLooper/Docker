@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Uptime Kuma

set "IMAGE_FILE=louislam/uptime-kuma:latest"
set "UPTIMEKUMA_PORT=3001"

REM 1. Build and start the Uptime Kuma container.
docker run -d -p %UPTIMEKUMA_PORT%:%UPTIMEKUMA_PORT% -m 512m --name local_uptimekuma --restart=always -v uptime-kuma:/app/data -v /var/run/docker.sock:/var/run/docker.sock %IMAGE_FILE%

REM 2. Launch UI as a health check.
start http://localhost:%UPTIMEKUMA_PORT%
