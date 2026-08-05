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
mkdir C:\Working\Storage\Dev\GitHub\Working
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

## SQL Server

A Microsoft SQL Server database installation.

Follow the directions in the [SQL Server README](.\SqlServer\README-SqlServer.md)

## PostgreSQL

A PostgreSQL database installation.

Follow the directions in the [PostgreSQL README](.\PostgreSQL\README-PostgreSQL.md).

## Pilot API (DotNet)

A .NET Core API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (DotNet) README](.\Api_dotnet\README-Api-dotnet.md).

## Pilot API (Java)

A Java Spring Boot API that presents data from the Northwind database (MS SQL Server or PostgreSQL)

Follow the directions in the [API (Java) README](.\Api_java\README-Api-java.md).

## Dozzle

A real time Docker log viewer or partition logs.

Follow the directions in the [Dozzle README](.\Dozzle\README-Dozzle.md).

## Uptime Kuma

Simple up or down checks and status pages for monitoring Docker partitions/applications, and other sources.

Follow the directions in the [Uptime Kuma README](.\UptimeKuma\README-UptimeKuma.md).

## Jaeger ‡

Natively supports OTLP to receive trace data.

Follow the directions in the [Jaeger README](.\README-Jaeger.md).

## Prometheus ‡

Send your metric data to Prometheus.

Follow the directions in the [Prometheus README](.\README-Prometheus.md).

## Zipkin ‡

A distributed tracing system. It helps gather timing data needed to troubleshoot latency problems in service architectures. Features include both the collection and lookup of this data.

Follow the directions in the [Zipkin README](.\README-Zipkin.md).

‡ = Future addition
