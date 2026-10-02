# Strategic recruit guidance

The live advisor uses evaluation version 6, retaining the version-3 strategic search with the effect-coverage and survival policies described in [scoring](scoring.md). Versions 1–3 and 5 remain available for saved requests. The full lobby-eligible catalog travels in `AdvisorRequest.strategyCatalog`; build recognition still describes the held board independently. Candidate directions use held and affordable offered cards, distance to missing tiers, shared-card specificity, supported seasonal production and a small, freshness-gated placement prior. Those are estimates, not measured purchase effects.

The selected direction supplies the existing bounded recruit search. Requirements distinguish interchangeable cards within a role from roles that must coexist. An unverified resource loop does not count as a complete engine. The planner retains immediate board strength, health-sensitive horizons, legal sequencing, action readiness, unknown-reward boundaries and matched combat scenarios. The panel shows a direction, missing pieces and at most two actions; source, commitment, alternatives and uncertainty are available in its tooltip.

## Composition knowledge

The bundle contains all 16 compositions in the September 26 public HSReplay capture, plus existing source/override coverage. The bundle retains factual IDs, membership, tier/difficulty labels and independent guide/tier timestamps. `strategy-recipes.json` contains independently authored requirements and concise guidance, checked against captured card definitions. Runtime code does not execute guide prose. Sustainable economy loops remain explicitly unverified where the observed cards do not establish one.

Refresh factual records from a complete local capture:

```sh
python3 scripts/import-hsreplay-comps.py HSreplayresearch/comps --captured-at YYYY-MM-DD
```

The importer checks the index/detail identity set, card-list shapes and mandatory fields, then atomically replaces the snapshot. It does not fetch gated data or retain cookies, account details, administrative links or raw pages. Review card roles against the current card text when refreshing. A guide whose defining cards cannot resolve or have rotated out is excluded. Explicit archetype joins avoid counting correlated HSReplay and Firestone definitions twice; placement evidence keeps its Firestone identity.

Firestone placement samples and sampled final boards have separate support checks. Under 50 sampled boards does not erase an otherwise supported placement estimate; those boards cannot establish card membership. A successful download/304 does not make an old source current. Outcome statistics over final compositions have survivorship and selection bias. Missing patch/population metadata stays unknown.

## Reliability and evidence

Every changed version-3 request withdraws the previous instruction before evaluating the replacement. Choice advice suspends recruit actions until the reveal. Known completed Untold Riches economy rewards do not disable combat projection; unresolved quests and unknown rewards remain explicit limitations. Supported seasonal mechanics are shared with the existing planner, not reimplemented as a second rules engine.

A turn retains its opening decision and the most recent distinct displayed decisions, capped at 12. They are saved with combat-start diagnostics under the existing 300-record/64 MiB retention policy. Requests contain the actual data used for that decision. `AdvisorCase.savedDiagnostics` exposes both decision and combat-start snapshots for replay, with fingerprint and game/turn validation. No evidence is uploaded.

`AdvisorQualityEvaluation` scores a frozen set of requests with a chosen evaluation version. It reports advice availability, unsupported-effect coverage, and optional independently reviewed acceptable/prohibited actions and build directions. Unreviewed cases never count as expert preference evidence. Freeze evaluation sets by whole game and patch before tuning; include losses, abandoned pivots and early-game decisions. Keep reviewer disagreement rather than forcing one supposedly optimal action.

Prospective evaluation should compare matched patch/rank populations, predeclare average placement as the primary outcome, and also report top-four/first-place rates, early eliminations, adherence, sample counts and uncertainty. Passing deterministic tests or scoring old games does not demonstrate a placement improvement. Human expert review and prospective matches remain necessary validation, not results supplied by this implementation.

The acquisition display reserves the estimated cost of pending role purchases (at least three gold), excludes targets above the current tavern tier, and reports a lower bound on the cost of missing requirements. Pool breadth is a search heuristic, not an exact appearance probability: tier weights, remaining shared copies and hidden holdings are not established. The advisor does not quote a fabricated chance to hit a desired card.

Editorial tiers have their own 14-day freshness gate; a recently edited or captured guide does not refresh an old tier ranking. The tooltip reports the tier timestamp and whether it was excluded. Directions with no positive attainability evidence yield to tempo, and alternate cards stay grouped by the requirement they can fill. Search reserves account for every pending role purchase, including affordable pieces still in the shop.
