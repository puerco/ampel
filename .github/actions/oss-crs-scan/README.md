# `oss-crs-scan` — reusable OSS CRS action

Runs [OSS CRS](https://github.com/ossf/oss-crs) — the OpenSSF orchestration
framework for autonomous bug-finding — against one harness of an
**OSS-Fuzz-format** project, using the `crs-libfuzzer` engine (a pure fuzzer:
**no LLM, no API keys, no secrets**).

## Self-contained bundle (architecture)

This directory is a project-agnostic unit meant to be served from a **third-party
repo** (e.g. `carabiner-dev/oss-crs-action`) and consumed elsewhere as
`uses: <owner>/oss-crs-action@<sha>`. It ships everything it needs:

| File | Role |
| --- | --- |
| `action.yaml` | The composite action (maps inputs → env → `scan.sh`). |
| `scan.sh` | The scan core (prepare → build-target → run → collect). Shared by the action and `local-run.sh`. |
| `local-run.sh` | Run the exact CI flow on your machine (see **Test it locally**). |
| `runner.Dockerfile` | The oss-crs runner image (oss-crs CLI + Docker client/compose/buildx). Nothing project-specific. |
| `entrypoint.sh` | Wrapper so `oss-crs …` works from the mounted workspace. |
| `crs-libfuzzer.compose.yaml` | Compose for the pure fuzzer (default); sized for a 4 vCPU / 16 GB runner. |
| `crs-bug-finding-claude-code.compose.yaml` | Compose for the Claude Code bug-finding CRS (OAuth); LLM-driven, secret-gated. |

It lives inline in ampel today. To extract: move this folder to a new repo's
root, move `.github/workflows/oss-crs-image.yaml` alongside it, and change the
default `image` in `action.yaml` to the new repo's published image. Consumers
then swap `uses: ./.github/actions/oss-crs-scan` for `uses: <owner>/oss-crs-action@<sha>`.

The runner image is published to GHCR as `oss-crs-runner` by
`.github/workflows/oss-crs-image.yaml`.

## Inputs

| Input | Default | Notes |
| --- | --- | --- |
| `harness` | — (required) | Harness name (from the project's `build.sh`). |
| `crs` | `crs-libfuzzer` | Engine; selects the bundled compose. Also `crs-bug-finding-claude-code`. |
| `proj-path` | `oss-fuzz` | `--fuzz-proj-path` (the OSS-Fuzz project dir). |
| `image` | `ghcr.io/<owner>/oss-crs-runner:latest` | Runner image. |
| `compose-file` | bundled `<crs>.compose.yaml` | Override to resize/retarget. |
| `timeout` | `300` | Run budget (seconds). |
| `fail-on-crash` | `true` | `true` fails the job on a PoV (presubmit); `false` reports only. |
| `claude-code-oauth-token` | `""` | For the Claude Code CRS; from `claude setup-token`. Forwarded to the container. |
| `anthropic-api-key` | `""` | Alternative LLM auth via the LiteLLM proxy. |

Outputs: `crashed` (`true`/`false`) and `artifacts-dir` (collected PoVs + logs).

## Bug-finding with Claude Code (LLM CRS)

`crs: crs-bug-finding-claude-code` runs an LLM agent instead of a fuzzer. It
still builds the same `oss-fuzz` target + harness (ASAN snapshot for PoV
verification) but Claude Code drives the analysis. Because it needs a secret it
is **manual-dispatch only** (`.github/workflows/oss-crs-claude-code.yaml`) and
**must never run on fork PRs**. It skips LiteLLM/Postgres (OAuth mode) and is
bounded by `timeout` + the compose's `llm_budget` / `AGENT_TIMEOUT`.

Setup: `claude setup-token` → store as the `CLAUDE_CODE_OAUTH_TOKEN` repo secret →
run the **oss-crs-claude-code** workflow (defaults: harness `parse_class`, Sonnet
4.6, ~25 min). Locally: `CRS=crs-bug-finding-claude-code CLAUDE_CODE_OAUTH_TOKEN=… local-run.sh parse_class 600`.

## OSS CRS architecture coverage

Mapped against the [OSS CRS design](https://oss-crs.openssf.org/docs/design/architecture),
for the pure-fuzzer (`crs-libfuzzer`, `llm_config: null`) path:

- **CRS Compose** — `prepare` builds CRS images with `docker buildx bake`; `run`
  uses `docker compose`. That is why `runner.Dockerfile` ships **buildx and the
  compose plugin**, not just the docker client.
- **CRS container** — cpuset/`mem_limit` set in `crs-libfuzzer.compose.yaml`.
- **oss-crs-infra** — the LiteLLM proxy + PostgreSQL + key-gen sidecars are
  **skipped** (no LLM), so no secrets and no extra images. The lightweight
  exchange sidecar still runs; `oss_crs_infra` gets its own cpuset/memory.
- **SUBMIT_DIR → EXCHANGE_DIR → FETCH_DIR** and per-CRS/shared Docker networks
  live under `--work-dir` and on the host daemon; `scan.sh` harvests PoVs from
  both the submit and exchange paths.
- **Host requirements** — Docker daemon only; **no root, no `--privileged`**.
  cpuset/memory use standard Docker limits, so `oss-crs setup` (cgroups) is not
  run. The CLI drives the daemon over a mounted socket and never joins the
  workload networks, so there is no Docker-in-Docker nesting.

## How it stays isolated

- Runs on an **ephemeral** GitHub-hosted runner (the isolation boundary).
- crs-libfuzzer needs **no secrets**; callers use `on: pull_request` (never
  `pull_request_target`), so fork PR code can't reach credentials.
- The oss-crs CLI runs inside the pinned image and drives the runner's own Docker
  daemon via a mounted socket. The workspace is bind-mounted at the **same
  absolute path** in/out of the container so paths handed to the daemon resolve.
- The exact checkout is fuzzed via `--target-source-path` (PR head on presubmit),
  never a stale `main`.

## How ampel consumes it

ampel supplies the project-specific pieces:

- `test/fuzz/` — native Go fuzz harnesses (`FuzzParse*`), also run under `go test`.
- `oss-fuzz/` — the in-repo OSS-Fuzz project (`project.yaml`, `Dockerfile`,
  `build.sh`) that compiles those harnesses.

Harness names come from `oss-fuzz/build.sh`:

| `--target-harness` | Go fuzz func | Exercises |
| --- | --- | --- |
| `parse_provider_json` | `FuzzParseProviderJSON` | `pkg/context.NewProviderFromJSON` |
| `parse_provider_yaml` | `FuzzParseProviderYAML` | `pkg/context.NewProviderFromYAML` |
| `parse_identity` | `FuzzParseIdentity` | `pkg/evaluator/class.ParseIdentity` |
| `parse_class` | `FuzzParseClass` | `pkg/evaluator/class.ParseClass` |

The callers are `.github/workflows/oss-crs-presubmit.yaml` (PRs) and
`.github/workflows/oss-crs-periodic.yaml` (cron).

## Test it locally

Because the action is a thin wrapper over `scan.sh`, you can run the identical
flow — build image, `prepare`, `build-target`, `run`, collect PoVs — on your own
machine. Requires Docker; use a **Linux/amd64** host for a faithful mirror (the
OSS-Fuzz base image is amd64; other hosts work under slow emulation).

```bash
# From the repo root: build the runner image and fuzz one harness for 120s.
.github/actions/oss-crs-scan/local-run.sh parse_class 120

# Reuse an already-published image instead of building:
IMAGE=ghcr.io/<owner>/oss-crs-runner:latest \
  .github/actions/oss-crs-scan/local-run.sh parse_provider_json 60
```

PoVs and logs land in `oss-crs-artifacts/<harness>/`.

## Status / caveat

The Go harnesses and the OSS-Fuzz build definition are validated locally with
`go test`. The full oss-crs Docker loop needs a Linux Docker host — validate it
with `local-run.sh` (above) or a CI dry-run (`workflow_dispatch` the image build,
then the periodic workflow) before relying on the presubmit. If the socket-mounted
approach trips over oss-crs's own bundled script paths, the fallback is to install
uv and run oss-crs directly on the runner (drop the `docker run` wrapper in
`scan.sh`).

## Bumping OSS CRS

Update `OSS_CRS_REF` in both `runner.Dockerfile` and `oss-crs-image.yaml`,
rebuild the image, and re-run a dry-run.
