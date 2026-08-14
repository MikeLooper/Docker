@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Dozzle

set "IMAGE_FILE=amir20/dozzle:latest"
set "DOZZLE_PORT=51101"

REM 1. Remove a previously existing partition, if any is present:
docker rm -f local-dozzle

REM 2. Build and start the Dozzle container.
docker run -d --name local-dozzle -m 512m -p %DOZZLE_PORT%:8080 --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v dozzle_data:/data %IMAGE_FILE%

REM 3. Launch UI as a health check.
start http://localhost:%DOZZLE_PORT%
