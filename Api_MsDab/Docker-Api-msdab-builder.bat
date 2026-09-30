@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - API (Microsoft Data API builder) - Compose-first

pushd "%~dp0"

set "DAB_VERSION=2.0.12"
set "DAB_IMAGE=mcr.microsoft.com/azure-databases/data-api-builder:%DAB_VERSION%"
set "INSPECTOR_IMAGE=ghcr.io/modelcontextprotocol/inspector:2.8.0"
set "COMPOSE_FILE=%~dp0docker-compose.api-msdab.yml"
set "COMPOSE_PROJECT=pilot-api-msdab"
set "SECRETS_FILE=%~dp0..\secrets\ms-dab.env"
set "CONFIG_DIR=%~dp0data-api"
set "MSSQL_CONFIG=%CONFIG_DIR%\dab-config.mssql.json"
set "POSTGRES_CONFIG=%CONFIG_DIR%\dab-config.postgres.json"
set "VALIDATE_SCRIPT=%~dp0scripts\Test-DabConfig.ps1"
set "MSDAB_MSSQL_PORT=56301"
set "MSDAB_POSTGRES_PORT=56401"
set "MSDAB_INSPECTOR_PORT=56501"

REM Connection strings use container names on pilot-net. The password is resolved by DAB at runtime.
set "MSSQL_CONNECTION=Server=local-mssql,1433;Database=NorthWind;User ID=DevUser;Password=@env('DATABASE_PASSWORD');TrustServerCertificate=True;"
set "POSTGRES_CONNECTION=Host=local-postgres;Port=5432;Database=northwind;Username=DevUser;Password=@env('DATABASE_PASSWORD');"

REM 1. Check prerequisites: secrets, dab CLI, Docker network, and database containers.
if not exist "%SECRETS_FILE%" (
	echo Secrets file not found: "%SECRETS_FILE%"
	echo Copy secrets\ms-dab.env.example to secrets\ms-dab.env and set its values.
	goto :fail
)

dotnet tool list -g | findstr /I /C:"microsoft.dataapibuilder" | findstr /C:"%DAB_VERSION%" >nul
if errorlevel 1 (
	echo Data API builder CLI %DAB_VERSION% is not installed. Install it with:
	echo   dotnet tool install -g Microsoft.DataApiBuilder --version %DAB_VERSION%
	echo Or, if another version is installed:
	echo   dotnet tool update -g Microsoft.DataApiBuilder --version %DAB_VERSION%
	goto :fail
)

docker network inspect pilot-net >nul 2>&1
if errorlevel 1 (
	echo Docker network pilot-net not found. Create it with: docker network create pilot-net
	goto :fail
)

call :require_running local-mssql
if errorlevel 1 goto :fail
call :require_running local-postgres
if errorlevel 1 goto :fail

REM Resolve host ports so Windows reserved/in-use ports do not break compose startup.
REM Stop this stack first so its own ports are free to reuse.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% --env-file "%SECRETS_FILE%" down --remove-orphans
if errorlevel 1 (
	echo docker compose down failed.
	goto :fail
)

call :resolve_open_port %MSDAB_MSSQL_PORT% MSDAB_MSSQL_PORT
if errorlevel 1 goto :fail
call :resolve_open_port %MSDAB_POSTGRES_PORT% MSDAB_POSTGRES_PORT
if errorlevel 1 goto :fail
call :resolve_open_port %MSDAB_INSPECTOR_PORT% MSDAB_INSPECTOR_PORT
if errorlevel 1 goto :fail

REM 2. Download the images.
docker pull "%DAB_IMAGE%"
if errorlevel 1 (
	echo Failed to pull "%DAB_IMAGE%".
	goto :fail
)
docker pull "%INSPECTOR_IMAGE%"
if errorlevel 1 (
	echo Failed to pull "%INSPECTOR_IMAGE%".
	goto :fail
)

REM 3. Generate the DAB configs. The script is the source of truth; a rerun overwrites them.
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
call :define_fields

call :generate_mssql_config
if errorlevel 1 (
	echo Failed to generate "%MSSQL_CONFIG%".
	goto :fail
)
call :generate_postgres_config
if errorlevel 1 (
	echo Failed to generate "%POSTGRES_CONFIG%".
	goto :fail
)

