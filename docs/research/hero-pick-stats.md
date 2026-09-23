# Hero, trinket and quest pick stats: data sources

Researched 2026-09-22 (local EDT). Some file timestamps are in UTC on 2026-09-23. Unless noted, every URL was retrieved on 2026-09-22 with plain `curl` and no special headers. Raw downloads and scripts (`join.py`, `fsalgo.py`) are in the session scratchpad under `herostats/`. Related docs: [ecosystem-and-data-sources.md](ecosystem-and-data-sources.md), [meta-comps-2026-09.md](meta-comps-2026-09.md), [minion-pool-and-tribe-inference.md](minion-pool-and-tribe-inference.md), [logs-and-extractable-state.md](logs-and-extractable-state.md).

## TL;DR

- **Firestone's static stats files are the only free, public, machine-readable source of BG hero pick stats.** They need no auth and no special headers. Each file gives, per hero: average placement, a conservative estimate, pick rate (`totalPicked/totalOffered`), the full 1st–8th placement distribution (so top-4 and win rate follow from it), combat winrate by turn, warband stats by turn, and **per-tribe placement impact** (`tribeStats`). There is one file per MMR percentile (100/50/25/10/1) and per time window (`last-patch`, `past-seven`, `past-three`, `all-time`). Trinket stats come in one file per window, with the MMR split inside it. **Correction to earlier docs:** the "403 for `past-7`/`past-3`" was the wrong slug. The real slugs are `past-seven` and `past-three`, and all of them return 200. S3 answers **403 AccessDenied for any missing key**, so a 403 here means "not found". It is not access control.
- **HSReplay Tier7** (`POST https://hsreplay.net/api/v1/battlegrounds/hero_pick/`, plus `trinket_pick/` and `quest_pick/`) is paid. It needs an OAuth account with `is_tier7` or a trial token (`X-Trial-Token`) that is tied to the account ID HSTracker reads from game memory. Document it only; don't use it.
- **No other public source has pick stats.** hsbg.cards and bgknowhow are card and hero databases with no placement data. hsguru and the HSReplay web pages return a Cloudflare 403 to scripts.
- **Firestone's overlay number** is `averagePosition` (not the conservative estimate) plus the sum of `impactAveragePosition` over the lobby's tribes. It filters out noisy tribe rows first and reads the top-25% file by default (see §3). **The catch for us:** the lobby's tribes are not in Power.log at hero pick. Firestone and HSTracker read them from memory. So at pick time we can only show the unadjusted number, plus optional per-tribe deltas, until tribe inference settles (about BG turn 4).
- **Rating 1805 falls in Firestone's `mmr-100` (all players) bucket.** Firestone's own percentile table puts the top-50% cut at about 5,809 (§5).
- **Join works for the fixture.** All 4 offered heroes (`BG35_HERO_001`, `BG20_HERO_283`, `BG23_HERO_305`, `TB_BaconShop_HERO_15`) join to every hero-stats file. The 36.6.1 heroes Drest'agath `BG36_HERO_000` and Kith'ix `BG36_HERO_002` are already present, with about 1.4k games each in `mmr-100` (§6).
- **Quest stats are empty** this season (`dataPoints: 0`). **Anomaly-split hero files** exist but are frozen at 2025-07-21, and the current season has no anomaly.

---

## 1. Sources compared

| Source | Access | Hero fields | MMR split | Tribe / anomaly | Trinkets / quests | Freshness | Terms |
|---|---|---|---|---|---|---|---|
| **Firestone static JSON** (`static.zerotoheroes.com/api/bgs/...`) | Public GET, gzip JSON, behind Cloudflare CDN | avg placement, conservative estimate, SD, pick rate, placement distribution 1–8, combat winrate and warband stats per turn | Separate files: top 100/50/25/10/1% | `tribeStats` impact per tribe (11 tribes); anomaly subfolders exist but are stale since 2025-07-21 | Trinkets yes (avg placement and pick rate, split by MMR). Quests: endpoint exists, currently empty | Rebuilt about every 3 h (`lastUpdateDate` 12:10/15:10/18:10/21:10/00:10 Z); CDN `cache-control: max-age=28800` | Zero-to-Heroes ToS: personal, non-commercial (acceptable here) |
| **HSReplay Tier7** (`hsreplay.net/api/v1/battlegrounds/hero_pick/`) | POST, OAuth plus Tier7 subscription, or trial token | `tier_v2`, `pick_rate`, `avg_placement`, `placement_distribution[]`, `first_place_comp_popularity` | Server-side, from `battlegrounds_rating` | Server-side, from `minion_types` and `anomaly_dbf_id` | `trinket_pick/`, `quest_pick/` (same auth) | Live | Commercial; **not used** |
| HSReplay web `/battlegrounds/heroes/` | Browser only; curl and WebFetch get 403 (Cloudflare) | n/a to scripts | | | | | Commercial |
| HSReplay `/api/v1/battlegrounds/hero_guides/` | Public GET, 200 | Curated guide text, `favorable_tribes`, no numbers | – | – | Separate trinket, quest and anomaly guide endpoints | Per guide (`last_updated`, e.g. 2026-08-18) | HSReplay ToS |
| hsbg.cards API (`/api/v1/`, OpenAPI at `/api/v1/openapi`) | Public, 120 req/min | Card data and patch history only; **no pick or placement stats** | – | – | – | Live | Free API |
| bgknowhow `bgjson/output/bg_heroes_all.json` | Public | Hero metadata (armor, buddy, HP text); no stats | – | – | – | `last-modified` 2026-02-03 (stale) | Community |
| hsguru.com/battlegrounds | 403 (Cloudflare) to curl | – | – | – | – | – | – |

