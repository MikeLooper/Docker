@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Homepage

set "IMAGE_FILE=ghcr.io/gethomepage/homepage:latest"
set "COMPOSE_FILE=%~dp0docker-compose.homepage.yml"
set "HOMEPAGE_PORT=56201"

REM 1. Download the image used to serve the Homepage bundle:
docker pull "%IMAGE_FILE%"

REM 2. Stop and remove any prior container or compose service for this stack.
docker compose -f "%COMPOSE_FILE%" down --remove-orphans
docker rm -f local-homepage >nul 2>&1

REM 3. Build and start the UI container with Compose.
docker compose -f "%COMPOSE_FILE%" -p local-homepage up -d --build --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	exit /b 1
)

REM 4. Launch UI as a health check.
start http://localhost:%HOMEPAGE_PORT%
