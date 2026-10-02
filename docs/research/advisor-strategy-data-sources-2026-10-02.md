# Advisor strategy and outcome data: verified additions

Checked October 2, 2026, around 21:12 UTC. Research only: no provider contact, subscriptions, uploads, application changes, or dataset redistribution. The ranked recommendations below distinguish technical availability from an established data license.

This updates the September 26 [source inventory](battlegrounds-advisor-external-sources-2026-09-26.md) and [strategy investigation](advisor-strategy-and-data-research-2026-09-26.md). Their observations are historical. Policy 10 now selects directions from the full eligible catalog and affordable shop offers, checks engine requirements, carries source evidence, and uses small observational/editorial priors. See [AdvisorStrategy](../../Sources/BGIntel/Advisor/AdvisorStrategy.swift), [HSReplayCompositions](../../Sources/HSData/HSReplayCompositions.swift), and [TavernEngine](../../Sources/TavernEngine/TavernEngine.swift). A claim that strategy selection is absent is no longer accurate.

## Highest-value additions

| Priority | Data | Obtainable in this check | Advisor use and limits |
|---|---|---|---|
| 1 | Firestone card performance by exact turn and MMR bucket | HTTP 200; 699 card records with 699 distinct IDs; 45,567 source games; 7,257 nested turn records | A contextual purchase prior for temporary tempo, cycle cards and offered enablers. Observed placement differences are associations, not the effect of buying a card in this state. |
| 2 | Fields already present in Firestone hero statistics | HTTP 200; 116 hero rows; 208,954 source games; turn-level board-strength means and combat win rates | Diagnose whether our board is unusually weak for its hero/turn. The delivered rows lack per-turn counts and strength distributions; they cannot replace combat simulation or establish lethal probability. |
| 3 | MMR-specific fields already present in Firestone trinket statistics | HTTP 200; 238 trinket rows; 426,184 source observations | Improve rank-matched choice priors. These are individual trinket marginals; no Lesser/Greater pair-conditioned fields were found. |
| 4 | Separate Firestone hero curves and trinket tips | Both HTTP 200, but newest tips date to April 2025 and November 2024 respectively | Reference material for independently reviewed opening/interaction rules. Exclude unreviewed seasonal advice from current recommendations. |
| 5 | Independent bgtracker community pool and collector | Documented feeds returned HTTP 200; only 43 solo games in `last-patch` | A second collector architecture and future independent source. Currently far too sparse for useful recommendation priors. |
| Partnership | HSReplay/Tier7 statistics and expert guide data | Current product/help pages verified; one ordinary GET to the public Undead guide returned HTTP 403 | Independent statistics, hero leveling frequencies and expert knowledge are valuable if supported access/reuse is arranged. Product access does not establish a bulk integration contract. |

