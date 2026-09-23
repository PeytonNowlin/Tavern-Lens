"""Independent reference for the hero-pick numbers the engine shows (ticket #15).

Reads the committed trimmed Firestone fixtures (Tests/Fixtures/Firestone) and prints, for the
full-game fixture's four offered heroes, Firestone's overlay numbers (research note
hero-pick-stats.md §3) with the lobby's tribes known and forced tribes left out:

    shown = averagePosition + Σ impactAveragePosition over the lobby's non-forced tribes,
    counting a tribe row only if dataPoints > hero.dataPoints/20 and
    dataPointsOnMissingTribe > dataPoints/20;
    tiers from μ/σ of every hero's shown average (heroes under 30 games, and heroes the
    lobby can't offer, left out).

Each hero's row comes from past-three when it has ≥ 300 games there, else past-seven, else
last-patch, else the window with the most games.

Usage: python3 expected_pick.py <repo root>
"""
import json, os, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
fixtures = os.path.join(root, "Tests/Fixtures/Firestone")
windows = ["past-three", "past-seven", "last-patch"]
files = {w: json.load(open(os.path.join(fixtures, f"hero-stats.mmr-100.{w}.trimmed.json"))) for w in windows}
index = {w: {h["heroCardId"]: h for h in files[w]["heroStats"]} for w in windows}

RACE = {"UNDEAD": 11, "MURLOC": 14, "DEMON": 15, "MECHANICAL": 17, "ELEMENTAL": 18, "BEAST": 20, "PIRATE": 23,
        "DRAGON": 24, "QUILBOAR": 43, "NAGA": 92, "ABERRATION": 126}
overrides = json.load(open(os.path.join(root, "Sources/HSData/Resources/bg-pool/overrides/36.6.1.json")))
rules = overrides["hero_tribe_rules"]

lobby = {"ABERRATION", "DRAGON", "ELEMENTAL", "QUILBOAR", "UNDEAD"}
forced = {"ABERRATION"}
weights = {RACE[t]: 1.0 for t in lobby - forced}


def stat(hero):
    best = None
    for w in windows:
        h = index[w].get(hero)
        if h is None:
            continue
        if h["dataPoints"] >= 300:
            return h, w
        if best is None or h["dataPoints"] > best[0]["dataPoints"]:
            best = (h, w)
    return best


def modifier(h):
    total = 0.0
    for t in h["tribeStats"]:
        w = weights.get(t["tribe"])
        if w and t["dataPoints"] > h["dataPoints"] / 20 and t["dataPointsOnMissingTribe"] > t["dataPoints"] / 20:
            total += w * t["impactAveragePosition"]
    return total


def offerable(hero):
    rule = rules.get(hero)
    if not rule:
        return True
    needs = set(rule.get("needs_any", []))
    if needs and not (needs & lobby):
        return False
    return not (set(rule.get("banned_with_any", [])) & lobby)


heroes = set().union(*[set(i) for i in index.values()])
shown = []
for hero in heroes:
    s = stat(hero)
    if s is None or s[0]["dataPoints"] < 30 or not offerable(hero):
        continue
    shown.append(s[0]["averagePosition"] + modifier(s[0]))
mu = sum(shown) / len(shown)
sigma = (sum((x - mu) ** 2 for x in shown) / len(shown)) ** 0.5


def tier(x):
    for letter, cut in [("S", mu - 3 * sigma), ("A", mu - 1.5 * sigma), ("B", mu), ("C", mu + sigma), ("D", mu + 2 * sigma)]:
        if x < cut:
            return letter
    return "E"


print(f"heroes {len(shown)}  mu {mu:.4f}  sigma {sigma:.4f}")
for hero in ["BG35_HERO_001", "TB_BaconShop_HERO_15", "BG23_HERO_305", "BG20_HERO_283"]:
    h, w = stat(hero)
    m = modifier(h)
    dist = {p["rank"]: p["percentage"] for p in h["placementDistribution"]}
    top4 = sum(v for r, v in dist.items() if r <= 4)
    print(f"{hero:22} {w:10} n={h['dataPoints']:5} base {h['averagePosition']:.2f} mod {m:+.4f} "
          f"shown {h['averagePosition'] + m:.4f} tier {tier(h['averagePosition'] + m)} top4 {top4:.1f} win {dist.get(1, 0):.1f}")
