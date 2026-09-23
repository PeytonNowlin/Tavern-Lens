"""Trims Firestone mmr-100 hero-stats files into the committed test fixtures (ticket #15).

Download the raw files first (plain curl works; Python's default User-Agent gets a 403):
    for t in past-three past-seven last-patch; do
      curl -s --compressed -o <raw>/$t.json \
        https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/$t/overview-from-hourly.gz.json
    done
Usage: python3 trim_hero_stats.py <raw dir> <repo>/Tests/Fixtures/Firestone

past-three keeps every hero (the tier cut-offs need the whole field); past-seven and
last-patch keep only the heroes past-three has fewer than 300 games for, plus the four
heroes the full-game fixture offers. Fields the overlay doesn't read are dropped.
"""
import json, os, sys

raw, out = sys.argv[1], sys.argv[2]
offered = {"BG35_HERO_001", "BG20_HERO_283", "BG23_HERO_305", "TB_BaconShop_HERO_15"}


def trim_hero(h):
    return {
        "heroCardId": h["heroCardId"],
        "dataPoints": h["dataPoints"],
        "totalOffered": h["totalOffered"],
        "totalPicked": h["totalPicked"],
        "averagePosition": h["averagePosition"],
        "conservativePositionEstimate": h["conservativePositionEstimate"],
        "placementDistribution": [
            {"rank": p["rank"], "percentage": round(p["percentage"], 3)}
            for p in h["placementDistribution"]
        ],
        "tribeStats": [
            {
                "tribe": t["tribe"],
                "dataPoints": t["dataPoints"],
                "dataPointsOnMissingTribe": t["dataPointsOnMissingTribe"],
                "impactAveragePosition": round(t["impactAveragePosition"], 4),
            }
            for t in h["tribeStats"]
        ],
        "mmrPercentile": h["mmrPercentile"],
        "timePeriod": h["timePeriod"],
    }


three = json.load(open(os.path.join(raw, "past-three.json")))
small = {h["heroCardId"] for h in three["heroStats"] if h["dataPoints"] < 300}
for t in ["past-three", "past-seven", "last-patch"]:
    d = json.load(open(os.path.join(raw, t + ".json")))
    keep = d["heroStats"] if t == "past-three" else [h for h in d["heroStats"] if h["heroCardId"] in small | offered]
    trimmed = {
        "lastUpdateDate": d["lastUpdateDate"],
        "dataPoints": d["dataPoints"],
        "mmrPercentiles": d["mmrPercentiles"],
        "heroStats": [trim_hero(h) for h in keep],
    }
    path = os.path.join(out, f"hero-stats.mmr-100.{t}.trimmed.json")
    with open(path, "w") as f:
        json.dump(trimmed, f, separators=(",", ":"))
        f.write("\n")
    print(path, len(keep), os.path.getsize(path))
