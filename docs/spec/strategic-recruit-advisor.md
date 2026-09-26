## Problem Statement

Tavern Lens should help the player win more Battlegrounds matches, but its recruit advisor often provides weak, stale or unavailable advice and does not explain how to reach a strong meta build. Recognizing an existing composition is insufficient: the player needs to know which direction is attainable, which purchases enable it, when to level or roll, when to commit, and when survival demands a pivot.

The current planner receives only already-detected builds and omits much of the strategic context already present in the catalog. Statistical evidence can disappear through an inappropriate shared sample gate. Unsupported effects can disable combat validation, and completed choices can leave stale advice visible. End-of-turn captures do not fully explain decisions made earlier in the turn. More feeds alone will not fix these failures.

## Solution

Make the advisor the app's primary strategic feature. Combine current, traceable meta evidence and reviewed build knowledge with the observed game state to propose attainable directions, a coherent turn plan and legal next actions. Explain the next enabler, commitment requirements, alternatives and pivot conditions. Reassess after purchases, discoveries, rewards and other meaningful changes.

Advice must reflect hero, available tribes, seasonal mechanics, health, resources, hand, board, shop, turn and tavern tier. Use combat simulation to assess immediate survival, not as a substitute for long-term strategy. Make uncertainty and missing coverage visible without abandoning useful supported guidance. Establish decision quality and playing strength through held-out cases and prospective evaluation rather than treating passing tests as proof of increased win rate.

## User Stories

1. As a player, I want viable build directions before my board already resembles one, so that I can recognize opportunities early.
2. As a player, I want the advisor to compare a small set of attainable builds, so that I understand my meaningful alternatives.
3. As a player, I want unavailable tribes excluded, so that I am never directed toward an impossible composition.
4. As a player, I want recommendations conditioned on my hero and hero power, so that I exploit this game's advantages.
5. As a player, I want quests and completed rewards included, so that their incentives and resources affect my plan.
6. As a player, I want Lesser Trinket choices evaluated for cost and strategic fit, so that my early investment supports a coherent direction.
7. As a player, I want Greater Trinket choices evaluated with my existing Lesser Trinket and board, so that I choose a useful combination.
8. As a player, I want Dark Gift effects considered with their recipient and engine, so that I understand the offered combination's value.
9. As a player, I want Aberration and Deity interactions understood, so that seasonal engines receive appropriate guidance.
10. As a player, I want newly offered shop enablers to introduce alternative directions, so that the advisor is not locked into my current board.
11. As a player, I want explicit commitment conditions, so that I do not force a build before I have its necessary pieces.
12. As a player, I want temporary tempo cards distinguished from long-term engine pieces, so that I know what to keep and what to replace.
13. As a player, I want resource generators, multipliers and payoffs distinguished, so that I assemble a functioning engine rather than unrelated strong cards.
14. As a player, I want acceptable replacement cards identified, so that missing one preferred card does not end my plan.
15. As a player, I want a clear next action with a short continuation, so that the strategic direction becomes practical play.
16. As a player, I want target and positioning advice where relevant and supported, so that the recommended sequence works as intended.
17. As a player, I want a reason for buying, selling, leveling, refreshing or freezing, so that I understand the tradeoff.
18. As a player, I want hero- and context-sensitive leveling guidance, so that a generic curve does not override a better opportunity.
19. As a player, I want roll decisions to reflect missing pieces and realistic acquisition chances, so that I do not spend gold chasing unlikely outcomes.
20. As a player, I want unknown shops and rewards treated as possibilities, so that recommendations never rely on invented cards.
21. As a player, I want the advisor to account for board space, hand space, triples and sequencing, so that every proposed plan is executable.
22. As a player, I want hero powers, Activate actions and Dark Discovery to compete with other uses of gold, so that important actions are not overlooked.
23. As a player, I want advice to resume promptly after finishing a choice, so that a stale choice message does not waste my remaining turn.
24. As a player, I want new advice after each meaningful reveal or action, so that recommendations reflect what I can do now.
25. As a player, I want low-health advice to prioritize credible survival, so that long-term potential does not justify an avoidable elimination.
26. As a player, I want explicit pivot and abandonment conditions, so that I can stop investing in a failing direction.
27. As a player, I want a flexible tempo option when no build is justified, so that the advisor does not force a meta composition prematurely.
28. As a player, I want a concise explanation when direction changes, so that I can follow the advisor's reasoning.
29. As a player, I want unsupported interactions identified specifically, so that I know which parts of the plan are uncertain.
30. As a player, I want known economy rewards to preserve otherwise valid combat checks, so that harmless coverage flags do not disable the advisor.
31. As a player, I want old opponent information clearly distinguished from current combat evidence, so that stale odds do not create false confidence.
32. As a player, I want build and card evidence to match the current patch and mode, so that outdated guidance does not mislead me.
33. As a player, I want source age and limited sample support reflected in confidence, so that a precise number is not mistaken for reliable evidence.
34. As a player, I want useful guidance when an external feed is unavailable, so that the advisor does not depend on a live website request each turn.
35. As a player, I want optional paid data to remain optional, so that the core advisor works without a subscription.
36. As a player, I want compact direction, next-action and next-enabler guidance, so that I can use it within the recruit timer.
37. As a player, I want further explanation available on demand, so that the overlay remains readable during play.
38. As a player, I want decision evidence recorded before actions, so that confusing advice can be investigated accurately.
39. As a player, I want my local logs and decision history kept local unless I authorize sharing, so that improvement does not require unnoticed uploads.
40. As a maintainer, I want reproducible cases preserving data versions and exact requests, so that changes can be compared fairly.
41. As a maintainer, I want evaluation cases to include losses and abandoned transitions, so that the advisor does not learn only from successful final boards.
42. As a maintainer, I want expert-reviewed acceptable and unacceptable plans, so that tests assess strategic behavior instead of reproducing arbitrary scores.
43. As a maintainer, I want advice availability, freshness and effect coverage measured, so that operational failures are distinguished from strategic mistakes.
44. As a player, I want measured evidence of improved placement and decision quality, so that the advisor earns my trust.

