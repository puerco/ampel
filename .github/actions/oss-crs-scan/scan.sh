#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Core OSS CRS scan logic, shared by the composite action (action.yaml) and the
# local runner (local-run.sh) so "local == CI" by construction. Configuration
# comes from environment variables:
#
#   HARNESS        (required) harness name, e.g. parse_class
#   PROJ_PATH      OSS-Fuzz project dir           (default: .oss-fuzz)
#   WORKSPACE      repo checkout root             (default: git toplevel)
#   IMAGE          runner image                   (default: ghcr.io/$OWNER/oss-crs-runner:latest)
#   OWNER          GHCR owner for the default IMAGE
#   COMPOSE_FILE   CRS compose file               (default: bundled compose)
#   TIMEOUT        run budget in seconds          (default: 300)
#   FAIL_ON_CRASH  exit non-zero on a PoV         (default: true)
#   GITHUB_OUTPUT  if set, `crashed`/`artifacts-dir` are written there
set -euo pipefail

SCAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HARNESS="${HARNESS:?HARNESS is required}"
PROJ_PATH="${PROJ_PATH:-.oss-fuzz}"
WORKSPACE="${WORKSPACE:-$(git rev-parse --show-toplevel)}"
TIMEOUT="${TIMEOUT:-300}"
FAIL_ON_CRASH="${FAIL_ON_CRASH:-true}"

IMAGE="${IMAGE:-}"
if [[ -z "$IMAGE" ]]; then
  if [[ -z "${OWNER:-}" ]]; then
    echo "error: set IMAGE, or OWNER to derive ghcr.io/<owner>/oss-crs-runner:latest" >&2
    exit 2
  fi
  IMAGE="ghcr.io/$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')/oss-crs-runner:latest"
fi

WORKDIR="${WORKSPACE}/.oss-crs-work"
ARTIFACTS="${WORKSPACE}/oss-crs-artifacts/${HARNESS}"
mkdir -p "$WORKDIR" "$ARTIFACTS"

# The container only sees $WORKSPACE, so a bundled default compose is copied in.
COMPOSE_FILE="${COMPOSE_FILE:-}"
if [[ -z "$COMPOSE_FILE" ]]; then
  COMPOSE_FILE="${WORKDIR}/crs-libfuzzer.compose.yaml"
  cp -f "${SCAN_DIR}/crs-libfuzzer.compose.yaml" "$COMPOSE_FILE"
fi

echo "::group::Config"
echo "image=$IMAGE"
echo "harness=$HARNESS  timeout=${TIMEOUT}s"
echo "compose=$COMPOSE_FILE  proj=$PROJ_PATH  work=$WORKDIR"
echo "::endgroup::"

# Run the oss-crs CLI from the image. The workspace is bind-mounted at the SAME
# absolute path in and out of the container, and the Docker socket is shared, so
# the paths oss-crs hands to the daemon resolve on the host.
oss_crs() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${WORKSPACE}:${WORKSPACE}" \
    -w "${WORKSPACE}" \
    "$IMAGE" "$@"
}

echo "::group::image"
# Pull only registry images; a locally-built image (e.g. :local) stays as-is.
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
echo "::endgroup::"

echo "::group::prepare"
oss_crs prepare --compose-file "$COMPOSE_FILE" --work-dir "$WORKDIR"
echo "::endgroup::"

echo "::group::build-target"
oss_crs build-target \
  --compose-file "$COMPOSE_FILE" \
  --fuzz-proj-path "$PROJ_PATH" \
  --target-source-path "${WORKSPACE}" \
  --work-dir "$WORKDIR"
echo "::endgroup::"

echo "::group::run"
run_rc=0
oss_crs run \
  --compose-file "$COMPOSE_FILE" \
  --fuzz-proj-path "$PROJ_PATH" \
  --target-source-path "${WORKSPACE}" \
  --target-harness "$HARNESS" \
  --timeout "$TIMEOUT" \
  --work-dir "$WORKDIR" || run_rc=$?
echo "run exit code: $run_rc"
echo "::endgroup::"

# Collect PoVs. A finding is written to a CRS's SUBMIT_DIR/<harness>/povs/, then
# promoted by the exchange sidecar to EXCHANGE_DIR/<target>/<harness>/povs/. The
# libFuzzer engine also drops raw reproducers (crash-*/oom-*/timeout-*/leak-*).
# Catch all of them so neither the submit nor the exchange path is missed.
echo "::group::collect"
crashed=false
while IFS= read -r -d '' pov; do
  crashed=true
  cp -f "$pov" "$ARTIFACTS/" 2>/dev/null || true
done < <(find "$WORKDIR" \
           \( -path '*/povs/*' \
              -o -name 'crash-*' -o -name 'oom-*' -o -name 'timeout-*' -o -name 'leak-*' \) \
           -type f -print0 2>/dev/null)
# Keep logs for triage regardless.
find "$WORKDIR" -type d -name 'logs' -exec cp -a {} "$ARTIFACTS/" \; 2>/dev/null || true
echo "crashed=$crashed"
ls -la "$ARTIFACTS" || true
echo "::endgroup::"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "crashed=$crashed"
    echo "artifacts-dir=$ARTIFACTS"
  } >> "$GITHUB_OUTPUT"
fi

if [[ "$crashed" == "true" ]]; then
  echo "PoV found for harness '${HARNESS}' (artifacts in ${ARTIFACTS})."
  if [[ "$FAIL_ON_CRASH" == "true" ]]; then
    echo "Failing because FAIL_ON_CRASH=true."
    exit 1
  fi
fi
