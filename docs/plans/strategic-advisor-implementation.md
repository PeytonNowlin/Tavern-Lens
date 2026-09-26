# Strategic advisor implementation

Spec: #23, docs/spec/strategic-recruit-advisor.md. Review baseline: 8baf89f9c5ae93efbf9e8e29f376acbaee9651d3.

Approved seams: engine replay/request → advisor result; provider/cache contracts; current live publication and overlay boundaries.

1. Version strategic requests and evaluate attainable directions from the entire eligible catalog.
2. Import the 16 captured public HSReplay compositions with card identity, guide provenance and independent source timestamps; integrate into the existing catalog.
3. Connect commitment, missing pieces and survival guidance to short legal plans and the overlay.
4. Correct source sample/freshness handling and stale live advice; scope effect uncertainty without inventing outcomes.
5. Validate archived replay compatibility and decision cases, run the full suite, review against the starting commit and commit on the current branch.

Measured match improvement requires prospective games; test success alone does not establish a win-rate gain.

## Verification

The standards review found two issues (purchase reserves and import validation), and the spec review found three (tier freshness, alternative requirements and tempo fallback). All five were fixed and rechecked by their respective reviewers.

The final focused run passed 22 tests, including archived-version compatibility and the opt-in last-match replay. In the debug audit, turn 8 took 2.12 seconds and turn 10 took 4.97 seconds for the combined search/evaluation checks; turn 10 performed four combat evaluations. Earlier audited states still had unsupported-effect limitations. These timings are diagnostic, not a live latency guarantee.

A release app was built and its advisor panel rendered offscreen successfully. The local signing identity was unavailable, so the verification bundle uses ad-hoc signing. The installed app was not replaced.

Final full verification: `scripts/test.sh` passed 494 tests across 81 suites, including the locally available captured-game fixtures. Existing archived goldens were preserved.
