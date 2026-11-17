# Compliance Reviewer

The Compliance Reviewer, from the sister repository `..\AIAssistants\compliance-reviewer_any-ai`, deployed to Docker as a **testing environment**. A single container, `local-compliance-reviewer`, runs:

- **The reviewer itself**: the orchestrator, worker and review skills (`compliance-reviewer/`), the Claude Code and GitHub Copilot adapters (`.claude/`, `.github/`, `AGENTS.md`), the report script, and `scripts/run_review.py`.
- **The testers**: `test/logic/` and the nine deliberately flawed sample apps in `test/`, plus the build tools they need (.NET SDK 10, JDK 25, Maven 3.9, Python).
- **comp-review-api**: the FastAPI application on port **12001**, which runs reviews and testers as background jobs.
- **comp-review-ui**: the Angular Web UI on port **12101**.
- **The AI tool CLIs** that do the reviewing: Claude Code (`claude`) and GitHub Copilot CLI (`copilot`).

Both applications run with `Environment = development`, so the tester endpoints and the Testers page are available.

For what the reviewer, the API and the Web UI do, see their own READMEs in the source repository:

- `..\AIAssistants\compliance-reviewer_any-ai\compliance-reviewer\README.md` (the reviewer, its subjects and flags)
- `..\AIAssistants\compliance-reviewer_any-ai\api\README.md` (endpoints and settings)
- `..\AIAssistants\compliance-reviewer_any-ai\webui\README.md` (pages and settings)
- `..\AIAssistants\compliance-reviewer_any-ai\test\README.md` (sample apps and the answer key)

## Files

| File | Description |
| --- | --- |
| `Docker-compliance-reviewer-builder.bat` | Builds the image, starts the container, and opens the API's About endpoint and the Web UI. |
| `docker-compose.compliance-reviewer.yml` | The Compose service: ports, settings, secrets and host folders. |
| `dockerfile` | Multi-stage build: Web UI test and build, API tests, and the runtime image. |
| `entrypoint.sh` | Container start-up: writes the Web UI's `config.json`, then starts the API and the Web UI server. |
| `spa_server.py` | Small static server for the Web UI build (unknown paths fall back to `index.html`). |
| `..\secrets\compliance-reviewer.env.example` | Template for the AI tool credentials. |

## Prerequisites

