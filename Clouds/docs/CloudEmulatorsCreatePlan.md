# Cloud Emulators – Implementation Plan

Plan for adding local AWS, Azure, and GCP emulators (Floci family) to this repository under `Clouds\`.

## 1. Goal

Add a builder script, `Clouds\Docker-clouds-builder.bat`, that deploys three emulator containers as one Docker Compose project:

| Subject | Container name | Image | API port (host:container) | Web console |
| --- | --- | --- | --- | --- |
| AWS   | `local-aws`   | `floci/floci:latest`     | `4566:4566` | `http://localhost:4566/_floci/ui` → redirects to `http://localhost:4500/` |
| Azure | `local-azure` | `floci/floci-az:latest`  | `4577:4577` | `http://localhost:4577/_floci/ui` → redirects to `http://localhost:4501/console/azure` |
| GCP   | `local-gcp`   | `floci/floci-gcp:latest` | `4588:4588` | None upstream. The info endpoint `http://localhost:4588/_floci-gcp/info` is opened instead |

- Compose project (parent) name: `local-clouds`
- Network: `pilot-net` (external, shared with the other stacks)

Sources:
- AWS: https://github.com/floci-io/floci (docs: https://floci.io/floci)
- Azure: https://github.com/floci-io/floci-az (docs: https://floci.io/floci-az)
- GCP: https://github.com/floci-io/floci-gcp (docs: https://floci.io/floci-gcp)

## 2. Decisions

| Topic | Decision |
| --- | --- |
| Host ports | Upstream defaults: AWS 4566, Azure 4577, GCP 4588. The AWS console stays on 4500 and the Azure console moves to **4501** (`FLOCI_AZ_UI_PORT`), because both default to 4500. |
| GCP "console" | floci-gcp has no web UI. The script opens `/_floci-gcp/info` as the GCP browser page. |
| Persistence | `hybrid` storage mode (async flush about every 5 s) with Docker named volumes. |
| Image tag | `:latest`, matching the other builders. |

## 3. Facts from upstream docs that shape the design

- **No secrets are required.** None of the three emulators needs an account, token, API key, or license key. AWS accepts any non-empty key and secret (`test`/`test` by convention). Azure does not validate SharedKey; it documents the well-known public dev-storage account `devstoreaccount1`. GCP needs no credentials and defaults to project `floci-local`. → **No `secrets\clouds-<subject>.env` files will be created.** The README will document the client settings. If secrets are added later (for example by enabling S3 auth enforcement or GCP IAM enforcement), they will follow the pattern `secrets\clouds-aws.env` / `clouds-aws.env.example`, and so on.
- **Web consoles are on-demand sidecar containers.** AWS and Azure start the console only on the first request to `/_floci/ui`. They launch it through the Docker socket, then redirect the browser. The sidecar container is created outside the Compose project:
  - AWS sidecar: Default name: `floci-aws-ui`. Joined to `pilot-net` with `FLOCI_SERVICES_UI_DOCKER_NETWORK`.
  - Azure sidecar: Default name: `floci-az-ui`. Azure removes a leftover sidecar on its own.
  - Both stop when their parent emulator stops (`*_KEEP_RUNNING_ON_SHUTDOWN=false`, the default).
- **Docker socket mount (`/var/run/docker.sock`) is required** for the consoles and for Docker-backed services: AWS Lambda/RDS/ECS, Azure Functions, and GCP Cloud Run/Cloud SQL/GKE/BigQuery. Several containers can mount the socket at once without conflict: it is a client connection to the Docker daemon's API, not an exclusive binding like a host port. The Dozzle stack already mounts it, and Dozzle will also show the emulator and sidecar logs. Sidecar name collisions between the emulators are avoided with each emulator's resource namespace setting where one exists (`FLOCI_AZ_DOCKER_RESOURCE_NAMESPACE`, `FLOCI_GCP_DOCKER_RESOURCE_NAMESPACE`; the AWS docs list none). AWS's documented `docker run` also uses `-u root` for socket access, so that is mirrored with `user: root`.
- **Health checks:**
  - AWS: `GET /_localstack/health` (LocalStack-compatible).
  - Azure: no documented health endpoint. Poll the API port until any HTTP response comes back (`curl -s -o nul`, without `-f`).
  - GCP: `GET /health`.

