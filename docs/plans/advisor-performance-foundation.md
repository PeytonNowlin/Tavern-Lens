# Advisor performance and foundation

The published change contains the production-role boundary, search optimizations, standalone benchmark, contract tests, and optional packaging toolchain selectors. The primary workspace already contained unpublished policy 12/13 and latency work. That work remains local. Its performance measurements and local app update are recorded separately from validation on clean remote main, which uses live policy 11.

## Workflow

- [x] Read the Principles section of Poteto Mode.
- [x] Frame. Trace the live and planner paths, preserve existing local edits, and set measurable completion criteria.
- [x] Design the workflow. Capture a repeatable baseline before changing production code.
- [x] Ground.
- [x] Sketch. Compare at least two designs for the measured bottleneck.
- [x] Agree. Proceed with the chosen design unless a product decision needs Peyton.
- [x] Implement. Verify each performance change separately against the baseline.
- [x] Scrap. Revisit the design if implementation violates its invariants. Removed the ineffective full-match cache.
- [x] Keep the audit trail. Record decisions and evidence in `.audit/advisor-foundation.tsv`.
- [x] Verify and hand back. Run replay, cancellation, effect, and full tests, build a staged app, and report measured limits.

## Completion criteria

The same frozen requests must produce identical search plans, values, limitations, and completed advice before and after optimization. Existing combat and advisor goldens must pass without re-recording. Cancellation and latest-state publication must continue to work. A repeatable release benchmark must show a planner or evaluator improvement without reducing depth, width, expansion limits, or simulation counts.

Live latency improvement requires app measurements from comparable game decisions. Headless search measurements establish search speed only. The launched app remains running while a verified update is staged.

## Scope and throughput checkpoint

Start with one benchmark harness and one measured planner improvement. Compare designs before adding caching or new ownership boundaries. Preserve all existing uncommitted work. Evaluate a second independent change only after the first passes its behavior and performance checks.

The initial saved release-app sample contains 172 measured decisions. Planner search takes 346.515 ms median and 691.401 ms p95 across 166 decisions. Fingerprinting takes 2.930 ms median. These observations select the search path for investigation. They are not a controlled before-and-after comparison.

## Constraints

Policy versions and deterministic request fingerprints are replay contracts. Keep derived runtime state outside Codable request fields. Effect dispatch remains version-gated and exact-definition checks stay in place. Approximate projections must not enter combat simulation. The simulator has one JavaScript VM and must preserve lane fairness and per-generator random state.

## Design and results

In the primary workspace, the live pipeline prepares request identity off the main actor. The runner evaluates detached work and rejects superseded results through `LatestRunner`. `RecruitEvaluation` selects the evaluated policy before search. `RecruitPlanner` owns exact transitions, raw beam valuation, end-of-turn projection, and best continuation selection. Combat evaluation consumes only projections with no limitations. This change retains these owners and the existing planner API on both checkouts.

Candidate A deepens the existing pure text parser and retains the best plan per first action during traversal. Candidate B introduces a request-local `RecruitSession` with compiled static rules and definition indexes. A separate `gpt-6-sol` review preferred A, scoring it 21/25 against B's 16/25 for replay safety, measured speed potential, API depth, ownership, and verification.

The first full-match cache prototype preserved all 32 benchmark outputs but reduced the sum of case medians by only 0.067%, within measurement noise. It was removed. A five-second CPU sample then identified repeated generic production recognition, especially Foundation substring searches, as the useful parsing boundary.

Search keeps the existing strict improvement rule in a map keyed by first action during traversal. It still values every successful projected plan and uses separate raw-state values for the beam. Terminal states and beams with no subsequent depth need no raw valuation.

The separate production design uses a private typed description of normalized card text. Only static wording recognition is shared. Board membership, hand supply, global bonuses, golden state, repeaters, card-specific overrides, and policy remain current inputs. The existing public production API and replay data shapes remain in place. Its cache has an advisory entry limit and can evict descriptors without changing behavior.

The request-local session was rejected for this change because it requires 19 production and 236 test call-site migrations without a measured benefit over the current boundaries. Definition indexes and precompiled semantic effects remain possible later if a profile supports them.

Model the Domain selected typed production roles and first-action map ownership. Laziness Protocol kept existing public APIs and removed the ineffective cache. Build the Lever selected exact-output benchmark signatures and a comparison script. Sequence Work into Verifiable Units isolated retention, unused scoring, and production recognition. Test Behavior, Not Implementation selected literal old-entry-point tests before replacing its internals. Prove It Works requires paired measurements and unchanged replay goldens before acceptance. Foundational Thinking kept derived recognition outside Codable requests and concurrent state valuation.

### Primary workspace measurements

