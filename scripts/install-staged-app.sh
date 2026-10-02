#!/usr/bin/env bash
# Promote a staged update without rebuilding, opening, or quitting Tavern Lens.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$ROOT/build"
APP="$BUILD/Tavern Lens.app"
ARCHIVE="$BUILD/Tavern Lens.zip"
BUNDLE_ID="${TAVERN_BUNDLE_ID:-com.nowlinautomation.TavernLens}"
# Read-only inspection override for the hermetic packaging tests; never a write destination.
APPLICATIONS_LINK="${TAVERN_APPLICATIONS_LINK:-/Applications/Tavern Lens.app}"

usage() {
    cat <<'HELP'
Usage: scripts/install-staged-app.sh [--archive ZIP]

Install build/Tavern Lens.zip into this checkout's existing build/Tavern Lens.app.
Quit Tavern Lens first. This script never quits or opens the app automatically.
The previous bundle is saved as build/Tavern Lens.previous.zip for rollback.

Options:
  --archive ZIP  Install a different staged or backup archive.
  -h, --help     Show this help.

TAVERN_BUNDLE_ID selects the expected bundle identity, as in bundle-app.sh.
TAVERN_APPLICATIONS_LINK overrides the inspected shortcut path for tests only.
HELP
}
fail() { echo "error: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail 'Missing ZIP after --archive'
            ARCHIVE="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "Unknown option: $1" ;;
    esac
    shift
done

ensure_install_location() {
    [[ -d "$APP" && ! -L "$APP" ]] || fail "Expected the existing physical bundle at $APP"
    if [[ -e "$APPLICATIONS_LINK" || -L "$APPLICATIONS_LINK" ]]; then
        [[ -L "$APPLICATIONS_LINK" && "$APPLICATIONS_LINK" -ef "$APP" ]] \
            || fail "$APPLICATIONS_LINK does not point to this checkout's bundle; keep one installation before updating."
    fi
}
ensure_stopped() {
    local pids status pid executable
    if pids="$(pgrep -x TavernLens 2>/dev/null)"; then
        for pid in $pids; do
            if ! executable="$(ps -p "$pid" -o comm=)" || [[ -z "$executable" ]]; then
                if kill -0 "$pid" 2>/dev/null; then fail "Cannot inspect Tavern Lens process $pid"; fi
                continue
            fi
            executable="${executable#"${executable%%[![:space:]]*}"}"
            if [[ "$executable" == "$APP/Contents/MacOS/TavernLens" \
                || "$executable" == "$APPLICATIONS_LINK/Contents/MacOS/TavernLens" \
                || "$executable" -ef "$APP/Contents/MacOS/TavernLens" ]]; then
                fail 'Tavern Lens is running. Quit it before installing the staged update.'
            fi
        done
    else
        status=$?
        [[ "$status" == 1 ]] || fail 'Cannot check whether Tavern Lens is running'
    fi
}

# Exact archive layout and no links keep extraction confined to the private work directory.
verify_archive() {
    python3 - archive "$1" <<'PY'
import pathlib, stat, sys, zipfile
with zipfile.ZipFile(sys.argv[2]) as archive:
    entries = archive.infolist()
    if not entries:
        raise SystemExit('Empty app archive')
    for entry in entries:
        path = pathlib.PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
            raise SystemExit('Unsafe archive path')
        if not path.parts or path.parts[0] not in ('Tavern Lens.app', '__MACOSX'):
            raise SystemExit('Archive must contain only Tavern Lens.app and ZIP metadata')
        if path.parts[0] == '__MACOSX' and (len(path.parts) > 1 and path.parts[1] not in ('Tavern Lens.app', '._Tavern Lens.app')):
            raise SystemExit('Unexpected ZIP metadata root')
        mode = entry.external_attr >> 16
        if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise SystemExit('App archive contains an unsupported link or special file')
    if archive.testzip() is not None:
        raise SystemExit('App archive failed its integrity check')
PY
}
verify_bundle() {
    [[ -d "$1" && ! -L "$1" && -x "$1/Contents/MacOS/TavernLens" ]] || fail 'Staged app executable is missing'
    python3 - identity "$1/Contents/Info.plist" "$BUNDLE_ID" <<'PY'
import plistlib, sys
with open(sys.argv[2], 'rb') as source:
    info = plistlib.load(source)
if info.get('CFBundleIdentifier') != sys.argv[3] or info.get('CFBundleExecutable') != 'TavernLens' or info.get('CFBundlePackageType') != 'APPL':
    raise SystemExit('App bundle identity does not match Tavern Lens')
PY
    codesign --verify --strict -R "=identifier \"$BUNDLE_ID\"" "$1"
}
swap_bundles() {
    python3 - swap "$APP" "$CANDIDATE" <<'PY'
import ctypes, os, sys
library = ctypes.CDLL(None, use_errno=True)
swap = library.renamex_np
swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
swap.restype = ctypes.c_int
if swap(os.fsencode(sys.argv[2]), os.fsencode(sys.argv[3]), 0x00000002) != 0:
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PY
}

ensure_install_location
ensure_stopped
[[ -f "$ARCHIVE" ]] || fail "Missing archive: $ARCHIVE"
[[ ! -d "$BUILD/Tavern Lens.previous.zip" ]] || fail 'Backup ZIP destination is a directory'
python3 - check-swap <<'PY'
import ctypes, sys
if sys.platform != 'darwin' or not hasattr(ctypes.CDLL(None), 'renamex_np'):
    raise SystemExit('Atomic bundle replacement is unavailable; existing app unchanged')
PY
verify_archive "$ARCHIVE"
verify_bundle "$APP"
OLD_ID="$(stat -f '%d:%i' "$APP")"
WORK_DIR="$(mktemp -d "$BUILD/.tavern-lens-install.XXXXXX")"
CANDIDATE="$WORK_DIR/candidate.noindex/Tavern Lens.app"
COMMITTED=0
cleanup() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    # Inspect inode identity rather than a flag after swap: a signal can arrive between
    # the atomic syscall and the shell receiving its successful exit status.
    if [[ "$COMMITTED" == 0 && -d "$CANDIDATE" \
        && "$(stat -f '%d:%i' "$CANDIDATE")" == "$OLD_ID" ]]; then
        if swap_bundles; then
            echo 'Restored the previous Tavern Lens bundle.' >&2
        else
            echo "Rollback failed; recovery bundle retained at $CANDIDATE" >&2
            echo "Verified backup: $BUILD/Tavern Lens.previous.zip" >&2
            exit 1
        fi
    fi
    rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

echo '==> Verifying staged update'
ditto -x -k "$ARCHIVE" "$WORK_DIR/candidate.noindex"
verify_bundle "$CANDIDATE"
echo '==> Saving previous app'
BACKUP="$WORK_DIR/Tavern Lens.previous.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BACKUP"
verify_archive "$BACKUP"
ditto -x -k "$BACKUP" "$WORK_DIR/backup-check.noindex"
verify_bundle "$WORK_DIR/backup-check.noindex/Tavern Lens.app"
# Publish the backup by same-volume rename only after it passes a round-trip check.
mv -f "$BACKUP" "$BUILD/Tavern Lens.previous.zip"
ensure_install_location
ensure_stopped
[[ "$(stat -f '%d:%i' "$APP")" == "$OLD_ID" ]] || fail 'The installed app changed while preparing this update'
echo '==> Installing staged update'
swap_bundles
verify_bundle "$APP"
COMMITTED=1
echo "==> Installed: $APP"
echo "==> Previous app: $BUILD/Tavern Lens.previous.zip"
echo 'Open Tavern Lens when ready.'
