#!/bin/sh
# Fetch the inputs for build_pool.py into the current directory.
# BUILD = client build (BuildNumber= in Power.log); HSDATA_REF = hsdata commit or tag for that build.
set -e
BUILD=${BUILD:-251952}
HSDATA_REF=${HSDATA_REF:-5212f4e178}
[ -f ../enums.json ] || curl -sSL -o ../enums.json "https://api.hearthstonejson.com/v1/enums.json"   # needed by ../powerlog.py
curl -sSL -o cards.json "https://api.hearthstonejson.com/v1/$BUILD/enUS/cards.json"
curl -sSL -o Bacon.xml "https://github.com/HearthSim/hsdata/raw/$HSDATA_REF/CardDefs.Bacon.xml"
curl -sSL -o mp.json "https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/"
curl -sSL -o rd_cards_rules.json "https://raw.githubusercontent.com/Zero-to-Heroes/hs-reference-data/master/src/cards_rules.json"
python3 - <<'PY'
import json, urllib.request, time
out, off = [], 0
while off is not None:
    req = urllib.request.Request(f"https://hsbg.cards/api/v1/cards?pool=true&limit=100&offset={off}", headers={"User-Agent": "pool-refresh"})
    d = json.load(urllib.request.urlopen(req)); out += d["data"]
    off = d["pagination"].get("nextOffset") if d["data"] else None; time.sleep(0.6)
json.dump(out, open("hsbg_all.json", "w"))
PY
python3 parse_bacon_xml.py >/dev/null   # writes bacon.json
