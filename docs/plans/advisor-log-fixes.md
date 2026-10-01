# Advisor fixes from captured games

Use seeds 670219605 (first-place Dragons), 483422699 (fourth-place Dragons), and
1179245919 (third-place Beetles) as development evidence. Their recorded policy is
version 3. Retained snapshots are selective; they do not measure live waiting time
or prove that an alternative plan would improve placement.

## Scope

- Project Steady Growth's observed pending t51e increment once per end-of-turn
  trigger. Never apply t51e2 historical growth again or guess absent script data.
- Recognize exact Faerie Dragon Scale and greater Beetle Band definitions as
  simulator-owned combat effects. Rockin' Music Box's next reward arrives next
  turn; preserve the observed hand without inventing random cards.
- Below or at 15 health, withhold any continuation containing a level step until
  all baseline/candidate scenarios are checked; reject increases in lethal risk.
- Separate chosen-plan limitations from missing alternative-action coverage.
  A fully combat-checked supported plan may have medium confidence, with the
  visible caveat that ranking covers supported plans and unfinished search may change
  the ranking. Do not wait for unrelated candidates once its matched checks finish.
  Unknown alternatives without
  combat evidence and unresolved chosen effects retain low confidence.

Use evaluation version 5, reserving version 4 for the existing uncommitted
advisor-quality worktree. Preserve evaluation and fingerprint behavior for the
recorded versions. Do not modify that worktree, the simulator package, or its bundle.

## Verification and delivery

`scripts/test.sh --filter AdvisorLogRegressionTests` reproduces the original
failures and validates their corrections. The optional
`TAVERN_LOG_AUDIT_DIAGNOSTICS` audit replays nine captured decisions with their
original policy, then evaluates the same inputs under the live policy and budget.
Run the full test wrapper with the private fixture directory explicitly supplied.

Push verified changes directly to main as requested. Do not reopen the app or
replace its running bundle tonight. Measure refresh latency separately before
changing debounce or claiming the captured Thinking states represent a timing bug.

## Verified results

- Original regression command failed with 11 assertions across four tests before
  production changes; the corrected cases pass.
- Full wrapper run with private fixtures and captured-game audit: 515 tests in
  83 suites passed. Nine recorded version-3 decisions reproduced their saved advice.
- The same captured inputs restored previously blocked combat evaluations and
  produced supported recommendations in Beetle positions under the existing time
  budget. The 11-HP unchecked leveling continuation is withheld. This is development
  evidence, not proof of improved placements or measured live display latency.
- No simulator package or bundled JavaScript changes; no private game data committed.
