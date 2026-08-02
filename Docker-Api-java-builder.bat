REM Docker - Setup - API (Java)

REM 1. Change to the working directory:
cd C:\Working\Storage\Dev\GitHub\Working

REM 2. Remove a previously existing partition (for SQL Server), if any is present:
docker rm -f pilot-api-java-mssql
  
REM 3. Remove a previously existing partition (for PostgreSQL), if any is present:
docker rm -f pilot-api-java-postgres
  
REM 4. Remove a previously existing image (for SQL Server), if any is present:
docker rmi pilot-api-java-mssql:1.0
  
REM 5. Remove a previously existing image (for PostgreSQL), if any is present:
docker rmi pilot-api-java-postgres:1.0
  
REM 6. Get the latest image for Java:
docker pull eclipse-temurin:25-jre-alpine

REM 7. Clean up prior working files:
erase /S /Q .\* > nul

REM 8. Change to the application's root directory (where pom.xml is located):
cd ..\PilotApiJava

REM 9. Build the application:
REM CALL mvn clean package -DskipTests

copy target\*.jar ..\Working\

@ECHO ON

REM 10. Change to the Working directory:
cd ..\Working

REM 11. Copy the dockerfile to the publish directory (for SQL Server):
copy /y "..\Docker\Api_java\dockerfile_mssql" ".\dockerfile"

REM 12. Build the current date variable:
FOR /F "usebackq tokens=*" %%i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%%i"
ECHO Current Date=%CURRENT_DATE%

REM 13. Build the docker image (for SQL Server):
docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" --build-arg DB_URL="jdbc:sqlserver://local_mssql:1433;databaseName=NorthWind;encrypt=true;trustServerCertificate=true;connectTimeout=30" --build-arg DB_PASSWORD="Hjm$435yVt7a" --build-arg SERVER_PORT="56661" -t pilot-api-java-mssql:1.0 .

REM 14. Create and start the container (for SQL Server):
docker run -d -p 56661:56661 --network pilot-net -m 1g --name pilot-api-java-mssql pilot-api-java-mssql:1.0

REM 15. Copy the dockerfile to the publish directory (for PostgreSQL):
copy /y "..\Docker\Api_java\dockerfile_postgres" ".\dockerfile"

REM 16. build the docker image (for PostgreSQL):
docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" --build-arg DB_URL="jdbc:postgresql://local_postgres:5432/northwind" --build-arg DB_PASSWORD="Pwo_698UVtra" --build-arg SERVER_PORT="56662" -t pilot-api-java-postgres:1.0 .

REM 17. Create and start the container (for PostgreSQL):
docker run -d -p 56662:56662 --network pilot-net -m 1g --name pilot-api-java-postgres pilot-api-java-postgres:1.0

REM 18. Clean up prior working files (optional):
REM erase /S /Q .\* > nul

REM 19. Launch the healthcheck to validate the deploy  (for SQL Server)
start http://localhost:56661/healthcheck

REM 20. Launch the healthcheck to validate the deploy  (for PostgreSQL)
start http://localhost:56662/healthcheck