## Implementation Decisions

- Preserve TavernEngine as the shared headless boundary for live tracking and replay. Keep strategic decisions in the engine/intelligence layer; the overlay presents the result rather than independently selecting a strategy.
- Retain the existing observed-state pipeline, legal recruit transitions, bounded planner and combat simulator. Extend their contracts instead of introducing a second disconnected advisor.
- Separate build recognition from strategic selection. Recognition describes the held board; selection evaluates the full eligible catalog against observed opportunities, commitment requirements, resources and survival. Display stabilization must not exclude a newly viable direction from evaluation.
- Extend the advisor input/output contract to preserve strategic evidence and expose candidate directions, selected direction, turn objective, next enablers, commitment/pivot conditions, legal next action, continuation, explanation and uncertainty. Version archived requests, results and fingerprints; retain old replay behavior.
- Represent reviewed archetype knowledge with explicit card roles, alternative enablers, minimum viable engines and timing/transition requirements. Keep reviewed strategic knowledge distinct from observational statistics and exact card mechanics. Do not execute unreviewed guide prose as rules.
- Keep a flexible tempo strategy available. Compare attainable outcomes instead of blindly forcing the highest population-average composition. Estimate acquisition cost and uncertainty with the current pool; never assume exact hidden opponent holdings or future shops.
- Make hero, quest/reward, Lesser and Greater Trinket, Dark Gift, Aberration and Deity context available to strategic selection and action evaluation. These categories are required advisor inputs when observed, not separate unrelated ranking panels.
- Rank seasonal choices by current board, engine, costs and alternatives. Distinguish a Dark Gift effect attached to a minion from that minion's standalone value. A source lacking joint statistics must not be presented as supplying a measured interaction benefit.
- Keep exact mechanics separate from uncertain future values. Support known economy-only effects without blanket disabling of combat checks; retain specific warnings and withholding for genuinely unresolved material effects. Audit the highest-frequency current-season interactions first and report remaining coverage.
- Ensure request identity, cancellation and publication preserve the latest decision. Completing or replacing a GENERAL choice must invalidate suspended advice and permit fresh evaluation. Older results must not overwrite newer observations or survive into the wrong phase/game.
- Use matching baseline/candidate combat scenarios for supported survival checks. Do not present stale boards or hypothetical growth scenarios as predictions of the next opponent's actual board.
- Introduce a normalized evidence contract retaining provider, source timestamp, fetch timestamp, patch/build compatibility, mode, MMR population, observation window, relevant turn, metric definition/sign, sample denominator, uncertainty and access status. Missing values remain unknown rather than becoming zero.
- Evaluate support for placement estimates separately from sampled-board support for card membership. Do not discard all evidence because one denominator fails, or lower thresholds without accounting for uncertainty. Detect upstream data that remains old despite a recent successful fetch.
- Preserve existing composition/strategy data through the full decision path. Add turn-conditioned minion evidence where a supported, permitted source is available. Treat observational placement impact as a prior, not a causal benefit from buying a card.
- Use HSReplay's composition, hero, minion, Lesser Trinket, Greater Trinket, Dark Gift and Aberration pages as explicit research/product references. Composition guide roles and commitment conditions are particularly relevant. Inspect source semantics and permitted access before depending on any provider's programmatic feed.
- Provide replaceable source adapters and a useful baseline based on current card definitions and independently authored or permitted strategic knowledge. HSReplay bulk integration is conditional on an established access arrangement; it must not block the baseline or be silently replaced with scraping. Firestone live access and freshness must be verified before adding dependencies. No provider outreach or purchase is authorized by this spec.
- Cache validated source snapshots locally with compatibility and freshness checks. External outages, access denial, malformed payloads and schema drift must preserve explicit degraded guidance rather than imply current statistics.
- Capture bounded decision-level evidence before meaningful actions and at information reveals, including observed offers/state, source/model versions, displayed plan, cancellation/completion state, and observed subsequent actions/outcome where available. Preserve existing combat-start diagnostics and bookmarks; do not treat them as a complete action history.
- Keep the player in control. Present a compact strategic direction and next action, with optional detail. Do not automate the game, read hidden information, or expose speculative numerical placement improvements as measured facts.
- Deliver in ordered increments: reliable fresh decisions and data preservation; explicit strategic selection and transitions; contextual source enrichment; then held-out and prospective evaluation. The implementation must document remaining coverage and data access limitations at each increment.

