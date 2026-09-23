#!/usr/bin/env bash
# Replays every bookmarked advisor case under new weights and reports how the advice changed.
#
# Usage: scripts/advisor-tune.sh <weights.json> [--bookmarks <record-store-dir>] [--out <report.txt>]
#
#   <weights.json>   AdvisorWeights as JSON; list only what changes, e.g. {"lobby": 0.8, "tierTurnValue": 7}
#   --bookmarks DIR  also replay the app's saved bookmarks, e.g.
#                    ~/Library/Application\ Support/TavernLens/Games (read only)
#   --out FILE       also write the report to FILE
#
# Cases: the committed golden bookmark cases with advice, the advisor's golden turn-11 state, and
# (when the private fixtures are present) the full game's turns 8-12. Each is re-scored with its
# recorded plan and seed, exactly as far as it was scored when shown, under the new weights.
# See docs/advisor/scoring.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

[[ $# -ge 1 ]] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac
WEIGHTS="$1"
shift
[[ -f "$WEIGHTS" ]] || { echo "no such weights file: $WEIGHTS" >&2; exit 2; }
BOOKMARKS=""
OUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bookmarks) BOOKMARKS="${2:?--bookmarks needs a directory}"; shift 2 ;;
        --out) OUT="${2:?--out needs a file}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

abs() { (cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"); }
export TAVERN_ADVISOR_WEIGHTS="$(abs "$WEIGHTS")"
export TAVERN_ADVISOR_BOOKMARKS="$BOOKMARKS"
if [[ -n "$OUT" ]]; then
    export TAVERN_ADVISOR_REPORT="$(abs "$OUT")"
else
    export TAVERN_ADVISOR_REPORT=""
fi

"$ROOT/scripts/test.sh" --filter "AdvisorTuningTests/tuningRun" 2>&1 \
    | sed -n '/===== Advisor tuning report =====/,/^=================================$/p;/error:\|recorded an issue\|failed after/p'
