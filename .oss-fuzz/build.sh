#!/bin/bash -eu
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Compiles ampel's native Go fuzz harnesses (test/fuzz) into libFuzzer binaries.
# Each entry maps a `func FuzzXxx(*testing.F)` to a harness name; that harness
# name is what OSS CRS receives via `--target-harness`.
#
# Usage of compile_native_go_fuzzer (provided by base-builder-go):
#   compile_native_go_fuzzer <package> <FuzzFunc> <harness_name>

FUZZ_PKG="github.com/carabiner-dev/ampel/test/fuzz"

compile_native_go_fuzzer "$FUZZ_PKG" FuzzParseProviderJSON parse_provider_json
compile_native_go_fuzzer "$FUZZ_PKG" FuzzParseProviderYAML parse_provider_yaml
compile_native_go_fuzzer "$FUZZ_PKG" FuzzParseIdentity      parse_identity
compile_native_go_fuzzer "$FUZZ_PKG" FuzzParseClass         parse_class
