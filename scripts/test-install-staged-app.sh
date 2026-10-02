#!/usr/bin/env bash
# Native atomic swaps on disposable fixture bundles; no real install, build, or app launch.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tavern-lens-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO="$TEST_ROOT/fixture repo"
BUILD="$REPO/build"
APP="$BUILD/Tavern Lens.app"
mkdir -p "$REPO/scripts" "$TEST_ROOT/tools" "$TEST_ROOT/Applications" "$TEST_ROOT/source.noindex/Tavern Lens.app/Contents/MacOS"
cp "$ROOT/scripts/install-staged-app.sh" "$REPO/scripts/"
SCRIPT="$REPO/scripts/install-staged-app.sh"
export TAVERN_TEST_REAL_PYTHON="$(command -v python3)"
export TAVERN_TEST_APP="$APP"
export TAVERN_APPLICATIONS_LINK="$TEST_ROOT/Applications/Tavern Lens.app"
export TAVERN_TEST_CALLS="$TEST_ROOT/calls"
export TAVERN_TEST_SWAPS="$TEST_ROOT/swaps"
export TAVERN_TEST_CHECKS="$TEST_ROOT/checks"
ln -s "$APP" "$TAVERN_APPLICATIONS_LINK"

cat > "$TEST_ROOT/tools/python3" <<'TOOL'
#!/usr/bin/env bash
if [[ "$2" == check-swap && "${TAVERN_TEST_NO_SWAP:-0}" == 1 ]]; then exit 1; fi
if [[ "$2" == swap ]]; then
    count=0
    [[ ! -f "$TAVERN_TEST_SWAPS" ]] || read -r count < "$TAVERN_TEST_SWAPS"
    count=$((count + 1)); printf '%s\n' "$count" > "$TAVERN_TEST_SWAPS"
    if [[ "${TAVERN_TEST_ROLLBACK_FAIL:-0}" == 1 && "$count" == 2 ]]; then exit 1; fi
    "$TAVERN_TEST_REAL_PYTHON" "$@"
    status=$?
    if [[ "$status" == 0 && "$count" == 1 && "${TAVERN_TEST_SWAP_SIGNAL:-0}" == 1 ]]; then
        kill -TERM "$PPID"
    fi
    exit "$status"
fi
exec "$TAVERN_TEST_REAL_PYTHON" "$@"
TOOL
cat > "$TEST_ROOT/tools/codesign" <<'TOOL'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >> "$TAVERN_TEST_CALLS"
app="${!#}"
if [[ "${TAVERN_TEST_REJECT_NEW:-0}" == 1 && "$(cat "$app/version.txt")" == new ]]; then exit 1; fi
if [[ "${TAVERN_TEST_POST_VERIFY_FAIL:-0}" == 1 && "$app" -ef "$TAVERN_TEST_APP" && "$(cat "$app/version.txt")" == new ]]; then exit 1; fi
TOOL
cat > "$TEST_ROOT/tools/pgrep" <<'TOOL'
#!/usr/bin/env bash
count=0
[[ ! -f "$TAVERN_TEST_CHECKS" ]] || read -r count < "$TAVERN_TEST_CHECKS"
count=$((count + 1)); printf '%s\n' "$count" > "$TAVERN_TEST_CHECKS"
if [[ -n "${TAVERN_TEST_RUNNING:-}" && "$count" -ge "${TAVERN_TEST_START_ON_CHECK:-1}" ]]; then printf '12345\n'; else exit 1; fi
TOOL
cat > "$TEST_ROOT/tools/ps" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$TAVERN_TEST_RUNNING"
TOOL
cat > "$TEST_ROOT/tools/ditto" <<'TOOL'
#!/usr/bin/env bash
if [[ "${TAVERN_TEST_BACKUP_FAIL:-0}" == 1 && "$*" == *'Tavern Lens.previous.zip'* && "$1" == -c ]]; then exit 1; fi
exec /usr/bin/ditto "$@"
TOOL
for forbidden in swift open osascript; do
    cat > "$TEST_ROOT/tools/$forbidden" <<'TOOL'
#!/usr/bin/env bash
printf 'forbidden command\n' >> "$TAVERN_TEST_CALLS"
exit 99
TOOL
done
chmod +x "$TEST_ROOT/tools/"*
export PATH="$TEST_ROOT/tools:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
reset_fixture() {
    unset TAVERN_TEST_RUNNING TAVERN_TEST_START_ON_CHECK TAVERN_TEST_NO_SWAP TAVERN_TEST_REJECT_NEW \
        TAVERN_TEST_POST_VERIFY_FAIL TAVERN_TEST_SWAP_SIGNAL TAVERN_TEST_ROLLBACK_FAIL TAVERN_TEST_BACKUP_FAIL
    rm -rf "$BUILD"
    mkdir -p "$APP/Contents/MacOS"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.nowlinautomation.TavernLens</string>
<key>CFBundleExecutable</key><string>TavernLens</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/TavernLens"
    chmod +x "$APP/Contents/MacOS/TavernLens"
    printf 'old\n' > "$APP/version.txt"
    /bin/cp -R "$APP/." "$TEST_ROOT/source.noindex/Tavern Lens.app/"
    printf 'new\n' > "$TEST_ROOT/source.noindex/Tavern Lens.app/version.txt"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TEST_ROOT/source.noindex/Tavern Lens.app" "$BUILD/Tavern Lens.zip"
    rm -f "$TAVERN_TEST_SWAPS" "$TAVERN_TEST_CHECKS"
    : > "$TAVERN_TEST_CALLS"
}
expect_failure() {
    if bash "$SCRIPT" "$@" > "$TEST_ROOT/result" 2>&1; then fail "unexpected install success: $*"; fi
}
old_unchanged() {
    [[ "$(cat "$APP/version.txt")" == old ]] || fail 'old app was not preserved/restored'
    [[ "$TAVERN_APPLICATIONS_LINK" -ef "$APP" ]] || fail 'Applications shortcut changed'
}
clean_workspace() {
    [[ -z "$(find "$BUILD" -maxdepth 1 -name '.tavern-lens-install.*' -print -quit)" ]] || fail 'temporary app workspace survived'
    [[ "$(find "$BUILD" -type d -name '*.app' | wc -l | tr -d ' ')" == 1 ]] || fail 'more than one installed bundle remains'
    ! grep -q 'forbidden command' "$TAVERN_TEST_CALLS" || fail 'install tried to build or open an app'
}