**Recommendation.**
- **Primary:** Firestone static JSON.
- **Fallback (degraded):** the last good cached copy, shown with a stale badge.
- **Fallback (no data):** "no stats" with the hero name only.

There is no second free numeric source, so the fallback has to be our own cache.

---

## 2. Firestone endpoints (verified 2026-09-22)

### 2.1 URL patterns

The patterns come from the Firestone app source, `Zero-to-Heroes/firestone` (depth-1 clone):
- `libs/battlegrounds/data-access/src/lib/meta-heroes/bgs-meta-hero-stats-access.service.ts`
- `libs/battlegrounds/services/src/lib/services/bgs-{trinkets,quests,cards}.service.ts`

```
HERO  https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-{P}/{T}/{anomalies/<AnomalyCardId>/}overview-from-hourly.gz.json
DUOS  https://static.zerotoheroes.com/api/bgs/duo/hero-stats/mmr-{P}/{T}/overview-from-hourly.gz.json
PCTL  https://static.zerotoheroes.com/api/bgs/hero-stats/{T}/mmr-percentiles.gz.json      (duo: /api/bgs/duo/hero-stats/{T}/...)
TRINK https://static.zerotoheroes.com/api/bgs/trinket-stats/{T}/overview-from-hourly.gz.json   (no mmr segment)
QUEST https://static.zerotoheroes.com/api/bgs/quest-stats/mmr-{P}/{T}/overview-from-hourly.gz.json
CARDS https://static.zerotoheroes.com/api/bgs/card-stats/mmr-{P}/{T}/overview-from-hourly.gz.json
ANOM  https://static.zerotoheroes.com/api/bgs/anomalies-list.gz.json
RULES https://static.firestoneapp.com/data/cards/card-rules.gz.json   (needTypesInLobby per hero)
```

- `P` ∈ {100, 50, 25, 10, 1}. The value 100 means all players; the others mean the top P%.
- `T` ∈ {`last-patch`, `past-seven`, `past-three`, `all-time`}. The type is `BgsActiveTimeFilterType = 'all-time' | 'past-three' | 'past-seven' | 'last-patch'`. Firestone's own `fixInvalidTimeSuffix()` maps `past-7`→`past-seven` and `past-3`→`past-three`, which confirms that the short forms are invalid keys.
- **403 means "no such key".** A bogus path such as `/hero-stats/mmr-100/last-patch/does-not-exist.json` returns the same `<Error><Code>AccessDenied</Code>…` body, because the S3 bucket does not allow listing. No header (Referer or User-Agent) changes this.

### 2.2 Probe results

The full matrix (all 200): `hero-stats`, `duo/hero-stats`, `card-stats` and `quest-stats` for each of the 5 MMR buckets and 4 windows, `trinket-stats` for each of the 4 windows, and `mmr-percentiles` for each of the 4 windows.