The live reads above correct the September 26 access observation: Firestone's tested feeds are accessible from this environment today. That does not guarantee future availability or permit republication. Firestone's [terms](https://github.com/Zero-to-Heroes/firestone/blob/master/tos.md) distinguish personal service access from copying, scraping and redistribution. No new supported third-party data contract was established here.

## 1. Card-by-turn feed: the best new runtime input

The [upstream loader](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/services/src/lib/services/bgs-cards.service.ts) requests:

```text
https://static.zerotoheroes.com/api/bgs/card-stats/mmr-25/last-patch/overview-from-hourly.gz.json
```

The [tested response](https://static.zerotoheroes.com/api/bgs/card-stats/mmr-25/last-patch/overview-from-hourly.gz.json) reports `lastUpdateDate=2026-10-02T12:10:37.777Z`, `dataPoints=45567`, and `timePeriod=last-patch`. File-level game count is not the sample size for every card/turn. Card IDs are distinct in this snapshot; the nested turn records are a separate count.

Verified shape, omitting most rows:

```json
{
  "cardStats": [{
    "cardId": "BG20_100",
    "totalPlayed": 3618,
    "averagePlacement": 3.320342730790492,
    "averagePlacementOther": 4.228617710583153,
    "turnStats": [{
      "turn": 1,
      "totalPlayed": 568,
      "averagePlacement": 3.88556338028169,
      "totalOther": 7582,
      "averagePlacementOther": 4.235821682933263
    }]
  }]
}
```

Firestone's [shop service](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/common/src/lib/minion-stats/bgs-board-stats.service.ts) uses an exact-turn record and subtracts `averagePlacementOther` from `averagePlacement`: negative is better. Its [display transformation](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/data-access/src/lib/meta-cards/bgs-meta-card-stats.ts) suppresses placement/impact for a non-exact turn. These sources do not document a causal purchase effect or expose matching on hero, board, health, gift, trinkets, composition or available alternatives.

Important ingestion findings: 217 nested rows have a null turn; accept only validated integer turns for exact-turn priors. There are 1,279 valid turn records with at least 200 `totalPlayed` observations, but 200 is a descriptive audit threshold, not a demonstrated reliability guarantee. Intersect IDs with the active pool for the actual game build; 699 IDs is not the current playable pool. Preserve both populations (`totalPlayed`, `totalOther`) and shrink uncertain comparisons toward no effect. Missing turn/card data should contribute no statistical adjustment.

Implementation validation found 4,140 null `averagePlacementOther` values in that
snapshot. Raw turn metrics must therefore decode as optional values; a null comparator
must not fail the whole download or become zero. Only 71 rows in the inspected snapshot
meet **both** 200-observation floors and contain valid placements. The 1,279-row count
above describes the played population alone, not usable comparison coverage. Policy 11
retains complete, exact-turn rows and omits incomplete evidence.

Proposed implementation seam: a new independent `Sources/HSData/CardTurnStats.swift` and store, following [BuildDataStore](../../Sources/HSData/BuildDataStore.swift)'s conditional-fetch/cache pattern; carry validated evidence through [AdvisorRequest](../../Sources/BGIntel/Advisor/AdvisorRequest.swift), then add a bounded contextual contribution in [RecruitPlanner](../../Sources/BGIntel/Advisor/RecruitPlanner.swift). An outcome prior must not override action legality, affordability, known effects or a genuine unsupported-mechanic block. The feed does not supply executable recruit effects.

## 2. Better use of existing hero and trinket downloads

The [hero response checked](https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/past-three/overview-from-hourly.gz.json) reports source time `2026-10-02T18:10:31.585Z`. Hero rows contain:

```json
{
  "warbandStats": [{"turn": 1, "averageStats": 4.27}],
  "combatWinrate": [{"turn": 1, "winrate": 0}],
  "standardDeviation": 2.14,
  "standardDeviationOfTheMean": 0.05
}
```

[HeroStats.swift](../../Sources/HSData/HeroStats.swift) currently omits all four fields. Firestone's [hero chart](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/legacy/feature-shell/src/lib/js/components/battlegrounds/desktop/categories/hero-details/bgs-warband-stats-for-hero.component.ts) compares `averageStats` with the player's recorded total statistics. Retain the fields for diagnostics first. Source averages do not describe opponent boards, stat allocation, keywords or tempo variance; the delivered `warbandStats`/`combatWinrate` rows also have no local sample counts. A zero value is not automatically reliable evidence. Confirm semantics before translating this into survival adjustments.

The [trinket response checked](https://static.zerotoheroes.com/api/bgs/trinket-stats/past-three/overview-from-hourly.gz.json) reports source time `2026-10-02T12:10:35.844Z`. Beyond the three fields retained by [TrinketStats.swift](../../Sources/HSData/TrinketStats.swift), each row includes `pickRate`, `pickRateAtMmr[{mmr,pickRate}]`, and `averagePlacementAtMmr[{mmr,dataPoints,placement}]`. Firestone [uses those MMR fields](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/data-access/src/lib/meta-trinkets/bgs-meta-trinket-stats.ts). Preserve each bucket's count when available; use a labeled fallback rather than applying the all-player count to a narrower bucket. Do not add two marginal trinket scores and describe the result as measured pair synergy.

The current [BuildCatalog](../../Sources/HSData/BuildCatalog.swift) separately gates placement evidence by composition games and board membership by sampled boards. The September 26 statement that its board gate discards all placement evidence is outdated. Existing composition data and strategy selection should remain the baseline while evaluating incremental feeds.

## 3. Hero curves exist, but their freshness is poor

Separate [hero-strategy](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/services/src/lib/services/bgs-meta-hero-strategies.service.ts) and [trinket-strategy](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/battlegrounds/services/src/lib/services/bgs-meta-trinket-strategies.service.ts) loaders expose structured tips beyond our comp loader.

- [Hero feed](https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-hero-strategies.gz.json): 110 heroes, 213 tips, 16 curve definitions; latest tip date April 11, 2025. Curves provide `id/name/notes/steps[{turn,actions}]`, including Basic, Jeef, Warrior, Rafaam, 3-on-3 and hero-specific variants. Tips include author, language, date and patch.
- [Trinket feed](https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-trinket-strategies.gz.json): 142 trinkets, 273 tips; latest tip date November 1, 2024; tips contain author, language, date, patch and summary.

These are useful examples of a structured opening-rule format, not current-season training labels. Curves need alternative opening conditions, legal action checks, patch review and low-health/shop overrides. The independently maintained [BG Curve Sheet](https://www.bgcurvesheet.com/curves) supplies a visible curve taxonomy, but no documented machine-readable API, current patch certification or dataset reuse grant was verified.

## 4. A genuinely independent community source, currently too small

[bgtracker](https://github.com/BattlegroundsHelp/bgtracker) describes a pool collected from its own users rather than Firestone. Its [published source configuration](https://github.com/BattlegroundsHelp/bgtracker/blob/main/sources.example.json) documents static hero, hero-power, card, trinket and composition feeds. The [bucket manifest](http://165.227.41.29/buckets.json) checked at `generatedAt=2026-10-02T20:30:18` reports 231 all-time solo games, 43 last-patch solo games, and nine past-three solo games; only bucket 100 is published. Its percentiles are within this server's shared rating population, not interchangeable with another provider's buckets.

Normal GETs to documented `heroes-100-last-patch.json`, `cards-100-last-patch.json`, `heropowers-100-last-patch.json` and `comps-100-last-patch.json` all returned 200: 85 hero rows, 147 card rows, 24 hero-power rows, and zero measured comp rows. Maximum per-row outcome counts were two, nine and two respectively. Many hero/power rows contain offers without played outcomes. The fetched feeds have mode/MMR/window metadata but no game-build stamp, and use plain HTTP.

The [server design](https://github.com/BattlegroundsHelp/bgtracker/blob/main/server/README.md) is a useful template for our own collector: de-duplicated match records, separate solo/Duos aggregates, explicit bracket metadata and sample floors. Its card metric currently derives from final boards, so it does not replace exact-turn decision evidence. The [MIT license](https://github.com/BattlegroundsHelp/bgtracker/blob/main/LICENSE) expressly covers repository code; it does not establish a license for downloaded pool statistics. Original [hero-tip schema](https://github.com/BattlegroundsHelp/bgtracker/blob/main/data/hero_tips.schema.json) is inspectable, but confirm content-license scope before adopting authored tips. Do not install/run the client for research: the README documents default uploads, which this session has not authorized.

## 5. HSReplay remains the best independent partnership candidate

[Tier7's current FAQ](https://hsreplay.net/battlegrounds/tier7/) describes lobby-specific hero tiers and composition guides and hourly statistic updates. Its [leveling chart definition](https://help.hearthsim.net/en/articles/3799260-how-do-i-interpret-the-when-to-tavern-up-chart) is hero-specific upgrade frequency, not the expected value of leveling now. [Play Impact](https://help.hearthsim.net/en/articles/3799569-what-does-play-impact-mean) compares placements of players who did/did not play a minion. Both definitions are historical help articles; neither certifies current seasonal coverage.

Tavern Lens already imports allowlisted public composition metadata and maintains its own recipes in [HSReplayCompositions](../../Sources/HSData/HSReplayCompositions.swift). This is not an unused source. In this check, a normal request to the [public Undead guide](https://hsreplay.net/battlegrounds/comps/14/undead-attack-scaling) returned 403, while the text web reader exposed only the page shell. The prior normal-browser extraction remains historical evidence; no current bulk strategy/statistics API was verified. HearthSim's [terms](https://hearthsim.net/legal/terms-of-service.html) require express permission for copying, redistribution and scraping. A supported integration would request permitted aggregates and exact schemas, not assume a subscription grants those rights.

## Required evidence contract

Each imported metric should keep provider, metric definition/sign, source URL, retrieval time, source update time, explicit game build/patch if supplied, time window, solo/Duos mode, population/MMR basis, conditioning dimensions, both comparison counts, and null/missing status. An inferred URL parameter should be labeled as inferred; absent build information remains unknown. Store guide author/date/patch separately from statistical evidence.

No inspected feed supplies a complete state-conditioned action policy, reliable trinket-pair outcomes, gift/Deity-conditioned recruit values or executable effects. Highest practical return: integrate validated card-turn priors, retain useful existing fields, and collect our own offered-actions/recommendation/actual-action/outcome evidence. Missing effect implementation still requires code; another placement table cannot teach the planner how an unsupported effect transforms the state.
