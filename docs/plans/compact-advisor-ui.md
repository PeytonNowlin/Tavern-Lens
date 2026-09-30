# Compact advisor UI

Approved scope: make recruit advice readable at a glance while preserving the
engine's uncertainty, observed build fit and proposed transitions.

- Use the existing 250 × 262 reference-point advisor area. Show one next action,
  its reason and confidence; keep prerequisites visible. Tentative advice stays
  explicitly tentative rather than becoming an imperative recommendation.
- Replace competing ranked highlights with a single `Next` target. Build-fit
  highlights remain a separate, quieter claim.
- Put the full sequence, explanation, limitations, alternative actions and build
  requirements in a scrollable details panel occupying the existing build-tips
  area. Register its exact interaction region only while open. Close details when
  the advice fingerprint changes.
- Distinguish current detected fit from suggested direction. Only show owned and
  affordable shop pieces when the request matches the displayed advice.
- Add persistent Compact / Comfortable density and visibility controls. Preserve
  storage preferences and click-through outside explicit overlay controls.
- Make refresh status explicit without presenting previous-board odds as current.

Verification: headless presentation and layout tests via `scripts/test.sh`, app
bundle compilation, rendered captured and edge-case states, and native disclosure
and settings interaction. Inspect minimum-size layouts and preserve no-overlap
checks. Live-game usefulness and improved placement require separate playtesting.

## Verification completed

- `scripts/test.sh`: 507 tests across 82 suites passed.
- `scripts/bundle-app.sh`: release app bundle built; local signing identity was
  unavailable, so the existing build script used ad-hoc signing.
- Native renders covered recorded recommendations and tentative advice, updating,
  thinking, missing-data and failure states, long titles, and minimum-size layouts.
- Native disclosure and collapse controls worked. Density and visibility controls
  updated, and their saved preferences persisted; original settings were restored.
  UI automation could not reconnect after the settings preview restarted, so saved
  values were verified through macOS preferences.
- Hearthstone was closed. Live game placement and click-through behavior still
  need a playtest; headless geometry tests verify registered interaction regions.
