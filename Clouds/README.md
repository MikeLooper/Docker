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

1. Creates the `pilot-net` network if it does not exist.
2. Pulls the three images.
3. Stops any existing `local-clouds` compose stack, and removes leftover console sidecars (`floci-aws-ui`, `floci-az-local-azure-ui`).
4. Starts a fresh stack using `docker-compose.clouds.yml`.
5. Waits for each emulator's health endpoint (up to 2 minutes each):
   - AWS: `http://localhost:4566/_localstack/health`
   - Azure: `http://localhost:4577/_floci/health`
   - GCP: `http://localhost:4588/health`
6. Opens the AWS console, the Azure console, and the GCP info page in the default browser.

All containers use `restart: unless-stopped`, so they start automatically when Docker starts unless you stopped them yourself.

## Prerequisites

- Docker Desktop installed and running.
- Docker Compose available via `docker compose`.
- Local Docker network `pilot-net` (created by the batch file if missing).

## Usage

From the `Clouds` folder:

```bat
Docker-clouds-builder.bat
```

Or from repository root:

```bat
Clouds\Docker-clouds-builder.bat
```

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