| Release search measurement | Sum of 32 case medians | Reduction from baseline |
| --- | ---: | ---: |
| Baseline | 1,632.497 ms | |
| Retain best continuations during traversal | 1,596.927 ms | 2.179% |
| Also skip unused raw beam valuation | 1,325.898 ms | 18.781% |
| Also recognize static production roles once | 572.619 ms | 64.924% |
| Confirm combined change in another process | 567.019 ms | 65.267% |

Both search changes passed 74 targeted tests and preserved the exact full search signatures, expansion counts, and returned plan counts for all 32 rows. Each benchmark used one first search plus five warm repetitions per row. These are search timings, not measured live decision latency.

Production recognition passed seven test functions, including 17 literal wording cases, against the original implementation before integration. After integration, 59 policy and planner test functions passed. The full paired corpus preserved all 32 search signatures. Production recognition alone reduced the sum of case medians by 56.813% from the already optimized search.

The complete release suite reported 736 tests across 129 suites and passed in 122.164 seconds. Captured-game replay, completed advisor goldens, policy fingerprints, latest-result cancellation, simulator scheduling, and effects passed. Opt-in private diagnostic audits and separate benchmarks remained skipped. Goldens were not re-recorded. After independent review, a terminal-roll search contract was added; the final focused gate passed 12 tests across two suites, including all production and search contracts.

Both hermetic packaging and atomic-installer test scripts passed. The staged primary-workspace archive passed signature and round-trip integrity verification. The canonical local bundle, including the existing unpublished work, was atomically updated and relaunched through `/Applications/Tavern Lens.app`. Its executable exactly matched the archive and its running process was verified. The previous app remains in `build/Tavern Lens.previous.zip`. Original staged and backup ZIPs were additionally preserved under `/private/tmp` before packaging. This installation does not represent a build of clean remote main.

The installed app and its replacement use ad-hoc signing because this host has no `Tavern Lens Local` identity. macOS may ask for existing permissions again. UI automation timed out before and after the update, so the overlay and resumed match were not visually verified. No controlled signed-app latency comparison was performed. The measured speed claim applies to search only.

Independent `gpt-6-sol` review found no supported product correctness issue. It identified weak historical evidence pointers and the default-suite terminal test gap. Append-only trail corrections restored the original aggregate observation from the active transcript and retained compiler-failure excerpts. The terminal search contract now runs in the default suite.

### Published change on clean main

The isolated publication checkout starts from remote main `b6fa79a`. Its planner and live policy differ from the primary workspace, so it has a separate frozen before/after comparison. Its benchmark reports 34 case/policy rows. All request identities, policy choices, budgets, expansion counts, retained plan counts, and full ordered output hashes match before and after.

| Clean-main search measurement | Sum of 34 case medians | Reduction from clean-main baseline |
| --- | ---: | ---: |
| Unmodified planner | 1,857.380 ms | |
| Production roles and search optimizations | 877.628 ms | 52.749% |
| Confirm optimized search in another process | 882.145 ms | 52.506% |

The complete clean-main release suite passed, reporting 745 tests across 130 suites. It used the original private replay fixture directory without copying private files into the publication checkout. Existing advisor and combat goldens passed without re-recording. Packaging and installer behavior scripts also passed against the newer upstream packaging code.

The standalone benchmark owns its synthetic tier/shop JSON fixture. Unsupported pool/economy metadata was removed after review. Those fields had already been ignored by clean main's decoder, and the final benchmark comparison proves that the fixture correction kept all 34 clean-main request identities and outputs unchanged. Every stored search-state field is encoded through reflection; unsupported fields or unordered set types fail explicitly. The earlier 32-case gate established serializer compatibility in the primary workspace before reducing this fixture. The final fixture and benchmark are verified by the clean-main pair.

The full clean-main suite ran before the fixture path/name correction. The final benchmark recompiled the corrected test source and exercised the corrected fixture. Production code was unchanged between these gates. Measurements are pure search timings; signed-app user latency and advice quality were not measured by this benchmark.

## Verification commands

The installed Swift 6.4 default build system cannot discover Testing macros under Command Line Tools. Its default macOS 27 SDK also references an absent SwiftUI macro plugin. This session uses the installed macOS 26.5 SDK and native SwiftPM. These are host-specific selectors, not advisor requirements.

```sh
scripts/test.sh --build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -c release
TAVERN_ADVISOR_BENCHMARK_OUTPUT=/tmp/before.json scripts/benchmark-advisor.sh --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
TAVERN_ADVISOR_BENCHMARK_OUTPUT=/tmp/after.json scripts/benchmark-advisor.sh --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
python3 scripts/compare-advisor-benchmarks.py /tmp/before.json /tmp/after.json
```

The benchmark measures pure Swift search with fixed budgets. Optional diagnostics stay local and are selected by stable request identity. Reports contain opaque identities and output hashes. They do not contain captured player data.

The initial baseline passes 58 tests across seven targeted suites, including policy goldens, planner behavior, latency identity, and cooperative simulation scheduling. Results from the new benchmark and implementation checks follow after each unit.