| File (mmr-100 unless noted) | lastUpdateDate (UTC) | dataPoints | heroes | Size (gzip / raw) |
|---|---|---|---|---|
| hero-stats last-patch | 2026-09-23T00:10:26Z | 1,518,367 | 117 | 74.8 KB / 553 KB |
| hero-stats past-seven | 2026-09-23T00:10:26Z | 458,445 | 117 | – / 421 KB |
| hero-stats past-three | 2026-09-23T00:10:26Z | 156,829 | 118 | – / 422 KB |
| hero-stats all-time | 2026-09-22T21:10:28Z | 1,580,174 | 117 | – / 564 KB |
| hero-stats mmr-25 last-patch | 2026-09-22T18:10:32Z | 375,333 | 115 | – / 539 KB |
| hero-stats mmr-10 last-patch | 2026-09-22T18:10:32Z | 150,231 | 115 | – / 525 KB |
| hero-stats mmr-1 last-patch | 2026-09-23T00:10:26Z | 15,368 | 110 | – / 372 KB |
| duo/hero-stats last-patch | 2026-09-23T00:20:53Z | 291,056 | 116 | – / 503 KB |
| trinket-stats last-patch | **2026-09-22T12:10:36Z** (lagging) | 2,821,274 | 250 | – / 188 KB |
| trinket-stats past-three | 2026-09-23T00:10:27Z | 448,547 | 262 | – / 192 KB |
| quest-stats (every combination) | 2026-09-23T00:10:29Z | **0** | 0 | 210 B |
| hero-stats …/anomalies/BG27_Anomaly_000/ | **2025-07-21** | 16,188 | 86 | – |

Observations:
- **What each window covers.** `patches.json` has `currentBattlegroundsMetaPatch: 251332` (36.4.2, 2026-09-03). So `last-patch` covers 36.4.2, 36.6.0 and the first hours of 36.6.1 (the 36.6.1 server update landed 2026-09-22). `past-three` is the window that is mostly the current meta.
- **"all-time" is not all time.** Its dataPoints (1.58M) are only slightly above last-patch (1.52M), so it looks like a season window.
- **Buckets are rebuilt on staggered schedules.** Some buckets were 6 h older than others at the same moment (mmr-25 and mmr-10 last-patch at 18:10 against 00:10 for the rest). The last-patch trinket file lagged by 12 h and was **missing 2 trinkets the fixture offered** (see §6). Always read `lastUpdateDate` per file.
- **Response headers:** `content-type: application/json`, `content-encoding: gzip` (despite the `.gz.json` name, HTTP clients decompress it transparently), `cache-control: max-age=28800`, `etag` and `last-modified` present, Cloudflare `cf-cache-status: HIT`. The CDN can therefore serve a copy up to 8 h old, and conditional GET (`If-None-Match`) is available.

### 2.3 Hero-stats schema

Excerpt from `hero-stats/mmr-100/last-patch`. Arrays are truncated; the lengths are placementDistribution 8, warbandStats 20, combatWinrate 20, tribeStats 11.

```json
{
  "lastUpdateDate": "2026-09-23T00:10:26.557Z",
  "dataPoints": 1518367,
  "mmrPercentiles": [{"percentile":100,"mmr":0},{"percentile":50,"mmr":5809},{"percentile":25,"mmr":6473},
                     {"percentile":10,"mmr":6993},{"percentile":1,"mmr":9684}],
  "heroStats": [{
    "heroCardId": "BG20_HERO_202",
    "dataPoints": 27354, "totalOffered": 64950, "totalPicked": 27200,
    "averagePosition": 4.05, "standardDeviation": 2.21, "standardDeviationOfTheMean": 0.01,
    "conservativePositionEstimate": 4.09,
    "placementDistribution": [{"rank":1,"percentage":16.93,"totalMatches":4631}, {"rank":2,"percentage":13.21,"totalMatches":3614}, "..."],
    "warbandStats":  [{"turn":1,"averageStats":4.53}, "..."],
    "combatWinrate": [{"turn":1,"winrate":null},{"turn":2,"winrate":47.85}, "..."],
    "tribeStats": [{"tribe":11,"dataPoints":13165,"dataPointsOnMissingTribe":14189,"totalOffered":31674,"totalPicked":13084,
                    "averagePosition":4.07,"averagePositionWithoutTribe":4.03,"refAveragePosition":4.05,
                    "impactAveragePosition":0.02,"impactAveragePositionVsMissingTribe":0.04}, "..."],
    "mmrPercentile": 100, "timePeriod": "last-patch"
  }]
}
```

- **Derived values**, as Firestone computes them in `buildHeroStats`:
  - `pickrate = totalPicked / totalOffered`
  - `top1 = placementDistribution[rank=1].percentage`
  - `top4 = Σ percentage for rank ≤ 4`
- **Tribe fields.** `impactAveragePosition = averagePosition(games with tribe) − refAveragePosition(hero overall)`; for example 4.07 − 4.05 = 0.02. `impactAveragePositionVsMissingTribe = averagePosition − averagePositionWithoutTribe`.
- **`tribe` is the Firestone `Race` enum:** UNDEAD 11, MURLOC 14, DEMON 15, MECH 17, ELEMENTAL 18, BEAST 20, PIRATE 23, DRAGON 24, QUILBOAR 43, NAGA 92, ABERRATION 126. These match the game's `CARDRACE` values.
- **Aberration rows are tiny in `last-patch`** (e.g. Genn 617 of 26,953 games). Aberrations only arrived with 36.6.1.
- **Keys are always base hero IDs.** 0 of 117 keys contain `_SKIN_`.

