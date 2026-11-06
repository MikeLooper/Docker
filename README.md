# Docker

Setup and usages for Docker, and how it can be used with local development and testing.

This repository now uses a Docker Compose-first process. Direct Docker CLI is still used only for operations that Compose does not replace well (for example, `dotnet publish`, `mvn package`, and `docker exec` SQL initialization commands).

## Install

Install and set up Docker on your local PC.

Docker documentation:
- [Download and Install](https://docs.docker.com/desktop/setup/install/windows-install/)
- [Get Started](https://www.docker.com/get-started/)
- [CheatSheet](https://docs.docker.com/get-started/docker_cheatsheet.pdf)

## Preparation

Open a command line window.
The commands found in this, and related, READMEs will be executed in this command line window.

Change to the current directory.
  
```
cd C:\Working\Storage\Dev\GitHub\Docker
```

Create a new working directory (if not already existing):

```
if not exist C:\Working\Storage\Dev\GitHub\Working mkdir C:\Working\Storage\Dev\GitHub\Working
```

Then, execute the networking command listed in the *Network* section below.

## Compose Files

- `Api_dotnet\docker-compose.api-dotnet.yml`
- `Api_java\docker-compose.api-java.yml`
- `Api_MsDab\docker-compose.api-msdab.yml`
- `Api_python\docker-compose.api-python.yml`
- `Api_python_with_claude\docker-compose.api-python-with-claude.yml`
- `Clouds\docker-compose.clouds.yml`
- `Homepage\docker-compose.homepage.yml`
- `PostgreSQL\docker-compose.postgresql.yml`
- `SqlServer\docker-compose.sqlserver.yml`
- `Ui_angular\docker-compose.ui-angular.yml`
- `Utility_dotnet\docker-compose.utility-dotnet.yml`

## Builder Scripts

- `Api_dotnet\Docker-Api-dotnet-builder.bat`
- `Api_java\Docker-Api-java-builder.bat`
- `Api_MsDab\Docker-Api-msdab-builder.bat`
- `Api_python\Docker-Api-python-builder.bat`
- `Api_python_with_claude\Docker-pythonapi-with-claude-builder.bat`
- `Clouds\Docker-clouds-builder.bat` (`-platform all|aws|azure|gcp`)
- `Clouds\Docker-clouds-api-images-builder.bat`
- `Clouds\Docker-clouds-aws-dbapi-builder.bat`
- `Clouds\Docker-clouds-azure-dbapi-builder.bat`
- `Clouds\Docker-clouds-gcp-dbapi-builder.bat`
- `Clouds\Docker-clouds-<cloud>-start.bat` / `Clouds\Docker-clouds-<cloud>-stop.bat` (`aws`, `azure`, `gcp`)
- `Dozzle\Docker-Dozzle-builder.bat`
- `Homepage\Docker-Homepage-builder.bat`
- `PostgreSQL\Docker-PostgreSQL-builder.bat`
- `SqlServer\Docker-SQLServer-builder.bat`
- `Ui_angular\Docker-Ui-angular-builder.bat`
- `UptimeKuma\Docker-UptimeKuma-builder.bat`
- `Utility_dotnet\Docker-Utility-dornet-builder.bat`

Each script is the primary entry point for its stack and is kept aligned with its corresponding README.

On Windows, the API builder scripts for .NET, Java, Python, Python with Claude, and Data API builder automatically probe and select open
host ports within predefined ranges when preferred ports are reserved or in use.

## Port Binding

Windows categorizes ports into distinct blocks:
- 0 – 1023 (Well-Known Ports): Reserved for core system protocols (e.g., HTTP 80, HTTPS 443, SMB 445). Avoid binding custom apps here unless building dedicated web infrastructure.
- 1024 – 49151 (Registered / User Ports): Partially used by third-party applications (like SQL Server on 1433). This is the best zone for custom bindings, provided you check for conflicts.
- 49152 – 65535 (Dynamic / Ephemeral Ports): The standard Windows 11 range for random outbound client connections and dynamic RPC systems. Do not use these for static custom bindings. Hyper-V, WSL2, and Windows clustering will dynamically seize blocks of 100+ ports in this range upon reboot, blocking your app with an Address already in use error.

### Port usage discovery
- To find host ports that are excluded from use by Windows:
```
netsh interface ipv4 show excludedportrange protocol=tcp
```
- To determine what application is currently using a port:
1. Execute this command:
```
netstat -ano > ports.txt
```
2. Examine ports.txt for the port you are researching, extract the related PID, then execute:
```
resmon.exe
```
3. Find the PID and extract the application name.

### Reserving

To force Windows to Exclude/Reserve Your Custom Port by adding an explicit Administered Port Exclusion, which will remain reserved even after you reboot your system:
```
powershell -Command "netsh int ipv4 add excludedportrange protocol=tcp startport=<YourPortNumber> numberofports=1 store=persistent"
```

### Checklist

Custom port binding checklist:
- Best choice: ports between 1024 – 49151.
- Never Use: any ports below 1024 or any ports above 49151.


## Secrets

Runtime secrets are now stored in separate local files under the `secrets/` directory.

- Template files (`*.env.example`) are committed.
- Local secret files (`*.env`) are ignored by git.

See [secrets/README.md](secrets/README.md) for setup details.

### Network

Create an internal network that will be shared by the different containers that need to communicate with one another (if not already existing).

```
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net
```

Read details about the new network:
```
docker network inspect pilot-net
```

## Active Subjects

### Cloud Emulators (AWS / Azure / GCP)

Local, credential-free emulators of AWS, Azure, and GCP services (Floci), for developing and testing cloud integrations without a cloud account.

Follow the directions in the [Clouds README](./Clouds/README.md).

After a cloud has been built, stop and start it (with its databases and APIs) using its own scripts. `<cloud>` is `aws`, `azure` or `gcp`:

```
Clouds\Docker-clouds-<cloud>-stop.bat
Clouds\Docker-clouds-<cloud>-start.bat
Clouds\Docker-clouds-<cloud>-start.bat -norebuild
```

- Stop: deletes nothing. Data, images and Terraform state are kept.
- Start: checks every API, and re-runs that cloud's dbapi builder if one does not answer.
- `-norebuild`: only reports unhealthy APIs, without rebuilding.

See [Starting and stopping one cloud](./Clouds/README.md#starting-and-stopping-one-cloud) for details.

To test the APIs deployed in a cloud emulator, see [Cloud emulator APIs](#cloud-emulator-apis).

### Dozzle

A real time Docker log viewer or partition logs.

Follow the directions in the [Dozzle README](./Dozzle/README.md).

### Homepage

A highly customizable homepage (or startpage / application dashboard) with Docker and service API integrations.

Follow the directions in the [Homepage README](./Homepage/README.md).

### Pilot API (DotNet)

A .NET Core API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (DotNet) README](./Api_dotnet/README.md).

### Pilot API (Java)

A Java Spring Boot API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (Java) README](./Api_java/README.md).

### Pilot API (Data API builder)

Microsoft Data API builder (DAB) serving REST, GraphQL, and MCP endpoints over the Northwind database (MS SQL Server or PostgreSQL), plus MCP Inspector.

Follow the directions in the [API (Data API builder) README](./Api_MsDab/README.md).

### Pilot API (Python)

A Python FastAPI application that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (Python) README](./Api_python/README.md).

### Python API with Claude

A Python FastAPI application (`PythonAPIWithClaude`) that answers questions by calling the Claude API. It does not use a database; it requires an `ANTHROPIC_API_KEY` in `secrets/api-python-with-claude.env` and sends telemetry to the OTEL collector. Its Bruno collection is included in `Testing\RunBrunoTests.bat`.

Follow the directions in the [API (Python with Claude) README](./Api_python_with_claude/README.md).

### Pilot UI (Angular)

An Angular single page application that presents the Northwind data from the Pilot APIs.

Follow the directions in the [UI (Angular) README](./Ui_angular/README.md).

### PostgreSQL

A PostgreSQL database installation.

Follow the directions in the [PostgreSQL README](./PostgreSQL/README.md).

### SQL Server

A Microsoft SQL Server database installation.

Follow the directions in the [SQL Server README](./SqlServer/README.md)

### Uptime Kuma

Simple up or down checks and status pages for monitoring Docker partitions/applications, and other sources.

Follow the directions in the [Uptime Kuma README](./UptimeKuma/README.md).

### Utility API (DotNet)

A .NET Core API that contain utility tooling (MS SQL Server or PostgreSQL)

Follow the directions in the [Utility (DotNet) README](./Utility_dotnet/README.md).

## Bruno Tests

The APIs hosted in this workspace are tested with [Bruno](https://www.usebruno.com/) collections. The scripts that run them, and their reports, are in the `Testing` folder.

| Script | Tests |
| ------ | ----- |
| `Testing\RunBrunoTests.bat` | The APIs running in local Docker containers, and PilotMcpServer |
| `Testing\RunBrunoCloudTests-aws.bat` | The Pilot APIs deployed in the AWS emulator |
| `Testing\RunBrunoCloudTests-azure.bat` | The Pilot APIs deployed in the Azure emulator |
| `Testing\RunBrunoCloudTests-gcp.bat` | The Pilot APIs deployed in the GCP emulator |

Prerequisites:

- Node.js. The scripts use the Bruno CLI (`bru`) if it is installed globally (`npm install -g @usebruno/cli`), otherwise they run it through `npx`.
- `local-keycloak` running. The collections get their bearer token from it, for both the Docker and the cloud APIs.
- A `.env` file in each collection folder, copied from its `.env.example`, with `IDP_HOST_PASSWORD` set.

### Collections

Most collections live in the repository of the API they test. Each Bruno environment points a collection at one deployment of its API.

| Collection | Location | Environments |
| ---------- | -------- | ------------ |
| PilotApiDotNet  | `PilotApiDotNet\test\Bruno\PilotApiDotNet`   | `Docker - SQL Server`, `Docker - PostgreSQL`, `AWS - ...`, `Azure - ...`, `GCP - ...`, `Local` |
| PilotApiJava    | `PilotApiJava\test\Bruno\PilotApiJava`       | `Docker - SQL Server`, `Docker - PostgreSQL`, `AWS - ...`, `Azure - ...`, `GCP - ...`, `Local` |
| PilotApiPython  | `PilotApiPython\tests\Bruno\PilotApiPython`  | `Docker - SQL Server`, `Docker - PostgreSQL`, `AWS - ...`, `Azure - ...`, `GCP - ...`, `Local` |
| PilotUtilityApi | `PilotUtilityApi\test\Bruno\PilotUtilityApi` | `Docker - SQL Server`, `Docker - PostgreSQL`, `Local` |
| PilotApiMsDab   | `Docker\Testing\MsDab\PilotApiMsDab`         | `Docker - SQL Server`, `Docker - PostgreSQL` |
| PythonAPIWithClaude | `PythonAPIWithClaude\tests\Bruno\PythonAPIWithClaude` | `Docker`, `Local` |
| PilotMcpServer  | `PilotMcpServer\tests\Bruno`                 | One per Pilot API deployment (`dotnet-mssql`, `java-postgres`, ...) |

Paths outside `Docker\` are relative to `C:\Working\Storage\Dev\GitHub`. Each cloud has a `SQL Server` and a `PostgreSQL` environment (for example `AWS - SQL Server`), which test `cloud-api-<lang>-mssql` and `cloud-api-<lang>-postgres` in that emulator.

### Docker APIs

```
Testing\RunBrunoTests.bat
Testing\RunBrunoTests.bat PostgreSQL
Testing\RunBrunoTests.bat PostgreSQL PilotApiDotNet
Testing\RunBrunoTests.bat McpServer
```

Runs every collection against the Docker containers, in this order: `Docker - PostgreSQL`, `Docker - SQL Server`, `Docker`, then PilotMcpServer once per Pilot API deployment. The first argument selects one environment (`PostgreSQL`, `SqlServer`, `Docker`, `McpServer` or one MCP deployment) and the second one collection. The containers must already be running. `RunBrunoTests.lnk` in the repository root starts the full run.

### Cloud emulator APIs

```
Testing\RunBrunoCloudTests-aws.bat
Testing\RunBrunoCloudTests-azure.bat PilotApiJava
Testing\RunBrunoCloudTests-gcp.bat -norebuild
```

Each script tests the six Pilot APIs deployed in one emulator:

1. Starts the emulator with `Clouds\Docker-clouds-<cloud>-start.bat`. That script checks every API and, if one does not answer, re-runs the cloud's dbapi builder to repair it. With `-norebuild` it only reports the problem, and the tests are skipped.
2. Runs PilotApiDotNet, PilotApiJava and PilotApiPython against `<Cloud> - SQL Server`, then `<Cloud> - PostgreSQL`.
3. Stops the emulator with `Clouds\Docker-clouds-<cloud>-stop.bat`. This step always runs, even when step 1 or 2 failed.

An optional argument selects one collection (`PilotApiDotNet`, `PilotApiJava` or `PilotApiPython`). The APIs must have been deployed once with `Clouds\Docker-clouds-<cloud>-dbapi-builder.bat` (see [Databases and APIs](./Clouds/README.md#databases-and-apis)). Otherwise every collection is reported as `NOT_DEPLOYED`.

The cloud API URLs change whenever an API is redeployed (AWS API ids, the Azure environment hash, the GCP Cloud Run token). The script therefore reads them from the Terraform state (output `api_base_urls` in `Clouds\terraform\<cloud>\20-apis`) and passes each one to Bruno as `--env-var Host=<url>/`. The `Host` values in the `<Cloud> - ...` environment files are only the last known URLs, for use in the Bruno app. After a redeploy, copy the current URLs from the start script's output.

The shared code is `Testing\scripts\RunBrunoCloudTests.bat`. It builds the summary report with the report code in `Testing\RunBrunoTests.bat`, so both kinds of run produce the same report.

### Reports

Each run writes to its own folder under `Testing\BrunoReports` (git-ignored): `<yyyyMMdd_HHmmss>` for `RunBrunoTests.bat`, `<yyyyMMdd_HHmmss>_<cloud>` for the cloud scripts. The folder holds:

- `Summary.html`: every collection run, with request, test and assertion totals and the failures of each request. It opens in the default browser when the run ends.
- `<Collection>_<Tag>.html`, `.json` and `.xml`: the Bruno HTML, JSON and JUnit reports of one run.
- `runs.txt`: the list of runs that the summary is built from.
- Cloud runs only: `api-urls.txt`, the API base URLs that were tested.

The exit code is `0` when every collection passed, and `1` otherwise.

## Future Subjects

### Jaeger

Natively supports OTLP to receive trace data.

Follow the directions in the [Jaeger README](./Future/README-Jaeger.md).

### Prometheus

Send your metric data to Prometheus.

Follow the directions in the [Prometheus README](./Future/README-Prometheus.md).

### Zipkin

A distributed tracing system. It helps gather timing data needed to troubleshoot latency problems in service architectures. Features include both the collection and lookup of this data.

Follow the directions in the [Zipkin README](./Future/README-Zipkin.md).

### Redis

Redis provides solutions for caching

Follow the directions in the [Redis README](./Future/README-Redis.md).

## Docker Containers and Ports

| Status: | Type:                   | Name:                       | Inner Port: | Outer Port: | URL |
| ------- | ----------------------- | --------------------------- | ----------- | ----------- | --- |
|  √      | Angular UI              | pilot-ui                    | 8080        | 11801      | http://localhost:11801/ |
|  √      | ApiDotNet (SQL Server)  | pilot-api-dotnet-mssql      | 8080        | 11001       | http://localhost:11001/swagger, http://localhost:11001/scalar |
|  √      | ApiDotNet (PostgreSQL)  | pilot-api-dotnet-postgres   | 8080        | 11101       | http://localhost:11101/swagger, http://localhost:11101/scalar |
|  √      | ApiJava (SQL Server)    | pilot-api-java-mssql        | 8080        | 11201       | http://localhost:11201/swagger-ui/index.html |
|  √      | ApiJava (PostgreSQL)    | pilot-api-java-postgres     | 8080        | 11301       | http://localhost:11301/swagger-ui/index.html |
|  √      | ApiMsDab (SQL Server)   | pilot-api-msdab-mssql       | 5000        | 11151       | http://localhost:11151/swagger, http://localhost:11151/graphql |
|  √      | ApiMsDab (PostgreSQL)   | pilot-api-msdab-postgres    | 5000        | 11161       | http://localhost:11161/swagger, http://localhost:11161/graphql |
|  √      | MCP Inspector (DAB)     | pilot-msdab-mcp-inspector   | 6274        | 11171       | http://localhost:11171/ |
|  √      | ApiPython (SQL Server)  | pilot-api-python-mssql      | 8000        | 11401       | http://localhost:11401/docs, http://localhost:11401/redoc |
|  √      | ApiPython (PostgreSQL)  | pilot-api-python-postgres   | 8000        | 11501       | http://localhost:11501/docs, http://localhost:11501/redoc |
|  √      | ApiPythonWithClaude     | python-api-with-claude      | 11111       | 11111       | http://localhost:11111/docs, http://localhost:11111/health |
|  √      | ApiUtility (SQL Server) | utility-api-dotnet-mssql    | 8080        | 11601       | http://localhost:11601/swagger, http://localhost:11601/scalar |
|  √      | ApiUtility (PostgreSQL) | utility-api-dotnet-postgres | 8080        | 11701       | http://localhost:11701/swagger, http://localhost:11701/scalar |
|  √      | AWS Emulator (Floci)    | local-aws                   | 4566        | 4566        | http://localhost:4566/_floci/ui |
|  √      | AWS Console (sidecar)   | floci-aws-ui                | 4500        | 4500        | http://localhost:4500   |
|  √      | AWS RDS proxy (cloud DBs) | local-aws                 | 7001-7010   | 7001-7010   | SQL Server 7001, PostgreSQL 7002 (see [Clouds README](./Clouds/README.md#databases-and-apis)) |
|  √      | Azure Emulator (Floci)  | local-azure                 | 4577        | 4577        | https://localhost:4577/_floci/ui (self-signed TLS; HTTP also answers) |
|  √      | Azure Console (sidecar) | floci-az-local-azure-ui     | 4500        | 4501        | http://localhost:4501/console/azure |
|  √      | GCP Emulator (Floci)    | local-gcp                   | 4588        | 4588        | http://localhost:4588/_floci-gcp/info |
|  √      | Dozzle                  | local-dozzle                | 8080        | 11121       | http://localhost:11121  |
|  √      | Grafana                 | local-grafana               | 3000        | 3000        | http://localhost:3000   |
|  √      | Homepage                | local-homepage              | 3000        | 11131       | http://localhost:11131  |
|  √      | PostgreSQL              | local-postgres              | 5432        | 5432        |                         |
|  √      | SQL Server              | local-mssql                 | 1433        | 1433        |                         |
|  √      | Uptime Kuma             | local-uptimekuma            | 3001        | 3001        | http://localhost:3001   |
| TBD     | Komodo                  | local-komodo                | 9120        | 9120        |                         |
| TBD     | Bitwarden               | local-bitwarden             | ???         | ???         |                         |
| TBD     | Duplicati               | local-duplicati             | 8200        | 8200        |                         |
| TBD     | Keycloak                | local-keycloak              | ???         | ???         |                         |
| TBD     | GO Feature Flag         | local-gofeatureflag         | ???         | ???         |                         |
