# Cloud Emulators – Databases and APIs – Implementation Plan

This plan uses the Floci cloud emulators (`local-aws`, `local-azure`, `local-gcp`; see [CloudEmulatorsCreatePlan.md](CloudEmulatorsCreatePlan.md)) to host:

- the Northwind databases (SQL Server and PostgreSQL), and
- the Pilot APIs (DotNet, Java, Python; one SQL Server and one PostgreSQL variant of each).

Every cloud resource is created with Terraform. A `-platform` flag lets you run a single cloud, to keep memory use low (§6.2).

**Status:** executed and verified on 2026-11-05 (Floci 2.4.0, floci-az 0.16.0, floci-gcp 0.12.0). This document describes the design **as built**, so it can be executed again with the same result. Each place where execution differed from the first draft is marked **(as built)** and gives the reason; §15 lists them all.

**Ground rule for every phase:** if a spike point or a required capability fails, stop and report it to the user, with the alternatives listed in this plan. Do not silently switch to a different service, provider, or workaround.

## 1. Goal

### 1.1 Components per platform

| Platform | AWS (`local-aws`, Floci 2.4.0) | Azure (`local-azure`, floci-az 0.16.0) | GCP (`local-gcp`, floci-gcp 0.12.0) |
| --- | --- | --- | --- |
| API front door | API Gateway, **HTTP API (v2)**, VPC link + Cloud Map | **Container Apps ingress** (as built; APIM is not usable, §2.1) | Cloud Run (the service URL *is* the front door) |
| API compute | **ECS (Fargate)** | **Container Apps** | Cloud Run |
| SQL Server | Amazon RDS (`sqlserver-se`) | Azure SQL Database (managed data plane) | ⚠ **Not supported by Cloud SQL.** Uses **Compute Engine** with SQL Server instead (§2) |
| PostgreSQL | Amazon RDS (`postgres`) | Azure Database for PostgreSQL – Flexible Server | Cloud SQL for PostgreSQL |

### 1.2 Database loads (each SQL Server and each PostgreSQL instance, on every cloud)

| Database | Database name | Scripts, in order |
| --- | --- | --- |
| SQL Server | `NorthWind` | `SqlServer\Northwind.sql` → validate tables (≥ 13) → `SqlServer\customobjects.sql` |
| PostgreSQL | `northwind` (schema `pilot`) | `PostgreSQL\northwind.sql` → validate tables (≥ 13) → `PostgreSQL\customobjects.sql` → `PostgreSQL\reset-primary-keys.sql` |

This order matches `SqlServer\Docker-SQLServer-builder.bat` and `PostgreSQL\Docker-PostgreSQL-builder.bat`.

### 1.3 APIs (deployed on every cloud)

| API | SQL Server variant | PostgreSQL variant | Build steps reused from |
| --- | --- | --- | --- |
| DotNet | `cloud-api-dotnet-mssql` | `cloud-api-dotnet-postgres` | `Api_dotnet\Docker-Api-dotnet-builder.bat` |
| Java | `cloud-api-java-mssql` | `cloud-api-java-postgres` | `Api_java\Docker-Api-java-builder.bat` |
| Python | `cloud-api-python-mssql` | `cloud-api-python-postgres` | `Api_python\Docker-Api-python-builder.bat` |

In total: 3 clouds × (2 database servers + 6 APIs) = 6 database servers and 18 API deployments. With `-platform <cloud>`, only one cloud's 2 servers and 6 APIs run at a time.

## 2. Platform support problems

### 2.1 Azure API Management (as built: not used)

The Azure spike (§8) showed that floci-az's APIM gateway cannot front the APIs:

1. It cannot reach a Container App by name. The app FQDN does not resolve inside `local-azure`. The replica container name (about 76 characters) is longer than a DNS label allows. A `set-header Host` policy, needed to route through the Container Apps ingress, is refused ("restricted header name").
2. Pointed at a replica's IP address, APIM routes `/healthcheck` correctly. But it **forwards no client headers** (checked with a header-echo backend), so `Authorization` never reaches the APIs, and every secured call returns 401.

**Decision (user, 2026-11-05):** the Container Apps **ingress** is the Azure front door, as the Cloud Run URL is on GCP. Security stays active (D10).

### 2.2 GCP SQL Server

> **GCP Cloud SQL cannot host SQL Server in the emulator.**
> floci-gcp's Cloud SQL accepts only `POSTGRES_15`–`POSTGRES_18` and `MYSQL_8_0`/`MYSQL_8_4`. Any other engine is rejected with `400 INVALID_ARGUMENT`.

**Decision (accepted):** host SQL Server on GCP **Compute Engine**. A `google_compute_instance` with a `gce-container-declaration` runs `mcr.microsoft.com/mssql/server:2025-latest`. floci-gcp runs it as a real Docker container (`<vm>_klt`) when `FLOCI_GCP_SERVICES_COMPUTE_MOCK=false`.

Other notes on the API row:

- **AWS API Gateway only routes requests.** ECS (Fargate) runs the code behind it.
- **GCP:** floci-gcp has no API Gateway, Apigee, or Cloud Endpoints, so the Cloud Run service URLs are used directly.

## 3. Decisions

| # | Topic | Decision |
| --- | --- | --- |
| D1 | GCP SQL Server | Compute Engine + SQL Server container (§2.2). |
| D2 | API compute / front door | AWS: ECS Fargate behind API Gateway HTTP API (v2). **Azure: Container Apps, ingress as the front door (as built, §2.1).** GCP: Cloud Run. |
| D3 | Terraform runtime | The `hashicorp/terraform` Docker image, run by the builder `.bat` inside the emulator's network namespace. Nothing is installed on the host. |
| D4 | Delivery | **Phase 0** (shared pieces) → **Azure go/no-go spike** → **Phase 1** AWS → **Phase 2** Azure → **Phase 3** GCP → **Phase 4** start/stop scripts. Each cloud phase has its own Terraform roots and builder, makes its own emulator changes, and is verified on its own. |
| D5 | Extra SQL scripts | Match the local builders: also load `customobjects.sql`, plus `reset-primary-keys.sql` for PostgreSQL. |
| D6 | Credentials | `secrets\clouds-db.env`, with a committed `secrets\clouds-db.env.example`. |
| D7 | API images | Build 6 images once (`cloud-api-<lang>-<db>:1.0`) with **no baked config**: no settings files and no DB build args. Each cloud injects its connection settings as container env vars. |
| D8 | Layout | `Clouds\terraform\<cloud>\...`, `Clouds\Docker-clouds-<cloud>-dbapi-builder.bat`, `Clouds\Docker-clouds-api-images-builder.bat`, `Clouds\Docker-clouds-<cloud>-start.bat` / `-stop.bat`, and shared code in `Clouds\scripts\`. |
| D9 | Ownership of DB objects | **Terraform owns servers and instances. The loader owns databases and logins.** No Terraform resource creates `NorthWind`, `northwind`, or `DevUser`, so the loader's drop-and-recreate never conflicts with Terraform state. Trade-off: the databases do not appear in ARM / Cloud SQL / RDS database listings. |
| D10 | API security | **Stays active**, as it is locally. Each API is given the Keycloak settings explicitly (§6.4). Verification gets a token from `local-keycloak`. |
| D11 | Single-platform mode | `Docker-clouds-builder.bat -platform aws\|azure\|gcp\|all` (default `all`). A single platform destroys the other clouds' deployments and stops their emulators (§6.2). |
| D12 | Restart behaviour | The emulators do **not** bring every database container back after a restart (§12.1). Each dbapi builder detects this and repairs it (`terraform apply -replace=...`) before reloading Northwind. `Docker-clouds-<cloud>-start.bat` (§13) starts everything and re-runs the builder only when the APIs do not answer. `Docker-StartAll.bat` only starts the selected emulators; it does not re-apply Terraform. |

### 3.1 Defaults

| Topic | Default |
| --- | --- |
| Terraform image tag | `hashicorp/terraform:latest`. Providers pinned in `versions.tf`: `hashicorp/aws ~> 6.0`, `hashicorp/azurerm ~> 4.0`, `hashicorp/google ~> 6.0`, `hashicorp/http ~> 3.0` (Azure). Versions resolved during execution: aws 6.72.0, azurerm 4.81.0, http 3.6.3, google 6.50.0. |
| Terraform state | Local backend: `terraform.tfstate` inside each root folder, git-ignored. **It holds the DB passwords in plain text.** |
| Cloud DB resource names | `cloud-mssql` and `cloud-postgres`; **on GCP the SQL Server VM is `mssql-vm`** (as built, §11.2). |
| Admin login | `cloudadmin` in Terraform. **As built:** on AWS RDS and Azure SQL the emulators apply the admin password to the engine's `sa` login, and `cloudadmin` has no server rights, so the SQL Server loader falls back to `sa`. On GCE the container's `sa` is used and disabled after `DevUser` is created. GCP Cloud SQL's admin login is fixed at `postgres`/`postgres`. |
| API login | `DevUser`, the same as locally, with `sysadmin` on SQL Server and owner of `northwind` on PostgreSQL. |
| SQL Server image | `mcr.microsoft.com/mssql/server:2025-latest` everywhere, matching `local-mssql`. |
| API container port | `8080` for all images. |
| API memory | Fargate task 1024 MB / 512 CPU, Container Apps 1 GiB / 0.5 CPU, Cloud Run 1Gi / 1 CPU. |
| OTEL | `service.name = <cloud>-<api-name>` (for example `aws-cloud-api-dotnet-mssql`). `OTEL_RESOURCE_ATTRIBUTES=service.instance.id=<cloud>-<api-name>,db.variant=<mssql\|postgres>,cloud.provider=<aws\|azure\|gcp>`. Collector `otel-collector` (gRPC 4317 for Java and Python, OTLP/HTTP 4318 for DotNet; §6.4). |
| Keycloak | Internal URL `http://local-keycloak:8080` (signing keys), public issuer `http://localhost:11141`, realm `local-realm`, client `local-client`. |
| Data probe endpoint | `GET /v1/customers/get-all` (the same route on all three APIs). |

