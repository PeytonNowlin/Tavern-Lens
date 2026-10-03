#!/usr/bin/env bash
# Builds "Tavern Lens.app" with SwiftPM (no Xcode needed): the TavernLens executable
# plus Packaging/Info.plist, code-signed with a stable local identity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${TAVERN_SIGN_IDENTITY:-Tavern Lens Local}"
BUNDLE_ID="${TAVERN_BUNDLE_ID:-com.nowlinautomation.TavernLens}"
VERSION="${TAVERN_VERSION:-0.1.0}"
CONFIG="release"
OUT_DIR="$ROOT/build"
INSTALL=0
STAGE=0
JOBS=""
SDK=""
BUILD_SYSTEM=""

usage() {
    cat <<EOF
Usage: scripts/bundle-app.sh [--debug] [--output DIR] [--jobs N] [--sdk PATH] [--build-system NAME] [--install | --stage]

Builds the TavernLens product and assembles "Tavern Lens.app" (default: build/).

Options:
  --debug        Build the debug configuration instead of release.
  --output DIR   Put the app or staged ZIP in DIR instead of build/.
  --jobs N       Limit Swift build parallelism to N jobs (positive integer).
  --sdk PATH     Use a specific installed SDK, as in swift build --sdk.
  --build-system NAME  Use a specific SwiftPM build system.
  --install      Link /Applications to this bundle, keeping one app copy.
  --stage        Write a verified Tavern Lens.zip; leave the installed app alone.
  -h, --help     Show this help.

Environment:
  TAVERN_SIGN_IDENTITY  Code-signing identity (default: "Tavern Lens Local").
  TAVERN_BUNDLE_ID      Bundle identifier (default: com.nowlinautomation.TavernLens).
  TAVERN_VERSION        CFBundleShortVersionString (default: 0.1.0).

Signing:
  The app is signed with a self-signed code-signing certificate so macOS keeps
  Screen Recording and Accessibility permissions across rebuilds (an ad-hoc
  signature changes every build, and macOS then forgets the grants). If the
  identity is missing, the script falls back to ad-hoc signing ("-") and warns.

  One-time setup of the identity:
    1. Open Keychain Access.
    2. Choose Keychain Access > Certificate Assistant > Create a Certificate...
    3. Name: "$IDENTITY"
       Identity Type: Self-Signed Root
       Certificate Type: Code Signing
       Then click Create and accept the defaults. It goes into the login keychain.
    4. Check it's visible:  security find-identity -p codesigning
       (It shows as not trusted; that's fine for signing locally.)
    5. On the first signing, macOS asks to let codesign use the key: choose
       "Always Allow".
EOF
}

require_value() {
    if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "Missing value for $1" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="debug" ;;
        --output) require_value "$@"; OUT_DIR="$2"; shift ;;
        --sdk) require_value "$@"; SDK="$2"; shift ;;
        --build-system) require_value "$@"; BUILD_SYSTEM="$2"; shift ;;
        --jobs)
            require_value "$@"
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--jobs requires a positive integer" >&2; exit 2; }
            JOBS="$2"; shift ;;
        --stage) STAGE=1 ;;
        --install) INSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ "$STAGE" == 1 && "$INSTALL" == 1 ]]; then
    echo "--stage and --install cannot be combined" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd -P)"
APP="$OUT_DIR/Tavern Lens.app"
DEST="/Applications/Tavern Lens.app"

# Compare executable files as well as paths: /Applications may be a symlink to build/.
ensure_stopped() {
    local target="$1/Contents/MacOS/TavernLens" pids status pid executable
    if pids="$(pgrep -x TavernLens 2>/dev/null)"; then
        for pid in $pids; do
            # An exited process is harmless; a live process we cannot inspect is not.
            if ! executable="$(ps -p "$pid" -o comm=)"; then
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Cannot inspect running Tavern Lens process $pid; use --stage." >&2
                    return 1
                fi
                continue
            fi
            executable="${executable#"${executable%%[![:space:]]*}"}"
            if [[ "$executable" == "$target" || "$executable" -ef "$target" ]]; then
                echo "Tavern Lens is running from $1. Quit it before replacing this bundle, or use --stage." >&2
                return 1
            fi
        done
    else
        status=$?
        if [[ "$status" != 1 ]]; then
            echo "Cannot check whether Tavern Lens is running; use --stage." >&2
            return 1
        fi
    fi
}

