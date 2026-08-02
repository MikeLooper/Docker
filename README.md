# Docker

Setup and usages for Docker, and how it can be used with local development and testing.

## Install

Install and set up Docker on your local PC.

Docker documentation:
- [Download and Install](https://docs.docker.com/desktop/setup/install/windows-install/)
- [Get Started](https://www.docker.com/get-started/)
- [CheatSheet](https://docs.docker.com/get-started/docker_cheatsheet.pdf)

## Preparation

Open a command prompt and change to a working directory:
  
```
cd C:\Working\Storage\Dev\GitHub\Working
```
  
The docker CLI commands found in this, and related, READMEs will be executed in this command line window.

### Network

Create an internal network that will be shared by the different containers that need to communicate with one another.

```
docker network create pilot-net
```

## SQL Server

Follow the directions in the [SQL Server README](.\README-SqlServer.md)

## PostgreSQL

Follow the directions in the [PostgreSQL README](.\README-PostgreSQL.md).

## Pilot API (DotNet)

Follow the directions in the [API (DotNet) README](.\README-Api-dotnet.md).

## Pilot API (Java)

Follow the directions in the [API (Java) README](.\README-Api-java.md).

## Jaeger

Natively supports OTLP to receive trace data.

Follow the directions in the [Jaeger README](.\README-Jaeger.md).

## Prometheus

Send your metric data to Prometheus.

Follow the directions in the [Prometheus README](.\README-Prometheus.md).

## Zipkin

A distributed tracing system. It helps gather timing data needed to troubleshoot latency problems in service architectures. Features include both the collection and lookup of this data.

Follow the directions in the [Zipkin README](.\README-Zipkin.md).