### 2.4 Trinket-stats schema

```json
{"lastUpdateDate":"...","dataPoints":2821274,"timePeriod":"last-patch","trinketStats":[{
  "trinketCardId":"BG30_MagicItem_426","dataPoints":36639,"pickRate":0.3359,"averagePlacement":3.7729,
  "averagePlacementAtMmr":[{"mmr":100,"dataPoints":36639,"placement":3.77},{"mmr":50,"dataPoints":16317,"placement":3.94}, "... 25,10,1"],
  "pickRateAtMmr":[{"mmr":100,"dataPoints":36639,"pickRate":0.336}, "..."]}]}
```

- The `mmr` values inside the arrays are **percentiles** (100/50/25/10/1), not ratings.
- There is no placement distribution and no tribe split.
- The Lesser and Greater versions of a trinket are separate IDs (`..._404` and `..._404t`).
- Firestone's in-game trinket overlay (`bgs-in-game-trinkets.service.ts`, `meta-trinkets/bgs-meta-trinket-stats.ts`) shows `averagePlacement`, `averagePlacementAtMmr[mmr=25]`, `pickRate` and `pickRateAtMmr[mmr=25]`, and drops rows with `dataPoints ≤ 100`.

### 2.5 Quest-stats

Response: `{"questStats":[],"rewardStats":[],"lastUpdateDate":"2026-09-23T00:10:29.702Z","dataPoints":0,...}` for every MMR bucket and window. Quests are not in the current BG rotation. The endpoint is cheap to support later, but its schema could not be observed.

---

## 3. How Firestone's hero-selection overlay computes its number

Sources:
- `libs/legacy/feature-shell/src/lib/js/components/battlegrounds/overlay/bgs-hero-selection-overlay.component.ts`
- `libs/battlegrounds/services/src/lib/services/bgs-player-hero-stats.service.ts`
- `libs/battlegrounds/data-access/src/lib/meta-heroes/bgs-meta-hero-stats.ts` (`buildHeroStats`)

1. **Configuration:**
   - `timeFilter: 'last-patch'` (hard-coded)
   - `rankFilter: DEFAULT_MMR_PERCENTILE` = **25**
   - `tribesFilter` = the lobby's `availableRaces` (read from memory), if the "use tribes filter" setting is on
   - `mmrFilter` = `mmrAtStart` if the "use MMR filter" setting is on, else null
   - anomalies: `[]`
2. **Bucket choice** (`extractRank`). When `mmrFilter` is set, load `hero-stats/{T}/mmr-percentiles.gz.json` and take the entry with the **highest `mmr` ≤ the player's rating**. Return its percentile, but **map 1 to 10**: the overlay never uses the top-1% file. If there is no match, use 100. Without `mmrFilter`, use 25.
3. **Load** `hero-stats/mmr-{P}/last-patch/overview-from-hourly.gz.json`.
4. **Hero filter.** If a tribe list is given (and is not every tribe), drop heroes whose `card-rules[heroId].bgsMinionTypesRules.needTypesInLobby` are not all in the lobby. Examples: `TB_BaconShop_HERO_53`/`_56` need DRAGON, `BG20_HERO_103` needs QUILBOAR, `TB_BaconShop_HERO_93`/`_95` need BEAST and UNDEAD.
5. **Tribe-row cleanup.** Keep a `tribeStats` row only if `t.dataPoints > hero.dataPoints/20` **and** `t.dataPointsOnMissingTribe > t.dataPoints/20`.
6. **Modifier.** When the lobby's tribes are known (Duos gets no modifier):
   ```
   tribesModifier = Σ impactAveragePosition over kept rows whose tribe ∈ lobbyTribes
   ```
   If the lobby filter is on but no rows remain, the hero is dropped.
7. **Displayed average:**
   ```
   displayed = (useConservativeEstimate ? conservativePositionEstimate : averagePosition) + tribesModifier
   ```
   The overlay's config sets no `options`, so it uses **`averagePosition`**. Only the desktop tier list honours the conservative-estimate setting.
8. **Other fields:**
   - `dataPoints = min(hero.dataPoints, Σ dataPoints of used tribe rows)`
   - `pickrate`, `top1` and `top4` as in §2.3
   - `placementDistribution`, and `combatWinrate` truncated to the first 15 turns
