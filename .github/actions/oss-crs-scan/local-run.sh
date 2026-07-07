#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Run locally exactly what the CI action does: build the oss-crs-runner image,
# then drive scan.sh (the same core the composite action calls) against this
# repo's .oss-fuzz project. Requires Docker; use a Linux/amd64 host for a
# faithful mirror of CI (the OSS-Fuzz base image is amd64).
#
# Usage:
#   .github/actions/oss-crs-scan/local-run.sh [HARNESS] [TIMEOUT_SECONDS]
#   HARNESS defaults to parse_class; TIMEOUT defaults to 120.
#
# Env overrides:
#   IMAGE=<ref>     use an existing image instead of building oss-crs-runner:local
#   NO_BUILD=1      skip the image build (implies a prebuilt IMAGE)
#   PROJ_PATH=...   OSS-Fuzz project dir (default: .oss-fuzz)
set -euo pipefail

SCAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCAN_DIR" rev-parse --show-toplevel)"

HARNESS="${1:-parse_class}"
TIMEOUT="${2:-120}"
IMAGE="${IMAGE:-oss-crs-runner:local}"

if ! docker info >/dev/null 2>&1; then
  echo "error: Docker is not available. Start Docker and retry." >&2
  exit 1
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "warning: non-Linux host — the OSS-Fuzz amd64 base image runs under" >&2
  echo "         emulation and will be slow; CI (ubuntu-latest) is the real target." >&2
fi

if [[ "${NO_BUILD:-0}" != "1" && "$IMAGE" == "oss-crs-runner:local" ]]; then
  echo "==> Building runner image ${IMAGE}"
  docker build -f "${SCAN_DIR}/runner.Dockerfile" -t "$IMAGE" "$SCAN_DIR"
fi

echo "==> Scanning harness '${HARNESS}' for ${TIMEOUT}s (fail-on-crash disabled)"
HARNESS="$HARNESS" \
TIMEOUT="$TIMEOUT" \
IMAGE="$IMAGE" \
WORKSPACE="$REPO_ROOT" \
PROJ_PATH="${PROJ_PATH:-.oss-fuzz}" \
FAIL_ON_CRASH="false" \
  bash "${SCAN_DIR}/scan.sh"

echo "==> Done. PoVs/logs (if any): ${REPO_ROOT}/oss-crs-artifacts/${HARNESS}"
