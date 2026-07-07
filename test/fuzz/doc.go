// SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
// SPDX-License-Identifier: Apache-2.0

// Package fuzz holds native Go fuzz harnesses that exercise ampel's parsing
// entrypoints. The harnesses double as OSS-Fuzz targets: they are compiled to
// libFuzzer binaries by oss-fuzz/build.sh (via compile_native_go_fuzzer) and
// driven by OSS CRS in CI. They also run as ordinary seed-corpus tests under
// `go test ./test/fuzz/...` and locally with `go test -fuzz`.
package fuzz