REM 4. Validate each config against the database through its host-exposed port.
powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_SCRIPT%" -ConfigPath "%MSSQL_CONFIG%" -SecretsFile "%SECRETS_FILE%" -PasswordKey MSSQL_DATABASE_PASSWORD -ContainerHost local-mssql
if errorlevel 1 (
	echo dab validate failed for the SQL Server config.
	goto :fail
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_SCRIPT%" -ConfigPath "%POSTGRES_CONFIG%" -SecretsFile "%SECRETS_FILE%" -PasswordKey POSTGRES_DATABASE_PASSWORD -ContainerHost local-postgres
if errorlevel 1 (
	echo dab validate failed for the PostgreSQL config.
	goto :fail
)

REM 5. Start both DAB containers and MCP Inspector with Compose.
docker compose -f "%COMPOSE_FILE%" -p %COMPOSE_PROJECT% --env-file "%SECRETS_FILE%" up -d --force-recreate
if errorlevel 1 (
	echo docker compose up failed.
	goto :fail
)

REM 6. Wait for both DAB containers to report healthy.
call :wait_healthy pilot-api-msdab-mssql
if errorlevel 1 goto :fail
call :wait_healthy pilot-api-msdab-postgres
if errorlevel 1 goto :fail

REM 7. Launch health checks and MCP Inspector (auto-connect links carry the Inspector token).
start "" "http://localhost:%MSDAB_MSSQL_PORT%/health"
start "" "http://localhost:%MSDAB_POSTGRES_PORT%/health"

set "INSPECTOR_TOKEN="
for /f "usebackq tokens=1,* delims==" %%A in ("%SECRETS_FILE%") do (
	if /I "%%A"=="MCP_INSPECTOR_API_TOKEN" set "INSPECTOR_TOKEN=%%~B"
)
if defined INSPECTOR_TOKEN (
	start "" "http://localhost:%MSDAB_INSPECTOR_PORT%/?serverUrl=http://pilot-api-msdab-mssql:5000/mcp&transport=http&autoConnect=%INSPECTOR_TOKEN:'=%"
	start "" "http://localhost:%MSDAB_INSPECTOR_PORT%/?serverUrl=http://pilot-api-msdab-postgres:5000/mcp&transport=http&autoConnect=%INSPECTOR_TOKEN:'=%"
)
set "INSPECTOR_TOKEN="

echo.
echo Data API builder is running:
echo   SQL Server : http://localhost:%MSDAB_MSSQL_PORT%/api  ^|  /graphql  ^|  /swagger  ^|  /mcp
echo   PostgreSQL : http://localhost:%MSDAB_POSTGRES_PORT%/api  ^|  /graphql  ^|  /swagger  ^|  /mcp
echo   MCP Inspector: http://localhost:%MSDAB_INSPECTOR_PORT%/  (auto-connect links: mcp-inspector\README.md)

popd
exit /b 0

:fail
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM  :define_fields   Exposed field names (PascalCase, as in SQL Server) and
REM  primary-key flags for each entity. Both configs expose the same fields.
REM ---------------------------------------------------------------------------
:define_fields
set "F_Categories=CategoryID,CategoryName,Description,Picture"
set "K_Categories=true,false,false,false"
set "F_Customers=CustomerID,CompanyName,ContactName,ContactTitle,Address,City,Region,PostalCode,Country,Phone,Fax"
set "K_Customers=true,false,false,false,false,false,false,false,false,false,false"
set "F_Employees=EmployeeID,LastName,FirstName,Title,TitleOfCourtesy,BirthDate,HireDate,Address,City,Region,PostalCode,Country,HomePhone,Extension,Photo,Notes,ReportsTo,PhotoPath"
set "K_Employees=true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false"
set "F_OrderDetails=OrderID,ProductID,UnitPrice,Quantity,Discount"
set "K_OrderDetails=true,true,false,false,false"
set "F_Orders=OrderID,CustomerID,EmployeeID,OrderDate,RequiredDate,ShippedDate,ShipVia,Freight,ShipName,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry"
set "K_Orders=true,false,false,false,false,false,false,false,false,false,false,false,false,false"
set "F_Products=ProductID,ProductName,SupplierID,CategoryID,QuantityPerUnit,UnitPrice,UnitsInStock,UnitsOnOrder,ReorderLevel,Discontinued"
set "K_Products=true,false,false,false,false,false,false,false,false,false"
set "F_Shippers=ShipperID,CompanyName,Phone"
set "K_Shippers=true,false,false"
set "F_Suppliers=SupplierID,CompanyName,ContactName,ContactTitle,Address,City,Region,PostalCode,Country,Phone,Fax,HomePage"
set "K_Suppliers=true,false,false,false,false,false,false,false,false,false,false,false"
exit /b 0

REM ---------------------------------------------------------------------------
REM  :generate_mssql_config   Tables in dbo already use PascalCase column names.
REM ---------------------------------------------------------------------------
:generate_mssql_config
set "CFG=%MSSQL_CONFIG%"
if exist "%CFG%" del /Q "%CFG%"
call dab init -c "%CFG%" --database-type mssql --host-mode Development --connection-string "%MSSQL_CONNECTION%" --rest.enabled true --graphql.enabled true --mcp.enabled true --cors-origin "*" || exit /b 1
call dab configure -c "%CFG%" --runtime.health.enabled true --runtime.health.roles anonymous || exit /b 1
call :add_entity Categories "dbo.Categories" "Product categories." "%F_Categories%" "%F_Categories%" "%K_Categories%" || exit /b 1
call :add_entity Customers "dbo.Customers" "Customers who place orders." "%F_Customers%" "%F_Customers%" "%K_Customers%" || exit /b 1
call :add_entity Employees "dbo.Employees" "Employees who take orders." "%F_Employees%" "%F_Employees%" "%K_Employees%" || exit /b 1
call :add_entity OrderDetails "dbo.[Order Details]" "Order line items. Composite key: OrderID and ProductID." "%F_OrderDetails%" "%F_OrderDetails%" "%K_OrderDetails%" || exit /b 1
call :add_entity Orders "dbo.Orders" "Customer orders." "%F_Orders%" "%F_Orders%" "%K_Orders%" || exit /b 1
call :add_entity Products "dbo.Products" "Products for sale." "%F_Products%" "%F_Products%" "%K_Products%" || exit /b 1
call :add_entity Shippers "dbo.Shippers" "Companies that ship orders." "%F_Shippers%" "%F_Shippers%" "%K_Shippers%" || exit /b 1
call :add_entity Suppliers "dbo.Suppliers" "Companies that supply products." "%F_Suppliers%" "%F_Suppliers%" "%K_Suppliers%" || exit /b 1
exit /b 0

REM ---------------------------------------------------------------------------
REM  :generate_postgres_config   Tables in pilot were created without quoted
REM  identifiers, so their names are lowercase. Each column is aliased to the
REM  PascalCase name used by SQL Server.
REM ---------------------------------------------------------------------------
:generate_postgres_config
set "CFG=%POSTGRES_CONFIG%"
if exist "%CFG%" del /Q "%CFG%"
call dab init -c "%CFG%" --database-type postgresql --host-mode Development --connection-string "%POSTGRES_CONNECTION%" --rest.enabled true --graphql.enabled true --mcp.enabled true --cors-origin "*" || exit /b 1
call dab configure -c "%CFG%" --runtime.health.enabled true --runtime.health.roles anonymous || exit /b 1
call :add_entity Categories "pilot.categories" "Product categories." "categoryid,categoryname,description,picture" "%F_Categories%" "%K_Categories%" || exit /b 1
call :add_entity Customers "pilot.customers" "Customers who place orders." "customerid,companyname,contactname,contacttitle,address,city,region,postalcode,country,phone,fax" "%F_Customers%" "%K_Customers%" || exit /b 1
call :add_entity Employees "pilot.employees" "Employees who take orders." "employeeid,lastname,firstname,title,titleofcourtesy,birthdate,hiredate,address,city,region,postalcode,country,homephone,extension,photo,notes,reportsto,photopath" "%F_Employees%" "%K_Employees%" || exit /b 1
call :add_entity OrderDetails "pilot.orderdetails" "Order line items. Composite key: OrderID and ProductID." "orderid,productid,unitprice,quantity,discount" "%F_OrderDetails%" "%K_OrderDetails%" || exit /b 1
call :add_entity Orders "pilot.orders" "Customer orders." "orderid,customerid,employeeid,orderdate,requireddate,shippeddate,shipvia,freight,shipname,shipaddress,shipcity,shipregion,shippostalcode,shipcountry" "%F_Orders%" "%K_Orders%" || exit /b 1
call :add_entity Products "pilot.products" "Products for sale." "productid,productname,supplierid,categoryid,quantityperunit,unitprice,unitsinstock,unitsonorder,reorderlevel,discontinued" "%F_Products%" "%K_Products%" || exit /b 1
call :add_entity Shippers "pilot.shippers" "Companies that ship orders." "shipperid,companyname,phone" "%F_Shippers%" "%K_Shippers%" || exit /b 1
call :add_entity Suppliers "pilot.suppliers" "Companies that supply products." "supplierid,companyname,contactname,contacttitle,address,city,region,postalcode,country,phone,fax,homepage" "%F_Suppliers%" "%K_Suppliers%" || exit /b 1
exit /b 0

REM ---------------------------------------------------------------------------
REM  :add_entity <Entity> <Source> <Description> <Columns> <Aliases> <PrimaryKeyFlags>   (uses CFG)
REM  Declaring fields explicitly is recommended by DAB when MCP is enabled.
REM ---------------------------------------------------------------------------
:add_entity
call dab add %~1 -c "%CFG%" --source "%~2" --source.type table --permissions "anonymous:*" --description "%~3" || exit /b 1
call dab update %~1 -c "%CFG%" --fields.name "%~4" --fields.alias "%~5" --fields.primary-key "%~6" || exit /b 1
exit /b 0

REM ---------------------------------------------------------------------------
REM  :require_running <ContainerName>
REM ---------------------------------------------------------------------------
:require_running
set "RUNNING="
for /f "usebackq tokens=*" %%R in (`docker inspect -f "{{.State.Running}}" %~1 2^>nul`) do set "RUNNING=%%R"
if /I not "%RUNNING%"=="true" (
	echo Database container %~1 is not running. Start it first, for example: docker start %~1
	exit /b 1
)
exit /b 0

REM ---------------------------------------------------------------------------
REM  :wait_healthy <ContainerName>   Waits up to 120 seconds for Docker health.
REM ---------------------------------------------------------------------------
:wait_healthy
echo Waiting for %~1 to report healthy...
powershell -NoProfile -Command "$deadline = (Get-Date).AddSeconds(120); do { $s = (docker inspect -f '{{.State.Health.Status}}' '%~1' 2>$null); if ($s -eq 'healthy') { exit 0 }; Start-Sleep -Seconds 3 } while ((Get-Date) -lt $deadline); exit 1"
if errorlevel 1 (
	echo %~1 did not become healthy within 120 seconds. Recent logs:
	docker logs --tail 50 %~1
	exit /b 1
)
echo %~1 is healthy.
exit /b 0

:resolve_open_port
set "RESOLVED_PORT="
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "$start = [int]%~1; $end = [Math]::Min($start + 98, 65535); function Test-Port([int]$port){ $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port); try { $listener.Start(); return $true } catch { return $false } finally { if ($listener.Server -and $listener.Server.IsBound) { $listener.Stop() } } }; foreach ($p in $start..$end) { if (Test-Port $p) { Write-Output $p; exit 0 } }; exit 1"`) do set "RESOLVED_PORT=%%P"

if not defined RESOLVED_PORT (
	goto :no_open_port
)

if not "%RESOLVED_PORT%"=="%~1" (
	echo Port %~1 unavailable. Using %RESOLVED_PORT% instead.
)

set "%~2=%RESOLVED_PORT%"
exit /b 0

:no_open_port
set /a "RANGE_END=%~1+98"
if %RANGE_END% GTR 65535 set "RANGE_END=65535"
echo Unable to find an available host port in the range %~1-%RANGE_END%.
exit /b 1