## 4. Facts that shape the design (upstream docs, confirmed or corrected during execution)

### 4.1 AWS (Floci)

- **RDS** runs real engine containers (`floci-aws-rds-<id>-<hash>`) and proxies TCP to them through ports in `FLOCI_SERVICES_RDS_PROXY_BASE_PORT`–`_MAX_PORT`. The `port` attribute picks the proxy port inside that range. From `pilot-net` a database is reached at `local-aws:<proxy-port>` (`FLOCI_SERVICES_RDS_ENDPOINT_HOST=local-aws`). The image override is `FLOCI_SERVICES_RDS_DEFAULT_SQL_SERVER_IMAGE`. **Confirmed:** the master user (`cloudadmin`) on `sqlserver-se` has only `CONNECT SQL`; `sa` with the master password is `sysadmin`. PostgreSQL's master user is a superuser.
- **API Gateway v2** `HTTP_PROXY` + `VPC_LINK` + Cloud Map service ARN works. The link only has to exist. **Invoke URL:** `http://{apiId}.execute-api.localhost.floci.io:4566/{path}` with the `$default` stage (`*.localhost.floci.io` resolves to 127.0.0.1 in public DNS). The `/execute-api/` path form is only documented for REST APIs, so it is not used.
- **ECS** runs tasks as real containers (`floci-aws-ecs-<task>-api`) on `FLOCI_SERVICES_ECS_DOCKER_NETWORK=pilot-net`. Cloud Map registers the container's `pilot-net` address and `containerPort`. If the pull of an ECR-shaped image fails, the local image with that tag runs, so the builder only `docker tag`s; nothing is pushed. ECR creates a `floci-aws-ecr-registry` container.
- **Terraform:** `hashicorp/aws ~> 6.0`, keys `test`/`test`, the three `skip_*` flags, and an `endpoints {}` entry for every service used.

### 4.2 Azure (floci-az)

- **azurerm requires TLS.** `FLOCI_AZ_TLS_ENABLED=true`. The CA from `GET /_floci/tls-cert` (CN `floci-az-ca`) must be trusted; the server cert's SANs include `localhost` and `*.localhost`. **Confirmed:** port 4577 still answers plain HTTP too, and the console sidecar stays on HTTP 4501. The provider uses `environment = "stack"`, `metadata_host = "localhost:4577"`, the seeded IDs and `resource_provider_registrations = "none"`.
- **Azure SQL** (`FLOCI_AZ_SERVICES_SQL_DATA_PLANE_PROVIDER=managed`, `_ACCEPT_EULA=Y`) runs one container per server, `floci-az-local-azure-sql-<server>`, on `pilot-net` port 1433. **Confirmed:** the admin password is set on `sa`; the `administrator_login` cannot log in. `/{account}-sql/servers/{name}/connect` returns `host` (the container name) and `port`, plus connection strings that **contain the admin password**.
- **PostgreSQL Flexible Server** runs `postgres:17-alpine` as `floci-az-local-azure-pg-<server>` on `pilot-net` port 5432. The admin user is a superuser. Database resources are metadata only. `/{account}-postgres/flexibleServers/{name}/connect` returns host and port.
- **Container Apps** (`FLOCI_AZ_SERVICES_CONTAINER_APPS_MOCKED=false`) run replicas as `floci-az-local-azure-ca-<app>-<revision>` on `pilot-net`, with labels `io.floci.service=containerapps` and `io.floci.resource-id=<app>`. Ingress enters on port 4577 and is routed by the `Host` header (`properties.configuration.ingress.fqdn`); it passes headers through. **As built:** `FLOCI_AZ_SERVICES_CONTAINER_APPS_DNS_SUFFIX=localhost` makes the FQDN `<app>.<env>.<hash>.localhost`, which browsers and `curl` resolve to 127.0.0.1. Use HTTP: the certificate's `*.localhost` covers one label only. Secrets (`secret` + `secret_name`) work; their values are not returned on read.
- **APIM:** not used (§2.1). Recorded for future re-tests: azurerm only applies `azurerm_api_management` with `sku_name = "Consumption_0"` (other SKUs call developer-portal APIs that return 404). Operation templates are matched per segment (`/*` does not match nested paths). APIs, operations and policies are in memory only.

### 4.3 GCP (floci-gcp)

- **Cloud SQL (PostgreSQL)** runs `postgres:<ver>-alpine` as `floci-gcp-local-gcp-cloudsql-<project>-<instance>` on `pilot-net`. `ip_address[0].ip_address` is that container's `pilot-net` address; the port is 5432. **The admin login is fixed at `postgres`/`postgres`.** `users.insert` passwords are not persisted.
- **Compute Engine** (`FLOCI_GCP_SERVICES_COMPUTE_MOCK=false`) runs each VM as `floci-gcp-<namespace>-compute-<project>-<zone>-<instance>` (on `bridge` and `pilot-net`), and the container declaration as `<that name>_klt`, which shares its network namespace. **Docker DNS only resolves names up to 63 characters**, so the instance name must be at most 9 characters with namespace `local-gcp`. The machine-type catalogue has only `e2-standard-2`, `n2-standard-4/8`, `c3-standard-4` and `g2-standard-4/8`. `cos-cloud/cos-stable` is not in the image catalogue and falls back to `debian:12` (fine: SQL Server runs from the declaration).
- **Cloud Run** runs one container per revision, `floci-gcp-local-gcp-cloudrun-<service>-...`, and injects `PORT`. URL: `http://{service}-{project-token}.{location}.run.localhost.floci.io:4588`, routed by Host header through port 4588. Secrets are not supported, so the DB password is a plain env var.
- **Terraform:** google provider with `access_token = "floci"`, project `floci-local`, and custom endpoints. **Confirmed paths:** `compute_custom_endpoint = "http://localhost:4588/compute/v1/"`, `sql_custom_endpoint = "http://localhost:4588/"` (the provider appends `sql/v1beta4/`), `cloud_run_v2_custom_endpoint = "http://localhost:4588/v2/"`.

## 5. Architecture

```text
                        ┌──────────── pilot-net ─────────────────────────────────────────────┐
 host / browser         │                                                                    │
   │ :4566 ─────────────┼─► local-aws ─ API GW v2 ─(VPC link / Cloud Map)─► ECS tasks ──┐      │
   │ :7001-7010 ────────┼─►    └─ RDS proxy :7001/7002 ─► rds sqlserver / postgres ◄──┘      │
   │ :4577 (http+TLS) ──┼─► local-azure ─ Container Apps ingress (Host) ─► replicas ─┐        │
   │                    │      └─ SQL / PG containers (by name, 1433 / 5432)  ◄─────┘        │
   │ :4588 ─────────────┼─► local-gcp ─ Cloud Run front door (Host) ─► Cloud Run containers ─┐│
   │                    │      ├─ Cloud SQL postgres container (IP, 5432)   ◄───────────────┤│
   │                    │      └─ GCE VM container + mssql (_klt) (by name, 1433) ◄─────────┘│
   │                    │                                                                    │
   │                    │  terraform (hashicorp/terraform, --network container:local-<cloud>)│
   │                    │  loader  (mssql / postgres image, sqlcmd / psql)                   │
   │                    │  otel-collector:4317/4318 ◄── API telemetry                        │
   │ :11141 ────────────┼─► local-keycloak:8080 ◄── API signing-key lookups                  │
                        └────────────────────────────────────────────────────────────────────┘
```