9. **Sample-size filter.** Drop heroes with `dataPoints < 30`.
10. **Tier.** Compute the mean μ and SD σ of all heroes' displayed averages and assign:

    | Tier | Displayed average |
    |---|---|
    | S | < μ−3σ |
    | A | [μ−3σ, μ−1.5σ) |
    | B | [μ−1.5σ, μ) |
    | C | [μ, μ+σ) |
    | D | [μ+σ, μ+2σ) |
    | E | ≥ μ+2σ |

11. **Join.** The offered hero's card ID goes through `normalizeHeroCardId` (§6) and is looked up by `baseCardId`. A hero with no stats still shows, with an empty stat.
12. **Paywall.** In the app (not the data), non-premium users get `BGS_HERO_SELECTION_DAILY_FREE_USES = 2` uses per day of the hero overlay (`free-quotas.ts`), `BGS_TRINKETS_DAILY_FREE_USES = 4` and `BGS_QUESTS_DAILY_FREE_USES = 2`. The static files themselves are open.

**Critique, for our implementation:**
- The per-tribe impacts are summed as if they were independent. They are marginal effects measured against the hero's overall average, and all of them come from lobbies that contain 5 tribes, so summing them double-counts. With 4–5 tribes the modifier is usually small (±0.05 in `mmr-100`), but it gets noisy in small buckets.
- **Aberration.** Until the fortnight ends, Aberration is in every 36.6.1 lobby, so its "impact" is really a *patch* effect, not a tribe effect. In `past-three` its rows pass the /20 filter and swing the modifier by up to ±0.5 in `mmr-25`. **We should exclude tribe 126 from the modifier while it is a forced tribe.** Also exclude any tribe whose `dataPointsOnMissingTribe` window mostly predates the current patch.

Worked example (`fsalgo.py`) for the fixture offer. The lobby tribes were inferred later as Aberration, Dragon, Elemental, Quilboar and Undead:

| Hero | mmr-100 last-patch: base → shown | mmr-25 last-patch: base → shown | mmr-25 past-three: base → shown (incl. Aberration) |
|---|---|---|---|
| George the Fallen `TB_BaconShop_HERO_15` | 3.86 → 3.87 | 4.08 → 4.26 | 4.15 → 4.72 (n=234) |
| Galewing `BG20_HERO_283` | 4.05 → 4.10 | 4.22 → 4.37 | 3.96 → 3.91 |
| Genn, Worgen King `BG35_HERO_001` | 4.15 → 4.14 | 4.27 → 4.25 | 4.37 → 4.03 |
| Heistbaron Togwaggle `BG23_HERO_305` | 4.15 → 4.18 | 4.28 → 4.26 | 4.30 → 3.83 (n=196) |

The `past-three` column shows how unstable small-sample tribe modifiers are. **The modifier also needs the lobby's tribes, which the log does not give at hero pick** (see §7).

---

## 4. HSReplay / Tier7 (documented, not used)

Source: `HearthSim/HSTracker` (depth-1 clone). Files:
- `HSTracker/HSReplay/HSReplay.swift`
- `HSReplayAPI.swift`
- `HSReplay/Data/BattlegroundsHeroPickStats*.swift`
- `Logging/Game.swift` (around lines 3099–3160 and 3201–3235)

- **Endpoints:**
  - `POST https://hsreplay.net/api/v1/battlegrounds/hero_pick/` (Duos: `/battlegrounds/duos/hero_pick/`)
  - `quest_pick/`, `trinket_pick/`, `first_place_comps/`, `alltime/`, `inspiration/`
- **Request body** (`BattlegroundsHeroPickStatsParams`):
  ```
  {hero_dbf_ids:[Int], minion_types:[Int], anomaly_dbf_id?, deity_dbf_id?, game_language, battlegrounds_rating?, include_toast:true, is_reroll}
  ```
  `minion_types` and `battlegrounds_rating` come from HearthMirror (memory).
- **Response:**
  ```
  {data:[{hero_dbf_id, tier_v2, pick_rate, avg_placement, placement_distribution:[Double], first_place_comp_popularity}], toast:{min_mmr, mmr_filter_value, anomaly_adjusted, parameters}}
  ```
