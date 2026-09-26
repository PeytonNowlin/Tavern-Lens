# Why the advisor is weak, and what stronger guidance requires

Research date: 2026-09-26. Scope: inspect the current implementation, saved match evidence, upstream data and reusable projects. No application code changes, builds, or experiments that claim measured playing strength. Recommendations below are research conclusions, not implemented behavior.

## Main conclusion

Tavern Lens has a short action planner and a build recognizer, but it does not yet have a strategy selector that compares reachable builds and plans a transition. More data would help, but the existing path already loses much of the strategic information we download. The advisor should help select a direction, acquire its enabling pieces, decide when to commit or pivot, and translate that plan into safe actions. Recognizing the composition after the player assembles it is not enough.

The immediate research recommendation is a hybrid: patch-aware archetype knowledge and statistical priors; explicit economic and recruit mechanics; bounded action search; combat survival checks; and a measured feedback loop. A learned policy could later replace weak heuristics, once suitable decision-level data and a faithful evaluation environment exist. No reviewed project establishes a current, ready-to-integrate winning Battlegrounds policy.

## Verified local findings

### 1. Build detection is reactive, and its output limits the advisor

[BuildDetector](../../Sources/BGIntel/BuildDetector.swift) scores already-held core/support cards, requires four evidence points, and retains incumbents through score carry-over and a switching margin. These choices stabilize a display. They do not estimate whether pursuing a different build would improve placement.

[TavernEngine.advisorRequest](../../Sources/TavernEngine/TavernEngine.swift) passes only the zero to two detected builds into the advisor. The shop is not part of the detector's input. A newly offered enabler for another composition therefore does not automatically become an alternative strategic direction. The planner can still buy that card for generic effect/stat value; it lacks that alternative build's structured destination value.

The [AdvisorBuild representation](../../Sources/BGIntel/Advisor/AdvisorRequest.swift) contains identity, share, core/add-on IDs and core tiers. It does not carry average placement, top-MMR placement, power rating, commitment instructions or tips from [BuildDefinition](../../Sources/HSData/BuildCatalog.swift). The detector uses average placement as a tie-breaker, not the planner's objective.

Last-game corroboration: saved requests for seed `127346189` contain no build on turns 1–2, only `demon_self_damage` on turns 3–10, and add `demon_boost_shop` on turn 11. This establishes what the saved planner requests knew, not whether a different composition was achievable from earlier shops.

### 2. The cached feed's statistical contribution is completely filtered out

Read-only inspection of `~/Library/Application Support/TavernLens/Builds/comp-stats.json` found source timestamp `2026-09-23T09:10:36.967Z`, window `last-patch`, 927 reported data points and 16 compositions. Each composition has only 0–18 sampled final boards. The cache file modification time was September 25, 21:42 local time.

[BuildCatalog.compose](../../Sources/HSData/BuildCatalog.swift) requires 50 sampled boards, and uses that same gate both for board-derived membership and for retaining the composition's placement statistics. Thus none of these 16 statistical records passes. Curated strategy records can still supply builds; this is not an empty-catalog claim.

Two separate research questions follow: how many games support a placement estimate, and how many sampled boards support card membership? They should not automatically share one sample threshold. Do not simply lower the threshold and treat tiny samples as reliable. Validate source semantics, use uncertainty and shrinkage, and retain reviewed strategy knowledge when statistics are sparse.

[BuildDataStore](../../Sources/HSData/BuildDataStore.swift) primarily uses retrieval/confirmation time for cache freshness. Successful retrieval does not prove that the upstream measurement window has advanced. Source age, game build, population, count and retrieval time need separate treatment. These counts describe the inspected cache; do not generalize them to all Firestone data.

The strategy cache also mixes `patchNumber` values 231720 and 251952, while the last game reports build 253216. That mismatch is a review signal, not proof every strategy is wrong. Pool filtering catches removed cards; it cannot establish that retained advice still matches changed effects or balance.

### 3. The objective is hand-written board value, not learned placement

