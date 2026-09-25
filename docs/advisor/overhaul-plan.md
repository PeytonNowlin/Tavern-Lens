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
