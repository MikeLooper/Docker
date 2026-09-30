# Docker - Setup - API (Microsoft Data API builder)

Run Microsoft Data API builder (DAB) against the Northwind databases (SQL Server and PostgreSQL) with Docker Compose. Each instance serves REST, GraphQL, and MCP endpoints. MCP Inspector runs alongside them for testing the MCP endpoints.

DAB needs no application code: each instance is the official DAB image plus a JSON config file that the builder script generates.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.

```
cd Api_MsDab
```

When this process is complete, change the directory back to the main directory.

```
cd ..
```

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- The shared `pilot-net` Docker network
- Running database containers `local-mssql` and `local-postgres`, with the Northwind data loaded (see the [SqlServer](../SqlServer/README.md) and [PostgreSQL](../PostgreSQL/README.md) READMEs)
- .NET SDK, with the DAB CLI installed at the pinned version:

```
dotnet tool install -g Microsoft.DataApiBuilder --version 2.0.12
```

If a different version is already installed, use `dotnet tool update` with the same arguments.

- The secrets file `..\secrets\ms-dab.env` (see [Secrets](#secrets))

## Versions

| Component | Version | Image |
| --- | --- | --- |
| Data API builder | 2.0.12 | `mcr.microsoft.com/azure-databases/data-api-builder:2.0.12` |
| DAB CLI | 2.0.12 | `Microsoft.DataApiBuilder` .NET tool |
| MCP Inspector | 2.8.0 | `ghcr.io/modelcontextprotocol/inspector:2.8.0` |

The DAB CLI and image versions must match. To upgrade, change `DAB_VERSION` in the builder script and the default image in the Compose file.

## Secrets

Create `..\secrets\ms-dab.env` from `..\secrets\ms-dab.env.example`:

| Key | Value |
| --- | --- |
| `MSSQL_DATABASE_PASSWORD` | `DevUser` password for `local-mssql` |
| `POSTGRES_DATABASE_PASSWORD` | `DevUser` password for `local-postgres` |
| `MCP_INSPECTOR_API_TOKEN` | Any long random string. It guards the MCP Inspector API. |

- Keep each value in single quotes (`KEY='value'`). Compose then reads it literally, so passwords may contain `$`. Values must not contain a single quote.
- Compose reads the file with `--env-file` and maps each password to `DATABASE_PASSWORD` in its own container. Each DAB config reads it with `@env('DATABASE_PASSWORD')`. No password is written to the config files or the images.

## Primary Script

Use:

```
Docker-Api-msdab-builder.bat
```

This script uses:

- `docker-compose.api-msdab.yml` for both DAB services and MCP Inspector
- `data-api\dab-config.mssql.json` and `data-api\dab-config.postgres.json` (generated)
- `scripts\Test-DabConfig.ps1` to run `dab validate`

## What The Script Does

1. Checks for the secrets file, the DAB CLI version, the `pilot-net` network, and running `local-mssql` and `local-postgres` containers. It stops with a message if any is missing.
2. Stops the prior stack with `docker compose down --remove-orphans`.
3. Probes the host ports and picks the next open port if one is reserved or in use:
   - SQL Server instance: `56301-56399`
   - PostgreSQL instance: `56401-56499`
   - MCP Inspector: `56501-56599`
4. Pulls the DAB and MCP Inspector images.
5. Generates both DAB configs with `dab init`, `dab configure`, `dab add`, and `dab update`. The script is the source of truth for the configs; a rerun overwrites them, so don't edit them by hand.
6. Runs `dab validate` on each config. It validates a temporary copy that points at `localhost` (the host-exposed database ports), with `DATABASE_PASSWORD` set for that process only.
7. Runs `docker compose -p pilot-api-msdab up -d --force-recreate`.
8. Waits up to 120 seconds for each DAB container to report healthy.
9. Opens both health endpoints and both MCP Inspector auto-connect links in the browser.

## Configuration

Both configs share these settings:

| Setting | Value |
| --- | --- |
| Host mode | `development`. DAB serves Swagger UI and the GraphQL (Nitro) UI only in this mode. |
| REST / GraphQL / MCP | Enabled at `/api`, `/graphql`, `/mcp` |
| Permissions | `anonymous:*` on every entity |
| CORS | `*` (local use only) |
| Health | `/health` enabled for the `anonymous` role |
| Pagination | DAB defaults: 100 rows per page, maximum 100,000. Larger results include a `nextLink`. |
| OpenTelemetry | Sent to `otel-collector:4317` as `pilot-api-msdab-mssql` or `pilot-api-msdab-postgres` |

### Entities

| Entity | SQL Server source | PostgreSQL source | Key |
| --- | --- | --- | --- |
| Categories | `dbo.Categories` | `pilot.categories` | CategoryID |
| Customers | `dbo.Customers` | `pilot.customers` | CustomerID |
| Employees | `dbo.Employees` | `pilot.employees` | EmployeeID |
| OrderDetails | `dbo.[Order Details]` | `pilot.orderdetails` | OrderID, ProductID |
| Orders | `dbo.Orders` | `pilot.orders` | OrderID |
| Products | `dbo.Products` | `pilot.products` | ProductID |
| Shippers | `dbo.Shippers` | `pilot.shippers` | ShipperID |
| Suppliers | `dbo.Suppliers` | `pilot.suppliers` | SupplierID |

- The PostgreSQL tables were created without quoted identifiers, so their table and column names are lowercase. The script aliases every PostgreSQL column to the PascalCase name used by SQL Server, so both instances expose the same entity and field names.
- PostgreSQL `money` columns (`UnitPrice`, `Freight`) come back as strings such as `"$14.00"`. SQL Server returns them as numbers.

## Quick Links

| | SQL Server | PostgreSQL |
| --- | --- | --- |
| Health | http://localhost:56301/health | http://localhost:56401/health |
| REST | http://localhost:56301/api/Products | http://localhost:56401/api/Products |
| GraphQL (Nitro UI) | http://localhost:56301/graphql | http://localhost:56401/graphql |
| Swagger UI | http://localhost:56301/swagger | http://localhost:56401/swagger |
| MCP (Streamable HTTP) | http://localhost:56301/mcp | http://localhost:56401/mcp |

MCP Inspector: http://localhost:56501/. See the [MCP Inspector README](./mcp-inspector/README.md) for its auto-connect links.

If the script picked a different host port, use that port instead.

## Validation

1. Health reports `"status": "Healthy"`:

```
curl http://localhost:56301/health
curl http://localhost:56401/health
```

2. REST returns rows, including by composite key:

```
curl "http://localhost:56301/api/OrderDetails?$first=5"
curl http://localhost:56401/api/OrderDetails/OrderID/10248/ProductID/11
```

3. GraphQL:

```
curl -X POST http://localhost:56301/graphql -H "Content-Type: application/json" -d "{\"query\":\"{ categories(first: 3) { items { CategoryID CategoryName } } }\"}"
```

4. MCP: open an auto-connect link from the [MCP Inspector README](./mcp-inspector/README.md), then choose **Tools > List Tools**.

## Bruno Tests

The Bruno collection is in [`Testing\MsDab\PilotApiMsDab`](../Testing/MsDab/PilotApiMsDab). No IDP token or `.env` file is needed.

| Folder | Covers |
| --- | --- |
| `System` | `/health` |
| `Rest` | For each entity: list, get by key (composite key for OrderDetails), `$first` paging, and following `nextLink`. `Queries` covers `$filter`, `$select`, `$orderby`, and a key that does not exist. |
| `GraphQL` | One paged query per entity |
| `Mcp` | `initialize`, `tools/list`, and a `describe_entities` tool call over Streamable HTTP |

The tests only read data, so they can be rerun at any time.

Run them with the other Pilot API collections, which writes a combined HTML report under `Testing\BrunoReports`:

```
..\Testing\RunBrunoTests.bat
```

Or run only this collection:

```
cd ..\Testing\MsDab\PilotApiMsDab
npx --yes @usebruno/cli run -r --env "Docker - SQL Server"
npx --yes @usebruno/cli run -r --env "Docker - PostgreSQL"
```

To use the Bruno app, open the `PilotApiMsDab` folder as a collection and select an environment.

The environments use ports 56301 and 56401. If the builder picked other ports, update `environments\*.yml`.

## Manual Commands (Equivalent)

Run from this folder after the configs have been generated:

```bat
set "MSDAB_MSSQL_PORT=56301"
set "MSDAB_POSTGRES_PORT=56401"
set "MSDAB_INSPECTOR_PORT=56501"
docker compose -f docker-compose.api-msdab.yml -p pilot-api-msdab --env-file ..\secrets\ms-dab.env up -d --force-recreate
```

Always pass `--env-file`, including for `down`, `restart`, and `logs`. Without it, Compose stops because the required secrets are not set.

## Troubleshooting

- **The script stops because `local-mssql` or `local-postgres` is not running.** Start it with `docker start <name>`, or run its builder script.
- **"Data API builder CLI 2.0.12 is not installed".** Run the install or update command the script prints.
- **`dab validate` fails.** Check that the database is reachable on `localhost:1433` or `localhost:5432`, the passwords in `ms-dab.env` are correct, and the Northwind data is loaded.
- **A container does not become healthy.** The script prints its last 50 log lines. For more:

```
docker compose -f docker-compose.api-msdab.yml -p pilot-api-msdab --env-file ..\secrets\ms-dab.env logs --tail 200
```

- **MCP Inspector auto-connect does nothing.** The `autoConnect` value must equal `MCP_INSPECTOR_API_TOKEN`, and the page must be opened at `http://localhost:<port>` or `http://127.0.0.1:<port>` (other origins get HTTP 403).
- **MCP Inspector cannot connect.** The server URL must use the container name (`http://pilot-api-msdab-mssql:5000/mcp`), not `localhost`. The Inspector connects from its own container, not from the browser.
- **Swagger or GraphQL UI returns 404.** The config is not in development mode. Rerun the builder.

## Adding Authentication Later

DAB is anonymous for now. To use the existing Keycloak realm, run `dab configure` in the builder script with `--runtime.host.authentication.provider` set to a JWT provider, plus `--runtime.host.authentication.jwt.issuer` (`http://local-keycloak:8080/realms/local-realm`) and `--runtime.host.authentication.jwt.audience`. Then replace `anonymous:*` with role-based permissions (for example `authenticated:read`). The Bruno collection would then need the same OAuth2 settings as the other Pilot API collections.

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.api-msdab.yml -p pilot-api-msdab --env-file ..\secrets\ms-dab.env restart
```

2. Stop and remove this stack (cleanup):

```
docker compose -f docker-compose.api-msdab.yml -p pilot-api-msdab --env-file ..\secrets\ms-dab.env down --remove-orphans
```

3. Remove the images as well:

```
docker image rm mcr.microsoft.com/azure-databases/data-api-builder:2.0.12 ghcr.io/modelcontextprotocol/inspector:2.8.0
```

4. Uninstall the DAB CLI:

```
dotnet tool uninstall -g Microsoft.DataApiBuilder
```
