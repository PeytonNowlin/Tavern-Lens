#!/usr/bin/env python3
"""Reduce Firestone's raw comp-stats file to the form Tavern Lens bundles and caches.

Mirrors `FirestoneCompStats.derive(fromFirestone:)` in Sources/HSData/BuildSources.swift:
per archetype, its placement numbers, the number of sampled final boards and, per card,
how many boards had it (`_G` goldens folded into the base card; cards on under 2% of
boards left out).

Usage (from the repo root):
  curl -s --compressed -o comp.json \
    https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json
  curl -s --compressed -o strategies.json \
    https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json
  python3 docs/research/validation-scripts/builds/derive_comp_stats.py comp.json \
    > Sources/HSData/Resources/bg-pool/builds/firestone-comp-stats.json
  cp strategies.json Sources/HSData/Resources/bg-pool/builds/firestone-comp-strategies.json
"""
import json
import sys

MINIMUM_SHARE = 0.02


def derive(raw):
    comps = []
    for comp in raw["compStats"]:
        boards = 0
        counts = {}
        for hero in comp.get("heroStats") or []:
            for board in hero.get("finalBoards") or []:
                boards += 1
                seen = set()
                for minion in (board.get("finalComp") or {}).get("board") or []:
                    card = minion.get("cardID")
                    if not card:
                        continue
                    if card.endswith("_G"):
                        card = card[:-2]
                    seen.add(card)
                for card in seen:
                    counts[card] = counts.get(card, 0) + 1
        floor = boards * MINIMUM_SHARE
        comps.append({
            "archetype": comp["archetype"],
            "dataPoints": comp.get("dataPoints") or 0,
            "averagePlacement": comp.get("averagePlacement") or 0,
            "averagePlacementAtMmr": [
                {"mmr": e["mmr"], "dataPoints": e.get("dataPoints") or 0, "placement": e["placement"]}
                for e in comp.get("averagePlacementAtMmr") or []
                if e.get("mmr") is not None and e.get("placement") is not None
            ],
            "sampledBoards": boards,
            "boardsWithCard": {k: v for k, v in counts.items() if v >= floor and v > 0},
        })
    comps.sort(key=lambda c: c["archetype"])
    return {
        "lastUpdateDate": raw.get("lastUpdateDate") or "",
        "timePeriod": raw.get("timePeriod") or "",
        "dataPoints": raw.get("dataPoints") or 0,
        "comps": comps,
    }


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        print(json.dumps(derive(json.load(f)), sort_keys=True, separators=(",", ":")))
