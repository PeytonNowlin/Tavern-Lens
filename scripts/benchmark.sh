#!/usr/bin/env bash
# Runs the opt-in benchmarks: timings on the captured games (catch-up, the log's entry point,
# the hero-pick banner's text recognition). They depend on the machine and on what else runs,
# so they aren't part of scripts/test.sh. Each test prints its time and checks it against the
# budget the spec gives.
#
#   scripts/benchmark.sh              debug build, as the tests run
#   scripts/benchmark.sh -c release   the budgets are for release builds
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAVERN_BENCHMARKS=1 exec "$ROOT/scripts/test.sh" --filter benchmark "$@"