Key design points:

1. **Terraform runs in a container that shares the emulator's network namespace** (`docker run --network container:local-<cloud>`). The providers then use `localhost:<port>`, which matches the Azure certificate's SAN and the URLs the emulators return.
2. **Two Terraform roots per cloud** (`10-databases`, `20-apis`). The database servers are created first, then loaded, then the APIs. `20-apis` reads the DB endpoints (and, on AWS, the VPC and subnets) from `10-databases` through `terraform_remote_state` (local backend).
3. **Every DB endpoint is a Terraform output of `10-databases`** (`mssql_host`, `mssql_port`, `postgres_host`, `postgres_port`; GCP adds `postgres_admin_user`). On Azure an `http` data source reads the emulator's `/connect` API; only host and port are exposed.
4. **The loader runs as throwaway containers on `pilot-net`**, using images already present locally: `mcr.microsoft.com/mssql/server:2025-latest` with `--entrypoint /opt/mssql-tools18/bin/sqlcmd`, and `postgres:latest` for `psql`. The `--entrypoint` matters: the image's default entrypoint prints a banner and broke stdin loads. SQL scripts are piped on stdin. The loader creates the databases and logins (D9).
5. **One API list for all clouds:** `Clouds\terraform\apis.json` drives every `for_each`.
6. **Front doors:** AWS has 6 HTTP APIs named after the APIs, each with a `$default` stage. Azure uses each Container App's ingress. GCP has one Cloud Run service per API.
7. **Shared batch code:** `Clouds\scripts\dbapi-common.bat` (builder routines) and `Clouds\scripts\cloud-lifecycle.bat` (start/stop). Each is called as `call file.bat :routine args`. Routines that need several Terraform arguments take them as **one quoted argument**, because `cmd` splits unquoted arguments on `=`.

### 5.1 Batch-file rules learned during execution

- **Save every `.bat` with CRLF line endings.** LF-only files break `goto`/`call` label lookup.
- **Inside `for /f (`command`)`, unquoted `=`, `,` and `;` become spaces.** Quote such arguments, or write the output to a temp file and read that.
- **Do not wait with `timeout /t`.** It exits at once when stdin is not a console (automation). Use `ping -n <seconds+1> 127.0.0.1 >nul`.
- **Windows PowerShell 5.1 strips embedded double quotes from native-command arguments.** Avoid Go templates such as `{{index .X "y"}}`; use `{{json ...}}` and parse it instead.
- **Never edit a `.bat` file while it runs.** `cmd` reads it incrementally.

## 6. Shared files (Phase 0)

| # | File | Action | Phase |
| --- | --- | --- | --- |
| 1 | `Clouds\docker-compose.clouds.yml` | **Modify**: each cloud phase adds its emulator settings (§9.1, §10.1, §11.1) | 1, 2, 3 |
| 2 | `Clouds\Docker-clouds-builder.bat` | **Modify**: `-platform` flag (§6.2). Phase 2: HTTPS health check and TLS cert save (§10.1). | 0, 2 |
| 3 | `Docker-StartAll.bat` (root) | **Modify**: start only the emulators named in `Clouds\.platform` | 0 |
| 4 | `Clouds\Docker-clouds-api-images-builder.bat` | **Create**: builds the 6 images (§6.3) | 0 |
| 5 | `Clouds\scripts\load-mssql.bat`, `load-postgres.bat` | **Create**: loaders (§6.5) | 0 |
| 6 | `Clouds\scripts\dbapi-common.bat` | **Create**: shared builder routines (§6.7) | 1 |
| 7 | `Clouds\terraform\apis.json` | **Create**: the 6 API definitions (§6.4) | 0 |
| 8 | `Clouds\terraform\modules\api-env\main.tf` | **Create**: per-language env-var maps (§6.4) | 0 |
| 9 | `Clouds\terraform\.gitignore` | **Create**: `.terraform/`, `*.tfstate`, `*.tfstate.*`, `.terraform.lock.hcl`, `*.tfplan`, `tls/` | 0 |
| 10 | `Clouds\.gitignore` | **Create**: `.platform` | 0 |
| 11 | `secrets\clouds-db.env.example` | **Create** (§6.6) | 0 |
| 12 | `secrets\README.md` | **Modify**: list `secrets/clouds-db.env` | 0 |
| 13 | `Clouds\Docker-clouds-aws-dbapi-builder.bat` + `Clouds\terraform\aws\{10-databases,20-apis}\` | **Create** (§9) | 1 |
| 14 | `Clouds\Docker-clouds-azure-dbapi-builder.bat` + `Clouds\terraform\azure\{10-databases,20-apis}\` | **Create** (§10) | 2 |
| 15 | `Clouds\Docker-clouds-gcp-dbapi-builder.bat` + `Clouds\terraform\gcp\{10-databases,20-apis}\` | **Create** (§11) | 3 |
| 16 | `Clouds\scripts\cloud-lifecycle.bat` + `Clouds\Docker-clouds-<cloud>-start.bat` / `-stop.bat` | **Create** (§13) | 4 |
| 17 | `Clouds\README.md` | **Modify**: the batch-file steps, `-platform`, and a "Databases and APIs" section (scripts, layout, endpoints, emulator behaviour, restarts, start/stop) | 0–4 |
| 18 | `README.md` (root) | **Modify**: builder scripts list, ports table (RDS proxy 7001-7010, Azure HTTPS) | 1–4 |

Each Terraform root has `versions.tf`, `providers.tf`, `variables.tf` (`db_admin_user`, `db_admin_password` sensitive, `db_devuser_password` sensitive with default `""`), `main.tf` and `outputs.tf`.

### 6.1 Phase 0 verification

1. `Docker-clouds-api-images-builder.bat` builds the 6 images, the unit tests pass, and the D7 checks in §6.3 pass.
2. Both loaders run against the local servers in mode `local`, into scratch databases (`CLOUD_DB_NAME_OVERRIDE=NorthWindCloudTest` / `northwind_cloud_test`). `CLOUD_DB_ADMIN_USER=DevUser` and both passwords come from `secrets\sqlserver.env` / `secrets\postgresql.env`. Check `dbo.Customers` / `pilot.customers` = 91 and that `GenerateUniqueKeyDynamic` / `generate_unique_key_dynamic` exist, then drop the scratch databases.
3. Render `modules\api-env` for the 6 APIs against `local-mssql:1433` / `local-postgres:5432` with a scratch Terraform root, then write each map to an `--env-file`. Run each image with `docker run --network pilot-net -p <port>:8080 --env-file ...`. Check `/healthcheck` = 200, `get-all` without a token = 401, and with a token = rows. (The local NorthWind SQL Server database had 92 customers on the day; the clouds load 91.) Delete the env files afterwards; they hold passwords.
4. `Docker-clouds-builder.bat -platform aws` starts only `local-aws`, `-platform all` starts all three again, and `-platform bogus` prints the usage and exits 1.

### 6.2 `-platform` flag (single-platform mode)

```text
Clouds\Docker-clouds-builder.bat [-platform all|aws|azure|gcp]     (default: all)
Clouds\Docker-clouds-<cloud>-dbapi-builder.bat [-destroy]
```

`Docker-clouds-builder.bat -platform <cloud>` does this:

1. Validates the value. Anything else prints the usage and exits 1. Checks that Docker is running.
2. Pulls only the selected emulator image (all three for `all`).
3. **For each cloud that is not selected** (`:retire_cloud`):
   - If its emulator is running **and** one of its `terraform.tfstate` files contains resources (`findstr "\"mode\":"`), it runs `Docker-clouds-<cloud>-dbapi-builder.bat -destroy`.
   - If the emulator is stopped and state with resources exists, it prints a warning.
   - It then runs `docker compose stop local-<cloud>` and removes that cloud's sidecars: `floci-aws-ui` and `floci-aws-ecr-registry` for AWS, `floci-az-local-azure-ui` for Azure.
4. `all`: `docker compose down --remove-orphans` plus sidecar removal, then `up -d --force-recreate`. One cloud: `up -d --force-recreate local-<cloud>` only.
5. Waits for the selected emulators. Azure uses `https://localhost:4577/_floci/health`, mode `strict-insecure` (`curl -sSfk`), and saves `terraform\tls\floci-az.pem`.
6. Writes the selection to `Clouds\.platform` and opens the selected consoles.