## Testing Decisions

- Primary seam, confirmed by Peyton: the existing production path from replayed observed events through TavernEngine request construction and advisor evaluation to published advice. Use this as the main feature acceptance boundary, with deterministic captured data and the real planner. This catches information lost between catalog, engine and advisor instead of only testing isolated scores.
- Test externally observable recommendations, legal continuations, strategic explanations, confidence and invalidation. Prefer acceptable plan sets and explicit prohibited behavior over exact heuristic totals, private helpers, beam ordering or snapshots that merely bless current output.
- Reuse existing synthetic replay, recruit planner, saved AdvisorCase/bookmark, diagnostic persistence and real-match audit patterns. Preserve archived version compatibility. Sanitized fixtures must run without private logs; optional local private-match audits must report skipped coverage honestly.
- Cover an offered enabler for a previously undetected build; insufficient commitment evidence; a justified pivot; a temporary tempo purchase; low-health stabilization; hero-specific resource timing; and an unchanged board whose seasonal choice changes the preferred direction.
- Cover Lesser/Greater Trinket interactions, recipient-sensitive Dark Gift choices and an Aberration/Deity engine. Unknown or insufficiently supported interactions must reduce confidence or withhold affected actions without fabricating outcomes.
- Replay choice-open, choice-complete, replacement-choice, action-reveal and combat-start events. Assert that old advice is withdrawn and cannot overwrite advice for a newer state. Include regressions derived from the last-game stale-choice and quest-coverage failures.
- Verify complete recommended sequences against observed resources, readiness, capacity and supported effects. Include triples, linked discards, unknown rewards and information boundaries; assert that hypothetical rewards are not treated as observed cards.
- Use the existing injectable data-source/cache boundary for focused provider contract tests: fresh fetch with old source timestamp, empty/sparse evidence, different denominators, incompatible patch/mode, duplicate correlated sources, sign conventions, malformed responses, access denial and offline fallback. These tests supplement the primary seam because provider failure cannot be meaningfully represented as a player action.
- Add a small integration check at the existing live publication/overlay boundary for cancellation and visible advice state. Reuse pure overlay layout tests and focused visual verification for the compact guidance display; avoid requiring a new test-only strategic interface.
- Before tuning, freeze a held-out decision corpus spanning early/mid/late game and split by whole game and patch. Have expert review identify acceptable alternatives, severe errors and disagreement. Compare current behavior, repaired reliability/data, strategic selection and added statistical priors separately.
- Report advice availability/freshness, illegal or materially invalid plans, unsupported-mechanic frequency, expert preference and severe-error rate. For prospective play, predefine average placement as the primary outcome and report top-four/first-place rates, catastrophic losses, patch/rank, adherence, counts and uncertainty. No win-rate claim is accepted solely from simulator self-play or replay tests.
- Run the project's test wrapper when implementation begins; Command Line Tools can make plain Swift testing report success without executing the intended tests. This specification task itself does not run builds or change application code.

