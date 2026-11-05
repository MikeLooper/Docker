# Docker - Setup - Clouds

Local emulators for AWS, Azure, and GCP, provided by the [Floci](https://floci.io) family of projects.
Floci emulators are free, MIT-licensed, and need no accounts, tokens, or license keys.

| Cloud | GitHub | Docs |
| ----- | ------ | ---- |
| AWS   | https://github.com/floci-io/floci     | https://floci.io/floci     |
| Azure | https://github.com/floci-io/floci-az  | https://floci.io/floci-az  |
| GCP   | https://github.com/floci-io/floci-gcp | https://floci.io/floci-gcp |

## Containers

All three run as one Docker Compose project named `local-clouds`, on the shared `pilot-net` network.

| Cloud | Container     | Image                    | Port | Console / browser page                  | Data volume                   |
| ----- | ------------- | ------------------------ | ---- | --------------------------------------- | ----------------------------- |
| AWS   | `local-aws`   | `floci/floci:latest`     | 4566 | http://localhost:4566/_floci/ui         | `local-clouds_local-aws-data`   |
| Azure | `local-azure` | `floci/floci-az:latest`  | 4577 | http://localhost:4577/_floci/ui         | `local-clouds_local-azure-data` |
| GCP   | `local-gcp`   | `floci/floci-gcp:latest` | 4588 | http://localhost:4588/_floci-gcp/info   | `local-clouds_local-gcp-data`   |

## Batch File

This folder includes `Docker-clouds-builder.bat`, which prepares and starts the emulators.

What the batch does:

1. Validates `-platform` (`all` by default; `aws`, `azure` or `gcp` for one cloud).
2. Creates the `pilot-net` network if it does not exist.
3. Pulls the selected images.
4. `all`: stops any existing `local-clouds` compose stack and removes leftover console sidecars (`floci-aws-ui`, `floci-az-local-azure-ui`).
   One cloud: for each other cloud, runs its `Docker-clouds-<cloud>-dbapi-builder.bat -destroy` (when it has Terraform state and its emulator is running), then stops that emulator and its sidecar.
5. Starts the selected emulators using `docker-compose.clouds.yml`.
6. Waits for each emulator's health endpoint (up to 2 minutes each):
   - AWS: `http://localhost:4566/_localstack/health`
   - Azure: `https://localhost:4577/_floci/health` (self-signed TLS; the CA certificate is saved to `terraform\tls\floci-az.pem`)
   - GCP: `http://localhost:4588/health`
7. Saves the selection in `Clouds\.platform` and opens the consoles of the selected emulators in the default browser.

All containers use `restart: unless-stopped`, so they start automatically when Docker starts unless you stopped them yourself.

## Prerequisites

- Docker Desktop installed and running.
- Docker Compose available via `docker compose`.
- Local Docker network `pilot-net` (created by the batch file if missing).

## Usage

From the `Clouds` folder:

```bat
Docker-clouds-builder.bat
Docker-clouds-builder.bat -platform aws
```

Or from repository root:

```bat
Clouds\Docker-clouds-builder.bat
```

### Starting and stopping one cloud

Once a cloud has been built, use its start and stop scripts day to day (`<cloud>` is `aws`, `azure` or `gcp`). From the `Clouds` folder:

```bat
REM Stop the AWS emulator and everything it manages (nothing is deleted)
Docker-clouds-aws-stop.bat

REM Start it again; if an API does not answer, the AWS dbapi builder is re-run to repair it
Docker-clouds-aws-start.bat

REM Start it again, but only report unhealthy APIs (exit code 1) instead of rebuilding
Docker-clouds-aws-start.bat -norebuild
```

The Azure and GCP scripts work the same way:

```bat
Docker-clouds-azure-stop.bat
Docker-clouds-azure-start.bat
Docker-clouds-gcp-stop.bat
Docker-clouds-gcp-start.bat
```

Or from repository root:

```bat
Clouds\Docker-clouds-aws-start.bat
Clouds\Docker-clouds-aws-stop.bat
```

- The start script only works for a cloud allowed by `Clouds\.platform`. For example, after `-platform aws`, `Docker-clouds-azure-start.bat` stops with an error. Run `Docker-clouds-builder.bat -platform azure` (or `all`) first.
- If nothing is deployed yet, the start script starts the emulator and tells you to run `Docker-clouds-<cloud>-dbapi-builder.bat`.
- On success, it prints the API base URLs.
- GCP: after a stop, SQL Server comes back empty. Use plain `Docker-clouds-gcp-start.bat`; with `-norebuild`, the three SQL Server APIs are reported as unhealthy.

See [Start and stop](#start-and-stop) for what each script does.

## Web Consoles

The AWS and Azure consoles are separate sidecar containers that the emulators create on demand, through the Docker socket, the first time `/_floci/ui` is opened. The emulator shows a "starting" page, then sends the browser to the console.

| Cloud | Sidecar container         | Console URL                          |
| ----- | ------------------------- | ------------------------------------ |
| AWS   | `floci-aws-ui`            | http://localhost:4500                |
| Azure | `floci-az-local-azure-ui` | http://localhost:4501/console/azure  |

- Both consoles listen on 4500 inside their containers, so Azure's is published on **4501** (`FLOCI_AZ_UI_PORT`).
- The Azure sidecar name includes the resource namespace (`FLOCI_AZ_DOCKER_RESOURCE_NAMESPACE=local-azure`).
- The sidecars are created outside the Compose project, and stop when their parent emulator stops.

GCP has no web console. Use these endpoints instead:

- Info: http://localhost:4588/_floci-gcp/info
- Health (per-service status): http://localhost:4588/health

AWS and Azure also expose a JSON info page at `/_floci/info`.

## Databases and APIs

The emulators also host the Northwind databases (SQL Server and PostgreSQL) and the six Pilot APIs (DotNet, Java, Python; a SQL Server and a PostgreSQL variant of each). Every cloud resource is created with Terraform. The full design is in [docs/CloudEmulatorsDbAndApi.md](docs/CloudEmulatorsDbAndApi.md).

| Cloud | SQL Server | PostgreSQL | API compute | API front door |
| ----- | ---------- | ---------- | ----------- | -------------- |
| AWS   | RDS `sqlserver-se` | RDS `postgres` | ECS (Fargate) | API Gateway HTTP API (v2), VPC link + Cloud Map |
| Azure | Azure SQL (managed data plane) | Flexible Server | Container Apps | Container Apps ingress (APIM not usable, see below) |
| GCP   | Compute Engine + SQL Server container | Cloud SQL | Cloud Run | Cloud Run service URL |

### Scripts

| Script | What it does |
| ------ | ------------ |
| `Docker-clouds-builder.bat [-platform all\|aws\|azure\|gcp]` | Starts the emulators. A single platform first destroys the other clouds' databases and APIs (while their emulators can still clean up), then stops those emulators. The choice is saved in `Clouds\.platform` (git-ignored); `Docker-StartAll.bat` starts only the selected emulators. |
| `Docker-clouds-api-images-builder.bat` | Builds the 6 images `cloud-api-<lang>-<db>:1.0` once, for all clouds. Runs the unit tests. The images hold **no** database or security settings; each cloud injects them as env vars (`terraform\modules\api-env`). Checks at the end that no password, `DB_URL`, `appsettings.Production.json` or `.env` is in any image. |
| `Docker-clouds-<cloud>-dbapi-builder.bat [-destroy]` | Applies `terraform\<cloud>\10-databases`, loads Northwind (`scripts\load-mssql.bat`, `scripts\load-postgres.bat`), applies the API roots, then waits for every `/healthcheck` and calls `GET /v1/customers/get-all` with a Keycloak token (expects data) and without one (expects 401). `-destroy` removes everything that cloud's builder created. |

Order: `Docker-clouds-builder.bat -platform <cloud>`, then `Docker-clouds-api-images-builder.bat` (once, or after API source changes), then `Docker-clouds-<cloud>-dbapi-builder.bat`.

Prerequisites: `secrets\clouds-db.env` (from `secrets\clouds-db.env.example`), and `local-keycloak` and `otel-collector` running. Terraform runs in the `hashicorp/terraform` image; nothing is installed on the host.

### Layout

```text
Clouds\terraform\apis.json              the 6 APIs (drives every for_each)
Clouds\terraform\modules\api-env\       per-language env vars (DB, Keycloak, OTEL)
Clouds\terraform\<cloud>\10-databases\  DB servers; outputs mssql_host/port, postgres_host/port
Clouds\terraform\<cloud>\20-apis\       API compute and front door
```

State is local (`terraform.tfstate` in each root, git-ignored). **It holds the DB passwords in plain text**; it stays on the local disk.

### Endpoints

| Cloud | API base URL (see the builder's output) | Databases from `pilot-net` / host |
| ----- | --------------------------------------- | --------------------------------- |
| AWS   | `http://<apiId>.execute-api.localhost.floci.io:4566` | `local-aws:7001` (SQL Server), `local-aws:7002` (PostgreSQL); the same ports on `localhost` |
| Azure | `http://<api-name>.cae-cloud-apis.<hash>.localhost:4577` | `floci-az-local-azure-sql-cloud-mssql:1433`, `floci-az-local-azure-pg-cloud-postgres:5432` |
| GCP   | `http://<api-name>-<token>.us-central1.run.localhost.floci.io:4588` | `floci-gcp-local-gcp-compute-floci-local-us-central1-a-mssql-vm:1433` (SQL Server); Cloud SQL container IP, port 5432 (`terraform output` in `gcp\10-databases`) |

`*.localhost.floci.io` resolves to `127.0.0.1` in public DNS. Logins: `DevUser` with `CLOUD_DB_DEVUSER_PASSWORD`. Traces appear in Grafana/Tempo as `<cloud>-cloud-api-*`, with `cloud.provider` set.

### Emulator behaviour worth knowing

- **SQL Server admin login.** On AWS RDS and Azure SQL, Floci applies the admin password to the engine's `sa` login; the master login (`cloudadmin`) exists but has no server rights. The loader therefore falls back to `sa` (and leaves it enabled). On GCP, `sa` is disabled after `DevUser` is created, as the local builder does.
- **GCP Cloud SQL admin login** is fixed at `postgres`/`postgres` in floci-gcp, whatever root password is sent.
- **GCP VM name.** The SQL Server VM is named `mssql-vm` (not `cloud-mssql`): floci-gcp names its container `floci-gcp-local-gcp-compute-<project>-<zone>-<instance>`, and Docker DNS only resolves names up to 63 characters. floci-gcp's machine-type catalogue has only `e2-standard-2`, `n2-standard-4/8`, `c3-standard-4` and `g2-*`; `e2-standard-2` (8 GB) is used. The `cos-stable` boot image is not in its image catalogue and falls back to `debian:12`, which is fine because SQL Server runs from the container declaration.
- **Azure TLS.** `local-azure` runs with `FLOCI_AZ_TLS_ENABLED=true` because the azurerm provider requires HTTPS. Port 4577 still answers plain HTTP as well. `Docker-clouds-builder.bat` saves the CA certificate to `terraform\tls\floci-az.pem`; clients using HTTPS must trust it (`/_floci/tls-cert`).
- **Azure front door: Container Apps ingress, not APIM.** floci-az's APIM gateway forwards no client headers to the backend, so the `Authorization` header never reaches the APIs and every secured call returns 401 (it also cannot reach a Container App by name). Container Apps ingress on port 4577 routes by `Host` header and passes headers through. `FLOCI_AZ_SERVICES_CONTAINER_APPS_DNS_SUFFIX=localhost` makes the app FQDNs end in `.localhost`, which browsers and `curl` resolve to `127.0.0.1`. Use plain HTTP for these URLs (the TLS certificate's `*.localhost` covers one label only).
- **Secrets.** ECS task definitions and Cloud Run services carry the DB password as a plain env var (Cloud Run secrets are not emulated); Container Apps use a secret reference. Dev-only stack.
- **The databases are owned by the loader**, not Terraform, so they do not appear in the RDS / ARM / Cloud SQL database listings.

### Start and stop

| Script | What it does |
| ------ | ------------ |
| `Docker-clouds-<cloud>-stop.bat` | Stops `local-<cloud>` first (so it cannot replace containers), then every container it manages: databases, APIs, console. Deletes nothing; data, images and Terraform state are kept. `local-keycloak` and the OTEL stack keep running. |
| `Docker-clouds-<cloud>-start.bat [-norebuild]` | Starts `local-keycloak` and the OTEL stack if needed, then `local-<cloud>`, then any of its managed containers that are still stopped. If the cloud is deployed, it checks every API (health + authenticated data probe). When an API does not answer, it re-runs `Docker-clouds-<cloud>-dbapi-builder.bat`, which repairs the databases and reloads Northwind; with `-norebuild` it only reports. |

`<cloud>` is `aws`, `azure` or `gcp`. The scripts respect `Clouds\.platform`, as the builders do. The shared code is `scripts\cloud-lifecycle.bat`.

### Restarts (what the emulators do)

After `docker restart local-<cloud>` or a host reboot, use `Docker-clouds-<cloud>-start.bat` (or re-run that cloud's dbapi builder). `Docker-StartAll.bat` only starts the selected emulators; it does not re-apply Terraform or check the APIs.

- **AWS:** after `docker restart local-aws` the RDS containers and new ECS tasks came back on their own, data intact, and the gateways answered. But Floci leaves the old tasks' network interfaces behind, which blocks deleting the subnets on `-destroy`; the builder then drops the VPC and subnets from the Terraform state with a warning.
- **GCP:** after `docker restart local-gcp`, Cloud Run and Cloud SQL came back, but the SQL Server container (`<vm>_klt`) did not. The GCP builder detects this and replaces the VM (`-replace=google_compute_instance.mssql`), then reloads Northwind. After a stop/start, the VM's SQL Server comes back empty (no persistent disk), so `Docker-clouds-gcp-start.bat` re-runs the builder.
- **Azure:** after `docker restart local-azure` the Container Apps replicas came back, but the SQL Server and PostgreSQL data-plane containers did not (`/connect` reports not ready / port 0). The Azure builder detects this and replaces both servers (`terraform apply -replace=...`), then reloads Northwind.

## Connecting Clients

None of the emulators validate credentials. Any non-empty value works.

### AWS

```bat
set AWS_ENDPOINT_URL=http://localhost:4566
set AWS_DEFAULT_REGION=us-east-1
set AWS_ACCESS_KEY_ID=test
set AWS_SECRET_ACCESS_KEY=test

aws s3 mb s3://demo
aws s3 ls
```

### Azure

Storage uses the well-known development account `devstoreaccount1`. Blob, Queue, and Table each have their own path on port 4577:

```
DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://localhost:4577/devstoreaccount1;QueueEndpoint=http://localhost:4577/devstoreaccount1-queue;TableEndpoint=http://localhost:4577/devstoreaccount1-table;
```

The SharedKey signature is not validated, so any key works. Example:

```bat
az storage container create --name demo --connection-string "<connection string above>"
```

Defaults reported by `/_floci/info`: subscription `00000000-0000-0000-0000-000000000001`, tenant `00000000-0000-0000-0000-000000000002`, location `eastus`.

### GCP

```bat
set GOOGLE_CLOUD_PROJECT=floci-local
set PUBSUB_EMULATOR_HOST=localhost:4588
set FIRESTORE_EMULATOR_HOST=localhost:4588
set DATASTORE_EMULATOR_HOST=localhost:4588
set STORAGE_EMULATOR_HOST=http://localhost:4588
set SECRET_MANAGER_EMULATOR_HOST=localhost:4588
set FIREBASE_AUTH_EMULATOR_HOST=localhost:4588
```

### From other containers on `pilot-net`

- AWS: `http://local-aws:4566`
- Azure: `http://local-azure:4577`
- GCP: `http://local-gcp:4588`

## Supported Services

- **AWS:** S3, SQS, SNS, DynamoDB, Lambda, IAM, STS, KMS, Secrets Manager, CloudWatch, and many more. See the [Floci AWS docs](https://floci.io/floci).
- **Azure:** Blob, Queue, Table, Cosmos DB, Key Vault, Service Bus, Event Hubs, Event Grid, Functions, App Configuration, ARM, Entra, and more. See the [Floci Azure docs](https://floci.io/floci-az).
- **GCP:** Cloud Storage, Pub/Sub, Firestore, Datastore, Secret Manager, KMS, IAM, BigQuery, Cloud Run, Cloud Functions, Cloud SQL, GKE, and more. See the [Floci GCP docs](https://floci.io/floci-gcp).

## Persistence

Each emulator runs in `hybrid` storage mode: state is kept in memory and flushed to its named volume about every 5 seconds. State survives `docker restart` and re-runs of the batch file.

To reset everything (removes the data volumes):

```bat
docker compose -f Clouds\docker-compose.clouds.yml -p local-clouds down -v
```

To reset only GCP state while it is running:

```bat
curl.exe -X POST http://localhost:4588/_floci-gcp/state/reset
```

## Notes

- **Returned URLs use `localhost`.** `FLOCI_HOSTNAME`, `FLOCI_AZ_HOSTNAME`, and `FLOCI_GCP_HOSTNAME` are not set, so URLs returned by the emulators (for example SQS queue URLs and blob endpoints) point to `localhost`. This suits clients running on the host. Containers on `pilot-net` can still call `http://local-aws:4566` and so on, but may need to rewrite returned URLs. Set the hostname variables to the container names if container clients become the main use.
- **Only the main API ports are published.** Secondary protocol ports are not published, to avoid collisions with each other and with future RabbitMQ or Kafka stacks. To use them, add them to `ports:` in `docker-compose.clouds.yml`:
  - AWS: 8182 (Neptune/Gremlin), 27017 (DocumentDB/MongoDB), 5672 (AMQP)
  - Azure: 5672 / 5673 (Service Bus AMQP), 9093 (Event Hubs Kafka), 9042 (Cosmos Cassandra), 8182 (Cosmos Gremlin)
- **Docker socket.** All three containers mount `/var/run/docker.sock` so they can start the consoles and Docker-backed services (AWS Lambda/RDS/ECS, Azure Functions, GCP Cloud Run/Cloud SQL/GKE/BigQuery). This gives them full control of the Docker daemon. Mounting the socket `:ro` does not restrict API calls. For hardening, put a filtering proxy such as `tecnativa/docker-socket-proxy` in front of it.
- **Testcontainers.** Floci provides Testcontainers modules for use in automated tests. See the upstream docs.
- Logs for the emulators and the console sidecars are visible in [Dozzle](../Dozzle/README.md).

## Secrets

None are required. If enforcement modes are enabled later (for example S3 auth enforcement or GCP IAM enforcement), put the values in `secrets\clouds-<subject>.env` (for example `secrets\clouds-aws.env`), with a committed `secrets\clouds-<subject>.env.example` template.
