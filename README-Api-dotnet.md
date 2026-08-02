# Docker - Setup - API

Before starting the build steps below, be sure that the current application version is reflected in the image version noted in steps 13, 14, 17, and 18.  (e.g. pilot-api-dotnet-mssql:1.0)

The code for the PilotApiDotNet can be found here: https://github.com/MikeLooper/PilotApiDotNet
This code should be cloned locally, to allow code build/publish.
For this document, the PilotApiDotNet code is assumed to have been cloned next to the directory for this repository (see step 8).

The steps in this document have been converted into a command script: Docker-Api-dotnet-builder.bat

## Publish

Publish the API by following the commands:

Run the standard command from your application's root directory:

1. Change to the Working directory:

  ```
  cd C:\Working\Storage\Dev\GitHub\Working
  ``` 

2. Remove a previously existing partition (for SQL Server), if any is present:
  ```
  docker rm -f pilot-api-dotnet-mssql
  ```
  
3. Remove a previously existing partition (for PostgreSQL), if any is present:
  ```
  docker rm -f pilot-api-dotnet-postgres
  ```
  
4. Remove a previously existing image (for SQL Server), if any is present:
  ```
  docker rmi pilot-api-dotnet-mssql:1.0
  ```
  
5. Remove a previously existing image (for PostgreSQL), if any is present:
  ```
  docker rmi pilot-api-dotnet-postgres:1.0
  ```
  
6. Get the latest image for .NET 10:

  ```
  docker pull mcr.microsoft.com/dotnet/aspnet:10.0
  ```

7. Clean up prior working files:

  ```
  erase /S /Q .\* > nul
  ```

8. Change to the application's root directory:

  ```
  cd ..\PilotApiDotNet
  ``` 

9. Build the application, so it can execute on Linux (API Publish)

  ```
  dotnet publish --configuration Release --os linux --arch x64 --output ..\Working
  ```

10. Change to the Working directory:

  ```
  cd ..\Working
  ``` 

11. Copy the dockerfile to the publish directory (for SQL Server):

  ```
  copy /y "..\PilotApiDotNet\docker\Api_dotnet\dockerfile_mssql" ".\dockerfile"
  ```

12. Copy the appsettings file to the publish directory (for SQL Server):

  ```
  copy /y "..\PilotApiDotNet\docker\SqlServer\appsettings.Production.json" "."
  ```

13. Build the current date variable:

  ```
  FOR /F "usebackq tokens=*" %i IN (`powershell -NoProfile -Command "Get-Date -Format u"`) DO SET "CURRENT_DATE=%i"
  ECHO Current Date=%CURRENT_DATE%
  ```

14. Build the docker image (for SQL Server):
	
  ```
  docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" -t pilot-api-dotnet-mssql:1.0 .
  ```

15. Create and start the container (for SQL Server):

  ```
  docker run -d -p 55551:8080 \
  --network pilot-net \
  -m 1g \
  --name pilot-api-dotnet-mssql pilot-api-dotnet-mssql:1.0
  ```

16. Copy the dockerfile to the publish directory (for PostgreSQL):

  ```
  copy /y "..\PilotApiDotNet\docker\Api_dotnet\dockerfile_postgres" ".\dockerfile"
  ```

17. Copy the appsettings file to the publish directory (PostgreSQL):

  ```
  copy /y "..\PilotApiDotNet\docker\PostgreSQL\appsettings.Production.json" "."
  ```

18. build the docker image (for PostgreSQL):
	
  ```
  docker build --build-arg DEPLOY_DATE="%CURRENT_DATE%" -t pilot-api-dotnet-postgres:1.0 .
  ```

19. Create and start the container (for PostgreSQL):

  ```
  docker run -d -p 55552:8080 \
  --network pilot-net \
  -m 1g \
  --name pilot-api-dotnet-postgres pilot-api-dotnet-postgres:1.0
  ```

20. Clean up prior working files (optional):

  ```
  erase /S /Q .\* > nul
  ```

21. Launch the healthcheck to validate the deploy  (for SQL Server)

  ```
  start http://localhost:55551/healthcheck
  ```

22. Launch the healthcheck to validate the deploy  (for PostgreSQL)

  ```
  start http://localhost:55552/healthcheck
  ```

## Usage

After executing the above steps, you can now access your API at following base URL.

### SQL Server

```
http://localhost:55551/healthcheck
```

### PostgreSQL

```
http://localhost:55552/healthcheck
```

### Example Usages


### Docker = Production

The Docker container is executing with an environment of 'Production'.
This means that the Scalar and Swagger UIs will not be available, which follows API deployment best practices.

## Additional CLI commands

1. Start the Docker container:

	```
    docker start pilot-api-...-dotnet
	```

2. Stop and remove container:
	```
    docker rm -f pilot-api-...-dotnet
	```

