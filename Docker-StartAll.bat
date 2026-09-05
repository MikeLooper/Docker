@echo off
setlocal EnableExtensions DisableDelayedExpansion

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