## 4. Files to create or modify

| # | File | Action |
| --- | --- | --- |
| 1 | `Clouds\docker-compose.clouds.yml` | **Create** |
| 2 | `Clouds\Docker-clouds-builder.bat` | **Create** |
| 3 | `Clouds\README.md` | **Create** |
| 4 | `README.md` (root) | **Modify** |
| 5 | `Docker-StartAll.bat` | **Modify** |

`secrets\` stays unchanged because no secrets are required (see §3).

### 4.1 `Clouds\docker-compose.clouds.yml`

Follows the `Otel\docker-compose.otel.yml` pattern: Compose-first, `container_name`, `mem_limit`, `restart: unless-stopped`, named volumes, and external `pilot-net`.

```yaml
# Local cloud emulators (Floci): AWS, Azure, GCP

services:
  local-aws:
    image: floci/floci:latest
    container_name: local-aws
    mem_limit: 2g
    restart: unless-stopped
    user: root
    environment:
      - FLOCI_STORAGE_MODE=hybrid
      - FLOCI_STORAGE_PERSISTENT_PATH=/app/data
      - FLOCI_SERVICES_UI_CONTAINER_NAME=floci-aws-ui
      - FLOCI_SERVICES_UI_PORT=4500
      - FLOCI_SERVICES_UI_DOCKER_NETWORK=pilot-net
    volumes:
      - local-aws-data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "4566:4566"   # AWS API (all services)
    networks:
      - pilot-net

  local-azure:
    image: floci/floci-az:latest
    container_name: local-azure
    mem_limit: 2g
    restart: unless-stopped
    environment:
      - FLOCI_AZ_STORAGE_MODE=hybrid
      - FLOCI_AZ_STORAGE_PATH=/app/data
      - FLOCI_AZ_UI_PORT=4501
      - FLOCI_AZ_DOCKER_RESOURCE_NAMESPACE=local-azure
    volumes:
      - local-azure-data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "4577:4577"   # Azure API (all HTTP services)
    networks:
      - pilot-net

  local-gcp:
    image: floci/floci-gcp:latest
    container_name: local-gcp
    mem_limit: 2g
    restart: unless-stopped
    environment:
      - FLOCI_GCP_STORAGE_MODE=hybrid
      - FLOCI_GCP_STORAGE_PERSISTENT_PATH=/app/data
      - FLOCI_GCP_SERVICES_DOCKER_NETWORK=pilot-net
      - FLOCI_GCP_DOCKER_RESOURCE_NAMESPACE=local-gcp
    volumes:
      - local-gcp-data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "4588:4588"   # GCP APIs (gRPC + REST)
    networks:
      - pilot-net

volumes:
  local-aws-data:
  local-azure-data:
  local-gcp-data:

networks:
  pilot-net:
    external: true
    name: pilot-net
```

Notes:
- Only the main API port of each emulator is published. Secondary protocol ports (AWS 8182/27017/5672, Azure 5672/5673/9093/9042/8182) are omitted at first, to avoid collisions with each other and with future RabbitMQ or Kafka stacks. The README will explain how to add them.
- `FLOCI_HOSTNAME` / `FLOCI_AZ_HOSTNAME` / `FLOCI_GCP_HOSTNAME` are left **unset**. Returned resource URLs, such as SQS queue URLs and blob endpoints, then point to `localhost`, which suits host-side development and the IDE. Containers on `pilot-net` can still reach the APIs at `http://local-aws:4566` and the other service names. The README will note this trade-off.
- `mem_limit` is set to 2g as a starting point and can be adjusted during verification.

### 4.2 `Clouds\Docker-clouds-builder.bat`

Structure mirrors `Otel\Docker-Otel-builder.bat` (`@echo off`, `setlocal EnableExtensions DisableDelayedExpansion`, `pushd "%~dp0"`, `REM` numbered steps).

