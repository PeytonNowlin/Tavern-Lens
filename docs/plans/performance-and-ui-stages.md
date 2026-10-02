# Performance and UI improvement stages

The ongoing objective is to improve Tavern Lens performance and its in-game UI, delivering tested builds in stages while Peyton plays. Keep one installed bundle and preserve ongoing tracking during games.

## First stage

- Reduce repeated sorted-JSON serialization of unchanged advisor requests during progressive publication. Preserve exact versioned fingerprints, cancellation, request pairing and recorded replay results.
- Show the principal coverage limitation when advice is tentative, where it can explain why no action is recommended. Keep uncertain actions out of the primary recommendation and retain full explanations in details.
- Build and sign a staged ZIP without changing the running bundle or keeping a second discoverable app. Limit build concurrency during play. Refuse to overwrite a bundle while its executable is running.

Validate the changed scheduling and diagnostic contracts with `scripts/test.sh`, inspect recorded-decision panel renders at small and normal scales, and verify packaging behavior with isolated shell fixtures. Measure performance with representative recorded requests without claiming a live latency or gameplay improvement from deterministic tests alone.

## Delivery and subsequent stages

Install a verified stage only between games, retaining the main checkout's bundle and its Applications shortcut. Confirm the process runs after replacement and check current game state again immediately before a restart. Preserve local records, diagnostics, user preferences and the separate experimental advisor-quality worktree.

Use subsequent real-game diagnostics and UI checks to select the next improvements. Known Quilboar recruit-effect coverage remains separate from these performance and presentation changes; do not describe it as fixed by this stage. A staged ZIP is a prepared build, not a launched update.