## Out of Scope

- Application implementation, builds or model training during this specification task.
- Replacing the current combat simulator solely to obtain strategic advice.
- A full general Hearthstone recruit rules engine, exhaustive long-horizon search or current-season reinforcement-learning champion in the first delivery.
- Unrestricted language-model gameplay decisions or invented card effects and probabilities.
- Automated game inputs, hidden-state access, account creation, subscription purchases, provider outreach or bypassing access restrictions.
- A guaranteed win-rate increase or a conclusion about the optimal play in every past match.
- Duos-specific planning and advice for non-Battlegrounds modes.
- Copying proprietary guide databases or treating source-visible applications as permissively licensed software.

## Further Notes

Research was performed against local implementation and saved match evidence, plus primary upstream sources. The observed last-game failures demonstrate gaps; they do not establish the best counterfactual purchasing sequence.

Peyton supplied the following product/data references, all relevant to the target experience:

- [HSReplay overlay](https://hsreplay.net/battlegrounds/overlay/)
- [Composition guides](https://hsreplay.net/battlegrounds/comps/)
- [Heroes](https://hsreplay.net/battlegrounds/heroes/)
- [Minions](https://hsreplay.net/battlegrounds/minions/)
- [Lesser Trinkets](https://hsreplay.net/battlegrounds/trinkets/lesser/)
- [Greater Trinkets](https://hsreplay.net/battlegrounds/trinkets/greater/)
- [Dark Gifts](https://hsreplay.net/battlegrounds/dark-gifts/)
- [Aberration minions](https://hsreplay.net/battlegrounds/minions/aberration/)

Rendered-page inspection found meaningful public guide content despite limited text-only extraction. The Self-Damage Demons guide separates core/support cards, common enablers and commitment conditions. Hero tables expose outcome columns but gate some values behind Tier7. Dark Gifts are an effect catalog in the inspected view, not an established outcome dataset. Public visibility does not itself establish bulk API access or redistribution rights.

Follow-up extraction research confirmed structured JSON embedded in the public composition index and detail pages. The index exposed 16 builds; detail records contain core/add-on card DBF IDs, how-to-play text, commitment conditions, common enablers and update timestamps. Both Self-Damage Demons and Undead Attack Scaling were verified while signed out. A separate API is therefore not a prerequisite for technically extracting public composition knowledge. Evaluate versioned local snapshots from these page records as a source option, with schema/card-ID/enum validation and explicit provenance. Direct HTTP fetching returned 403 here although normal browser navigation worked; unattended collection reliability and permitted reuse remain separate questions. Tier7-restricted statistics are not included in this finding.

Peyton confirmed the testing approach and authorized publication on September 26, 2026. This spec is ready for agent implementation; no application implementation has been performed as part of writing it.