ensure_targets_stopped() {
    ensure_stopped "$APP"
    if [[ "$INSTALL" == 1 && "$APP" != "$DEST" && ! "$APP" -ef "$DEST" ]]; then
        ensure_stopped "$DEST"
    fi
}

if [[ "$STAGE" == 1 ]]; then
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tavern-lens-stage.XXXXXX")"
    STAGED_ARCHIVE=""
    cleanup_stage() {
        rm -rf "$WORK_DIR"
        if [[ -n "$STAGED_ARCHIVE" ]]; then rm -f "$STAGED_ARCHIVE"; fi
    }
    trap cleanup_stage EXIT
    # Temporary, excluded from indexing, and never opened or registered with LaunchServices.
    APP="$WORK_DIR/stage.noindex/Tavern Lens.app"
else
    ensure_targets_stopped
fi

BUILD_ARGS=(--package-path "$ROOT" -c "$CONFIG")
if [[ -n "$JOBS" ]]; then BUILD_ARGS+=(--jobs "$JOBS"); fi
if [[ -n "$SDK" ]]; then BUILD_ARGS+=(--sdk "$SDK"); fi
if [[ -n "$BUILD_SYSTEM" ]]; then BUILD_ARGS+=(--build-system "$BUILD_SYSTEM"); fi
echo "==> Building TavernLens ($CONFIG)"
swift build "${BUILD_ARGS[@]}" --product TavernLens
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

# The user may have launched the app while Swift was building.
if [[ "$STAGE" == 0 ]]; then ensure_targets_stopped; fi
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TavernLens" "$APP/Contents/MacOS/TavernLens"

BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
# plutil -replace takes the values verbatim; sed would treat "|" and "&" in them as syntax.
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resources. A module's <Package>_<Module>.bundle is a flat folder that SwiftPM's
# accessor looks for next to the app's root, which code signing rejects, so its contents go
# to Contents/Resources/<Module> and the module looks there first (HSDataResources).
mkdir -p "$APP/Contents/Resources/HSData"
cp -R "$BIN_DIR/TavernLens_HSData.bundle/bg-pool" "$APP/Contents/Resources/HSData/"

# The other SwiftPM resource bundles (e.g. TavernLens_SimulatorRuntime.bundle) are copied whole
# into Contents/Resources and looked up from Bundle.main.resourceURL (see SimulatorResources).
for bundle in "$BIN_DIR"/TavernLens_*.bundle; do
    [[ -d "$bundle" ]] || continue
    [[ "$(basename "$bundle")" == TavernLens_HSData.bundle ]] && continue
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

# JavaScriptCore needs allow-jit to JIT the combat simulator (7x faster than interpreted).
ENTITLEMENTS="$ROOT/Packaging/TavernLens.entitlements"

echo "==> Signing"
if security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS" "$APP"
else
    echo "warning: code-signing identity \"$IDENTITY\" not found; signing ad-hoc." >&2
    echo "warning: macOS will forget permission grants on every rebuild. See --help to create it." >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --strict "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)=' || true

if [[ "$STAGE" == 1 ]]; then
    ARCHIVE="$WORK_DIR/Tavern Lens.zip"
    echo "==> Staging $OUT_DIR/Tavern Lens.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
    # TMPDIR and output can live on different disks. Copy to a hidden sibling first,
    # preserving the previous ZIP if copying or verification fails, then rename atomically.
    STAGED_ARCHIVE="$(mktemp "$OUT_DIR/.Tavern-Lens-stage.XXXXXX")"
    cp "$ARCHIVE" "$STAGED_ARCHIVE"
    unzip -tq "$STAGED_ARCHIVE"
    # Verify the signed bundle survives the archive round trip before publishing the ZIP.
    ditto -x -k "$STAGED_ARCHIVE" "$WORK_DIR/verify.noindex"
    codesign --verify --strict "$WORK_DIR/verify.noindex/Tavern Lens.app"
    mv -f "$STAGED_ARCHIVE" "$OUT_DIR/Tavern Lens.zip"
    STAGED_ARCHIVE=""
    echo "==> Staged: $OUT_DIR/Tavern Lens.zip (installed app unchanged)"
    exit 0
fi

if [[ "$INSTALL" == 1 ]]; then
    ensure_targets_stopped
    if [[ "$APP" != "$DEST" && ! "$APP" -ef "$DEST" ]]; then
        echo "==> Linking $DEST to $APP"
        rm -rf "$DEST"
        ln -s "$APP" "$DEST"
    fi
fi

echo "==> Done: $APP"
