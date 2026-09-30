# Microsoft Data API builder (DAB) Deploy Builder

## Introduction

Create a Windows batch script in the `Docker-Api-msdab-builder.bat` file that will use the Microsoft Data API builder (DAB) against two existing databases (SQL Server and PostgreSQL) and deploy to Docker containers.

The result must fit the existing Pilot stack in this repository: same conventions, same shared network, same secrets handling, and same test runner as the other `Api_*` builders.

## Example

The `Api_dotnet\Docker-Api-dotnet-builder.bat` batch file demonstrates how a similar build process (without the DAB) was accomplished with a different application. Reuse its conventions:
- `setlocal EnableExtensions DisableDelayedExpansion`, `pushd "%~dp0"` / `popd`.
- The `:resolve_open_port` subroutine, so a reserved or in-use host port falls back to the next free port instead of breaking startup.
- `docker compose -f ... down --remove-orphans` before `up -d --force-recreate`, with an explicit project name (`-p pilot-api-msdab`).
- Check `errorlevel` after every step that can fail, print a clear message, and `exit /b 1`.
- Finish by opening the health endpoints in the browser.

The database connection details are **not** in that batch file. They come from these sources:
- Host, port, and user: `secrets\appsettings-api-dotnet-sqlserver.env.example` and `secrets\appsettings-api-dotnet-postgresql.env.example`.
- Database names: `SqlServer\Docker-SQLServer-builder.bat` (`NorthWind`) and `PostgreSQL\Docker-PostgreSQL-builder.bat` (`northwind`).

| Database | Host (container name on `pilot-net`) | Port | Database | User |
| --- | --- | --- | --- | --- |
| SQL Server | local-mssql | 1433 | NorthWind | DevUser |
| PostgreSQL | local-postgres | 5432 | northwind | DevUser |

SQL Server connection strings must include `TrustServerCertificate=True` (the container uses a self-signed certificate).

## Specifications

The new Docker containers will match the following definitions:
| Database | Name | Inner Port | Outer Port |
| --- | --- | --- | --- |
| SQL Server | pilot-api-msdab-mssql | 5000 | 56301 |
| PostgreSQL | pilot-api-msdab-postgres | 5000 | 56401 |
| (MCP Inspector UI) | pilot-msdab-mcp-inspector | 6274 | 56501 |
| (MCP Inspector proxy) | pilot-msdab-mcp-inspector | 6277 | 56502 |

- Use the official image `mcr.microsoft.com/azure-databases/data-api-builder`, pinned to a specific version tag (not `latest`). The version must support MCP (`--mcp.enabled`, DAB 1.7 or later). Use the same version of the `dab` CLI to generate the configs.
- Set `ASPNETCORE_URLS=http://+:5000` so DAB listens on the inner port.
- Apply `mem_limit: 1g` to each container, matching the other APIs.
- Add a Compose `healthcheck` against DAB's `/health` endpoint.
- The containers join the existing external network; they do not start or depend on the database containers. The batch script must check that `local-mssql` and `local-postgres` are running and stop with a clear message if not.

The DAB would be initialized with the following flags:
| Flag | Value |
| --- | --- |
| --database-type | [mssql OR postgresql] |
| --host-mode | Development (see note) |
| --connection-string | `@env('DATABASE_PASSWORD')`-based string built from the table above |
| --rest.enabled | true |
| --graphql.enabled | true |
| --mcp.enabled | true |
| --permissions (on each `dab add`) | "anonymous:*" |

> **Host mode note:** DAB serves Swagger UI (`/swagger`) and the GraphQL playground only in `Development` mode. The README quick links require them, so use `Development`. If `Production` is required instead, drop the Swagger and GraphQL playground links from the README and state why.

> `--permissions` is a `dab add` option, not a `dab init` option. Apply it to every entity.

Database tables that will be available in the APIs are:
- Categories
- Customers
- Employees
- [choose one based upon the database]:
	- SQL Server => Order Details
	- PostgreSQL => OrderDetails
- Orders
- Products
- Shippers
- Suppliers

