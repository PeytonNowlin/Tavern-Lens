#!/usr/bin/env bash
# Refreshes the pinned HearthstoneJSON enums.json that the build generates Swift enums from
# (Plugins/HSEnumsPlugin -> Tools/HSEnumsGenerator).
#
# Usage: scripts/update-enums.sh <build>
#   <build>  the Hearthstone build the new enums belong to, e.g. 251952 (the last part of
#            CFBundleVersion in /Applications/Hearthstone/Hearthstone.app/Contents/Info.plist).
#
# HearthstoneJSON publishes enums.json unversioned (https://api.hearthstonejson.com/v1/enums.json),
# updated with each patch, so run this after HearthstoneJSON has picked up the patch, then
# review the diff and commit Data/HearthstoneJSON/enums.json and enums.build together.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="$ROOT/Data/HearthstoneJSON"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

curl --fail --silent --show-error --location -o "$TMP" "https://api.hearthstonejson.com/v1/enums.json"
# Sanity check: a JSON object with a GameTag group.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d.get("GameTag"), dict) and len(d["GameTag"]) > 1000' "$TMP"

mv "$TMP" "$DATA/enums.json"
trap - EXIT
echo "$1" > "$DATA/enums.build"
echo "Updated $DATA/enums.json for build $1. Rebuild to regenerate the enums, then review the diff."
