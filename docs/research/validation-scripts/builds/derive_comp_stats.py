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
import math
import sys

MINIMUM_SHARE = 0.02
ALIASES = {
    "abberation_deathrattle": "aberration_deathrattle",
    "abberation_discard": "aberration_discard",
}


def normalize(comps):
    groups = {}
    for comp in comps:
        key = ALIASES.get(comp["archetype"], comp["archetype"])
        # An identical label repeated in the source is not another population.
        groups.setdefault(key, {}).setdefault(comp["archetype"], comp)
    result = []
    for key, group in sorted(groups.items()):
        rows = [group[label] for label in sorted(group)]
        merged = dict(rows[0], archetype=key)
        if len(rows) > 1:
            population = sum(row["dataPoints"] for row in rows)
            merged["dataPoints"] = population
            if population > 0:
                merged["averagePlacement"] = sum(row["averagePlacement"] * row["dataPoints"] for row in rows) / population
            merged["sampledBoards"] = sum(row["sampledBoards"] for row in rows)
            counts = {}
            for row in rows:
                for card, count in row["boardsWithCard"].items():
                    counts[card] = counts.get(card, 0) + count
            merged["boardsWithCard"] = counts
            buckets = sorted({item["mmr"] for row in rows for item in row["averagePlacementAtMmr"]}, reverse=True)
            placements = []
            for mmr in buckets:
                observations = [next((item for item in row["averagePlacementAtMmr"] if item["mmr"] == mmr), None) for row in rows]
                observations = [item for item in observations if item is not None and item["dataPoints"] > 0
                                and math.isfinite(item["placement"]) and 1 <= item["placement"] <= 8]
                population = sum(item["dataPoints"] for item in observations)
                if population > 0:
                    placements.append({"mmr": mmr, "dataPoints": population,
                                       "placement": sum(item["placement"] * item["dataPoints"] for item in observations) / population})
            merged["averagePlacementAtMmr"] = placements
        result.append(merged)
    return result


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
            "boardsWithCard": counts,
        })
    comps = normalize(comps)
    for comp in comps:
        floor = comp["sampledBoards"] * MINIMUM_SHARE
        comp["boardsWithCard"] = {k: v for k, v in comp["boardsWithCard"].items() if v >= floor and v > 0}
    return {
        "lastUpdateDate": raw.get("lastUpdateDate") or "",
        "timePeriod": raw.get("timePeriod") or "",
        "dataPoints": raw.get("dataPoints") or 0,
        "comps": comps,
    }


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        print(json.dumps(derive(json.load(f)), sort_keys=True, separators=(",", ":")))
