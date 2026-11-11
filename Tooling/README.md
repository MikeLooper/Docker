# Tooling

Developer tools that run locally in Docker containers. Each tool has a builder script in this folder, which creates its image and container, and a sub-folder with helper scripts for daily use.

| Tool | Purpose | Builder | Helpers | Container |
| --- | --- | --- | --- | --- |
| [SkillSpector](#skillspector) | Security scanner for AI agent skills | `Docker-SkillSpector-builder.bat` | `SkillSpector\` | `local-skillspector` |

Run the commands below from the repository root (`C:\Working\Storage\Dev\GitHub\Docker`).

---

## SkillSpector

SkillSpector, from NVIDIA, is a security scanner for AI agent skills, such as a Claude Code skill folder with a `SKILL.md`. It looks for risks like prompt injection, data exfiltration, too much autonomy, tool misuse, and unpinned dependencies. It uses static analysis (regex patterns, Python AST, YARA rules, taint tracking), and can also have an LLM review the skill. It never runs the skill it scans.

Each report has a risk score from 0 to 100, a severity (`LOW`, `MEDIUM`, `HIGH`, `CRITICAL`), and a recommendation (`SAFE`, `CAUTION`, `DO_NOT_INSTALL`), with each finding's location and remediation.

Source and full documentation: [https://github.com/NVIDIA/SkillSpector](https://github.com/NVIDIA/SkillSpector)

### Batch files

| File | Description |
| --- | --- |
| `Tooling\Docker-SkillSpector-builder.bat [git-ref]` | Clones SkillSpector at a pinned release (default `v2.13.4`, or the tag or branch given), builds the image `local-skillspector` with the project's own Dockerfile, and creates the container `local-skillspector`. Afterwards it deletes the source clone and any older, now untagged SkillSpector images. Rerun it to upgrade or to apply changed LLM settings. |
| `Tooling\SkillSpector\SkillSpector-scan.bat <skill> [options]` | Scans a skill and prints the report to the console. |
| `Tooling\SkillSpector\SkillSpector-report.bat <skill> [options]` | Scans a skill, saves Markdown and JSON reports to the reports folder, prints the Markdown report, and opens the folder. |
| `Tooling\SkillSpector\SkillSpector.bat <command> [options]` | Runs any SkillSpector command in the container, such as `--help`, `scan --help` or `baseline`. It takes container paths (see below). |
| `Tooling\SkillSpector\SkillSpector-start.bat` | Starts the container and prints the SkillSpector version. |
| `Tooling\SkillSpector\SkillSpector-stop.bat` | Stops the container. Nothing is deleted. |
| `Tooling\SkillSpector\skillspector-common.bat` | Shared routines for the helpers. It is not run directly. |

`<skill>` can be a skill folder, a single `SKILL.md`, a `.zip`, or a git URL. Any `[options]` after it are passed to `skillspector scan`.

### How it works

The image's entrypoint is the one-shot `skillspector` CLI. So the container is kept running idle (`sleep infinity`), and each scan runs with `docker exec`. The container has two mounts:

| Host | Container | Access |
| --- | --- | --- |
| `C:\Working\Storage\Dev\GitHub` | `/scan` | read-only |
| `C:\Working\Storage\Dev\GitHub\Working\skillspector-reports` | `/reports` | read-write |

The helpers translate Windows paths under `C:\Working\Storage\Dev\GitHub` to `/scan/...`. For a path anywhere else, they scan in a throwaway container (`docker run --rm`) that mounts the path's parent folder.

The scan helpers start the container if it is stopped. If it does not exist, they ask you to run the builder.

### LLM analysis (optional)

By default, scans are **static-only** (`--no-llm`), and the skill's contents stay on your PC. One exception: the dependency check still sends dependency names and versions to OSV.dev.

To also run SkillSpector's LLM review:

1. Copy `secrets\skillspector.env.example` to `secrets\skillspector.env`, and set `ANTHROPIC_API_KEY`. You can choose another provider with `SKILLSPECTOR_PROVIDER` (see the source README for the list).
2. Rerun `Tooling\Docker-SkillSpector-builder.bat`.

When the container has a provider set, the helpers stop adding `--no-llm`. To keep a single scan local anyway, pass `--no-llm` yourself.

> With LLM analysis on, the skill's file contents are sent to the configured provider.

### Usage

Build (first time, and whenever you upgrade):

```
Tooling\Docker-SkillSpector-builder.bat
```

Scan one skill file, or a whole skill folder (its `references\` and scripts included):

```
Tooling\SkillSpector\SkillSpector-scan.bat C:\Working\Storage\Dev\GitHub\AI-Working\.claude\skills\domain-feature-scaffold\SKILL.md
Tooling\SkillSpector\SkillSpector-scan.bat C:\Working\Storage\Dev\GitHub\AI-Working\.claude\skills\domain-feature-scaffold
```

Save reports to `C:\Working\Storage\Dev\GitHub\Working\skillspector-reports`:

```
Tooling\SkillSpector\SkillSpector-report.bat C:\Working\Storage\Dev\GitHub\AI-Working\.claude\skills\domain-feature-scaffold
```

Common options:

```
REM Scan every skill under a folder (up to 50)
Tooling\SkillSpector\SkillSpector-scan.bat C:\Working\Storage\Dev\GitHub\AI-Working\.claude\skills --recursive --max-skills 50

REM JSON or SARIF to the console; verbose output
Tooling\SkillSpector\SkillSpector-scan.bat <skill> -f json
Tooling\SkillSpector\SkillSpector-scan.bat <skill> -f sarif
Tooling\SkillSpector\SkillSpector-scan.bat <skill> -V

REM Make CI-style gates fail the exit code
Tooling\SkillSpector\SkillSpector-scan.bat <skill> --fail-on-findings --min-coverage 90

REM Scan a skill straight from a git repository
Tooling\SkillSpector\SkillSpector-scan.bat https://github.com/<owner>/<repo>.git
```

Baselines record findings you have reviewed and accepted, so later scans report only new ones. `SkillSpector.bat` takes container paths:

```
Tooling\SkillSpector\SkillSpector.bat baseline /scan/AI-Working/.claude/skills/domain-feature-scaffold -o /reports/domain-feature-scaffold.baseline.json
Tooling\SkillSpector\SkillSpector-scan.bat <skill> --baseline /reports/domain-feature-scaffold.baseline.json --show-suppressed
```

Help:

```
Tooling\SkillSpector\SkillSpector.bat --help
Tooling\SkillSpector\SkillSpector.bat scan --help
```

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Scan completed, and the score is 50 or less. |
| `1` | The score is above 50, or a strict gate (`--fail-on-findings`, `--min-coverage`, ...) fired. |
| `2` | Error. |

### Remove

```
docker rm -f local-skillspector
docker rmi local-skillspector:latest local-skillspector:v2.13.4
```
