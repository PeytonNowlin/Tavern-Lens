#!/usr/bin/env bash
# Packaging behavior tests using fake compiler, signer, and process inspection tools.
# No Swift compilation, app installation, app launch, or running-process changes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tavern-lens-packaging-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/repo/scripts" "$TEST_ROOT/repo/Packaging" "$TEST_ROOT/tools" \
    "$TEST_ROOT/bin/TavernLens_HSData.bundle/bg-pool" "$TEST_ROOT/bin/TavernLens_SimulatorRuntime.bundle" \
    "$TEST_ROOT/temporary" "$TEST_ROOT/output/Tavern Lens.app/Contents/MacOS"
cp "$ROOT/scripts/bundle-app.sh" "$TEST_ROOT/repo/scripts/"
cp "$ROOT/Packaging/Info.plist" "$ROOT/Packaging/TavernLens.entitlements" "$TEST_ROOT/repo/Packaging/"
printf 'fake executable\n' > "$TEST_ROOT/bin/TavernLens"
printf 'pool\n' > "$TEST_ROOT/bin/TavernLens_HSData.bundle/bg-pool/data.json"
printf 'simulator\n' > "$TEST_ROOT/bin/TavernLens_SimulatorRuntime.bundle/runtime.js"
printf 'running executable\n' > "$TEST_ROOT/output/Tavern Lens.app/Contents/MacOS/TavernLens"
printf 'existing app\n' > "$TEST_ROOT/output/Tavern Lens.app/sentinel"

cat > "$TEST_ROOT/tools/swift" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TAVERN_TEST_CALLS"
if [[ "$*" == *--show-bin-path* ]]; then printf '%s\n' "$TAVERN_TEST_BIN"; fi
TOOL
cat > "$TEST_ROOT/tools/security" <<'TOOL'
#!/usr/bin/env bash
exit 1
TOOL
cat > "$TEST_ROOT/tools/codesign" <<'TOOL'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >> "$TAVERN_TEST_CALLS"
TOOL
cat > "$TEST_ROOT/tools/pgrep" <<'TOOL'
#!/usr/bin/env bash
count=0
[[ ! -f "$TAVERN_TEST_PROCESS_CALLS" ]] || read -r count < "$TAVERN_TEST_PROCESS_CALLS"
count=$((count + 1))
printf '%s\n' "$count" > "$TAVERN_TEST_PROCESS_CALLS"
if [[ -n "${TAVERN_TEST_RUNNING_EXEC:-}" && "$count" -ge "${TAVERN_TEST_START_ON_CHECK:-1}" ]]; then
    printf '12345\n'
else
    exit 1
fi
TOOL
cat > "$TEST_ROOT/tools/ps" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$TAVERN_TEST_RUNNING_EXEC"
TOOL
cat > "$TEST_ROOT/tools/unzip" <<'TOOL'
#!/usr/bin/env bash
if [[ "${TAVERN_TEST_BAD_ARCHIVE:-0}" == 1 ]]; then exit 1; fi
exec /usr/bin/unzip "$@"
TOOL
cat > "$TEST_ROOT/tools/cp" <<'TOOL'
#!/usr/bin/env bash
if [[ "${TAVERN_TEST_COPY_FAIL:-0}" == 1 && "$2" == */.Tavern-Lens-stage.* ]]; then
    printf 'partial copy\n' > "$2"
    exit 1
fi
exec /bin/cp "$@"
TOOL
cat > "$TEST_ROOT/tools/mv" <<'TOOL'
#!/usr/bin/env bash
if [[ "$3" == */Tavern\ Lens.zip ]]; then
    [[ "$(dirname "$2")" == "$(dirname "$3")" ]] || exit 1
    printf 'atomic archive publication\n' >> "$TAVERN_TEST_CALLS"
fi
exec /bin/mv "$@"
TOOL
chmod +x "$TEST_ROOT/tools/"*
export PATH="$TEST_ROOT/tools:$PATH"
export TMPDIR="$TEST_ROOT/temporary"
export TAVERN_TEST_CALLS="$TEST_ROOT/calls"
export TAVERN_TEST_PROCESS_CALLS="$TEST_ROOT/process-calls"
export TAVERN_TEST_BIN="$TEST_ROOT/bin"
SCRIPT="$TEST_ROOT/repo/scripts/bundle-app.sh"
OUT="$TEST_ROOT/output"

fail() { echo "FAIL: $*" >&2; exit 1; }
reset_calls() { : > "$TAVERN_TEST_CALLS"; rm -f "$TAVERN_TEST_PROCESS_CALLS"; }
unchanged_app() { [[ "$(cat "$OUT/Tavern Lens.app/sentinel")" == 'existing app' ]] || fail 'existing app was replaced'; }
no_staging_bundles() {
    [[ -z "$(find "$TMPDIR" \( -name '*.app' -o -name 'tavern-lens-stage.*' \) -print -quit)" ]] \
        || fail 'temporary staging bundles survived'
    [[ -z "$(find "$OUT" -maxdepth 1 -name '.Tavern-Lens-stage.*' -print -quit)" ]] \
        || fail 'partial archive sibling survived'
}
expect_failure() {
    if bash "$SCRIPT" "$@" > "$TEST_ROOT/result" 2>&1; then fail "unexpected success: $*"; fi
}

