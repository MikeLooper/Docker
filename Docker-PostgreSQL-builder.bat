REM Docker - Setup - PostgreSQL

REM Prep
REM 	A. Substitutions - in order for this script to work the follwing placeholders will need correct values substituted:
REM 		- <dev-user-password>

REM 	B. Change to the working directory:
cd C:\Working\Storage\Dev\GitHub\Working

REM 1. Setup - nothing to do here

REM 2. Clean up prior working files:
erase /S /Q .\*

REM 3. Remove a previously existing partition, if any is present:
docker rm -f local_postgres

REM 4. Get the latest image:
docker pull postgres

REM 5. Create and start an instance:
docker run --name local_postgres -p 5432:5432 --network pilot-net -m 512m -e POSTGRES_USER=DevUser -e POSTGRES_PASSWORD=<dev-user-password> -e POSTGRES_DB=devDb -v "postgres_data:/var/lib/postgresql" -v ".:/local_working" -d postgres

REM 6. Create the northwind database:
docker exec local_postgres psql -U DevUser -d devDb -c "CREATE DATABASE northwind;"

REM 	A. Validate database was created (should not get an error):
docker exec local_postgres psql -U DevUser -d northwind

REM 7. Copy database script:
copy "..\PilotApiDotNet\docker\PostgreSQL\northwind.sql" "."

REM 8. Load data into the database:
docker exec -i local_postgres psql -U DevUser -d northwind < ..\PilotApiDotNet\docker\PostgreSQL\northwind.sql

REM 	A. Validate (should show a list of tables):
docker exec local_postgres psql -U DevUser -d northwind -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'pilot' AND table_type = 'BASE TABLE';"

REM 9. Clean up prior working files:
erase /S /Q .\*

REM 10. Copy custom script:
copy "..\PilotApiDotNet\docker\PostgreSQL\customobjects.sql" "."

REM 11. Load data into the database:
docker exec -i local_postgres psql -U DevUser -d northwind < ..\PilotApiDotNet\docker\PostgreSQL\customobjects.sql

REM 12. Clean up prior working files (optional):
REM erase /S /Q .\*
