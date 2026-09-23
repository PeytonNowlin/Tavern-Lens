#!/usr/bin/env bash
# Bumps the pinned combat simulator (@firestone-hs/simulate-bgs-battle), rebuilds its
# JavaScriptCore bundle and the card data pinned with it, and keeps the result only if the
# golden odds tests pass. Otherwise every pinned file is put back as it was.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/Tools/Simulator"
RESOURCES="$ROOT/Sources/SimulatorRuntime/Resources"
CARDS_URL="https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json"

usage() {
    cat <<EOF
Usage: scripts/update-simulator.sh <version> [--reference-data <version>] [--cards FILE | --keep-cards]
       scripts/update-simulator.sh --rebuild [--cards FILE | --keep-cards]

Pins @firestone-hs/simulate-bgs-battle at <version> (exactly) in Tools/Simulator/package.json,
bundles it with esbuild into Sources/SimulatorRuntime/Resources/bgs-simulator.js, refreshes
the trimmed card DB pinned with it (simulator-cards.json.gz), and runs the golden odds tests
(scripts/test.sh --filter CombatOdds). If any step or test fails, the previous pin, bundle
and card data are restored and the script exits non-zero. Commit the changed files yourself.

Options:
  --rebuild                   Rebuild at the current pin (after editing Tools/Simulator/entry.js).
  --reference-data <version>  Pin @firestone-hs/reference-data at this version. Default: the
                              newest version the simulator's dependency range allows.
  --cards FILE                Trim this cards_enUS JSON (or .gz) instead of downloading it.
  --keep-cards                Keep the pinned card data as it is.
  -h, --help                  Show this help.

The card DB is Firestone's cards_enUS ($CARDS_URL),
trimmed to the Battlegrounds cards and the fields the simulator reads. It is fetched only
here, on a deliberate update, never by the app.
EOF
}

VERSION=""
REBUILD=0
REFERENCE=""
CARDS_FILE=""
KEEP_CARDS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild) REBUILD=1 ;;
        --reference-data) REFERENCE="$2"; shift ;;
        --cards) CARDS_FILE="$2"; shift ;;
        --keep-cards) KEEP_CARDS=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) VERSION="$1" ;;
    esac
    shift
done
if [[ "$REBUILD" == 0 && -z "$VERSION" ]]; then usage >&2; exit 2; fi

PINNED=(
    "$TOOLS/package.json" "$TOOLS/package-lock.json"
    "$RESOURCES/bgs-simulator.js" "$RESOURCES/bgs-simulator.pin.json" "$RESOURCES/simulator-cards.json.gz"
)
BACKUP="$(mktemp -d)"
trap 'rm -rf "$BACKUP"' EXIT
for file in "${PINNED[@]}"; do
    [[ -f "$file" ]] && cp "$file" "$BACKUP/$(basename "$file")"
done

restore() {
    echo "==> Restoring the previous pin, bundle and card data" >&2
    for file in "${PINNED[@]}"; do
        if [[ -f "$BACKUP/$(basename "$file")" ]]; then cp "$BACKUP/$(basename "$file")" "$file"; fi
    done
    npm ci --prefix "$TOOLS" --no-audit --no-fund >/dev/null 2>&1 || true
}
fail() {
    echo "error: $1" >&2
    restore
    exit 1
}

cd "$ROOT"
if [[ "$REBUILD" == 1 ]]; then
    echo "==> Installing the pinned packages"
    npm ci --prefix "$TOOLS" --no-audit --no-fund || fail "npm ci failed"
else
    if [[ -z "$REFERENCE" ]]; then
        RANGE="$(npm view "@firestone-hs/simulate-bgs-battle@$VERSION" 'dependencies.@firestone-hs/reference-data')" \
            || fail "no simulator version $VERSION on npm"
        REFERENCE="$(npm view "@firestone-hs/reference-data@$RANGE" version --json | node -e \
            'let v=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(Array.isArray(v)?v[v.length-1]:v)')"
    fi
    echo "==> Pinning simulate-bgs-battle $VERSION with reference-data $REFERENCE"
    npm install --prefix "$TOOLS" --save-exact --no-audit --no-fund \
        "@firestone-hs/simulate-bgs-battle@$VERSION" "@firestone-hs/reference-data@$REFERENCE" \
        || fail "npm install failed"
fi

echo "==> Bundling"
node "$TOOLS/build.mjs" || fail "esbuild failed"

if [[ "$KEEP_CARDS" == 0 ]]; then
    if [[ -z "$CARDS_FILE" ]]; then
        CARDS_FILE="$BACKUP/cards_enUS.json"
        echo "==> Downloading the card DB"
        curl --fail --silent --show-error --location --compressed -o "$CARDS_FILE" "$CARDS_URL" \
            || fail "could not download $CARDS_URL"
    fi
    echo "==> Trimming the card DB"
    node "$TOOLS/trim-cards.mjs" "$CARDS_FILE" "$RESOURCES/simulator-cards.json.gz" || fail "trimming the card DB failed"
fi

echo "==> Running the golden odds tests"
if ! "$ROOT/scripts/test.sh" --filter CombatOdds; then
    fail "the golden odds tests failed with this simulator; it was not accepted"
fi

echo "==> Accepted: $(tr -d '\n ' < "$RESOURCES/bgs-simulator.pin.json")"
echo "Review and commit: Tools/Simulator/package*.json and Sources/SimulatorRuntime/Resources/."