Entity rules:
- Use the same entity names in both configs (`Categories`, `Customers`, `Employees`, `OrderDetails`, `Orders`, `Products`, `Shippers`, `Suppliers`) so REST paths, GraphQL types, and Bruno tests are the same for both databases. Only the `--source` differs.
- SQL Server `Order Details` has a space in its name: use `--source "dbo.[Order Details]"` and the entity name `OrderDetails`. Its primary key is composite (`OrderID`, `ProductID`).
- PostgreSQL tables were created without quoted identifiers, so their real names are lowercase. Use lowercase sources (for example `pilot.orderdetails`, `pilot.customers`).
- Only these tables are exposed. Do not expose views, stored procedures, or other tables.
- Add relationships (for example Orders → OrderDetails, Products → Categories) only if they don't complicate validation. They are optional.

The database schema used will depend upon the database:
- SQL Server: dbo
- PostgreSQL: pilot

The Docker shared network is called `pilot-net`.

Runtime settings for both configs:
- Enable CORS for the Angular UI (`Ui_angular`) and Homepage origins, or `*` for local use. Say which one you chose in the README.
- Keep the DAB default pagination, and write the page size into the README so tests don't assume that every row comes back.
- Optional: send OpenTelemetry to the existing `otel-collector` on `pilot-net` (see `Otel\otel-collector.yaml` for the OTLP endpoint and port), so DAB appears in the existing Grafana stack. The service name must be `pilot-api-msdab-mssql` or `pilot-api-msdab-postgres`.

## Reference Material

Use these docs during implementation:
- DAB CLI reference: https://learn.microsoft.com/azure/data-api-builder/command-line/
- `dab init`: https://learn.microsoft.com/azure/data-api-builder/command-line/dab-init
- `dab add`: https://learn.microsoft.com/azure/data-api-builder/command-line/dab-add
- `dab validate`: https://learn.microsoft.com/azure/data-api-builder/command-line/dab-validate
- `dab start`: https://learn.microsoft.com/azure/data-api-builder/command-line/dab-start
- DAB MCP overview: https://learn.microsoft.com/azure/data-api-builder/mcp/overview
- DAB configuration: https://learn.microsoft.com/azure/data-api-builder/configuration/
- DAB in Docker: https://learn.microsoft.com/azure/data-api-builder/deployment/how-to-run-container
- MCP Inspector: https://github.com/modelcontextprotocol/inspector

If the docs contradict this prompt (for example about flag names or the MCP endpoint path), follow the docs and list the differences in the final summary.

## Tasks

1. Create this structure under the `Api_MsDab` directory:
- `Docker-Api-msdab-builder.bat` (currently empty) that builds the stack.
- `docker-compose.api-msdab.yml` for both DAB services and the MCP Inspector.
- `data-api/dab-config.mssql.json` and `data-api/dab-config.postgres.json`. Each DAB container needs its own config because `data-source` is set once per config file.
- `mcp-inspector/README.md` with the auto-connect URLs for both DAB instances.
- `README.md` with prerequisites, run, validation, troubleshooting, and cleanup steps. It should also include quick links to REST, GraphQL, Swagger, health, and MCP Inspector for both instances. Follow the style of `Api_dotnet\README.md`.

2. Create a `ms-dab.env` file, in the `secrets` directory, for sensitive values.
- Also create `secrets\ms-dab.env.example` with placeholder values, and add both files to the list in `secrets\README.md`.
- `secrets/*.env` is already git-ignored. Confirm that `ms-dab.env` is ignored and that `ms-dab.env.example` is not.

3. Handle secrets first. Use `DATABASE_PASSWORD`. Never print secret values. Use `@env('DATABASE_PASSWORD')`, in the database connection string, within each DAB config file. Avoid `$` in Docker Compose passwords because Compose treats `$` as variable interpolation.
- Pass the file to the containers with `env_file: ../secrets/ms-dab.env`. Do not copy secrets into the working directory or bake them into an image.
- If the SQL Server and PostgreSQL passwords differ, use `MSSQL_DATABASE_PASSWORD` and `POSTGRES_DATABASE_PASSWORD` in the env file, and map each one to `DATABASE_PASSWORD` in its service's `environment:` block.
- The batch script must fail early with a clear message if `secrets\ms-dab.env` is missing.
- The committed config files must not contain passwords.

