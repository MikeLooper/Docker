REM Docker - Setup - SQL Server

REM Prep
REM 	A. Substitutions - in order for this script to work the follwing placeholders will need correct values substituted:
REM 		- Mji_389erHz2#ytx
REM 		- Hjm$435yVt7a

REM 	B. Change to the working directory:
cd C:\Working\Storage\Dev\GitHub\Working

REM 1. Setup - nothing to do here

REM 2. Clean up prior working files:
erase /S /Q .\* > nul

REM 3. Remove a previously existing partition, if any is present:
docker rm -f local_mssql

REM 4. Download the SQL Server image:
docker pull mcr.microsoft.com/mssql/server:2025-latest

REM 5. Create and start the new container:
docker run -p 1433:1433 --hostname local_mssql --name local_mssql --network pilot-net -m 2g -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Mji_389erHz2#ytx" -e "MSSQL_AGENT_ENABLED=true" -v "mssql_data:/var/opt/mssql" -v "C:\Working\Storage\Dev\Docker\Working:/local_working" -d mcr.microsoft.com/mssql/server:2025-latest

REM 6. Validate assignment of password:
docker exec -it local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "Mji_389erHz2#ytx" -C

REM 7. Disable the 'sa' account:

REM 	A. Create a new login user (to take the place of the 'sa' user id):
docker exec -it local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "Mji_389erHz2#ytx" -C -Q "CREATE LOGIN [DevUser] WITH PASSWORD = 'Hjm$435yVt7a'; ALTER SERVER ROLE [sysadmin] ADD MEMBER [DevUser];"

REM 	B. Disable the 'sa' account:
docker exec -it local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "Hjm$435yVt7a" -C -Q "ALTER LOGIN [sa] DISABLE;"

REM 8. Create the NorthWind database:
docker exec -it local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "Hjm$435yVt7a" -C -Q "CREATE DATABASE NorthWind;"

REM 	A. Validate database was created (should not get an error):
docker exec local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost \
-U DevUser -P "Hjm$435yVt7a" -C -d NorthWind

REM 9. Copy database script:
erase /S /Q .\* > nul
copy "..\PilotApiDotNet\docker\SqlServer\Northwind.sql" "."

REM 10. Load data into the database:
docker exec -i local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "Hjm$435yVt7a" -d northwind -C < ..\PilotApiDotNet\docker\SqlServer\Northwind.sql

REM 	A. Validate (should show a list of tables):
docker exec local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "Hjm$435yVt7a" -d NorthWind -C -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';"

REM 11. Clean up prior working files:
erase /S /Q .\* > nul

REM 12. Copy custom script:
copy "..\PilotApiDotNet\docker\SqlServer\customobjects.sql" "."

REM 13. Load data into the database:
docker exec -i local_mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U DevUser -P "Hjm$435yVt7a" -d northwind -C < ..\PilotApiDotNet\docker\SqlServer\customobjects.sql

REM 14. Clean up prior working files (optional):
erase /S /Q .\*
