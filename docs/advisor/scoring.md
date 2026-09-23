# Advisor scoring, sanity layer and weight tuning

The advisor (spec #1, tickets #19 and #20) ranks what the player could do this recruit phase. This
note describes how a suggestion is scored, the hand-written rules that veto or move down clearly
bad advice, and how to tune the weights from playtest bookmarks.

Code: `Sources/BGIntel/Advisor/` (pure: candidates, terms, ranking, sanity) and
`Sources/TavernEngine/Advisor.swift` (the evaluation passes, the runner) and
`Sources/TavernEngine/AdvisorTuning.swift` (the tuning replay).

## The blended score

Every suggestion's **gain** over keeping the board is the sum of four weighted terms
(`AdvisorTerms`, all in percentage points of win equity against the next opponent):

| Term | Weight | What it measures | How |
|---|---|---|---|
| combat | `combat` (1.0) | the next combat against the next opponent's last-seen board | simulated: equity + 0.5 × damage dealt − 1 × damage taken − lethal risk |
| lobby | `lobby` (0.5) | the same board against every other living opponent's last-seen board | simulated for the baseline and the best `lobbyGroups` board changes, `lobbySimulations` each |
| build | `build` (1.0) | progress toward the detected builds (0–2, the second at 60%) | rule of thumb |
| economy | `economy` (1.0) | gold and levelling tempo over this turn and the next two | rule of thumb |

The terms that need no simulation (build, economy) also order the candidates before the refine and
lobby passes, so a build card's buy gets its placements tried and is scored against the lobby.

### Lobby

Each other opponent counts by `likelihood × freshness`: the one fought last turn counts
`lobbyRecentFactor` (0.5), since they're less likely to come up again at once; a board counts half
as much every `lobbyStaleHalfLife` (3) turns after the first. The lobby gain is the weighted mean,
over the opponents both were scored against, of the candidate's combat value minus the baseline's.
A suggestion outside the best few has no lobby term (nil), which counts as 0. Only the baseline and
the best `lobbyGroups` board changes are scored against the lobby because each costs one evaluation
per opponent: every candidate would be about 180 evaluations late in a game, far past the time
budget, and the other terms have already ranked the rest too low for the lobby to change the top
(`docs/deviations.md`).

### An unseen next opponent: a stand-in

Matchmaking avoids recent opponents, so early in a game the next opponent is usually one not fought
yet, and has no board to simulate against. Then the combat term fights a **stand-in**
(`AdvisorRequest.standIn`): the most recently seen living opponent's board (a combat-start side
before a rebuilt one, then the lower PlayerID), with the next opponent's health and tier. It is
usually last turn's opponent, the freshest sample of how strong boards are now. The stand-in leaves
the lobby term, which covers the rest. Its advice is capped at medium confidence, the reasons name it
("+8% win vs last opponent"), and the note says the next opponent hasn't been fought. Only with no
opponent seen at all (turn 1) is there no data.

### Builds

The value of the cards held (board and hand), per build and by its share: `buildCoreCard` (6) per
core card, `buildAddonCard` (2) per add-on, `buildCopy` (1.5) per extra copy toward a triple (at
most two; a golden is done). A buy, sell or swap gains the change in that value. Levelling to the
tier of a missing core card gains `buildUnlock` (3) per build.

### Economy (1–2 turns ahead, no search)

A plan "level in k turns" (k = 0, 1, 2) is worth `tierTurnValue × urgency × (3 − k)` minus
`goldValue ×` the upgrade's price then (it gets 1 cheaper a turn), and needs that much gold then
(income grows by 1 a turn up to the cap). Not levelling is worth 0. Urgency comes from a steady
levelling curve (tier 2 on turn 2, 3 on turn 5, 4 on turn 7, 5 on turn 9, 6 on turn 11): 1.5 behind
it, 1 on it, 0.5 ahead of it.

- **Level**: levelling now minus the best later plan (negative when waiting is better).
- **A board change that spends gold** (buy, swap, shop spell, refresh): when it makes levelling now
  unaffordable and levelling now is the best plan, it costs that plan's advantage; a sale that makes
  levelling affordable now gains it.
- **Refresh**: `freshShopValue × need − goldValue × cost` plus its tempo, where need is the chance of
  losing the next combat as the board is.
- **Freeze**: `freezeShare × (kept − freshShopValue × need)`, where kept is the best too-dear buy's
  gain or the best build card in the shop.