- Docker Desktop, running.
- The [MikeLooper/AIAssistants](https://github.com/MikeLooper/AIAssistants) repository cloned next to this one, so that `..\AIAssistants\compliance-reviewer_any-ai` exists.
- At least one AI tool credential in `secrets\compliance-reviewer.env` (see [Credentials](#credentials)).

Nothing else is needed on the PC. Python, Node.js, .NET, Java and Maven are all inside the image, and the unit tests run inside the image build.

## Credentials

Copy the template and edit the copy:

```
copy secrets\compliance-reviewer.env.example secrets\compliance-reviewer.env
```

Uncomment the credentials you use and replace their placeholder values:

| Variable | Tool | How to get it |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Claude Code | An Anthropic Console API key. Billed per token. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code | Run `claude setup-token` on your PC. Uses your Claude subscription. |
| `COPILOT_GITHUB_TOKEN` | GitHub Copilot CLI | A fine-grained GitHub personal access token with the **Copilot Requests** permission. |

- Set one Claude credential, not both. If both are set, Claude Code uses the API key.
- The builder stops if no credential is set.
- A tool without a credential is still installed and listed as found by `/api/about`, but its jobs fail at sign-in.
- The file is passed to the container at runtime. It is never copied into the image, and git ignores it.

The same file can also override API settings with `COMP_REVIEW_API_*` variables, such as `COMP_REVIEW_API_DEFAULT_MODEL`. The template lists the common ones. The settings that define this deployment are fixed in the Compose file and take precedence: `Environment`, `Host`, `Port` and `CorsOrigins`.

## Build and start

Run from the repository root:

```
compliance-reviewer\Docker-compliance-reviewer-builder.bat
compliance-reviewer\Docker-compliance-reviewer-builder.bat -skiptests
```

The script:

1. Checks Docker, the source folder and the secrets file, and creates the `pilot-net` network if it does not exist.
2. Removes the previous container.
3. Picks the host ports. It uses 12001 (API) and 12101 (Web UI), or the next free port in each range if one is reserved or in use.
4. Copies the source into the build context `..\Working\compliance-reviewer\build`. The copy leaves out build output, dependencies, caches, Git data and earlier run output: `node_modules`, `bin`, `obj`, `target`, `.venv`, `__pycache__`, `transitions`, `reports`, `results`, and similar.
5. Builds the image:
   - The Web UI's Vitest tests run, then the Web UI is built.
   - The API's pytest tests run.
   - If any test fails, the build stops and the test output is shown.
   - `-skiptests` skips both test runs.
6. Starts the container and waits until `GET /api/health` answers.
7. Opens the API's About endpoint and the Web UI in the browser.

Rerun the script after changing the source. It also updates Claude Code and Copilot CLI to their latest versions.

The first build downloads the base images and takes several minutes. The image is about 3.2 GB, because it holds the .NET, Java and Node.js tool chains for the testers.

## URLs

| What | URL |
| --- | --- |
| Web UI | http://localhost:12101/ |
| API About | http://localhost:12001/api/about |
| API health | http://localhost:12001/api/health |
| Swagger UI | http://localhost:12001/swagger |
| OpenAPI document | http://localhost:12001/openapi.json |

If the builder picked other ports, it prints them, and the Web UI is set up to call the API on its actual port.

## Using it

### Web UI

| Page | Use |
| --- | --- |
| **Review** | Pick a zip file or a folder of source code. Choose the tool (`auto`, `claude` or `copilot`), the model, the subjects, advanced usage and a time limit, then start the review. |
| **Testers** | Run one or more of the nine testers. Each one runs a review of a sample app and scores it against the answer key. |
| **Jobs** | Lists every job, with its status, verdict, score and duration. |
| **Job** | Shows the live console output while a job runs. When it finishes, shows the report (and the test result for a tester). |
| **About** | The UI and API settings, health checks, and the tools found in the container. |

The Web UI zips a chosen folder in the browser and uploads it. The container never reads your folders directly.

### API

```
curl -F "file=@myapp.zip" -F "tool=claude" -F "model=claude-sonnet-5-5" http://localhost:12001/api/reviews
curl http://localhost:12001/api/jobs/<id>
curl http://localhost:12001/api/jobs/<id>/report -o myapp-review.md
curl -X POST http://localhost:12001/api/testers/api-python -H "Content-Type: application/json" -d "{\"noBuild\": true}"
```

### Command line in the container

The reviewer scripts can also be run directly. The working directory is the reviewer workspace, `/app/reviewer`:

```
docker exec -it local-compliance-reviewer python scripts/run_review.py --help
docker exec -it local-compliance-reviewer python test/logic/test_api_python.py --tool claude
docker exec -it local-compliance-reviewer python test/logic/test_all.py --help
docker exec -it local-compliance-reviewer bash
```

A target for `run_review.py` must be a path inside the container, such as one of the sample apps under `test/`. Code on your PC is reviewed through the Web UI or the API.

## Output on the host

Reports, transition files and tester results are written to host folders, so they survive rebuilds:

| Host | Container | Contents |
| --- | --- | --- |
| `..\Working\compliance-reviewer\reports` | `/app/reviewer/docs/reports` | Every review report (`<target>-compliance-review-<date>.md`) |
| `..\Working\compliance-reviewer\transitions` | `/app/reviewer/transitions` | Per-run transition files (`<runId>/`) |
| `..\Working\compliance-reviewer\test-results` | `/app/reviewer/test/logic/results` | Tester results, logs and reports |

Jobs themselves live in the API's memory. Restarting the container forgets them, but their files in these folders remain.

## Day-to-day commands

```
docker stop local-compliance-reviewer
docker start local-compliance-reviewer
docker logs -f local-compliance-reviewer
```

The container restarts automatically with Docker Desktop (`restart: unless-stopped`).

## Notes and limits

- **Testing environment only.** The API has no authentication, and every review spends model credit. Don't publish the ports beyond your PC.
- **The sample apps are insecure on purpose.** The testers only build and review them; they never run them.
- **One job at a time** (`MaxConcurrentJobs = 1`). Other jobs wait as `queued`.
- **Memory.** The container may use up to 6 GB. A tester run builds a sample app and runs an AI tool at the same time.
- **Time limits.** Reviews and testers stop after 60 minutes by default. A request can set its own limit.

## Remove

```
docker compose -f compliance-reviewer\docker-compose.compliance-reviewer.yml -p compliance-reviewer down
docker rmi local-compliance-reviewer
rmdir /S /Q ..\Working\compliance-reviewer
```

The last command also deletes the saved reports and results.
