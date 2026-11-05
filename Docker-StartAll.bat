@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Cloud emulators: only the ones selected by Clouds\Docker-clouds-builder.bat -platform
REM (saved in Clouds\.platform; a missing file means all).
set "CLOUD_PLATFORM=all"
if exist "%~dp0Clouds\.platform" set /p CLOUD_PLATFORM=<"%~dp0Clouds\.platform"
for /f "tokens=1" %%P in ("%CLOUD_PLATFORM%") do set "CLOUD_PLATFORM=%%P"

ECHO Start PostGreSQL ...
docker start local-postgres

ECHO .
ECHO Start SQL Server ...
docker start local-mssql

ECHO .
ECHO Start Loki ...
docker start local-loki

ECHO .
ECHO Start Mimir ...
docker start local-mimir

ECHO .
ECHO Start Tempo ...
docker start local-tempo

ECHO .
ECHO Start otel-collector ...
docker start otel-collector

ECHO .
ECHO Start Grafana ...
docker start local-grafana

ECHO .
ECHO Start Keycloak ...
docker start local-keycloak

ECHO .
ECHO Start AWS emulator ...
if /I "%CLOUD_PLATFORM%"=="all" docker start local-aws
if /I "%CLOUD_PLATFORM%"=="aws" docker start local-aws

ECHO .
ECHO Start Azure emulator ...
if /I "%CLOUD_PLATFORM%"=="all" docker start local-azure
if /I "%CLOUD_PLATFORM%"=="azure" docker start local-azure

ECHO .
ECHO Start GCP emulator ...
if /I "%CLOUD_PLATFORM%"=="all" docker start local-gcp
if /I "%CLOUD_PLATFORM%"=="gcp" docker start local-gcp

ECHO .
ECHO Start Pilot API .NET PostGreSQL ...
docker start pilot-api-dotnet-postgres

ECHO .
ECHO Start Pilot API .NET SQL Server ...
docker start pilot-api-dotnet-mssql

ECHO .
ECHO Start Pilot API Java PostGreSQL ...
docker start pilot-api-java-postgres

ECHO .
ECHO Start Pilot API Java SQL Server ...
docker start pilot-api-java-mssql

ECHO .
ECHO Start Pilot API Python PostGreSQL ...
docker start pilot-api-python-postgres

ECHO .
ECHO Start Pilot API Python SQL Server ...
docker start pilot-api-python-mssql

ECHO .
ECHO Start Pilot API Python with Claude ...
docker start python-api-with-claude

ECHO .
ECHO Start Pilot API DAB PostGreSQL ...
docker start pilot-api-msdab-postgres

ECHO .
ECHO Start Pilot API DAB SQL Server ...
docker start pilot-api-msdab-mssql

ECHO .
ECHO Start MCP Inspector (DAB) ...
docker start pilot-msdab-mcp-inspector

ECHO .
ECHO Start Utility API .NET PostGreSQL ...
docker start utility-api-dotnet-postgres

ECHO .
ECHO Start Utility API .NET SQL Server ...
docker start utility-api-dotnet-mssql

ECHO .
ECHO Start Pilot UI ...
docker start pilot-ui

ECHO .
ECHO Start Homepage ...
docker start local-homepage

ECHO .
ECHO Start Dozzle ...
docker start local-dozzle

ECHO .
ECHO Start Uptime Kuma ...
docker start local-uptimekuma

ECHO Finished
