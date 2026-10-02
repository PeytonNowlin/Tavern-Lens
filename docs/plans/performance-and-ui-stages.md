# Performance and UI improvement stages

The ongoing objective is to improve Tavern Lens performance and its in-game UI, delivering tested builds in stages while Peyton plays. Keep one installed bundle and preserve ongoing tracking during games.

## First stage

- Reduce repeated sorted-JSON serialization of unchanged advisor requests during progressive publication. Preserve exact versioned fingerprints, cancellation, request pairing and recorded replay results.
- Show the principal coverage limitation when advice is tentative, where it can explain why no action is recommended. Keep uncertain actions out of the primary recommendation and retain full explanations in details.
- Build and sign a staged ZIP without changing the running bundle or keeping a second discoverable app. Limit build concurrency during play. Refuse to overwrite a bundle while its executable is running.

Validate the changed scheduling and diagnostic contracts with `scripts/test.sh`, inspect recorded-decision panel renders at small and normal scales, and verify packaging behavior with isolated shell fixtures. Measure performance with representative recorded requests without claiming a live latency or gameplay improvement from deterministic tests alone.

## Delivery and subsequent stages

Peyton also authorizes replacing and relaunching Tavern Lens during a game. Build and verify the staged archive first, stop only Tavern Lens, atomically replace the main checkout's bundle, then relaunch through its existing Applications shortcut. Confirm there is one bundle and one process, and that the live tracker resumes the same ongoing match. Hearthstone stays running. Preserve local records, diagnostics, user preferences and the separate experimental advisor-quality worktree.

Use subsequent real-game diagnostics and UI checks to select the next improvements. Known Quilboar recruit-effect coverage remains separate from these performance and presentation changes; do not describe it as fixed by this stage. A staged ZIP is a prepared build, not a launched update.

## Second stage

- Improve the next-opponent panel's text at small scales without expanding its input boundaries. Validate actual rendered seven-minion boards and odds/status states.
- Add a separate MMR history window, atomic local history storage, explicit entry/correction, and conservative lobby-only screen readings. Never derive ratings from placement. Unknown or ambiguous readings are not saved.
- Add policy 7 minion Activate candidates using observed readiness and cost. Preserve archived policies and distinguish unsupported activation families in the UI.
- Check the active game's trinkets at both the advisor coverage boundary and the simulator input boundary; a known card definition does not establish effect support.
- Promote staged archives with a verified atomic installer and a restorable previous ZIP, retaining one installed bundle.
