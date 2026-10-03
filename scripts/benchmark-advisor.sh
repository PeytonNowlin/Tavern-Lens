#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'USAGE'
Usage: scripts/benchmark-advisor.sh [swift test arguments]

Defaults to the native build system, release configuration and 5 warm repetitions per case/policy.
TAVERN_ADVISOR_BENCHMARK_OUTPUT selects the JSON report path.
TAVERN_ADVISOR_BENCHMARK_REPETITIONS selects 1 through 100 repetitions.
TAVERN_ADVISOR_BENCHMARK_DIAGNOSTICS optionally selects a local captured corpus.
TAVERN_ADVISOR_BENCHMARK_MAX_CAPTURED caps it at 12 distinct requests by default.
The report contains opaque case IDs and behavior hashes, with no raw game data.
Run again in a fresh process to compare first-search timing across processes.
USAGE
    exit 0
fi

export TAVERN_ADVISOR_BENCHMARK=1
export TAVERN_ADVISOR_BENCHMARK_OUTPUT="${TAVERN_ADVISOR_BENCHMARK_OUTPUT:-${TMPDIR:-/tmp}/tavern-advisor-benchmark.json}"
ARGS=()
HAS_CONFIGURATION=0
HAS_BUILD_SYSTEM=0
for ARG in "$@"; do
    case "$ARG" in
        -c|--configuration|--configuration=*) HAS_CONFIGURATION=1 ;;
    esac
    case "$ARG" in
        --build-system|--build-system=*) HAS_BUILD_SYSTEM=1 ;;
    esac
done
if [[ "$HAS_CONFIGURATION" == 0 ]]; then
    ARGS+=(--configuration release)
fi
if [[ "$HAS_BUILD_SYSTEM" == 0 ]]; then
    ARGS+=(--build-system native)
fi
exec "$ROOT/scripts/test.sh" "${ARGS[@]}" --filter "AdvisorPerformanceTests/benchmark" "$@"
