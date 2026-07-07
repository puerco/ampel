# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# OSS-Fuzz builder image for ampel's native Go fuzz harnesses.
#
# The `git clone` only scaffolds $SRC/ampel (go.mod, module layout) so layers
# cache well. At build/run time OSS CRS overlays the actual checked-out tree via
# `--target-source-path`, so the code that gets fuzzed is exactly what CI checked
# out (the PR head on presubmit, the scanned ref on periodic) — never stale main.
FROM gcr.io/oss-fuzz-base/base-builder-go

RUN git clone --depth=1 https://github.com/carabiner-dev/ampel "$SRC/ampel"
WORKDIR $SRC/ampel
COPY build.sh $SRC/