4. Use Docker Compose, not raw `docker run`, for the project. Containers must talk by service name, not `localhost`. Mount each DAB config read-only at `/App/dab-config.json` in its container.

5. Config generation in the batch script:
- Check that the `dab` CLI is installed (`dotnet tool list -g`). If it is missing, print the install command (`dotnet tool install -g Microsoft.DataApiBuilder --version <pinned>`) and exit.
- Generate both config files with `dab init` and `dab add`. This makes the script the source of truth for the configs, and a rerun overwrites them.
- Run `dab validate` on each config before `docker compose up`. `dab validate` connects to the database, so set `DATABASE_PASSWORD` for that process only (read it from `secrets\ms-dab.env` without echoing it) and point the connection at the host-exposed database ports. Keep the service names in the committed configs.
- After `up`, wait for each container's `/health` to report healthy, with a timeout, before opening browser links.

6. Add MCP Inspector with the auto-connect URL. Use Streamable HTTP.
- Run it in Docker on `pilot-net` (for example a `node` image running `npx @modelcontextprotocol/inspector` with a pinned version) so its proxy can reach DAB by service name: `http://pilot-api-msdab-mssql:5000/mcp` and `http://pilot-api-msdab-postgres:5000/mcp`.
- Set `HOST=0.0.0.0`, and set `ALLOWED_ORIGINS` or the equivalent so the browser UI on port 56501 is accepted.
- Proxy authentication: disabling it is acceptable for local use only (`DANGEROUSLY_OMIT_AUTH=true`). Document this in the README.
- The auto-connect URL format is `http://localhost:56501/?transport=streamable-http&serverUrl=<encoded MCP URL>&MCP_PROXY_PORT=56502`. Verify this against the pinned Inspector version.

7. In the `Testing\MsDab` directory create Bruno tests, similar to those found in `C:\Working\Storage\Dev\GitHub\PilotApiDotNet\test\Bruno`, to validate the DAB endpoints.
- Use the same OpenCollection format (`opencollection.yml`) and environment names that `RunBrunoTests.bat` expects: `Docker - PostgreSQL` (`Host` = `http://localhost:56401/`) and `Docker - SQL Server` (`Host` = `http://localhost:56301/`).
- Coverage: `/health`; REST for every entity (list, get by key including the composite key on `OrderDetails`, `$filter`, `$select`, `$orderby`, `$first` paging with `nextLink`); one GraphQL query per entity; one MCP call (`tools/list`) over Streamable HTTP.
- Do not change data. Only include create, update, and delete tests if each one cleans up after itself, so that runs can be repeated.
- No IDP token is needed (anonymous permissions). Don't add an `.env` file unless one is required.
- Include the execution of these new Bruno tests in the `Testing\RunBrunoTests.bat` file by adding one `:RunCollection "PilotApiMsDab" "%~dp0MsDab\<collection folder>"` line in `:RunEnvironment`. Make no other changes to the script.
- Include directions on using these tests in the README file.

8. Integrate with the rest of the repo:
- Add `docker start` lines for the three new containers to `Docker-StartAll.bat`, after the databases.
- Add Homepage entries in `Homepage\services.yaml`, following the existing API entries (REST link plus a status check against `/health` using the container name on `pilot-net`).
- Add the new builder and ports to the root `README.md` wherever the other APIs are listed.

## Acceptance Criteria

The work is done when all of these are true:
- A clean run of `Docker-Api-msdab-builder.bat` (with both databases running) exits with code 0, and three containers are running on `pilot-net`.
- `http://localhost:56301/health` and `http://localhost:56401/health` report healthy.
- `GET /api/OrderDetails` returns rows on both instances.
- MCP Inspector auto-connects to both instances and lists DAB's tools.
- `Testing\RunBrunoTests.bat` runs the MsDab collection in both environments, and it passes.
- `git status` shows no secret values in tracked files.
- Rerunning the builder is safe: the stack is recreated with no leftover containers and no errors.

## Out of Scope

- Keycloak or JWT authentication for DAB (anonymous only for now). Mention in the README how to add it later with the `authentication` section in the config and the existing Keycloak realm.
- Custom Docker images for DAB. Use the official image with a mounted config.