[RecruitPlanner.value](../../Sources/BGIntel/Advisor/RecruitPlanner.swift) combines stat-based tempo, effect production estimates, generic resource options and membership bonuses. Build value counts core/support cards in detected builds. Search is capped at five actions, 18 beam states and 1,800 expansions; rolls and unknown rewards stop a branch. Health selects a short heuristic production horizon.

This is useful tactical machinery, but it lacks a calibrated estimate of the chance and cost of finding a build's missing pieces. It does not model a multi-turn route through temporary tempo cards, leveling, expected shop opportunities, resource generation and a later pivot. Increasing search depth alone would explore more states under the same incomplete objective.

### 4. Mechanics gaps and stale advice undermine the strategic layer

[RecruitEffects.combatProjection](../../Sources/BGIntel/Advisor/RecruitEffects.swift) adds a limitation whenever a quest or quest reward exists. [RecruitEvaluation.run](../../Sources/TavernEngine/RecruitEvaluation.swift) only simulates projections without limitations. Last game's 11 captured advisor states all show zero evaluations, including after the economy reward Untold Riches was obtained. This is a coverage problem independent of the meta feed.

Turns 9–10 retain pending-choice advice despite raw log choice dismissal before combat. This establishes stale displayed advice in the saved evidence; it does not isolate the fault to the choice parser. Refresh, cancellation, publication and request matching remain candidates.

Stored preview percentages are not proof of displayed percentages: [PreviewOdds](../../Sources/TavernLensApp/Overlay/PreviewOdds.swift) hides results when the opponent board is at least three turns old. Keep that distinction in future audits.

### 5. Current evidence cannot demonstrate increased win rate

[AdvisorTurnDiagnostic](../../Sources/TavernEngine/AdvisorDiagnostics.swift) saves the last displayed request at combat start. It can be older than the final recruit state, and it does not retain every intermediate purchasing decision. [The scoring guide](../advisor/scoring.md) explicitly distinguishes regression correctness from optimal play.

We need decisions and outcomes, not only final boards. Replaying the action actually taken cannot reveal the true final placement of an action never taken. Offline tests are useful for legality, coverage and expert preference; an honest playing-strength claim requires prospective comparison or a sufficiently validated full-game environment.

## External sources and projects

See the companion [source inventory](battlegrounds-advisor-external-sources-2026-09-26.md) for live feed checks, first-party links, access and reuse limitations. The most promising incremental statistical source is Firestone's card-by-turn data; existing composition and strategy data should first be preserved and used correctly. HSReplay is a potential independent data partnership and a product reference, not an assumed public bulk API.

Public source visibility, an accessible JSON endpoint, and a reusable software license are different things. Keep provider data access separate from package code licensing. No accounts, paid subscriptions or provider outreach were initiated in this research.

### Full-game or AI projects checked

Repository metadata was read from GitHub's API on September 26. A repository push date does not establish card coverage or algorithm quality.

