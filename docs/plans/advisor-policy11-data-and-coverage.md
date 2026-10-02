# Advisor policy 11: data and coverage

The October 2 source audit and captured games identify two immediate projection failures:
completed Ornate Clock blocks purchase checks, and Fortify's health-only wording is missed.
The Elemental replay also supplies exact Living Prison and Arcane Absorption transitions.

## Implementation

- Gate new recruit behavior at evaluation version 11. Keep older policy replay and
  request fingerprints stable.
- Repair Clock and Fortify, and model observed Prison and Absorption transitions.
  Offer Lionfish activation only for attack chains the projection can represent exactly.
  Keep an explicit limitation for unsupported chains.
- Fetch Firestone's MMR-25, last-patch card-by-turn statistics with a bounded,
  conditional cache. Require fresh source dates, valid placement values, both comparison
  counts, exact turns and currently eligible cards. Archive relevant rows with the request.
  Apply a small population prior only to newly purchased minions deployed on the board.
  Restrict it to recruit turns 1–3, where the comparison population remains usable.
- Preserve logged options and outgoing selections with the preceding recruit request.
  Bound local storage and exclude catch-up actions from live evidence. Record individual
  advice display times; never infer advice adherence from a selection alone.
- Retain richer hero/trinket source fields and write diagnostic coverage evidence useful
  for the next source audit. Avoid deriving combat danger from population averages.
- Incorporate independently checked findings from the supplied Claude synthesis:
  expire forced Aberration at the official 36.6.3 publication boundary, correct dated
  shop-pool deltas and Deity combat rules, refresh composition statistics and recipes,
  and choose hero-stat populations from fresh same-window MMR percentiles.
  Preserve the source date, population and selection reason with that evidence.

## Verification and delivery

Run focused tests through `scripts/test.sh`, then the complete suite with available
private replay fixtures. Audit captured policy-10 fingerprints and the reproduced
Clock/Fortify/Elemental cases. Build with `scripts/bundle-app.sh`; stage before replacing
the running bundle, install the canonical app and verify launch and cache refresh.

Use independently authored effect rules. Keep the MIT simulator package and card-data
pins; rebuild its wrapper with a dated, per-run 36.6.3 Deity correction. Newer upstream
versions have a different license. Population placement differences remain
associations, and this build does not establish an improvement in placement or MMR.

Evidence: [source priorities](../research/advisor-data-gap-priorities-2026-10-02.md).
The supplied deep review is integrated in
[build 74 source decisions](../research/advisor-build74-review-integration.md).
