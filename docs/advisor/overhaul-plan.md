# Recruit planner overhaul

Replace the live advisor's one-action, last-opponent objective with a bounded recruit planner.
Preserve versioned evaluation of old feedback bookmarks so saved evidence remains reproducible.

1. Carry current card text, mechanics, golden mappings and hero-power costs in replayable requests.
2. Resolve supported recruit actions through a pure state transition: gold, spaces, buffs, triggers,
   triples and hero powers. Stop at unresolved random outcomes; disclose unsupported effects.
3. Search short legal sequences with deterministic beam limits. Score retained board strength,
   scaling production, economy and build coherence; protect engines by their contribution rather
   than raw stats. Return the first action with its planned continuation.
4. Check shortlisted plans against multiple observed opponent scenarios. Treat old observations as
   uncertain evidence, cap confidence, and prioritize survival at low health. Never present the
   historical opponent as the next opponent's predicted board.
5. Automatically retain the last displayed recruit advice/request and combat inputs/results in a
   bounded local diagnostic store, including incomplete/stale advice and write failures.
6. Test legal transitions, unsupported effects, sequence value, engine preservation, uncertainty,
   deterministic budget stops, persistence and acceptable/unacceptable decisions. Run
   `scripts/test.sh`, then `scripts/bundle-app.sh` and inspect the resulting application.

Acceptance: live advice works without a previously seen opponent, does not treat battlecries as
vanilla minions, can recommend a legal multi-action plan, explains strategic value, and can be
audited after a match without a manual bookmark. Unknown mechanics must reduce coverage rather
than silently inventing outcomes. Search and card-effect coverage remain explicitly bounded.

## Seasonal mechanics and trinket picks

Carry equipped trinket and attached enchantment definitions with every recruit request. Read
Activate availability and cost from the live entities, rather than guessing from card text alone.
Resolve supported discard actions, Sludge's double cast, both Portrait rewards, and Dark Gift
play/counter triggers. Preserve unknown outcomes as replan boundaries. Include Aberration/Deity
progress and attached combat effects in strategic estimates without applying combat buffs twice.

Track GENERAL trinket offers through displayed-task and chosen events. Show all choices in their
screen order, with separate ranks, explanations, observed costs and population sample counts.
Use Firestone's public past-three-day aggregates as a modest baseline; current-board synergies
can outweigh it. Reject stale/sparse/invalid data. Retain a last-good cache and clear the panel
when the offer resolves. Verify the actual match, synthetic mechanic regressions, and rendered UI.