```text
@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds (AWS / Azure / GCP emulators)

pushd "%~dp0"

set "PARTITION_NAME=local-clouds"
set "COMPOSE_FILE=%~dp0docker-compose.clouds.yml"
set "IMAGE_FILE_AWS=floci/floci:latest"
set "IMAGE_FILE_AZURE=floci/floci-az:latest"
set "IMAGE_FILE_GCP=floci/floci-gcp:latest"
set "AWS_PORT=4566"
set "AZURE_PORT=4577"
set "GCP_PORT=4588"

REM 1. Ensure the shared network exists.
docker network inspect pilot-net >nul 2>&1 || docker network create pilot-net

REM 2. Download the images.
docker pull ... (x3)

REM 3. Stop any prior compose services for this stack, and remove stale console sidecars.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" down --remove-orphans
docker rm -f floci-aws-ui floci-az-ui >nul 2>&1

REM 4. Start containers with Compose.
docker compose -f "%COMPOSE_FILE%" -p "%PARTITION_NAME%" up -d --force-recreate
(fail with message + exit /b 1 on error)

REM 5. Wait for each emulator to become ready (call :wait_for_url, 60 x 2s).
call :wait_for_url "AWS"   "http://localhost:%AWS_PORT%/_localstack/health"  strict
call :wait_for_url "Azure" "http://localhost:%AZURE_PORT%/"                    any
call :wait_for_url "GCP"   "http://localhost:%GCP_PORT%/health"              strict

popd

REM 6. Display the consoles in the browser.
start http://localhost:%AWS_PORT%/_floci/ui
start http://localhost:%AZURE_PORT%/_floci/ui
start http://localhost:%GCP_PORT%/_floci-gcp/info

goto :eof

:wait_for_url
REM "strict" = curl -sSf (HTTP 2xx/3xx); "any" = curl -s -o nul (any HTTP response)
...loop with timeout /t 2 /nobreak; on timeout echo "<name> did not become ready in time." and exit /b 1
```

Implementation details:
- Pass `-p "%PARTITION_NAME%"` to **both** `down` and `up`. The Otel script omits it on `down`, so its `down` targets a differently named project.
- `--build` is not needed because all images are prebuilt.
- Each wait failure is fatal (`exit /b 1`), as in the Otel script.
- Use `curl.exe` explicitly, as in the Otel script, so a PowerShell alias cannot intercept it.

### 4.3 `Clouds\README.md`

Follows the `Otel\README.md` style. Sections:

1. **Title and intro.** What Floci is: free, MIT-licensed, credential-free local emulators of AWS, Azure, and GCP. Links to the three GitHub repos and doc sites.
2. **Containers.** Table of name, image, port, console URL, and data volume.
3. **Batch File.** What `Docker-clouds-builder.bat` does, step by step.
4. **Prerequisites.** Docker Desktop, `docker compose`, and the `pilot-net` network (created automatically).
5. **Usage.** Run from `Clouds\` or from the repo root.
6. **Web consoles.** Explain the on-demand sidecars (`floci-aws-ui` on 4500, `floci-az-ui` on 4501). Explain that GCP has no console and the info and health endpoints are listed instead.
7. **Connecting clients:**
   - AWS: `AWS_ENDPOINT_URL=http://localhost:4566`, `AWS_DEFAULT_REGION=us-east-1`, `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, and a sample `aws s3 mb s3://demo`.
   - Azure: the dev-storage connection string (`devstoreaccount1` with Blob/Queue/Table endpoints on 4577), and a note that any key works.
   - GCP: `PUBSUB_EMULATOR_HOST`, `FIRESTORE_EMULATOR_HOST`, `DATASTORE_EMULATOR_HOST`, `STORAGE_EMULATOR_HOST`, `SECRET_MANAGER_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, and `GOOGLE_CLOUD_PROJECT=floci-local`.
   - From other containers on `pilot-net`: `http://local-aws:4566`, `http://local-azure:4577`, `http://local-gcp:4588`.
