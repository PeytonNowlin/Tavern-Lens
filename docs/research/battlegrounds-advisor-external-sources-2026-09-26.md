# Battlegrounds advisor: external data opportunities

Research date: 2026-09-26. Research only; no application changes or builds. Findings distinguish public source visibility, documented API access, and permission to reuse content. Source URLs below were checked during this research; GitHub default branches remain moving targets.

## Recommendation

The strongest near-term opportunity is to use the existing composition knowledge more completely, then add **card-by-turn outcome priors**, **explicit transition/commit guidance**, and **expert-labelled decisions**. Another combat simulator cannot supply those missing strategic judgments. End-state composition rankings describe what succeeded; they do not establish whether abandoning this board to chase that composition is a good decision.

Tavern Lens already names Firestone composition statistics and curated strategy endpoints in `Sources/HSData/BuildDataStore.swift`. HearthstoneJSON is already a card source, and `hsbg.cards` is already referenced in a pool override. These are extensions of existing sources, not three newly discovered integrations. The application audit belongs in the companion research report.

## Sources ranked by practical value

| Source | What it provides | Best use | Limits and access status |
| --- | --- | --- | --- |
| Firestone card statistics | Card/turn observations with average placement, comparator placement, and sample counts; source requests configurable MMR percentile and time window | Turn-sensitive shop priors, identifying early direction cards, offline comparison with current scoring | Verified upstream consumer, not a licensed public API contract. Direct live feed request returned 403; current payload freshness unverified |
| Firestone curated compositions | A strategy loader keyed by composition ID with card lists; existing Tavern Lens source | Candidate destinations and creator-authored strategy knowledge, provided retained throughout advice generation | Already integrated. Reachable source code does not grant guide/data redistribution rights; direct feed returned 403 |
| HSReplay Tier7 / Jeef | Lobby-conditioned hero/composition statistics, patch-updated guides, recent high-MMR board examples | Partnership for strategic reference data and evaluation examples; benchmark the product experience | A subscription product, not an established public redistribution API. Source code and service permissions are separate |
| HSBG Cards | Public card, relationship, patch-diff and historical-state API | Detect obsolete cards/builds, enrich card relationships, validate season/patch compatibility | Documented community-project use; attribution and mirroring restrictions. No match outcomes or learned strategy |
| HearthstoneJSON + HearthSim parsers | Build-versioned game metadata; reusable MIT parsing libraries | Reliable state/card identity and independent log parsing checks | Metadata is not a meta strategy dataset; Blizzard retains rights in extracted game data |
| BG Know-How | MIT website source and historical composition presentation | Study information design only | Discontinued July 2025; demonstration frozen at patch 31.6.2; database is absent from repository |

## Firestone: the useful additional data is turn-conditioned

The upstream card service uses this endpoint template:

```text
https://static.zerotoheroes.com/api/bgs/card-stats/mmr-%mmrPercentile%/%timePeriod%/overview-from-hourly.gz.json
```

It accepts rank and time filters, defaulting to `last-patch`; it maps `past-7` and `past-3` to `past-seven` and `past-three`. This establishes what the client expects, not a guarantee of every possible bucket's availability. [Card statistics loader](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/services/src/lib/services/bgs-cards.service.ts)

The shop overlay loads `last-patch`, percentile `25`, selects the current turn, and computes impact as `averagePlacement - averagePlacementOther`. It can omit missing card/turn rows. [Shop statistics service](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/common/src/lib/minion-stats/bgs-board-stats.service.ts)

The display builder exposes `totalPlayed` as the sample weight, averages placements, and only exposes placement/impact for an exact-turn selection. Tribe filtering in this function checks the card's tribe; that is **not proof of lobby-tribe-conditioned outcome statistics**. [Card statistics transformation](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/data-access/src/lib/meta-cards/bgs-meta-card-stats.ts)

Inference: use these numbers as uncertain priors, not “buying this card improves your placement by X.” Players who can obtain a card early may already be ahead. Useful conditioning still missing from this inspected consumer includes the player's existing board, offered alternatives, health, gold, hero, and intended transition. Sample size should downweight uncertain evidence, not silently turn every statistical candidate into no data.

The curated loader requests `bgs-comps-strategies.gz.json`, requires a composition ID and cards, and removes `#N/A` card entries. This is directly relevant to candidate destinations, unlike a raw combat result. [Strategy loader](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/services/src/lib/services/bgs-meta-composition-strategies.service.ts)

### Access verification and reuse

