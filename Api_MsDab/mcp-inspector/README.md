# MCP Inspector (Data API builder)

MCP Inspector runs as `pilot-msdab-mcp-inspector` on `pilot-net` and is published only on the loopback address:

```
http://localhost:56501/
```

It uses Inspector v2 (`ghcr.io/modelcontextprotocol/inspector:2.8.0`). v2 has a single web port (6274 in the container). v1's separate proxy port and `MCP_PROXY_PORT` setting no longer exist.

## Auto-Connect Links

Replace `<MCP_INSPECTOR_API_TOKEN>` with the value from `secrets\ms-dab.env`. The builder script opens both links for you.

SQL Server:

```
http://localhost:56501/?serverUrl=http://pilot-api-msdab-mssql:5000/mcp&transport=http&autoConnect=<MCP_INSPECTOR_API_TOKEN>
```

PostgreSQL:

```
http://localhost:56501/?serverUrl=http://pilot-api-msdab-postgres:5000/mcp&transport=http&autoConnect=<MCP_INSPECTOR_API_TOKEN>
```

| Parameter | Value |
| --- | --- |
| `serverUrl` | DAB's MCP endpoint, by container name. The Inspector backend connects from its own container, so `localhost` would not reach DAB. |
| `transport` | `http` means Streamable HTTP. |
| `autoConnect` | Must equal `MCP_INSPECTOR_API_TOKEN`. Without a match, the Inspector ignores the link. |

## Authentication

Authentication stays on. The Inspector backend can start processes on request, so the token protects it. Instead of disabling authentication (`DANGEROUSLY_OMIT_AUTH`), the setup:

- sets a fixed token from `secrets\ms-dab.env` (`MCP_INSPECTOR_API_TOKEN`), so auto-connect links keep working across restarts;
- publishes the port on `127.0.0.1` only;
- limits `ALLOWED_ORIGINS` to `http://localhost:56501` and `http://127.0.0.1:56501`. Other origins get HTTP 403.

## Manual Connection

In the Inspector UI, add a server with:

- Transport: **Streamable HTTP**
- URL: `http://pilot-api-msdab-mssql:5000/mcp` or `http://pilot-api-msdab-postgres:5000/mcp`

Then choose **Connect**, and **Tools > List Tools**. DAB exposes `describe_entities`, `read_records`, `create_record`, `update_record`, `delete_record`, `aggregate_records`, and `execute_entity`.

The tools can change data (the entities use `anonymous:*` permissions).

## Command-Line Check

The Inspector CLI in the container can check the MCP endpoints without a browser:

```
docker exec pilot-msdab-mcp-inspector mcp-inspector --cli --server-url http://pilot-api-msdab-mssql:5000/mcp --transport http --method tools/list
```