| Project | Verified evidence | Research value and limitation |
|---|---|---|
| [RosettaStone](https://github.com/utilForever/RosettaStone) | AGPL-3.0; repository pushed August 19, 2026. [Architecture](https://github.com/utilForever/RosettaStone/blob/main/ARCHITECTURE.md) describes separate recruit/combat game flow. Its [BG card implementation file](https://github.com/utilForever/RosettaStone/blob/main/Sources/Rosetta/Battlegrounds/CardSets/BattlegroundsCardsGen.cpp) has 430 lines, only ten distinct quoted BG/BGS/TB_Bacon-prefixed IDs, and no BG36 IDs. | Worth studying game-state and action interfaces. Not evidence of current seasonal coverage. The identifier count is an audit of that file, not a claimed complete engine card count. Current project activity should not be mistaken for current BG support. |
| [battlegrounds-rs](https://github.com/utilForever/battlegrounds-rs) | MIT; latest repository push September 25, 2022. | Potential reusable simulation architecture; modern season support would require substantial verification and likely reconstruction. No reviewed evidence of a current trained winning policy. |
| [BGSimulator](https://github.com/yossielimelech/BGSimulator) | Latest push January 11, 2020; README explicitly says no heroes and all rights reserved; GitHub reports no license. | Historical reinforcement-learning environment reference, not a current licensed replacement. |
| [RL-Hearthstone](https://github.com/noahlattari/RL-Hearthstone) | Student project with eight PPO agents and custom BG implementation; latest push April 21, 2021; no license detected by GitHub. | Shows a research setup, not competitive current-season performance. Do not mistake ordinary Hearthstone agent research for Battlegrounds competence. |
| [twanvl battle simulator](https://github.com/twanvl/hearthstone-battlegrounds-simulator) | MIT; latest push January 22, 2020. README documents order optimization and explicitly excludes buying, selling and leveling. | Useful positioning-optimizer ideas; cannot supply strategic recruiting policy. |

No simulator or candidate package was installed or built. Coverage claims above are source inspections, not runtime certification.

## What an advisor that leads toward a build needs

### Lessons from the HSReplay overlay supplied by Peyton

The [official overlay page](https://hsreplay.net/battlegrounds/overlay/) distinguishes combat odds from lobby-conditioned Tier7 guidance. Its FAQ advertises filtered composition guides, tribe-aware hero rankings and hourly meta refreshes, with patch data typically available within two hours. These are vendor descriptions, not independently measured performance or a guarantee of access to their data.

| Documented product idea | Implication for Tavern Lens |
|---|---|
| Lobby-specific composition guides and rankings ([overlay](https://hsreplay.net/battlegrounds/overlay/)) | Show viable destination builds before the board already matches one; condition on this lobby and the available opportunities. |
| Jeef collaboration, composition/hero guides and an inspiration tool ([official product update](https://articles.hsreplay.net/2025/05/16/a-new-chapter-for-hsreplay-net/)) | Expert knowledge and concrete example boards complement statistics. Add our own reviewed transition rules; do not infer a ready-made action policy from the feature list. |
| Card synergy highlights and progress counters ([same update](https://articles.hsreplay.net/2025/05/16/a-new-chapter-for-hsreplay-net/)) | Surface the resource engine and its next payoff, including relevant hand/shop opportunities, rather than only card membership in an existing build. |
| Hero-specific leveling frequency ([help article](https://help.hearthsim.net/en/articles/3799260-how-do-i-interpret-the-when-to-tavern-up-chart)) | A single universal leveling curve is a weak default. Compare hero/context-specific timing, then override for current health, shop and survival. Historical frequencies are guidance, not an instruction to copy winners. |
| Play Impact compares placements of players who played a minion with those who did not, and varies with turn/composition ([definition](https://help.hearthsim.net/en/articles/3799569-what-does-play-impact-mean)) | Preserve turn and composition context. Harmonize sign conventions across providers. These observational comparisons do not establish causal improvement from a purchase. |

The help definitions were published in 2020; use them for metric interpretation, not current card or balance advice. A [typical final board](https://help.hearthsim.net/en/articles/3799422-what-does-the-typical-final-board-show-me) illustrates a destination, but cannot by itself teach how to reach it from a weak turn-five board. Tavern Lens should connect destination, commitment conditions and immediate actions. That last connection is our proposed product requirement, not a claim that HSReplay offers automated turn-by-turn purchasing advice.

### Proposed strategic behavior

The following is a proposed design direction, not a claim that these capabilities exist in any downloaded feed.

1. **Compare attainable directions.** Examine the full eligible archetype catalog, current shop and discover offers, hero, quest/reward, trinkets, tribes, tier, health and current investment. Maintain a few plausible directions plus a flexible tempo option. Do not force the highest population-average build from turn one.
2. **Represent how a build works.** Distinguish enabler, resource generator, multiplier, payoff, temporary body, cycle card and tech slot. Record alternative enablers, minimum viable engines, commitment conditions and pivot exit conditions. Curated prose can inform reviewed structured rules; parsing a tip is not validation.
3. **Price the route.** Estimate acquisition probabilities and roll/level costs with the current pool and uncertainty about other players' holdings. Model distributions of unknown shops; do not pretend a future shop is known. Value partial progress and fallback lines, not just completed boards.
4. **Choose a turn plan.** Decide whether this turn buys tempo, completes an engine, builds economy, levels for access, or pivots. Then use legal action search for sequence, targets, board space and resource management. Evaluate a plan's survival before recommending it at low health.
5. **Explain and update.** Show the preferred direction, the evidence for it, the next action, what to look for, and what would change the plan. “Buy this enabler; keep this temporary body until you find the payoff” is more useful than a generic core-card highlight. Replan at every real information reveal.

A language model may help turn licensed guide text into candidate structured knowledge or explain an already-validated plan. It should not invent card effects, approve illegal sequences, or produce uncited numerical win probabilities. Replacing the existing score with unrestricted prose reasoning would not solve the state/effect/data problems.

## Data needed, in priority order

| Data | Decision it helps | Main limitation |
|---|---|---|
| Validated patch-specific archetype roles and commitment/pivot conditions | Which direction is attainable and when to commit | Requires expert review; final-board frequencies omit temporary/cycle cards |
| Card performance by turn and MMR, with counts | Whether a shop card is useful now | Association is confounded by hero, board, health and player choices |
| Hero/quest/trinket/archetype interactions | Which engines this game rewards | Sparse combinations; avoid summing unrelated marginal statistics |
| Decision snapshots with available actions, recommendation, actual action and outcome | Diagnose mistakes and train/rank candidate decisions | Private logs require consent before any external sharing; hidden actions remain unknown |
| Strength distributions by turn/tier/patch/rank | Survival and tempo benchmarks | Current +25% stat stress boards are not an empirical growth model |
| Expert-labeled counterexamples, including failed transitions | Distinguish flexible play from forced builds | Expert disagreement should be retained; no single label proves optimality |

Final-composition placement is conditional on having ended in that composition. It is not the expected result of trying to force it from the current state. We need failed attempts, early deaths and transitional boards represented, or the data will preferentially reward strategies that look good only after successful assembly. Multiple sites using the same Firestone feed are one statistical source, not independent corroboration.

## How to establish that it helps win

Proposed acceptance evidence before calling the advisor stronger:

- A diverse held-out decision set, split by whole game and patch rather than adjacent snapshots. Include early shops, discoveries, commitments, pivots, low-health stabilization and unsupported mechanics.
- Expert comparison of complete short plans against the current advisor, with reasons and acceptable alternatives. Track severe errors separately from close preferences.
- Correct action legality and effect execution; coverage weighted by how often mechanics occur in real games, not merely the number of implemented cards.
- Advice freshness and availability at meaningful decision points. A strong plan that arrives after the decision is not useful.
- Ablations: current advisor, repaired data/coverage, strategic direction layer, then additional feeds or learned values. This reveals which changes actually help.
- Prospective assisted/unassisted or version-to-version comparison with predefined primary outcome, patch/rank tracking, adherence and uncertainty. Expected placement/top-four rate are more informative primary targets than maximizing first places regardless of bottom finishes. Track first-place rate and catastrophic losses as secondary outcomes.

One player's few games cannot distinguish improvement from matchmaking and combat variance. Do not promise a percentage lift before data supports it. Self-play in an incomplete simulator can reward exploiting simulator errors rather than playing Hearthstone well.

## Recommended order after research approval

First establish reliable, fresh decisions and separate harmless known effects from genuinely unresolved mechanics. In parallel, validate and preserve existing meta data. Next introduce explicit build selection and transitions with expert-reviewed roles. Then incorporate licensed card-by-turn and contextual statistics, and evaluate against held-out decisions and prospective games. Full-game reinforcement learning is a later research investment, not a shortcut around these prerequisites.

The goal should be an advisor that gives a coherent, adaptable route toward a strong finish and can demonstrate improved decisions. More downloaded JSON and more tactical search, without that route and measurement, would repeat the current failure pattern.