- **Auth.** `startAuthorizedRequest` uses the HSReplay OAuth token and requires `accountData.is_tier7`. Otherwise it needs `Tier7Trial.remainingTrials > 0`: a trial is activated through `/api/v1/playertrials/` with the Blizzard account hi/lo read by `MirrorHelper.getAccountId()`, and the token is sent as `X-Trial-Token`. HSReplay advertises "All in-game Tier7 features are available for free twice a week" ([Tier7 page](https://hsreplay.net/battlegrounds/tier7/)). This is a **paid service with an account-bound trial**: out of scope.
- **Free HSReplay pieces:**
  - `GET /api/v1/battlegrounds/hero_guides/` returned 200 (54 KB). Fields: `hero` (dbfId), `published_guide`, `buddy_guide`, `favorable_tribes`, `last_updated`. It has no numbers but could serve as tooltip text.
  - `GET /api/v1/battlegrounds/meta_periods/live/` returned 200 with an `HSTracker/…` User-Agent and 403 with a Chrome UA (Cloudflare rules). The web page `/battlegrounds/heroes/` and the `analytics/query/battlegrounds_list_heroes` query both returned 403.
- **Rerolls.** HSTracker detects a hero reroll as `CHANGE_ENTITY` on a player-controlled HERO while `GameEntity.STEP ≤ BEGIN_MULLIGAN` (`PowerGameStateParser.swift` ~L536), then re-requests with `is_reroll: true`.

---

## 5. Mapping the user's rating to a bucket

Rating is not in the logs. The user reads it off the lobby screen and enters it as a setting (e.g. 1805).

Percentile table, from `https://static.zerotoheroes.com/api/bgs/hero-stats/last-patch/mmr-percentiles.gz.json` (retrieved 2026-09-22):

```json
[{"percentile":100,"mmr":0},{"percentile":50,"mmr":5826},{"percentile":25,"mmr":6477},{"percentile":10,"mmr":6977},{"percentile":1,"mmr":9625}]
```

The same table is embedded as `mmrPercentiles` in each hero-stats file (the mmr-100 last-patch copy says 5809/6473/6993/9684). These are **displayed BG ratings of Firestone users**, a population that skews high.

**Rule** (same as Firestone): `bucket = percentile of the entry with the highest mmr ≤ rating`, where 1 maps to 10 and a missing table means 100.
- Rating 1805: only `{100, 0}` qualifies, so use **`mmr-100`**.
- The bucket changes at about 5.8k (50), 6.5k (25) and 7.0k (10).

Also let the user override the bucket manually. The `mmr-100` sample is the largest, so it is also the least noisy.

---

## 6. Identifying offered heroes in Power.log and joining to the stats

**Log pattern** (fixture `Hearthstone_2026_09_22_21_08_40/Power.log`, read-only; BattleTags redacted):

```
GameState.DebugPrintEntityChoices() - id=1 Player=<redacted> TaskList=7 ChoiceType=MULLIGAN CountMin=1 CountMax=1
GameState.DebugPrintEntityChoices() -   Source=GameEntity
GameState.DebugPrintEntityChoices() -   Entities[0]=[entityName=Genn, Worgen King id=105 zone=HAND zonePos=1 cardId=BG35_HERO_001 player=6]
...Entities[1] cardId=TB_BaconShop_HERO_15, Entities[2] cardId=BG23_HERO_305, Entities[3] cardId=BG20_HERO_283
GameState.DebugPrintEntitiesChosen() - id=1 ... Entities[0]=[entityName=George the Fallen id=108 ... cardId=TB_BaconShop_HERO_15]
```

**How to read it:**
- The earlier `FULL_ENTITY - Creating ID=105 CardID=BG35_HERO_001` block carries `CARDTYPE=HERO`, `ZONE=HAND`, `BACON_HERO_CAN_BE_DRAFTED=1` and `HERO_POWER=<dbfId>`.
- `BACON_MULLIGAN_HERO_REROLL_ACTIVE=1` and `BACON_NUM_MAX_REROLL_PER_HERO=1` are on the game entity. A reroll arrives as `CHANGE_ENTITY` on one of those hand entities before the mulligan step ends. None happened in this fixture.
- The first 4-entity `MULLIGAN` choice is the offer. Re-read the offer on each `CHANGE_ENTITY` of a hand HERO.

**Skins.** A skinned hero entity carries `BACON_SKIN=1` and `BACON_SKIN_PARENT_ID=<base dbfId>`. Seen in this log: an opponent's `BG20_HERO_202_SKIN_B4` with `BACON_SKIN_PARENT_ID=71908`, and `TB_BaconShop_HERO_94_SKIN_F` with parent 67356. The offered cards in this fixture were all base IDs; a player who owns skins will see skin IDs in the offer.

**Normalization** (port of `normalizeHeroCardId`, `@firestone-hs/reference-data` 3.0.211 `dist/services/bgs-utils.js`). Try the steps in order:
1. If the log gave `BACON_SKIN_PARENT_ID`, the base is the card with that dbfId. This is the best source and needs no card DB entry for the skin.
2. Otherwise, if the card DB entry has `battlegroundsHeroParentDbfId` (Firestone cards JSON; HSJSON calls it `battlegroundsSkinParentId`), use the card with that dbfId.
3. Otherwise, if the ID matches `^(.*)_SKIN_.*$`, use capture group 1.
4. Apply two special cases: `TB_BaconShop_HERO_59t` → `TB_BaconShop_HERO_59`, and the Queen Azshara Naga-token hero → `BG22_HERO_007`.
5. Look up `heroStats[].heroCardId == normalized`.

The same function correctly normalized `BG20_HERO_202_SKIN_B4` → `BG20_HERO_202` and `TB_BaconShop_HERO_94_SKIN_F` → `TB_BaconShop_HERO_94`.

**Fixture join results** (mmr-100 / 25 / 10, last-patch):

| Offered cardId | Name | Joins | mmr-100: n / avg / cons / pick rate / top-4 / 1st |
|---|---|---|---|
| `BG35_HERO_001` | Genn, Worgen King | yes, in all | 26,953 / 4.15 / 4.19 / 41.4% / 55.4% / 18.1% |
| `BG20_HERO_283` | Galewing | yes, in all | 11,274 / 4.05 / 4.11 / 17.5% / 57.8% / 17.0% |
| `BG23_HERO_305` | Heistbaron Togwaggle | yes, in all | 7,691 / 4.15 / 4.22 / 11.9% / 55.6% / 14.6% |
| `TB_BaconShop_HERO_15` | George the Fallen (picked) | yes, in all | 14,297 / 3.86 / 3.91 / 22.1% / 61.5% / 16.6% |

**36.6.1 heroes** in mmr-100: Drest'agath `BG36_HERO_000` has 1,436 games in last-patch, past-seven and past-three. Kith'ix `BG36_HERO_002` has 1,419. They are **missing** from the older mmr-25 and mmr-10 last-patch files (built at 18:10Z) but present in their past-three files. So a missing hero should fall back to another window or bucket; don't show it as "no data".

**Trinkets in the fixture.** Offers are `ChoiceType=GENERAL` choices whose entities are `BG*_MagicItem_*` in SETASIDE. They join on the raw cardId (no normalization; keep the `t` suffix).
- Lesser offer: `BG36_MagicItem_852`, `BG36_MagicItem_404`, `BG36_MagicItem_411`, `BG30_MagicItem_891`.
- Greater offer: `BG36_MagicItem_418`, `BG30_MagicItem_426t`, `BG36_MagicItem_404t`, `BG36_MagicItem_610`.
- 6 of 8 joined in `trinket-stats/last-patch`. `BG36_MagicItem_411` (Reinvigorating Light) and `BG36_MagicItem_610` (Sinister Invitation) were missing there because that file lagged at 12:10Z. They are present in past-seven and past-three, with n=487 and n=685.

---

## 7. Lobby tribes at pick time: the main constraint

- Nothing in Power.log names the lobby's tribes (see [minion-pool-and-tribe-inference.md](minion-pool-and-tribe-inference.md)). Firestone reads `AvailableRaces` from memory, and HSTracker gets it through HearthMirror. Our Bayesian inference resolves the lobby around BG turn 4, which is too late for the hero pick. The 21:08 fixture resolved to Aberration, Dragon, Elemental, Quilboar and Undead.
- What we do know at pick time:
  - Aberration is forced into every lobby until about 2026-10-06, and Naga is out of rotation.
  - The 8 lobby heroes, but only after the pick.
  - Hero offers are themselves weak evidence, because heroes with `needTypesInLobby` can only be offered when their tribe is present (card-rules). Kept as an open question below.
- **Proposed display:**
  - Show the unadjusted `averagePosition` from the chosen bucket.
  - Show a compact "tribe sensitivity" row with the strongest ± `impactAveragePosition` values that survive Firestone's filter, e.g. "+0.2 if Demon". Exclude Aberration while it is forced.
  - If a later version adds a memory reader, switch to Firestone's summed modifier.
- The same sensitivity data can explain the pick after the fact once tribes resolve. That fits the session recap, not the pick overlay.

---

## 8. Refresh and caching policy (suggested)

- **What to fetch:**
  - `hero-stats/mmr-{P}/{last-patch,past-three}` for the user's bucket, plus `mmr-100` as a fallback.
  - `trinket-stats/{last-patch,past-three}`.
  - `hero-stats/last-patch/mmr-percentiles`.
  - `card-rules` (weekly).
  - Duos: `duo/hero-stats/...` only when a Duos game is detected.
  - Solo total is about 150–300 KB gzip per refresh.
- **When:** at app launch, then every 6 h while the app is running, plus a forced check when `CREATE_GAME` is seen and the cache is more than 6 h old. Use `If-None-Match` with the stored `etag`. Don't poll more than hourly: the files change about every 3 h and the CDN TTL is 8 h.
- **Cache:** keep each file on disk under `~/Library/Application Support/<app>/stats/` with `fetchedAt`, `etag` and the file's own `lastUpdateDate`. Keep the last good copy if a fetch fails or returns fewer than 50 heroes or a `dataPoints` of 0.
- **Window choice:**
  - For about 7 days after a BG patch (detect via `patches.json` or a build-number change in the log), prefer `past-three` whenever the hero has n ≥ 300 in it.
  - Otherwise use `last-patch`.
  - Always show n.
- **Fallback chain for a missing hero or trinket:** same bucket in `past-three`, then `mmr-100` in the same window, then "no data".
- **Stale indicator:**
  - Grey badge if the file's `lastUpdateDate` is more than 24 h old.
  - Red badge if it is more than 72 h old, or if it predates the current patch (`lastUpdateDate` < patch date).
  - Tooltip shows the window, the bucket, n and the update time.
- **Confidence:** show `conservativePositionEstimate` or ±`standardDeviationOfTheMean` in the tooltip, and dim entries with n < 300.

---

## 9. Open questions

1. **Offers as tribe evidence.** Can the four offered heroes, and their `needTypesInLobby` rules, narrow the lobby enough to apply even part of the tribe modifier at pick time? Or does the server roll heroes without regard to tribes? We need offer logs from lobbies whose tribes are known.
2. **Rerolls.** Confirm the reroll log shape (`CHANGE_ENTITY` on a hand HERO while `STEP ≤ BEGIN_MULLIGAN`) with a fixture where a reroll is used.
3. **Skin offers.** Capture an offer from an account that owns skins. Check that skinned offers carry `BACON_SKIN_PARENT_ID` in the `FULL_ENTITY` block, and not only once the hero is in play.
4. **Quest-stats schema.** The quest file is empty this season, so its schema is unverified. Firestone's `BgsQuestStats` type is in `@firestone-hs/bgs-global-stats`, which was not inspected.
5. **Anomalies.** The anomaly-split hero files are frozen at 2025-07-21. If anomalies return, check that the folder resumes updating before using it. Anomaly keys are card IDs from `anomalies-list.gz.json`.
6. **`all-time` window.** Its exact span (season?) is undocumented.
7. **Bucket freshness.** Why do mmr-25 and mmr-10 last-patch lag other buckets by 6 h, and why does trinket last-patch lag by 12 h? Is it a staggered rebuild or a CDN cache? Re-probe with `cf-cache-status` and `age`.
8. **Terms.** Zero-to-Heroes terms allow personal, non-commercial use (per the user). The files are undocumented and could change without notice. Keep the parser tolerant and pin the tests to saved samples.

## Sources (retrieved 2026-09-22)

- Firestone files: `https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-{100,50,25,10,1}/{last-patch,past-seven,past-three,all-time}/overview-from-hourly.gz.json`; `.../hero-stats/{T}/mmr-percentiles.gz.json`; `.../duo/hero-stats/...`; `.../trinket-stats/{T}/overview-from-hourly.gz.json`; `.../quest-stats/mmr-{P}/{T}/overview-from-hourly.gz.json`; `.../card-stats/...`; `.../anomalies-list.gz.json`; `.../hero-stats/mmr-100/{T}/anomalies/BG27_Anomaly_000/overview-from-hourly.gz.json`; `https://static.firestoneapp.com/data/cards/card-rules.gz.json`; `https://static.zerotoheroes.com/hearthstone/data/patches.json`
- Firestone source: https://github.com/Zero-to-Heroes/firestone (files named in §2–3)
- `@firestone-hs/reference-data` 3.0.211 (npm): `dist/services/bgs-utils.js` (`normalizeHeroCardId`, `ALL_BG_RACES`), Race enum
- HSTracker source: https://github.com/HearthSim/HSTracker (files named in §4)
- HSReplay: https://hsreplay.net/api/v1/battlegrounds/hero_guides/ (200); https://hsreplay.net/battlegrounds/heroes/ (403); https://hsreplay.net/battlegrounds/tier7/
- hsbg.cards: https://hsbg.cards/api-docs, https://hsbg.cards/llms.txt; bgknowhow: https://bgknowhow.com/bgjson/output/bg_heroes_all.json; hsguru: https://www.hsguru.com/battlegrounds (403)
- Local fixture (read-only): `fixtures/private-logs/Hearthstone_2026_09_22_21_08_40/Power.log`
