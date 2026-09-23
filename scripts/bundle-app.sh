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

usage() {
    cat <<EOF
Usage: scripts/bundle-app.sh [--debug] [--output DIR] [--install]

Builds the TavernLens product and assembles "Tavern Lens.app" (default: build/).

Options:
  --debug        Build the debug configuration instead of release.
  --output DIR   Put the app in DIR instead of build/.
  --install      Also copy the app to /Applications (replacing an older copy).
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="debug" ;;
        --output) OUT_DIR="$2"; shift ;;
        --install) INSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

APP="$OUT_DIR/Tavern Lens.app"

echo "==> Building TavernLens ($CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG" --product TavernLens
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TavernLens" "$APP/Contents/MacOS/TavernLens"

BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|" \
    -e "s|__VERSION__|$VERSION|" \
    -e "s|__BUILD__|$BUILD_NUMBER|" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
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

if [[ "$INSTALL" == 1 ]]; then
    DEST="/Applications/Tavern Lens.app"
    echo "==> Installing to $DEST"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
fi

echo "==> Done: $APP"