Other scripts read `Clouds\.platform` (a missing file means `all`):

- **`Docker-StartAll.bat`:** each `docker start local-<cloud>` runs only if the platform is `all` or that cloud.
- **dbapi builders and the start scripts:** if the platform is set to another cloud, they stop with: "Platform is set to <x>. Run Clouds\Docker-clouds-builder.bat -platform <cloud> first." (`-destroy` skips this check.)

**Memory effect:** one SQL Server (about 2–3 GB), one PostgreSQL server, 6 APIs (1 GB each), and one 2 GB emulator, instead of three of each.

### 6.3 `Clouds\Docker-clouds-api-images-builder.bat`

| Image | Source build | Dockerfile reused | Notes |
| --- | --- | --- | --- |
| `cloud-api-dotnet-mssql:1.0` / `-postgres:1.0` | `dotnet test` + `dotnet publish --os linux --arch x64` of `..\..\PilotApiDotNet` | `Api_dotnet\dockerfile_mssql` / `_postgres` | Any `appsettings.Production.json` in the publish output is deleted |
| `cloud-api-java-mssql:1.0` / `-postgres:1.0` | `mvn -q clean package` of `..\..\PilotApiJava` | `Api_java\dockerfile_mssql` / `_postgres` | **No `DB_URL` / `DB_PASSWORD` build args**: the dockerfiles copy ARGs into ENV, so a password would land in the image |
| `cloud-api-python-mssql:1.0` / `-postgres:1.0` | `pytest -q` + `pip wheel` of `..\..\PilotApiPython` (project `.venv` if present) | `Api_python\dockerfile_mssql` / `_postgres` | **No** `.env` copied in |

- Builds with `docker build -q -f <dockerfile> -t <image> --build-arg DEPLOY_DATE=... --build-arg APP_PORT=8080 <context>`. Java passes `SERVER_PORT=8080` instead of `APP_PORT`.
- Build contexts go under `C:\Working\Storage\Dev\GitHub\Working\clouds\` (only this subfolder is wiped).
- Requires `secrets\clouds-db.env` (for the history check).
- **D7 checks**, for each name in `apis.json`:
  - `docker image inspect` succeeds.
  - The image env has no `DB_PASSWORD=` or `DB_URL=` with a value.
  - `docker history --no-trunc` does not contain `CLOUD_DB_DEVUSER_PASSWORD`.
  - `docker run --rm --entrypoint sh <image> -c "ls -a /app"` shows no `appsettings.Production.json` or `.env`.

### 6.4 API list and configuration via env vars

**`Clouds\terraform\apis.json`** is the only list of APIs:

```json
[
  { "name": "cloud-api-dotnet-mssql",    "lang": "dotnet", "db": "mssql" },
  { "name": "cloud-api-dotnet-postgres", "lang": "dotnet", "db": "postgres" },
  { "name": "cloud-api-java-mssql",      "lang": "java",   "db": "mssql" },
  { "name": "cloud-api-java-postgres",   "lang": "java",   "db": "postgres" },
  { "name": "cloud-api-python-mssql",    "lang": "python", "db": "mssql" },
  { "name": "cloud-api-python-postgres", "lang": "python", "db": "postgres" }
]
```

Each `20-apis` root loads it with `locals { apis = { for a in jsondecode(file("${path.module}/../../apis.json")) : a.name => a } }`. The batch files read it with `powershell -NoProfile -Command "(Get-Content ... -Raw | ConvertFrom-Json).name"`.

**`modules\api-env`** has these inputs:

- `lang`, `db`, `host`, `port`, `user` (`DevUser`), `password` (sensitive), `cloud`, `api_name`
- `app_port` (8080)
- `keycloak_url`, `keycloak_public_url`, `keycloak_realm`, `keycloak_client_id`
- `otlp_host` (`otel-collector`), `otlp_grpc_port` (4317), `otlp_http_port` (4318)

Its outputs are `env` (sensitive map) and `secret_names` (the env names that hold the password).

| Language | Database | Security (Keycloak) | OTEL |
| --- | --- | --- | --- |
| DotNet (`__` = `:`) | `ASPNETCORE_HTTP_PORTS=8080`, `Application__DataConnections__0__Active=true`, `…__DataSourceName=NorthWind_SQL` / `NorthWind_Pgs`, `…__Host`, `…__Port`, `…__UserName`, `…__Password`, `…__ConnectTimeout=30` | `Application__Security__Active=true`, `…__BaseUrl`, `…__PublicBaseUrl`, `…__Realm`, `…__ClientId` | **As built:** PilotApiDotNet builds the OTLP endpoint in code from `Application__OpenTelemetry__Server` / `__Port` (OTLP/HTTP 4318), and takes `service.name` from `Application__OpenApi__Title`. Both are set; `OTEL_SERVICE_NAME` alone has no effect. |
| Java | `SPRING_PROFILES_ACTIVE=prod-sqlserver` / `prod-postgres`, `SERVER_PORT=8080`, `DB_URL` **and `SPRING_DATASOURCE_URL`** (as built: `application-prod-sqlserver.yml` hard-codes its URL; OS env wins), `DB_USERNAME`, `DB_PASSWORD`. URLs: `jdbc:sqlserver://<host>:<port>;databaseName=NorthWind;encrypt=true;trustServerCertificate=true;connectTimeout=30` / `jdbc:postgresql://<host>:<port>/northwind` | `APP_SECURITY_ACTIVE=true`, `APP_SECURITY_PROVIDER_URL`, `APP_SECURITY_PUBLIC_PROVIDER_URL`, `APP_SECURITY_REALM`, `APP_SECURITY_CLIENT_ID` | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` |
| Python | `APP_PORT=8080`, `DB_BACKEND=sqlserver` / `postgresql`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_SCHEMA=dbo` / `pilot`, `DB_USER`, `DB_PASSWORD`, `DB_CONNECT_TIMEOUT=30`, `DB_DRIVER` (SQL Server only), `DB_TRUST_SERVER_CERTIFICATE=true`, `LOG_JSON=true` | `SECURITY_ACTIVE=true`, `IDENTITY_PROVIDER_BASE_URL`, `IDENTITY_PROVIDER_PUBLIC_BASE_URL`, `IDENTITY_PROVIDER_REALM`, `IDENTITY_PROVIDER_CLIENT_ID` | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` |

All languages also get `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` (§3.1).

**Implementation checks (done before Phase 0 step 3):**

- PilotApiDotNet uses `WebApplication.CreateBuilder` and binds `Application` from `IConfiguration`.
- The `DataSources` entries are in the base `appsettings.json`.
- PilotApiPython uses `pydantic_settings.BaseSettings` without an `env_prefix`.
- All three APIs serve `GET /v1/customers/get-all`.
- **Python's `/healthcheck` runs `SELECT 1`**, so it fails while its database is down; the DotNet and Java health checks do not touch the database.

**Passing the env to each platform** (sensitive values must not be `for_each` keys):

- **ECS:** `environment = [for k in sort(keys(env)) : { name = k, value = env[k] }]` inside `jsonencode(container_definitions)`.
- **Container Apps and Cloud Run:** `dynamic "env" { for_each = toset(nonsensitive(keys(env))) ... value = env[env.value] }`. Container Apps excludes `secret_names` and maps them with `secret_name = "db-password"`.

### 6.5 Loaders (`Clouds\scripts\`)

Passwords are never on a command line. The loaders read `CLOUD_DB_ADMIN_USER`, `CLOUD_DB_ADMIN_PASSWORD` and `CLOUD_DB_DEVUSER_PASSWORD` from the environment. They pass them to the tool containers as name-only env vars: `SQLCMDPASSWORD` and `PGPASSWORD` for login, and `CLOUD_DEVPW` for the new login's password. sqlcmd reads that one as the scripting variable `$(CLOUD_DEVPW)`; psql reads it with `\getenv`.

`load-mssql.bat <host> <port> <managed|gce|local>`:

```bat
set "SQLCMD=docker run --rm -i --network pilot-net -e SQLCMDPASSWORD -e CLOUD_DEVPW --entrypoint /opt/mssql-tools18/bin/sqlcmd mcr.microsoft.com/mssql/server:2025-latest -S %DB_HOST%,%DB_PORT% -C -l 30"
```

1. Waits (60 × 5 s) for a login that is **sysadmin** (`IF IS_SRVROLEMEMBER('sysadmin') = 1 SELECT 1 ELSE RAISERROR`). Candidates, in order:
   - `managed`: `CLOUD_DB_ADMIN_USER`, then `sa` with the same password (as built, §4.1/§4.2).
   - `gce`: `sa`, then `DevUser` (sa is disabled after the first load).
   - `local`: `CLOUD_DB_ADMIN_USER`.
2. Unless the mode is `local`: creates `DevUser` (`CHECK_POLICY = OFF`) or resets its password, and adds it to `sysadmin`.
3. As `DevUser`: drops and recreates the database (`SINGLE_USER WITH ROLLBACK IMMEDIATE`).
4. Loads `Northwind.sql` on stdin.
5. Counts the base tables into a temp file; the count must be numeric and at least 13.
6. Loads `customobjects.sql` with `-b`.
7. `gce` only: `ALTER LOGIN [sa] DISABLE`.

`load-postgres.bat <host> <port> <managed|local>`:

```bat
set "PSQL=docker run --rm -i --network pilot-net -e PGPASSWORD -e CLOUD_DEVPW -e PGCONNECT_TIMEOUT=10 postgres:latest psql -h %DB_HOST% -p %DB_PORT% -v ON_ERROR_STOP=1 -q"
```

1. Waits (60 × 5 s) for `SELECT 1` as `CLOUD_DB_ADMIN_USER`.
2. Unless the mode is `local`, runs a temp SQL file:
   - `\getenv devpw CLOUD_DEVPW`
   - `CREATE ROLE "DevUser" LOGIN CREATEDB PASSWORD …` if it is missing, then `ALTER ROLE` to reset the password (`format(...) \gexec`)
   - `GRANT "DevUser" TO current_user` if the admin is not already a member
3. `DROP DATABASE IF EXISTS <db> WITH (FORCE)`, then `CREATE DATABASE <db> OWNER "DevUser"`.
4. As `DevUser`: loads `northwind.sql`, then counts the tables in schema `pilot` (≥ 13).
5. Loads `customobjects.sql`, then `reset-primary-keys.sql`.

`CLOUD_DB_NAME_OVERRIDE` replaces `NorthWind` / `northwind` (Phase 0 test only). Passwords must not contain `" % ^ & < > | ; =` (batch) or `'` (SQL literals).

### 6.6 `secrets\clouds-db.env.example`

```text
# Copy to secrets/clouds-db.env and replace placeholder values.
# Used by Clouds\Docker-clouds-<cloud>-dbapi-builder.bat (passed to Terraform as TF_VAR_*).
# SQL Server rules apply: at least 8 characters, using 3 of upper, lower, digit, symbol.
# Avoid the characters " % ^ & < > | ; = because they break .bat parsing and connection strings.
CLOUD_DB_ADMIN_USER=cloudadmin
CLOUD_DB_ADMIN_PASSWORD=<cloud-db-admin-password>
CLOUD_DB_DEVUSER_PASSWORD=<cloud-db-devuser-password>
# Optional: a local-realm Keycloak user for the authenticated data probe.
# If left as placeholders, the builder skips the probe and prints a warning.
CLOUD_TEST_USER=<keycloak-test-user>
CLOUD_TEST_PASSWORD=<keycloak-test-user-password>
```

On execution, the real file was created with generated passwords (14 random alphanumerics + `_Aa9`), and with the `READER_USERID` / `READER_PASSWORD` user from `secrets\keycloak.env`, which has a direct-access-grant client (`local-client`).

### 6.7 Builder skeleton and `scripts\dbapi-common.bat`

Each builder is `setlocal`, `pushd "%~dp0"`, then calls `"%~dp0scripts\dbapi-common.bat" :<routine>`:

```text
REM Usage: Docker-clouds-<cloud>-dbapi-builder.bat [-destroy]
 -. docker info (stop if Docker is not available).
 0. :load_secrets       secrets\clouds-db.env -> CLOUD_*, TF_VAR_db_admin_user/_password, TF_VAR_db_devuser_password,
                        CLOUD_PROBE (set when CLOUD_TEST_* are real values).
    -destroy: :is_running local-<cloud>, then :tf_destroy on the API root(s) and 10-databases, then :remove_leftovers.
 1. :check_platform <cloud>   :check_running <cloud> (local-<cloud>, local-keycloak, otel-collector)
 2. :check_images             (the 6 cloud-api-*:1.0 images from apis.json)
 3. docker pull -q hashicorp/terraform:latest    (+ Azure: CA bundle, §10.1)
 4. <cloud repair step, §9–§11>   :tf_apply <cloud> 10-databases
 5. :tf_output <cloud> 10-databases mssql_host|mssql_port|postgres_host|postgres_port <VAR>
 6. load-mssql.bat <host> <port> <mode>   load-postgres.bat <host> <port> managed
 7. <cloud image step: AWS docker tag to the ECR-shaped URI; Azure/GCP none>
 8. :tf_apply <cloud> 20-apis
 9. :verify_apis <cloud> 20-apis
      For each api_base_urls entry (:tf_output_map -> "name url" lines):
        a. :wait_for_url <base>/healthcheck (WFU_TRIES x 3 s, default 120).
        b. With a token (password grant; the password goes to curl from a temp file: --data-urlencode password@file):
           GET <base>/v1/customers/get-all without a token -> must be 401;
           with the token -> must be 200 and a non-empty array. Up to 5 tries, because the first calls after a
           DB reload can fail on stale pooled connections.
      The URL list is saved to %TEMP%\cloud-<cloud>-api-urls.txt.
10. :open_healthchecks <cloud>   (start each <base>/healthcheck in the browser)

:tf <cloud> <root> "<terraform args>"
docker run --rm --network container:local-<cloud> -v "<Clouds\terraform>:/workspace" -w /workspace/<cloud>/<root>
  -e TF_VAR_db_admin_user -e TF_VAR_db_admin_password -e TF_VAR_db_devuser_password -e TF_IN_AUTOMATION=1
  [-e SSL_CERT_FILE=/workspace/tls/ca-bundle.pem]   (Azure only)
  hashicorp/terraform:latest <args>
```

`:tf_apply` runs `init -input=false` and then `apply -auto-approve -input=false -no-color`. `:tf_destroy` skips a root with no `terraform.tfstate`. `:remove_leftovers <prefix>...` removes containers whose names start with each prefix.

## 7. Delivery order

| Step | Content | Exit criterion |
| --- | --- | --- |
| Phase 0 | §6: images builder, loaders, `apis.json`, `api-env`, secrets, `-platform` flag | §6.1 passes |
| Azure spike | §8: go/no-go for the riskiest platform | All points pass, or the user picks an alternative |
| Phase 1 | AWS (§9) | §12 passes for AWS |
| Phase 2 | Azure (§10) | §12 passes for Azure |
| Phase 3 | GCP (§11) | §12 passes for GCP |
| Phase 4 | Start/stop scripts (§13) | §13.3 passes for each cloud |

Switch clouds between phases with `Docker-clouds-builder.bat -platform <cloud>`; this also tests §12 step 10.

## 8. Azure go/no-go spike (before Phase 1)

**Spike setup (no committed changes):** `local-azure` is started with a throwaway override file, `C:\Working\Storage\Dev\GitHub\Working\clouds\azure-spike.override.yml`, holding the §10.1 environment. The spike Terraform root lives in the scratch folder. Afterwards, destroy the spike resources and re-run `Docker-clouds-builder.bat`.

| # | Point | Result (2026-11-05) |
| --- | --- | --- |
| 1 | Console sidecar with TLS on | ✅ still HTTP on 4501. Port 4577 answers both HTTPS and HTTP. |
| 2 | `azurerm_mssql_server` + `azurerm_postgresql_flexible_server` + `/connect` | ✅ The containers join `pilot-net`; `/connect` returns the container name and port. ⚠ The PG `zone` drifts (`ignore_changes`). ⚠ The SQL admin login cannot log in; `sa` works with the admin password. |
| 3 | `azurerm_container_app_environment` + `azurerm_container_app` (local image) | ✅ The replica runs on `pilot-net`. ⚠ `secret` drifts (`ignore_changes`). |
| 4 | Replica reaches DB, `local-keycloak:8080`, `otel-collector:4317/4318` by name | ✅ |
| 5 | `azurerm_api_management` + `_api`; gateway reaches the Container App | ❌ Only `Consumption_0` applies. The gateway cannot reach the app by name and forwards no client headers (§2.1). **User decision: ingress as the front door.** |
| 6 | Second `terraform plan` shows no changes | ✅ with the `ignore_changes` above |
| 7 | Container name pattern for `-destroy` | `floci-az-local-azure-{sql,pg,ca}-...`, labels `floci_namespace=local-azure`, `io.floci.service` |