# Staging works while the installed target is running and leaves only a verified ZIP.
export TAVERN_TEST_RUNNING_EXEC="$OUT/Tavern Lens.app/Contents/MacOS/TavernLens"
reset_calls
bash "$SCRIPT" --stage --jobs 2 --output "$OUT" > "$TEST_ROOT/result" 2>&1
unchanged_app
[[ -f "$OUT/Tavern Lens.zip" ]] || fail 'staged archive missing'
/usr/bin/unzip -Z1 "$OUT/Tavern Lens.zip" > "$TEST_ROOT/archive-files"
grep -Fxq 'Tavern Lens.app/Contents/MacOS/TavernLens' "$TEST_ROOT/archive-files" || fail 'ZIP has wrong executable layout'
grep -Fxq 'Tavern Lens.app/Contents/Resources/TavernLens_SimulatorRuntime.bundle/runtime.js' "$TEST_ROOT/archive-files" || fail 'resource bundle missing from ZIP'
grep -q -- '--jobs 2 --product TavernLens' "$TAVERN_TEST_CALLS" || fail 'Swift build job limit missing'
grep -q 'codesign --verify --strict .*verify.noindex/Tavern Lens.app' "$TAVERN_TEST_CALLS" || fail 'archive round-trip signature was not checked'
grep -q 'atomic archive publication' "$TAVERN_TEST_CALLS" || fail 'archive publication did not use same-directory rename'
no_staging_bundles

# A running bundle reached through a symlink is protected before any compilation.
ln -s "$OUT/Tavern Lens.app" "$TEST_ROOT/Installed Tavern Lens.app"
export TAVERN_TEST_RUNNING_EXEC="$TEST_ROOT/Installed Tavern Lens.app/Contents/MacOS/TavernLens"
reset_calls
expect_failure --output "$OUT"
grep -q 'Tavern Lens is running' "$TEST_ROOT/result" || fail 'symlink target was not recognized'
[[ ! -s "$TAVERN_TEST_CALLS" ]] || fail 'guard should run before building'
unchanged_app

# Installing another output must also protect an existing running /Applications copy.
export TAVERN_TEST_RUNNING_EXEC="/Applications/Tavern Lens.app/Contents/MacOS/TavernLens"
reset_calls
expect_failure --install --output "$OUT"
grep -q 'Tavern Lens is running from /Applications' "$TEST_ROOT/result" || fail 'running install destination was not protected'
[[ ! -s "$TAVERN_TEST_CALLS" ]] || fail 'install guard should run before building'
unchanged_app
export TAVERN_TEST_RUNNING_EXEC="$TEST_ROOT/Installed Tavern Lens.app/Contents/MacOS/TavernLens"

# Check again after compilation in case the user opened the app during the build.
export TAVERN_TEST_START_ON_CHECK=2
reset_calls
expect_failure --output "$OUT"
grep -q -- '--product TavernLens' "$TAVERN_TEST_CALLS" || fail 'race fixture did not reach the build'
grep -q 'Tavern Lens is running' "$TEST_ROOT/result" || fail 'running target was not rechecked after building'
unchanged_app
unset TAVERN_TEST_START_ON_CHECK

# A failed archive check keeps the prior staged archive and still cleans up.
cp "$OUT/Tavern Lens.zip" "$TEST_ROOT/prior.zip"
export TAVERN_TEST_BAD_ARCHIVE=1
expect_failure --stage --output "$OUT"
cmp -s "$OUT/Tavern Lens.zip" "$TEST_ROOT/prior.zip" || fail 'failed staging replaced the previous archive'
unchanged_app
no_staging_bundles
unset TAVERN_TEST_BAD_ARCHIVE

# Simulated disk-full during the cross-volume copy cannot truncate the previous ZIP.
export TAVERN_TEST_COPY_FAIL=1
expect_failure --stage --output "$OUT"
cmp -s "$OUT/Tavern Lens.zip" "$TEST_ROOT/prior.zip" || fail 'partial copy replaced the previous archive'
unchanged_app
no_staging_bundles
unset TAVERN_TEST_COPY_FAIL

# Invalid combinations and job limits fail without calling build or signing tools.
for jobs in 0 -1 1.5 abc; do
    reset_calls
    expect_failure --jobs "$jobs"
    [[ ! -s "$TAVERN_TEST_CALLS" ]] || fail "invalid job count built: $jobs"
done
reset_calls
expect_failure --stage --install
expect_failure --jobs
expect_failure --output
[[ ! -s "$TAVERN_TEST_CALLS" ]] || fail 'invalid options called build tools'
printf 'Packaging behavior tests passed.\n'