One direct read-only GET each to `card-stats/mmr-25/last-patch/overview-from-hourly.gz.json`, `comp-stats/last-patch/overview-from-hourly.gz.json`, and the curated-strategy feed returned HTTP 403 in this environment. No access-control bypass was attempted. This does not establish that Tavern Lens cannot access them, nor that its cached snapshots are current. Obtain a supported feed arrangement before making a new dependency on these URLs.

The inspected Firestone repository tree has no general `LICENSE` file. Its published terms describe personal, noncommercial service access and restrict copying, scraping, redistribution, and other exploitation without permission. The CC-BY-SA notice at the end licenses the **terms document**, not the app or datasets. Treat upstream source as inspectable research material and ask the maintainer about supported data access and permitted in-app use. [Firestone terms, sections 2, 7 and 17](https://github.com/Zero-to-Heroes/firestone/blob/master/tos.md)

## HSReplay: useful benchmark and partnership target

Tier7 currently describes hero statistics tailored to available tribes and seasonal mechanics, filtered composition guides, composition outcome statistics, and an inspiration tool with successful recent high-MMR boards. It also advertises minion positioning/combat statistics and MMR filters. Its Battlegrounds landing page identifies Jeef as its guide author and says guides update with patches. This is much closer to the desired strategic experience than an odds display alone. [Tier7 features](https://hsreplay.net/battlegrounds/tier7/), [Battlegrounds overview](https://hsreplay.net/es/battlegrounds/)

No supported third-party bulk strategy-data API was established during this research. A paid subscription is access to their product, not demonstrated permission to redistribute its database. HearthSim's service terms restrict use and copying; the current Hearthstone Deck Tracker README says all rights reserved. Neither should be treated as a permissively licensed advisor engine. [HearthSim terms](https://hearthsim.net/legal/terms-of-service.html), [HDT README](https://github.com/HearthSim/Hearthstone-Deck-Tracker)

Recommendation: request licensed aggregates and expert-guide access, with explicit permission for local inference/caching and in-app explanations. If unavailable, independently authored strategic annotations are a viable path. No outreach was sent.

### Lessons from the user-supplied overlay page

The official overlay FAQ separates combat odds, opponent tracking and minion browsing from Tier7's lobby-specific strategic data. It says Bob's Buddy simulates more than 10,000 outcomes **when combat starts**, while meta statistics update hourly and new-patch data typically arrives within two hours. These are provider claims, not independently measured service guarantees. The page confirms macOS HSTracker has most core features, rather than claiming complete parity. [HSReplay Battlegrounds overlay](https://hsreplay.net/battlegrounds/overlay/)

Product implications for Tavern Lens:

- Make current-patch evidence and compatible lobby builds visible before commitment.
- Keep direction available as a persistent plan: next enabler, temporary alternatives, and the reason to pivot.
- Expose source freshness and confidence so unavailable data cannot resemble confident advice.
- Separate observed-board combat odds from uncertain predictions about a future opponent.
- Evaluate acquisition guidance and survival decisions independently of combat simulation accuracy.

The lesson is a layered coaching experience; the page does not establish that Bob's Buddy itself is a recruit-phase planner or that its data can be copied into another product.

## Card correctness and genuinely reusable supporting projects

**HSBG Cards** documents a free versioned REST API for card lookup, batches, related entities, current pool filters, patch diffs and historical card states. Most endpoints require no authentication; autocomplete requires a key. The documented anonymous rate limit is 120 requests/minute. Historical snapshots carry provenance: current pool, patch-note snapshot, or reconstructed fallback. Those distinctions matter when replaying old decisions. Use `/api/v1/*`, not its undocumented internal website endpoint. [API documentation](https://hsbg.cards/api-docs)

Its terms allow card/data use in community projects, request attribution, and restrict substantial competing mirrors and excessive scraping. The site retains original work; Blizzard owns game assets. This is a documented integration opportunity for metadata, not outcome training data. [HSBG Cards terms](https://hsbg.cards/terms)

**HearthstoneJSON** separates data by game build and locale and publishes a latest-build redirect. Its site distinguishes its CC0 website license from Blizzard's rights in the actual game data. Preserve explicit build identity when comparing strategies across patches. [HearthstoneJSON](https://hearthstonejson.com/)

**python-hearthstone** is MIT and offers CardDefs/DBF parsers and enums. **python-hslog** is MIT and parses `Power.log` into a nested packet tree. A notable trap: its default entity-tree exporter ignores Choices, Options and MetaData; a decision dataset needs a custom exporter retaining those events. These libraries help establish reliable observations, not choose a winning purchase. [python-hearthstone](https://github.com/HearthSim/python-hearthstone), [python-hslog](https://github.com/HearthSim/python-hslog)

**BG Know-How** redirects its old composition site to its repository. Its README says it stopped at the end of Season 10 in July 2025, the demo is frozen at 31.6.2, and database data/schema are not included. The repository is MIT. It is not a current build feed. [Repository and discontinuation notice](https://github.com/O-Nemet/bgknowhow)

## What a useful acquisition should contain

### Verified public-page JSON extraction

Follow-up browser inspection found a concrete extraction path: `script#react_context` contains JSON on both the composition index and individual guide pages. The signed-out index returned 16 composition records. Index records include IDs/slugs, core card DBF IDs, tier, difficulty, and separate guide/tier update timestamps. Detail records additionally expose `comp_addon_cards`, `comp_how_to_play`, `comp_when_to_commit` and `comp_common_enablers`. Thus a separate JSON API is not required for technical extraction; the initial text-reader failures did not mean the public data was absent.

Verified detail examples: [Self-Damage Demons](https://hsreplay.net/battlegrounds/comps/13/demons-self-damage) and Peyton's [Undead Attack Scaling](https://hsreplay.net/battlegrounds/comps/14/undead-attack-scaling). The Undead record contains five core and five add-on DBF IDs, with populated play/commit/enabler fields and a guide timestamp of September 22, 2026. Card IDs should be resolved against the correct game-build database; enum meanings should be verified against visible labels instead of guessed.

A direct non-browser HTML request returned 403 in this environment, while normal signed-out browser navigation rendered the public page and its JSON. A future collector can inspect the normally rendered page, validate the schema and save a versioned local snapshot; unattended HTTP fetch reliability is not established. No private endpoint, login bypass or Tier7 data extraction was needed for these findings. No documented public bulk API was established. Access/reuse considerations above still apply separately from this confirmed technical path; they should not be conflated with an inability to inspect the data.

Only schema and factual metadata were retained during this check; a full mirror of all authored guide text was not created.

### Additional HSReplay pages supplied by Peyton

Rendered browser inspection on September 26 resolved content that the text-only web reader missed. [Comps](https://hsreplay.net/battlegrounds/comps/) lists Jeef's curated tier, difficulty and core cards, with a visible nine-day-old update indicator. Its [Self-Damage Demons detail](https://hsreplay.net/battlegrounds/comps/13/demons-self-damage) separates core cards, add-ons, how to play, commitment conditions and common enablers. This is concrete strategic knowledge, not merely a list of final-board frequencies. It supports the proposed separation of early enablers, stabilization and later payoffs without proving an optimal route from any particular shop.

[Heroes](https://hsreplay.net/battlegrounds/heroes/) exposes rank/time/tribe filters and pick-rate, best-composition, average-placement and placement-distribution columns. The inspected signed-out view gated several outcome values behind Tier7. [Minions](https://hsreplay.net/battlegrounds/minions/) and its [Aberration filter](https://hsreplay.net/battlegrounds/minions/aberration/) expose current-season cards and rank/time/tier/tribe filtering; a page-level game count is not the sample count for every card or conditional decision.

[Lesser](https://hsreplay.net/battlegrounds/trinkets/lesser/) and [Greater Trinkets](https://hsreplay.net/battlegrounds/trinkets/greater/) are separate views. The rendered Greater table includes pick rate, average placement and placement distribution. Pair-conditioned Lesser/Greater performance was not established by this inspection. [Dark Gifts](https://hsreplay.net/battlegrounds/dark-gifts/) lists named effects in the inspected view; do not label it a gift win-rate dataset without further evidence.

These pages should inform the spec's source categories and strategic context. They do not establish a bulk API or remove the access/reuse questions above. Do not conflate curated tiers with measured placement estimates or duplicate the same observations across category pages as independent evidence.

For statistics: patch/build, season/mode, MMR population, timestamp, independent sample count, card turn, hero/seasonal mechanic where sufficiently sampled, and uncertainty. Do not mix late winning boards with all early decisions as if they were the same population.

For strategy: engine/enabler/payoff/temporary-unit roles, cards that actually justify committing, acceptable alternatives, expected strength growth, timing windows, upgrade/roll guidance, and when to abandon a line. Expert content should describe a path into a build, not only seven final minions.

For learning and evaluation: snapshots **before** the decision, complete shop/choice/hand/board, legal actions and resources, chosen action sequence, later observations and final outcome. Include ordinary losses and aborted transitions, not only perfect-game examples. Track which decisions were unavailable or incorrectly observed separately from strategic mistakes. These are proposed requirements, not claims that any inspected source supplies them all.

A combat simulator estimates one fight. A recruit simulator predicts legal state changes after shop actions. A strategic policy weighs survival, economy and future options over multiple turns. Good external data can improve each layer, but none of the feeds inspected is a complete learned policy or evidence of a ready-made winning advisor.