8. **Supported services.** A short per-cloud summary with links to the upstream service lists.
9. **Persistence.** Hybrid mode, the named volumes, how to reset (`docker compose -p local-clouds down -v`, or GCP `POST /_floci-gcp/state/reset`).
10. **Notes.** Hostname and returned-URL trade-off, optional extra protocol ports, Docker-socket security caveat (the containers can control the Docker daemon; `:ro` does not restrict API calls; `tecnativa/docker-socket-proxy` is the optional hardening path), and Testcontainers modules.
11. **Secrets.** None required. If enforcement modes are enabled later, secrets go in `secrets\clouds-<subject>.env`.

### 4.4 Root `README.md`

- **Compose Files:** add `Clouds\docker-compose.clouds.yml` in alphabetical order.
- **Builder Scripts:** add `Clouds\Docker-clouds-builder.bat` in alphabetical order.
- **Active Subjects:** add a `### Cloud Emulators (AWS / Azure / GCP)` section with a one-line description and the link `Follow the directions in the [Clouds README](./Clouds/README.md).`, placed alphabetically before Dozzle.
- **Docker Containers and Ports table:** add the following rows:

| Status: | Type: | Name: | Inner Port: | Outer Port: | URL |
| --- | --- | --- | --- | --- | --- |
| √ | AWS Emulator (Floci) | local-aws | 4566 | 4566 | http://localhost:4566/_floci/ui |
| √ | AWS Console (sidecar) | floci-aws-ui | 4500 | 4500 | http://localhost:4500 |
| √ | Azure Emulator (Floci) | local-azure | 4577 | 4577 | http://localhost:4577/_floci/ui |
| √ | Azure Console (sidecar) | floci-az-ui | 4500 | 4501 | http://localhost:4501/console/azure |
| √ | GCP Emulator (Floci) | local-gcp | 4588 | 4588 | http://localhost:4588/_floci-gcp/info |

### 4.5 `Docker-StartAll.bat`

Add a block after Keycloak and before the Pilot APIs, so that APIs which later depend on cloud services start after the emulators:

```bat
ECHO .
ECHO Start AWS emulator ...
docker start local-aws

ECHO .
ECHO Start Azure emulator ...
docker start local-azure

ECHO .
ECHO Start GCP emulator ...
docker start local-gcp
```

The console sidecars are not started here. They are created on demand when `/_floci/ui` is first opened.

## 5. Verification steps

1. Run `Clouds\Docker-clouds-builder.bat` from a clean state. It should exit 0, and three browser tabs should open: the AWS console, the Azure console, and the GCP info JSON.
2. Run `docker ps --filter "label=com.docker.compose.project=local-clouds"`. It should show `local-aws`, `local-azure`, and `local-gcp`.
3. Run `docker network inspect pilot-net`. All three containers, plus `floci-aws-ui`, should be attached.
4. Smoke tests:
   - AWS: `aws --endpoint-url http://localhost:4566 s3 mb s3://demo`, then `s3 ls`.
   - Azure: an HTTP request to the blob endpoint with the dev connection string, for example via Azure Storage Explorer or `az storage container create --connection-string ...`.
   - GCP: `curl http://localhost:4588/health`.
5. Persistence: create a resource, run `docker restart local-aws`, then confirm the resource still exists. Repeat for Azure and GCP.
6. Re-run the builder script to confirm it is idempotent: no name conflicts, and the stale-sidecar cleanup works. Check with `docker ps -a` whether the namespace settings change the sidecar container names (for example, whether `floci-az-ui` gets a `local-azure` prefix). If they do, update the `docker rm -f` cleanup line and the README ports table to match.
7. Run `Docker-StartAll.bat` after `docker stop local-aws local-azure local-gcp`. All three should start.

## 6. Out of scope (possible follow-ups)

- Homepage and Uptime Kuma entries for the three emulators.
- A root-level `Clouds-builder.lnk` shortcut (`.lnk` files are git-ignored and created by hand).
- Publishing secondary protocol ports (AMQP, Kafka, Cassandra, Gremlin, MongoDB).
- Wiring the Pilot APIs to use the emulated cloud services.

## 7. Constraints

If Docker is nt orunning or is not available for some other reason, stop processing and notify the user.
