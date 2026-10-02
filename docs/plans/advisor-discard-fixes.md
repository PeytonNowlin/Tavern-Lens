# Discard advisor fixes from the October 1 win

Use completed seed 2034216535 as development evidence, preserving its version-5
requests and evaluations. Implement version 6 for the exact observed lesser Hammer
of Twilight, normal/golden Parasitic Fleshling, Time Turning and Affinity effects.

The failing synthetic regression command is `scripts/test.sh --jobs 2 --no-parallel
--filter AdvisorDiscardRegressionTests`: seven tests initially produced 25 failed
assertions. Fix the supported transitions and projection, including Hammer aura
metadata on board entry, stat replacement and triples. Current observed stats
already contain previous growth; project only the pending end-of-turn effects.
Unknown random rewards must remain unknown, and hand-sensitive combat or possible
Affinity triples must retain uncertainty. Do not fit a special Envoy sale penalty
to a suggestion whose outcome was not independently evaluated.

Preserve evaluation policies and fingerprints through version 5. Run targeted
regressions, saved version-5 replay comparisons, and the full test wrapper. Use
low-priority, limited-job test processes while the user plays. Do not replace or
restart the running app or bundle. The unrelated experimental advisor-quality
worktree remains separate.

## Verified results

- Focused regressions plus the new private replay audit: 17 tests in two suites
  passed. Five archived version-5 decisions reproduced their advice exactly.
- Version 6 restored combat checks in four of those five sampled positions;
  the due Affinity reward with a board pair remained uncertain. The sampled
  turn-8 pair-free state produced a supported recommendation.
- Full wrapper run with private captured logs and the earlier nine-decision
  version-3 audit: 533 tests in 85 suites passed. Serial low-priority execution
  took 577 seconds; this is test runtime, not measured in-game latency.
- The user finished their next game and requested the new release for the next
  launch. Package and restart only after these checks; keep the new game's
  separate Quilboar coverage findings out of this discard patch.