Also needed: azurerm `features { api_management { purge_soft_delete_on_destroy = false, recover_soft_deleted = false } }` (floci-az has no soft-delete endpoints), and `resource_group { prevent_deletion_if_contains_resources = false }`.

## 9. Phase 1 – AWS

### 9.1 Emulator changes (`docker-compose.clouds.yml`, `local-aws`)

```yaml
      - FLOCI_SERVICES_DOCKER_NETWORK=pilot-net
      - FLOCI_SERVICES_ECS_DOCKER_NETWORK=pilot-net
      - FLOCI_SERVICES_RDS_ENDPOINT_HOST=local-aws
      - FLOCI_SERVICES_RDS_PROXY_BASE_PORT=7001
      - FLOCI_SERVICES_RDS_PROXY_MAX_PORT=7010
      - FLOCI_SERVICES_RDS_DEFAULT_SQL_SERVER_IMAGE=mcr.microsoft.com/mssql/server:2025-latest
    ports:
      - "4566:4566"
      - "7001-7010:7001-7010"   # RDS proxy (host tools such as SSMS / psql)
```

### 9.2 `terraform\aws\10-databases`

- `providers.tf`: endpoints `ec2`, `iam`, `rds`, `sts` = `http://localhost:4566`.
- Resources:
  - `aws_vpc.cloud` (`10.42.0.0/16`, tag `Name = cloud-vpc`)
  - `aws_subnet.a` / `.b` (`10.42.1.0/24` in `us-east-1a`, `10.42.2.0/24` in `us-east-1b`), each with **`timeouts { delete = "2m" }`** (§12.1)
  - `aws_db_subnet_group.cloud`, and `aws_security_group.db` allowing 1433 and 5432 from the VPC
- `aws_db_instance.mssql`: `identifier = "cloud-mssql"`, `engine = "sqlserver-se"`, `license_model = "license-included"`, `instance_class = "db.m5.large"`, `allocated_storage = 20`, `port = 7001`, `skip_final_snapshot = true`, `apply_immediately = true`, **`lifecycle { ignore_changes = [license_model] }`** (not echoed back).
- `aws_db_instance.postgres`: `identifier = "cloud-postgres"`, `engine = "postgres"`, `engine_version = "17"`, `instance_class = "db.t3.micro"`, `port = 7002`, and the same credential and snapshot settings. No `db_name` (D9).
- Outputs: `mssql_host`, `mssql_port`, `postgres_host`, `postgres_port` (`local-aws`, 7001, `local-aws`, 7002), plus **`vpc_id`** and **`subnet_ids`**.

### 9.3 `terraform\aws\20-apis`

- `providers.tf` endpoints: `apigatewayv2`, `ec2`, `ecr`, `ecs`, `iam`, `logs`, `servicediscovery`, `sts`.
- VPC and subnets come from `terraform_remote_state` (not a tag lookup), so a network left behind by §12.1 is never matched by mistake.
- Shared resources:
  - `aws_security_group.api` (ingress 8080, egress all)
  - `aws_ecr_repository` per API (`force_delete = true`)
  - `aws_ecs_cluster "cloud-apis"`
  - `aws_iam_role "cloud-api-task-execution"`
  - `aws_cloudwatch_log_group "/ecs/<api>"`
  - `aws_service_discovery_private_dns_namespace "cloud.local"` + `aws_service_discovery_service` per API (A record, MULTIVALUE)
- Per API (`for_each = local.apis`):
  - `aws_ecs_task_definition`: `FARGATE`, `awsvpc`, `cpu = 512`, `memory = 1024`, container `api` with image `000000000000.dkr.ecr.us-east-1.amazonaws.com/<api>:1.0` and port 8080, the env from `module.api_env`, and the `awslogs` driver.
  - `aws_ecs_service`: `desired_count = 1`, `FARGATE`, private subnets, and `service_registries { container_name = "api", container_port = 8080 }`.
  - `aws_apigatewayv2_api` (`HTTP`) + `aws_apigatewayv2_integration` (`HTTP_PROXY`, `ANY`, `VPC_LINK`, `integration_uri = <cloud map service arn>`) + `aws_apigatewayv2_route "ANY /{proxy+}"` + `aws_apigatewayv2_stage "$default"` (`auto_deploy = true`). One `aws_apigatewayv2_vpc_link "cloud-apis"` is shared.
- Outputs: `api_base_urls = http://<apiId>.execute-api.localhost.floci.io:4566`, and `healthcheck_urls`.

### 9.4 `Docker-clouds-aws-dbapi-builder.bat`

- Step 6 uses mode `managed` for both loaders.
- Step 7 runs `docker tag <api>:1.0 000000000000.dkr.ecr.us-east-1.amazonaws.com/<api>:1.0` for each API.
- `-destroy` destroys 20-apis, then 10-databases. If 10-databases fails and only `aws_subnet.*` / `aws_vpc.*` are left in its state, `:forget_network` prints a warning and `state rm`s them (§12.1). Leftovers: `floci-aws-ecs-`, `floci-aws-rds-`.

### 9.5 Phase 1 spike results

1. ✅ `sqlserver-se` runs and is reachable at `local-aws:7001`; PostgreSQL at `local-aws:7002`.
2. ✅ Fargate tasks with local images start on `pilot-net`.
3. ✅ API Gateway v2 → VPC link → Cloud Map → task answers `/healthcheck`.
4. ✅ Tasks reach `local-aws:7001/7002`, `local-keycloak:8080` and `otel-collector`.
5. Container patterns: `floci-aws-ecs-<task>-api`, `floci-aws-rds-db-<id>-<hash>`, `floci-aws-ecr-registry`, `floci-aws-ui`.

## 10. Phase 2 – Azure

### 10.1 Emulator, builder and TLS changes

`docker-compose.clouds.yml`, `local-azure`:

```yaml
      - FLOCI_AZ_TLS_ENABLED=true
      - FLOCI_AZ_SERVICES_SQL_DATA_PLANE_PROVIDER=managed
      - FLOCI_AZ_SERVICES_SQL_ACCEPT_EULA=Y
      - FLOCI_AZ_SERVICES_SQL_IMAGE=mcr.microsoft.com/mssql/server:2025-latest
      - FLOCI_AZ_SERVICES_CONTAINER_APPS_MOCKED=false
      - FLOCI_AZ_SERVICES_CONTAINER_APPS_DNS_SUFFIX=localhost   # app URLs resolve to 127.0.0.1
```

Changing the DNS suffix only affects apps created afterwards: recreate `local-azure` and the apps.

`Docker-clouds-builder.bat` (`:wait_azure`) changes:

- It waits on `https://localhost:4577/_floci/health` (`strict-insecure`).
- It saves `curl -sfk https://localhost:4577/_floci/tls-cert` to `terraform\tls\floci-az.pem`.

**TLS for Terraform** (`:ca_bundle` in the Azure builder) fetches the cert again and copies `/etc/ssl/certs/ca-certificates.crt` out of the Terraform image once, as `terraform\tls\system-ca.pem`. It joins the two into `terraform\tls\ca-bundle.pem` with `copy /B`. `:tf` sets `SSL_CERT_FILE` for Azure.

### 10.2 `terraform\azure\10-databases`

- `providers.tf`: azurerm (§4.2, §8 features) and `hashicorp/http`.
- `azurerm_resource_group "rg-cloud-data"` (`eastus`).
- `azurerm_mssql_server "cloud-mssql"` (`version = "12.0"`, admin login and password), and `azurerm_mssql_firewall_rule "allow-all"`. No database resource (D9).
- `azurerm_postgresql_flexible_server "cloud-postgres"` (`version = "16"`, `sku_name = "B_Standard_B1ms"`, `storage_mb = 32768`, `public_network_access_enabled = true`, `ignore_changes = [zone]`), and `azurerm_postgresql_flexible_server_firewall_rule "allow-all"`.
- `data "http"` for `https://localhost:4577/devstoreaccount1-sql/servers/cloud-mssql/connect` and `.../devstoreaccount1-postgres/flexibleServers/cloud-postgres/connect`. Each has `depends_on` on its server and a `postcondition` that `status_code == 200`.
- Outputs: `mssql_host` / `mssql_port` (`floci-az-local-azure-sql-cloud-mssql`, 1433) and `postgres_host` / `postgres_port` (`floci-az-local-azure-pg-cloud-postgres`, 5432), taken from the JSON. The password fields are never output.

