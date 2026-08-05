@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Dozzle

set "IMAGE_FILE=amir20/dozzle:latest"
set "DOZZLE_PORT=55601"

REM 1. Build and start the Dozzle container.
docker run -d --name local_dozzle -m 512m -p %DOZZLE_PORT%:8080 -v /var/run/docker.sock:/var/run/docker.sock -v dozzle_data:/data %IMAGE_FILE%

REM 2. Launch UI as a health check.
start http://localhost:%DOZZLE_PORT%
