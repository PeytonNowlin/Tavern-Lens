# Build 74: independently checked deep-review findings

The supplied `claude advisor deep review/00-SYNTHESIS.md` ranks ten opportunities from
103 reports. This build takes the confirmed patch corrections and bounded source
improvements alongside the captured-game policy-11 fixes. Other opportunities remain
research; report count is not evidence that a recommendation improves gameplay.

## Current patch and combat rules

[Blizzard's 36.6.3 notes](https://hearthstone.blizzard.com/en-gb/news/24303864/36-6-3-patch-notes)
ended forced Aberration lobbies, raised the Deity threshold to four deaths, and made
both Deities Tier 1. The official news API's publication timestamp is
2026-10-01T15:55:00Z; the article's CMS creation timestamp belongs to an earlier date.
Historical lobbies retain their earlier forced-tribe rule. Unknown log dates retain
the existing replay contract.

The pinned MIT simulator 1.1.755 calculates Deity damage from its static card database,
which still resolves to Tier 3. Its unset sigil counter defaults to three. An independently
authored wrapper uses an archived, dated ruleset to select an isolated card service with
Tier-1 Deities and a four-death default. Positive script-data counters remain the observed
remaining deaths. The package and pinned card database remain unchanged. Node tests
exercise both Deities, normal/golden variants, counter values, and interleaved legacy/current
runs; a JavaScriptCore test verifies the bundled damage behavior.

Local build 253216 and the current cached meta-period also miss returning shop cards
and several tier changes. Corrections must be selected by the log's date, not the current
wall clock. The pool-copy table is unchanged: the proposed replacement numbers have
not been verified against shop draws.

## Composition and hero populations

The refreshed Firestone comp feed contains 25 raw rows, including both `abberation_*`
and `aberration_*` spellings. Merge only the two demonstrated aliases, using game-count
weights separately for each MMR population. Merge board-presence counts and denominators
before applying the share floor; deduplicate repeated cards within a board. Existing
sample gates remain in effect. The refreshed recipes contain 18 usable compositions;
blank IDs and demonstrated `#N/A` placeholders are excluded. Recipe weights remain
source metadata. Bundled source URLs, dates, validators and hashes are recorded in
`Sources/HSData/Resources/bg-pool/builds/firestone-sources.json`.

Hero stats use a recent entered/screen rating and a fresh percentile table for the same
window. Embedded tables carry the hero feed's generation date; standalone tables carry
their own Last-Modified date. Never substitute a threshold from another window or renew
the publication date on a 304. Missing or invalid evidence falls back to all-player stats.
The matched top-1% population broadens to top 10% because the observed top-1% hero
samples are sparse. Selection provenance retains the matched population, actual bucket,
window, source and reason. This does not establish a global ladder percentile.

## Card-turn prior and remaining work

Firestone's public client maps raw turn numbers with `ceil(turnNumber / 2)` and looks
up the exact recruit turn. Policy 11 uses only turns 1–3, valid placement values, fresh
source dates, and at least 200 observations in both compared populations. It rewards
only newly purchased minions that remain deployed, with bounded influence. This is a
population association. The current conservative shrinkage remains: the review's
empirical-Bayes estimates depend on assumed variance and filtering, and overlapping
time windows are not an independent validation set.

Public client references:
[turn parser](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/game-state/src/lib/services/real-time-stats/event-parsers/battlegrounds/rtstats-bgs-turn-start-parser.ts),
[shop card stats](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/common/src/lib/minion-stats/bgs-board-stats.service.ts).

Next work needs separate validation: hypergeometric shop odds with verified pool-copy
counts; robust tempo/opponent-growth estimates; typed expert commit gates; additional
economy-tag semantics; and labelled end-board regression profiles. Rich hero/trinket
fields are retained for that work. The perfect-games feed's rows do not themselves prove
first-place outcomes. Public endpoints do not establish reuse terms; no blocked API is
crawled and no gated stats access is assumed.

## Verification

The complete CLT test runner passed 675 tests across 116 suites with private captured
games enabled. The archived policy-10 advice and request fingerprint remained exact.
The simulator wrapper rebuild passed all 11 combat golden checks; the three Node
behavior tests covered Deity variants, observed counters and interleaved rulesets.
No historical advice or combat goldens were re-recorded.