### 10.3 `terraform\azure\20-apis`

- `azurerm_resource_group "rg-cloud-apis"`, `azurerm_container_app_environment "cae-cloud-apis"`.
- `azurerm_container_app` per API:
  - `revision_mode = "Single"`, `min_replicas = max_replicas = 1`
  - container `api`, image `<api>:1.0`, `cpu = 0.5`, `memory = "1Gi"`
  - env from `module.api_env`, with the password through `secret "db-password"` / `secret_name`
  - `ingress { external_enabled = true, target_port = 8080, traffic_weight { latest_revision = true, percentage = 100 } }`
  - `ignore_changes = [secret]`
- Outputs: `api_base_urls = http://<ingress fqdn>:4577` and `healthcheck_urls`.

### 10.4 `Docker-clouds-azure-dbapi-builder.bat`

- Step 3 also runs `:ca_bundle`.
- **Step 4 repair (`:heal_data_plane`, D12):** this runs when 10-databases has state. If SQL `/connect` answers 409 (`DataPlaneNotReady`), or the PostgreSQL `/connect` reports `"port":0,`, the builder removes the stale containers and runs `apply -replace=azurerm_mssql_server.mssql` and/or `-replace=azurerm_postgresql_flexible_server.postgres`.
- Step 6 uses mode `managed` (the SQL Server loader falls back to `sa`). There is no image step.
- Steps 8 and 9 run on 20-apis.
- `-destroy` destroys 20-apis, then 10-databases. Leftovers: `floci-az-local-azure-ca-`, `-sql-`, `-pg-`.

## 11. Phase 3 – GCP

### 11.1 Emulator changes (`docker-compose.clouds.yml`, `local-gcp`)

```yaml
      - FLOCI_GCP_SERVICES_COMPUTE_MOCK=false
```

(`FLOCI_GCP_SERVICES_DOCKER_NETWORK=pilot-net` and `FLOCI_GCP_DOCKER_RESOURCE_NAMESPACE=local-gcp` were already set.)

### 11.2 `terraform\gcp\10-databases`

- `providers.tf` (the same in both GCP roots):
  - `project = "floci-local"`, `region = "us-central1"`, `zone = "us-central1-a"`, `access_token = "floci"`
  - `compute_custom_endpoint = "http://localhost:4588/compute/v1/"`
  - `sql_custom_endpoint = "http://localhost:4588/"`
  - `cloud_run_v2_custom_endpoint = "http://localhost:4588/v2/"`
  - `service_usage`, `resource_manager` and `iam` endpoints = `http://localhost:4588/v1/`
- **PostgreSQL:** `google_sql_database_instance "cloud-postgres"` (`POSTGRES_17`, `tier = "db-custom-1-3840"`, `deletion_protection = false`). No `google_sql_database` or `google_sql_user` (D9).
- **SQL Server:**
  - `google_compute_network "cloud-net"` (no auto subnets) + `google_compute_subnetwork "cloud-subnet"` (`10.43.0.0/24`) + `google_compute_firewall "allow-mssql"` (tcp:1433)
  - **`google_compute_instance "mssql-vm"`**:
    - `machine_type = "e2-standard-2"`, boot image `cos-cloud/cos-stable`
    - `metadata.gce-container-declaration = yamlencode({spec = {containers = [{name = "mssql", image = "mcr.microsoft.com/mssql/server:2025-latest", env = [ACCEPT_EULA=Y, MSSQL_SA_PASSWORD=var.db_admin_password, MSSQL_AGENT_ENABLED=true]}], restartPolicy = "Always"}})`
    - Locals `namespace = "local-gcp"` and `mssql_instance = "mssql-vm"` (63-character limit, §4.3).
- Outputs:
  - `mssql_host = "floci-gcp-${namespace}-compute-${project}-${zone}-${instance}"` (62 characters), `mssql_port = 1433`
  - `postgres_host = ip_address[0].ip_address`, `postgres_port = 5432`, `postgres_admin_user = "postgres"`

### 11.3 `terraform\gcp\20-apis`

- `google_cloud_run_v2_service` per API:
  - `location = "us-central1"`, `deletion_protection = false`, `ingress = "INGRESS_TRAFFIC_ALL"`
  - `scaling { min_instance_count = 1, max_instance_count = 1 }`
  - image `<api>:1.0`, `ports { container_port = 8080 }`, limits `cpu = "1"`, `memory = "1Gi"`
  - env from `module.api_env`, with the password as a plain value
- `google_cloud_run_v2_service_iam_member` `allUsers` → `roles/run.invoker`.
- Outputs: `api_base_urls = <service>.uri`, and `healthcheck_urls`.

### 11.4 `Docker-clouds-gcp-dbapi-builder.bat`

- **Step 4 repair (`:heal_mssql_vm`, D12):** when the state has the VM and `<mssql_host>_klt` is not running, the builder runs `apply -replace=google_compute_instance.mssql`.
- Step 6 runs `load-mssql.bat ... gce`. Then, inside `setlocal`, it sets `CLOUD_DB_ADMIN_USER=postgres` and `CLOUD_DB_ADMIN_PASSWORD=postgres` and runs `load-postgres.bat ... managed`.
- There is no image step.
- `-destroy` destroys 20-apis, then 10-databases. Leftovers: `floci-gcp-local-gcp-`.

### 11.5 Phase 3 spike results

1. `cos-stable` is unmapped and falls back to `debian:12`. No image catalogue is needed.
2. ✅ `_klt` SQL Server starts. `e2-standard-2` gives 8 GB. It is reachable by the VM container's name, once the name is ≤ 63 characters.
3. ✅ Cloud SQL and Cloud Run containers join `pilot-net` and reach Keycloak and OTEL.
4. ✅ The Cloud SQL admin login is `postgres`/`postgres` (documented by floci-gcp).
5. ✅ Cloud Run URIs answer from the host.
6. ✅ Custom endpoints work, with the `sql` path above.
7. Container pattern: `floci-gcp-local-gcp-{cloudsql,compute,cloudrun}-...`.

## 12. Verification (per phase)

1. `Clouds\Docker-clouds-builder.bat -platform <cloud>`: only that emulator runs and is healthy (Azure over HTTPS).
2. The 6 `cloud-api-*:1.0` images exist and pass D7.
3. `Clouds\Docker-clouds-<cloud>-dbapi-builder.bat` exits 0, including "All API checks passed."
4. Databases: `dbo.Customers` = 91 and `pilot.customers` = 91; `GenerateUniqueKeyDynamic` and `generate_unique_key_dynamic` exist.
5. APIs: all 6 healthchecks return 200; `get-all` returns 91 rows with a token and 401 without one.
6. Bruno collections against one cloud's base URL (**not run on 2026-11-05**).
7. Tempo: `curl http://localhost:3200/api/search/tag/service.name/values` lists `<cloud>-cloud-api-*` (all 6, DotNet included), and `.../tag/cloud.provider/values` lists the cloud.
8. Idempotency: run `terraform plan -detailed-exitcode` on each root (exit 0), and re-run the builder.
9. Restart: run `docker restart local-<cloud>`, record what comes back (§12.1), then re-run the builder; it must exit 0.
10. Single-platform switch: run `-platform <another>`. The current cloud is destroyed, its emulator stopped, and none of its containers remain (except, on AWS, the `floci-aws-ecr-registry` infrastructure container, which is removed with the sidecars).
11. Teardown: `-destroy` leaves no `floci-<cloud>-*` DB or API containers.

### 12.1 Results (2026-11-05)

All three clouds passed steps 1–5 and 7–11, with 91 customers on every API.

