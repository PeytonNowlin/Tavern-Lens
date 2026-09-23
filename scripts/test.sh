#!/usr/bin/env bash
# Runs `swift test`, adding what Swift Testing needs when only the Command Line
# Tools are installed.
#
# With the CLT (no Xcode), SwiftPM compiles its generated test runner without the
# CLT's Testing.framework on the framework search path, so the runner's
# `#if canImport(Testing)` is false and plain `swift test` builds, runs zero tests
# and exits 0. Passing -F for every Swift compile fixes that. (Package.swift adds
# the test target's own flags; see `commandLineToolsTesting` there.)
#
# Arguments are passed through, e.g. scripts/test.sh --filter FixtureReplayTests
# Record goldens with: TAVERN_RECORD_GOLDENS=1 scripts/test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

# The active toolchain decides it (DEVELOPER_DIR, else xcode-select), not whether Xcode is installed.
DEVELOPER="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ -d "$FRAMEWORKS/Testing.framework" && "$DEVELOPER" == /Library/Developer/CommandLineTools* ]]; then
    exec swift test --package-path "$ROOT" -Xswiftc -F -Xswiftc "$FRAMEWORKS" "$@"
else
    exec swift test --package-path "$ROOT" "$@"
fi
