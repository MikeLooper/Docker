REM Docker - Setup - API (DotNet)

REM 1. Change to the working directory:
cd C:\Working\Storage\Dev\GitHub\Working

REM 2. Remove a previously existing partition (for SQL Server), if any is present:
docker rm -f pilot-api-dotnet-mssql
  
REM 3. Remove a previously existing partition (for PostgreSQL), if any is present:
docker rm -f pilot-api-dotnet-postgres
  
REM 4. Remove a previously existing image (for SQL Server), if any is present:
docker rmi pilot-api-dotnet-mssql:1.0
  
REM 5. Remove a previously existing image (for PostgreSQL), if any is present:
docker rmi pilot-api-dotnet-postgres:1.0
  
REM 6. Get the latest image for .NET 10:
docker pull mcr.microsoft.com/dotnet/aspnet:10.0

REM 7. Clean up prior working files:
erase /S /Q .\* > nul

REM 8. Change to the application's root directory:
cd ..\PilotApiDotNet

REM 9. Build the application, so it can execute on Linux (API Publish)
dotnet publish --configuration Release --os linux --arch x64 --output ..\Working

REM 10. Change to the Working directory:
cd ..\Working

REM 11. Copy the dockerfile to the publish directory (for SQL Server):
copy /y "..\PilotApiDotNet\docker\Api_dotnet\dockerfile_mssql" ".\dockerfile"

REM 12. Copy the appsettings file to the publish directory (for SQL Server):
copy /y "..\PilotApiDotNet\docker\SqlServer\appsettings.Production.json" "."

REM 13. Build the docker image (for SQL Server):
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%
docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" -t pilot-api-dotnet-mssql:1.0 .

REM 14. Create and start the container (for SQL Server):
docker run -d -p 55551:8080 --network pilot-net -m 1g --name pilot-api-dotnet-mssql pilot-api-dotnet-mssql:1.0

REM 15. Copy the dockerfile to the publish directory (for PostgreSQL):
copy /y "..\PilotApiDotNet\docker\Api_dotnet\dockerfile_postgres" ".\dockerfile"

REM 16. Copy the appsettings file to the publish directory (PostgreSQL):
copy /y "..\PilotApiDotNet\docker\PostgreSQL\appsettings.Production.json" "."

REM 17. build the docker image (for PostgreSQL):
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%
docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" -t pilot-api-dotnet-postgres:1.0 .

REM 18. Create and start the container (for PostgreSQL):
docker run -d -p 55552:8080 --network pilot-net -m 1g --name pilot-api-dotnet-postgres pilot-api-dotnet-postgres:1.0

REM 19. Clean up prior working files (optional):
REM erase /S /Q .\* > nul

REM 20. Launch the healthcheck to validate the deploy  (for SQL Server)
start http://localhost:55551/healthcheck

REM 21. Launch the healthcheck to validate the deploy  (for PostgreSQL)
start http://localhost:55552/healthcheck