| Cloud | After `docker restart local-<cloud>` | Builder repair |
| --- | --- | --- |
| AWS | RDS containers and new ECS tasks come back by themselves, with data intact, and the gateways answer. **But** Floci keeps the old tasks' ENIs ("in use", not deletable through the API, task unknown), and they block `aws_subnet` deletion on a later `-destroy`. | 2-minute subnet delete timeout, then `:forget_network` (`state rm` of the VPC and subnets). Verified: the switch to `-platform azure` after an AWS stop/start printed the warning and completed. The timeout is stored at create time, so states created before it was added still wait the provider default (20 minutes). |
| Azure | Container Apps replicas come back. The SQL container exits (137), the PG container is gone, and `/connect` reports 409 / port 0. | `:heal_data_plane` replaces both servers. Verified. |
| GCP | Cloud Run and Cloud SQL come back. `<vm>_klt` exits (137). | `:heal_mssql_vm` replaces the VM. Verified. |

## 13. Phase 4 – Start / stop scripts

### 13.1 Files

| File | Usage |
| --- | --- |
| `Clouds\Docker-clouds-aws-start.bat`, `-azure-start.bat`, `-gcp-start.bat` | `[-norebuild]` |
| `Clouds\Docker-clouds-aws-stop.bat`, `-azure-stop.bat`, `-gcp-stop.bat` | no arguments |
| `Clouds\scripts\cloud-lifecycle.bat` | `:start <cloud> [-norebuild]` / `:stop <cloud>`; each wrapper only calls this |

Managed-container prefixes: AWS `floci-aws-`, Azure `floci-az-local-azure-`, GCP `floci-gcp-local-gcp-`.

### 13.2 Behaviour

**Start** (`:start <cloud>`):

1. `:check_platform`: a different single platform stops the script with the usual hint.
2. Creates `pilot-net` if needed. Runs `docker start` on `local-keycloak`, `local-loki`, `local-mimir`, `local-tempo`, `otel-collector` and `local-grafana` (a warning for any that do not exist).
3. Runs `docker start local-<cloud>`. If the container does not exist, it runs `docker compose up -d local-<cloud>` instead. Then it waits for the health URL. On Azure it also saves the TLS cert.
4. Waits 10 s for the emulator to reconcile its own containers. Then it starts the managed containers that are still `exited`, sorted by name (so a GCP VM container starts before its `_klt`).
5. If 20-apis has no resources in its state, it prints "run the dbapi builder" and exits 0.
6. Otherwise it runs `:verify_apis` with `WFU_TRIES=40` (about 2 minutes per API).
   - If the APIs fail: with `-norebuild` it prints the repair hint and exits 1; without it, it runs `Docker-clouds-<cloud>-dbapi-builder.bat`, which repairs the databases (D12) and reloads Northwind.
   - If they pass, it prints the base URLs.

**Stop** (`:stop <cloud>`):

1. Runs `docker stop local-<cloud>` **first**, so the emulator cannot replace containers (for example the ECS service's desired count).
2. Runs `docker stop` on every running container whose name starts with the cloud's prefix: databases, APIs, console sidecar, and the ECR registry.
3. Deletes nothing: data volumes, images and Terraform state are kept. `local-keycloak` and the OTEL stack keep running, because the local APIs use them too.

### 13.3 Verification

For each cloud, with that cloud deployed:

1. Run `Docker-clouds-<cloud>-stop.bat`. `docker ps` shows no `local-<cloud>` and no `floci-<cloud>-*` container.
2. Run `Docker-clouds-<cloud>-start.bat -norebuild`. Record whether the APIs pass without the builder.
3. Run `Docker-clouds-<cloud>-start.bat`. It must end with all 6 data probes OK, re-running the builder if needed.

Results: see §15.2.

## 14. Risks and open items

| Risk | Impact | Mitigation |
| --- | --- | --- |
| floci-az APIM does not forward headers or reach Container Apps | No API gateway on Azure | Ingress as the front door (§2.1); re-test APIM on newer floci-az releases |
| Enabling Azure TLS changes client usage | HTTPS clients must trust the floci-az CA | Port 4577 still answers HTTP; documented in `Clouds\README.md` |
| Emulators do not restart every DB container | APIs fail after a restart | Builders repair (D12); start scripts re-run the builder |
| AWS leaks ECS ENIs after a restart | `-destroy` hangs on subnets | Delete timeout + `:forget_network` |
| SQL Server × 3 (≈2–3 GB each) + 18 APIs (1 GB each) | Host memory pressure | `-platform <cloud>` |
| DB passwords as plain env vars (ECS, Cloud Run) and in `terraform.tfstate` | Visible in `docker inspect` and on local disk | Dev-only stack; state git-ignored; documented |
| Emulator container naming is undocumented and versioned | Hosts, leftovers and start/stop prefixes break on upgrade | Patterns recorded in §4, §9.5, §11.5 and §13.1; re-check after emulator upgrades |
| The databases are not visible in RDS / ARM / Cloud SQL listings (D9) | Less realistic consoles | Accepted trade-off |
| AWS RDS catalogue lists SQL Server Standard 15 while the image is 2025 | Version metadata differs | Cosmetic |

## 15. Execution notes (2026-11-05)

### 15.1 Differences from the first draft of this plan, and why

| Area | First draft | As built | Reason |
| --- | --- | --- | --- |
| Azure front door | APIM (`cloud-apim`) | Container Apps ingress, DNS suffix `localhost` | §2.1; user decision |
| SQL Server admin (AWS, Azure) | `cloudadmin` | `cloudadmin`, falling back to `sa` | Emulators apply the password to `sa` |
| GCP Cloud SQL admin | to be found | `postgres`/`postgres` | Fixed in floci-gcp |
| GCP VM | `cloud-mssql`, `e2-standard-4` | `mssql-vm`, `e2-standard-2` | 63-character DNS limit; machine catalogue |
| GCP `sql_custom_endpoint` | `.../sql/v1beta4/` | `http://localhost:4588/` | The provider appends the path |
| AWS invoke URL | path form `/execute-api/` | host form `*.execute-api.localhost.floci.io` | The path form is not documented for HTTP APIs |
| AWS 20-apis network | tag lookup | remote state outputs | Safe after `:forget_network` |
| DotNet OTEL / service name | `OTEL_*` | `Application__OpenTelemetry__*`, `Application__OpenApi__Title` | Set in code by PilotApiDotNet |
| Java DB URL | `DB_URL` | `DB_URL` + `SPRING_DATASOURCE_URL` | `application-prod-sqlserver.yml` hard-codes its URL |
| Loader sqlcmd | image default entrypoint | `--entrypoint /opt/mssql-tools18/bin/sqlcmd` | The banner broke stdin loads and the table count |
| Restart (D12) | "re-run the builder" | builder repairs + start/stop scripts | §12.1 |
| Data probe | single call | up to 5 tries | Stale pooled connections after a DB reload |
| Waits | `timeout /t` | `ping` | `timeout` fails without a console |
| Builder code | one self-contained `.bat` per cloud | shared `scripts\dbapi-common.bat` | Removes duplication across three builders |

### 15.2 Start/stop results (§13.3, 2026-11-05)

| Cloud | Stop | `start -norebuild` | `start` |
| --- | --- | --- | --- |
| AWS | Emulator + 9 containers stopped | ✅ All 6 probes OK. On start, Floci restarts RDS and replaces the stopped ECS tasks with new ones (old ones removed); the script restarted only the console and the ECR registry. | ✅ |
| Azure | Emulator + 3 running containers stopped (the emulator had already stopped the Container Apps replicas) | ✅ All 6 probes OK. The script restarted the SQL and PostgreSQL containers; floci-az restarted the replicas. | ✅ |
| GCP | Emulator + 9 containers stopped | ❌ (as designed, exit 1) The PostgreSQL APIs are OK, but the SQL Server APIs return 500: floci-gcp brings the VM and `_klt` back with a **fresh SQL Server** (the `DevUser` login is gone). | ✅ The builder runs on its own and reloads SQL Server (as `sa`); all 6 probes OK. |

So after a stop, AWS and Azure keep their data. GCP's SQL Server loses its data (no persistent disk is mounted for the container declaration), and `Docker-clouds-gcp-start.bat` reloads it.

## 16. Out of scope (possible follow-ups)

- Homepage, Uptime Kuma, and Dozzle entries for the cloud APIs.
- A UI (`Ui_angular`) configuration that points at the cloud URLs.
- JWT validation at the gateways. The APIs themselves still validate tokens (D10).
- Remote Terraform state (an S3 backend on `local-aws`).
- Root-level `.lnk` shortcuts for the new scripts.

## 17. Constraints

If Docker is not running or is not available for some other reason, stop processing and notify the user.
