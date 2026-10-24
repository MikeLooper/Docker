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
|  √      | Angular UI              | pilot-ui                    | 4200        | 11301       | http://localhost:11801/ |
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
