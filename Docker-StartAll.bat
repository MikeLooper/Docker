@echo off
setlocal EnableExtensions DisableDelayedExpansion

docker start local-postgres
docker start local-mssql
docker start local-loki
docker start local-mimir
docker start local-tempo
docker start otel-collector
docker start local-grafana
docker start pilot-api-dotnet-postgres
docker start pilot-api-dotnet-mssql
docker start pilot-api-java-postgres
docker start pilot-api-java-mssql
docker start pilot-api-python-postgres
docker start pilot-api-python-mssql
docker start utility-api-dotnet-postgres
docker start utility-api-dotnet-mssql
docker start pilot-ui
docker start local-homepage