These replace #19's placeholders (level first when ahead, refresh first when behind, freeze when a
dear card would help).

### Confidence and "no strong recommendation"

A suggestion is an **improvement** when its gain is at least `minimumGain` and at least `minimumZ`
standard errors of its simulated part (combat and lobby). Only improvements are shown.

- Board changes: high at `highZ` (3) standard errors, medium at `mediumZ` (1.5), else low; at most
  medium when a runner-up is within noise, when build and economy make up more than half the gain,
  or when the opponent's board is `staleAfterTurns` (3) or more turns old or rebuilt from history;
  low under `minimumSimulations`.
- Level, refresh and freeze (rules of thumb): medium when scoring is complete and the gain is at least
  twice `minimumGain`, else low.
- A suggestion moved down by the sanity layer is low.

The status is **no strong recommendation** when the top two are within `minimumGain` or one
standard error of each other ("Options are close"), when nothing is an improvement ("Nothing clearly
improves your odds"), or when the top suggestion is low confidence.

## The sanity layer

`AdvisorSanity` runs on the improvements in ranked order. A **veto** takes a suggestion out; a
**downrank** moves it after every suggestion no rule moved. The rules that fired are listed in
`Advice.sanity` (and so in bookmarks).

| Rule | Effect | When |
|---|---|---|
| `unaffordable` | veto | the action costs more gold than there is |
| `lastMinion` | veto | selling the only minion |
| `newLethalRisk` | veto | a board change raises the next combat's lethal risk by `sanityLethalIncrease` (5) points or more, and by more than twice its noise |
| `survivalFirst` | downrank | the board as it is has `sanitySurvivalLethal` (20)% or more lethal risk: level and freeze go below every board change that cuts it by 5 points or more |
| `keepPairs` | veto | selling or swapping out one of two copies of a minion, unless the combat gains `sanityOverrideGain` (15) or more |
| `keepBuildCore` | veto | selling or swapping out a core card of a detected build, unless the combat gains `sanityOverrideGain` or more |
| `rollPastImprovement` | veto | refreshing while a buy, swap or spell from the current shop is an improvement |
| `freezeForNothing` | veto | freezing when nothing in the shop is worth keeping |

Each rule has a synthetic test in `AdvisorSanityTests`: a state where the score alone would list the
bad suggestion. Every bookmarked case's advice (the committed golden cases, the advisor's golden
states and the fixture games' late turns) is checked with `AdvisorSanity.violations`.

## Determinism and time

The plan (`AdvisorPlan`) runs fixed passes, each with one seed for all its simulations: stage 0,
stage 1, the refine pass, then the lobby pass. The same request, plan and weights give the same
advice, and so does stopping after the same number of evaluations (what a bookmark records). The
runner's time budget (6 s) stops only between evaluations, and a combat start cancels the advisor
at once, so combat odds never wait for more than one evaluation. The live plan's lobby pass adds
(1 + 3) × up to 6 opponents × 150 simulations, about 1 s with the JIT.

## Tuning the weights

Weights are `AdvisorWeights` (JSON; a file lists only what it changes, the rest keep their
defaults). To see how new weights change the advice on every bookmarked case:

```sh
echo '{"lobby": 0.8, "tierTurnValue": 7}' > /tmp/weights.json
scripts/advisor-tune.sh /tmp/weights.json                      # committed cases (and the fixture games when present)
scripts/advisor-tune.sh /tmp/weights.json --bookmarks ~/Library/Application\ Support/TavernLens/Games
scripts/advisor-tune.sh /tmp/weights.json --out /tmp/report.txt
```

Each case is re-scored with its recorded plan (seed, simulations, passes), exactly as far as it was
scored when shown, under the new weights, and compared with the advice recorded. The report lists
every case, marks the changed ones with their suggestions before and after, and any sanity rule the
new advice breaks. A bookmark keeps the state its advice was for (`FeedbackBookmark.adviceRequest`),
so saved bookmarks replay without their logs.

When a playtest bookmark shows bad advice: export it as a golden case (debug window → Bookmarks →
Export Golden Case…), change the weights or add a sanity rule until the report shows the advice you
wanted without breaking the other cases, then re-record the goldens
(`TAVERN_RECORD_GOLDENS=1 scripts/test.sh`) and commit the new defaults with the case.
