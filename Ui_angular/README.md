# Docker - Setup - UI (Angular)

Build and run the Pilot Angular single page application container using Docker Compose.

## Preparation

Previous setup noted in the [Main README](../README.md) should have already been accomplished.

Change to the current directory.

```
cd Ui_angular
```

When this process is complete, change the directory back to the main directory.

```
cd ..
```

## Dependencies

- Docker Desktop with Docker Compose V2 (`docker compose`)
- Node.js and npm (matching the Angular CLI requirements of the project)
- Local clone of `PilotUiAngular` at:

```
C:\Working\Storage\Dev\GitHub\PilotUiAngular
```

## Files

| File | Purpose |
| --- | --- |
| `Docker-Ui-angular-builder.bat` | Primary entry point: publishes the Angular app and builds/starts the container. |
| `docker-compose.ui-angular.yml` | Compose definition for the `pilot-ui` container / `pilot-ui-angular` image. |
| `dockerfile` | Copies the published bundle into a non-root Nginx image. |
| `nginx.conf` | Static file server configuration with SPA fallback routing, `/api/<port>` reverse proxy routes, and a `/healthcheck` route. |
| `pilot-proxy-headers.conf` | Shared `proxy_set_header` snippet included by each `/api/<port>` location. |

## API Routing

Because the browser runs on the host, the API host names in these values must be reachable from the
host (for example `localhost` with the published API ports), not the internal `pilot-net` names.

The production bundle uses `apiBaseUrl: '/api'`, so the browser calls the UI's own origin and Nginx
reverse proxies `/api/<published-port>/...` to the API container over `pilot-net`. This mirrors
`proxy.conf.json` used by `ng serve` and avoids cross-origin requests, which the APIs do not permit
because no CORS policy is configured.

| Browser path | Upstream container | Container port |
| --- | --- | --- |
| `/api/55501/` | `pilot-api-dotnet-mssql` | `8080` |
| `/api/55601/` | `pilot-api-dotnet-postgres` | `8080` |
| `/api/56601/` | `pilot-api-java-mssql` | `56601` |
| `/api/56701/` | `pilot-api-java-postgres` | `56701` |

The API stacks must be running on the external `pilot-net` network before the UI can reach them.
The path segment is only a label matching the published host port; the upstream port is the
container's internal listener.

## Primary Script

Use:

```
Docker-Ui-angular-builder.bat
```

## What The Script Does

1. Pulls the `nginxinc/nginx-unprivileged:stable-alpine` image.
2. Runs `docker compose down` and `docker rm -f pilot-ui` to clear any prior container.
3. Backs up `src\environments\environment.ts`, regenerates it from `secrets\ui-angular.env`,
   runs `npm ci` and `npm run build:prod`, then restores the original file.
4. Copies `dist\PilotUiAngular\browser` and `nginx.conf` into the isolated build context
   `C:\Working\Storage\Dev\GitHub\Working\ui-angular`.
5. Runs `docker compose -p pilot-ui-angular up -d --build --force-recreate`, which builds the
   `pilot-ui-angular:1.0` image and starts the `pilot-ui` container on host port `55401`.
6. Opens `http://localhost:55401/` in the system browser.

`APP_DEPLOY_DATE` is set on the image (build argument `DEPLOY_DATE`) and on the running container
with the timestamp of the build.

Before compose startup, the script probes host ports in the range `55401-55499`. If the preferred
port is blocked, reserved, or in use on Windows, the script picks the first open port in that range
and prints the replacement.

## Manual Commands (Equivalent)

Run from this repository folder after the Angular bundle has been staged:

```bat
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "CURRENT_DATE=2026-08-03 00:00:00Z"
set "UI_ANGULAR_PORT=55401"
docker compose -f docker-compose.ui-angular.yml -p pilot-ui-angular up -d --build --force-recreate
```

## Endpoints

```
http://localhost:<UI_ANGULAR_PORT>/
http://localhost:<UI_ANGULAR_PORT>/healthcheck
```

## Additional Notes

- The container serves static files as a non-root user on container port `8080`.
- Inspect logs with:

```
docker compose -f docker-compose.ui-angular.yml logs --tail 200
```

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.ui-angular.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.ui-angular.yml down
```