reset_fixture
bash "$SCRIPT" > "$TEST_ROOT/result" 2>&1
[[ "$(cat "$APP/version.txt")" == new ]] || fail 'new bundle was not promoted'
[[ "$TAVERN_APPLICATIONS_LINK" -ef "$APP" ]] || fail 'shortcut no longer reaches canonical bundle'
[[ "$(/usr/bin/unzip -p "$BUILD/Tavern Lens.previous.zip" 'Tavern Lens.app/version.txt')" == old ]] || fail 'backup does not contain old bundle'
grep -q '=identifier "com.nowlinautomation.TavernLens"' "$TAVERN_TEST_CALLS" || fail 'signature identity requirement missing'
clean_workspace
# The previous ZIP is directly usable, even though this promotion replaces that backup.
bash "$SCRIPT" --archive "$BUILD/Tavern Lens.previous.zip" > "$TEST_ROOT/result" 2>&1
old_unchanged
[[ "$(/usr/bin/unzip -p "$BUILD/Tavern Lens.previous.zip" 'Tavern Lens.app/version.txt')" == new ]] || fail 'rollback did not preserve replaced new bundle'
clean_workspace

# Block a running target through the Applications symlink, including a launch during preparation.
for check in 1 2; do
    reset_fixture
    export TAVERN_TEST_RUNNING="$TAVERN_APPLICATIONS_LINK/Contents/MacOS/TavernLens"
    export TAVERN_TEST_START_ON_CHECK="$check"
    expect_failure
    old_unchanged
    [[ ! -f "$TAVERN_TEST_SWAPS" ]] || fail 'running target was swapped'
    clean_workspace
done

# Reject a mismatched installation rather than creating a competing app.
reset_fixture
rm "$TAVERN_APPLICATIONS_LINK"
ln -s "$TEST_ROOT/source.noindex/Tavern Lens.app" "$TAVERN_APPLICATIONS_LINK"
expect_failure
[[ "$(cat "$APP/version.txt")" == old && ! -s "$TAVERN_TEST_CALLS" ]] || fail 'mismatched install was modified'
rm "$TAVERN_APPLICATIONS_LINK"
ln -s "$APP" "$TAVERN_APPLICATIONS_LINK"

# Archive, identity, signature, native-swap availability, and backup failures preserve the app.
for failure in archive traversal identity signature unavailable backup backup-directory; do
    reset_fixture
    case "$failure" in
        archive) printf 'not a zip' > "$BUILD/Tavern Lens.zip" ;;
        traversal)
            "$TAVERN_TEST_REAL_PYTHON" - "$BUILD/Tavern Lens.zip" <<'PYTHON'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('../escape', 'unsafe')
PYTHON
            ;;
        backup-directory) mkdir "$BUILD/Tavern Lens.previous.zip" ;;
        identity)
            sed -i '' 's/com.nowlinautomation.TavernLens/example.WrongApp/' "$TEST_ROOT/source.noindex/Tavern Lens.app/Contents/Info.plist"
            /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TEST_ROOT/source.noindex/Tavern Lens.app" "$BUILD/Tavern Lens.zip" ;;
        signature) export TAVERN_TEST_REJECT_NEW=1 ;;
        unavailable) export TAVERN_TEST_NO_SWAP=1 ;;
        backup) export TAVERN_TEST_BACKUP_FAIL=1 ;;
    esac
    expect_failure
    old_unchanged
    [[ ! -f "$TAVERN_TEST_SWAPS" ]] || fail "$failure reached app replacement"
    clean_workspace
done

# Both a verification failure and a signal immediately after the syscall restore the old inode.
for failure in verify signal; do
    reset_fixture
    old_inode="$(stat -f '%d:%i' "$APP")"
    if [[ "$failure" == verify ]]; then export TAVERN_TEST_POST_VERIFY_FAIL=1; else export TAVERN_TEST_SWAP_SIGNAL=1; fi
    expect_failure
    old_unchanged
    [[ "$(stat -f '%d:%i' "$APP")" == "$old_inode" && "$(cat "$TAVERN_TEST_SWAPS")" == 2 ]] || fail "$failure did not atomically roll back"
    clean_workspace
done

# If rollback itself fails, retain the old bundle and verified ZIP for recovery.
reset_fixture
export TAVERN_TEST_POST_VERIFY_FAIL=1 TAVERN_TEST_ROLLBACK_FAIL=1
expect_failure
grep -q 'Rollback failed; recovery bundle retained' "$TEST_ROOT/result" || fail 'rollback failure was not reported'
[[ "$(/usr/bin/unzip -p "$BUILD/Tavern Lens.previous.zip" 'Tavern Lens.app/version.txt')" == old ]] || fail 'recovery ZIP missing'
[[ "$(find "$BUILD" -path '*/candidate.noindex/Tavern Lens.app/version.txt' -exec cat {} \;)" == old ]] || fail 'old recovery bundle was deleted'
printf 'Staged installation behavior tests passed.\n'
