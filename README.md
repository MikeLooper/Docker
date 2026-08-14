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

- `SqlServer\docker-compose.sqlserver.yml`
- `PostgreSQL\docker-compose.postgresql.yml`
- `Api_dotnet\docker-compose.api-dotnet.yml`
- `Api_java\docker-compose.api-java.yml`

## Builder Scripts

- `SqlServer\Docker-SQLServer-builder.bat`
- `PostgreSQL\Docker-PostgreSQL-builder.bat`
- `Api_dotnet\Docker-Api-dotnet-builder.bat`
- `Api_java\Docker-Api-java-builder.bat`
- `Dozzle\Docker-Dozzle-builder.bat`
- `UptimeKuma\Docker-UptimeKuma-builder.bat`

Each script is the primary entry point for its stack and is kept aligned with its corresponding README.

On Windows, the API builder scripts for .NET and Java automatically probe and select open host ports
within predefined ranges when preferred ports are reserved or in use.

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

## Active Subjects

### SQL Server

A Microsoft SQL Server database installation.

Follow the directions in the [SQL Server README](./SqlServer/README.md)

### PostgreSQL

A PostgreSQL database installation.

Follow the directions in the [PostgreSQL README](./PostgreSQL/README.md).

### Pilot API (DotNet)

A .NET Core API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (DotNet) README](./Api_dotnet/README.md).

### Pilot API (Java)

A Java Spring Boot API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (Java) README](./Api_java/README.md).

### Dozzle

A real time Docker log viewer or partition logs.

Follow the directions in the [Dozzle README](./Dozzle/README.md).

### Uptime Kuma

Simple up or down checks and status pages for monitoring Docker partitions/applications, and other sources.

Follow the directions in the [Uptime Kuma README](./UptimeKuma/README.md).

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

| Status: | Type:                   | Name:                       | Inner Port: | Outer Port: |
| ------- | ----------------------- | --------------------------- | ----------- | ----------- |
|         | SQL Server              | local-mssql                 | 1433        | 1433        |
|         | PostgreSQL              | local-postgres              | 5432        | 5432        |
|         | ApiDotNet (SQL Server)  | pilot-api-dotnet-mssql      | 8080        | 55501       |
|         | ApiDotNet (PostgreSQL)  | pilot-api-dotnet-postgres   | 8080        | 55601       |
|         | ApiJava (SQL Server)    | pilot-api-java-mssql        | 8080        | 56601       |
|         | ApiJava (PostgreSQL)    | pilot-api-java-postgres     | 8080        | 56701       |
| TBD     | ApiUtility (SQL Server) | utility-api-dotnet-mssql    | 8080        | 58501       |
| TBD     | ApiUtility (PostgreSQL) | utility-api-dotnet-postgres | 8080        | 58601       |
| TBD     | ApiPython (SQL Server)  | pilot-api-python-mssql      | 8080        | 57601       |
| TBD     | ApiPython (PostgreSQL)  | pilot-api-python-postgres   | 8080        | 57701       |
| TBD     | Angular UI              | pilot-ui                    | ???         | ???         |
| TBD     | Jaeger                  | local-jaeger                | 4317        | 4317        |
| TBD     | Prometheus              | local-prometheus            | 9464        | 9464        |
| TBD     | Zipkin                  | local-zipkin                | 9411        | 9411        |
| TBD     | Grafana                 | local-grafana               | 3000        | 3000        |
|         | Dozzle                  | local-dozzle                | 8080        | 51101       |
| TBD     | Komodo                  | local-komodo                | 9120        | 9120        |
|         | Uptime Kuma             | local-uptimekuma            | 3001        | 3001        |
| TBD     | Homer                   | local-homer                 | 8080        | 51201       |
| TBD     | Bitwarden               | local-bitwarden             | ???         | ???         |
| TBD     | Duplicati               | local-duplicati             | 8200        | 8200        |
| TBD     | Keycloak                | local-keycloak              | ???         | ???         |
| TBD     | GO Feature Flag         | local-gofeatureflag         | ???         | ???         |
