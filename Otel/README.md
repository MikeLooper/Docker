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

## Interactions

To work with the different containers directly, there are APIs that can be accessed via CURL.

### Loki

#### API Documentation

https://grafana.com/docs/loki/latest/reference/loki-http-api/

#### Select Commands

List the version:

```bash
curl -s http://localhost:3100/loki/api/v1/status/buildinfo
```

List labels:

Should return a `data` element with an array of labels.
If that element is missing, there are no records.

```bash
curl -G -s --data-urlencode "since=3h" http://localhost:3100/loki/api/v1/labels
```

List records:

Replace `docker` with a label.

```bash
curl -G -s http://localhost:3100/loki/api/v1/query_range" --data-urlencode 'query={job="service_name"}'
```

### Mimir

#### API Documentation

https://grafana.com/docs/mimir/latest/references/http-api/

#### Select Commands

List the version:

```bash
curl http://localhost:9009/api/v1/status/buildinfo
```

List metrics:

```bash
curl -G -s http://localhost:9009/metrics
```

### Tempo

#### API Documentation

https://grafana.com/docs/tempo/latest/api_docs/

#### Select Commands

List the version:
```bash
curl http://localhost:3200/status/version
```

List Tags:
```bash
curl -G -s http://localhost:3200/api/search/tags?scope=span
```

### Grafana

#### API Documentation

https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/

#### Select Commands

List the version:
```bash
curl http://localhost:3000/api/health
```

List dashboards:
```bash
curl -G -s http://localhost:3000/apis/dashboard.grafana.app/v1/namespaces/default/dashboards
```

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

### Troubleshooting

#### Port Tracing

When troubleshooting OTEL, you can check for port usages at the command line:
```
netstat -ano | findstr 4318
```

When working correctly, this will result in something similar to the following:
```
   Proto  Local Address          Foreign Address        State           PID
   ...
   TCP    0.0.0.0:4318           0.0.0.0:0              LISTENING       25384
   TCP    [::]:4318              [::]:0                 LISTENING       25384
   TCP    [::1]:4318             [::]:0                 LISTENING       46888
   TCP    [::1]:4318             [::1]:59028            TIME_WAIT       0
   ...
```

The start the command (via Win+R) the `resmon.exe` application.  Locate the PID, from the port listing, on the PID column.

Examples fro the above:
| PID | Application |
| --- | ----------- |
| 25384 | Docker Desktop Backend |
| 46888 | Windows Subsystem for Linux |
