# Docker - Setup - OTEL

[OTEL](https://opentelemetry.io) OpenTelemetry observability stack for local development.

## Batch File

This folder includes `Docker-Otel-builder.bat`, which prepares and starts a local LGTM stack:

- OpenTelemetry Collector
- Grafana Tempo
- Grafana Mimir
- Grafana Loki
- Grafana

What the batch does:

1. Pulls required container images.
2. Stops any existing OTEL compose stack for this folder.
3. Starts a fresh stack using `docker-compose.otel.yml`.
4. Waits for Grafana health endpoint to respond.
5. Attempts best-effort Grafana limited-user provisioning (non-fatal if not allowed).
6. Opens Grafana in the default browser.

## Prerequisites

- Docker Desktop installed and running.
- Docker Compose available via `docker compose`.
- Local Docker network `pilot-net` exists (referenced by compose file).

## Usage

From the `Otel` folder:

```bat
Docker-Otel-builder.bat
```

Or from repository root:

```bat
Otel\Docker-Otel-builder.bat
```

After start, open:

- Grafana: http://localhost:3000

## Notes

- If Grafana user provisioning cannot run due to permissions or existing persisted state, the script continues and the stack still starts.
- If you use persisted Grafana volumes, admin credentials can differ from compose environment values from previous runs.

## References

OpenTelemetry:

- https://opentelemetry.io/docs
- https://oneuptime.com/blog/post/2026-02-06-build-local-lgtm-stack-opentelemetry-development/view
- https://learn.microsoft.com/en-us/dotnet/core/diagnostics/observability-with-otel

Grafana:

- https://grafana.com/docs/grafana/latest/

Loki:

- https://grafana.com/docs/loki/latest/

Mimir:

- https://grafana.com/docs/mimir/latest/

Tempo:

- https://grafana.com/docs/tempo/latest/
