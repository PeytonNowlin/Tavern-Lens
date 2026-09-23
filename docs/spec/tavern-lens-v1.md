# Tavern Lens v1: a native macOS Battlegrounds companion

## Problem Statement

I play Hearthstone Battlegrounds (solo) on a MacBook. The only serious tracker on macOS, HSTracker, doesn't work well for me: features are missing or broken, and its core Battlegrounds pieces depend on closed binaries, memory reading and a paid stats service. During a game I have no reliable way to:
- see what my opponents were playing when I last fought them
- know which build I'm drifting into and which shop cards fit it
- judge my odds in the coming combat
- get sound, explainable advice on what to do with my gold this turn

Hero selection has the same problem: I pick without data on how each hero performs in the current meta.

## Solution

Tavern Lens is a personal, macOS-only companion app that I open manually before playing. It reconstructs the live Battlegrounds game deterministically from Hearthstone's own `Power.log`. Screen reading is used only to fill gaps the log can't cover, such as the lobby's tribes. The app shows a native, translucent overlay on top of Hearthstone:
- **Hero pick:** each offered hero shows current-meta stats, adjusted for the lobby's tribes.
- **Leaderboard:** hovering a portrait shows that opponent's last-seen board, tier, triples and likely build, and the next opponent is highlighted.
- **Shop turn:** the builds I'm leaning into are detected, shop cards that fit them are highlighted, and a live preview estimates my combat odds against the next opponent's last-seen board.
- **Advisor:** a simulation-backed advisor ranks the best actions this turn (buy, sell, level, roll, freeze), with reasons and a confidence level. Suggestions appear as highlights on the board and as a compact ranked list.
- **Combat start:** a panel shows win/tie/loss %, the expected damage, and any lethal risk.

The app never shows information before the game itself has shown it. It never reads game memory, and it never automates or touches the game client or network. A menu-bar item gives status, settings and a debug view. A hotkey lets me bookmark any moment with a note, so problems found during playtests can be reproduced exactly.

## User Stories

### Setup and lifecycle
1. As the player, I want to open Tavern Lens manually from Applications, so that it only runs when I want it.
2. As the player, I want the app to live in the menu bar with no Dock clutter, so that it stays out of my way.
3. As the player, I want the app to check and fix Hearthstone's `log.config` automatically, so that I never have to edit config files.
4. As the player, I want the app to make sure the log size cap is removed, so that logging never stops partway through a game.
5. As the player, I want a clear notice telling me to restart Hearthstone when the app had to change the log config while the game was running, so that I know why nothing is tracked yet.
6. As the player, I want the app to warn me if HSTracker is running, so that it can't delete or rewrite the logs Tavern Lens depends on.
7. As the player, I want the app to detect when Hearthstone launches and quits, so that tracking starts and stops on its own.
8. As the player, I want the app to detect when a Battlegrounds solo game starts and ends, so that the overlay appears only during Battlegrounds.
9. As the player, I want other game modes to be ignored cleanly, so that a constructed game or a Brawl never produces a broken overlay.
10. As the player, I want the menu-bar item to show the current status ("Waiting for Hearthstone", "Tracking game — Turn 6", "Restart Hearthstone required"), so that I can tell at a glance whether things are working.
11. As the player, I want the app to recover when I open it in the middle of a game, so that I don't lose tracking because I launched it late.
12. As the player, I want the app to survive a reconnect or a Hearthstone restart mid-game and keep its history, such as opponent boards already seen, so that a disconnect doesn't wipe my information.
13. As the player, I want to grant Screen Recording and Accessibility permissions once, with a clear explanation of why each helps, so that I understand what the app does on my Mac.
14. As the player, I want the app to keep working, with reduced accuracy, if I deny Screen Recording, so that a missing permission never breaks tracking.

### Game state tracking
15. As the player, I want the app to know my hero, health, armor, gold (current and max), tavern tier, turn number and phase (recruit or combat), so that every other feature has an accurate foundation.
16. As the player, I want the app to know my board (each minion's card, attack, health, golden status and keywords, in order) and my hand, so that build detection, odds and advice use exact data.
17. As the player, I want the app to know Bob's current shop, including frozen cards and tavern spells, so that highlights and advice are about what I can actually buy.
18. As the player, I want the app to track every lobby hero's health, armor, tier, triples and leaderboard place, so that I understand the state of the lobby.
19. As the player, I want the app to know who my next opponent is, so that previews and advice target the right board.
20. As the player, I want the app to capture each opponent's full board at the start of every combat against them, so that I have a last-seen board for everyone I've fought.
21. As the player, I want the app to track Battlegrounds mechanics such as the Deity and its counters, trinkets, quests, tavern-spell buffs, blood gems and the damage cap, so that simulations and advice aren't missing key effects.
22. As the player, I want the app to know opponents' display names once I've fought them, so that I can recognise players on the leaderboard.
23. As the player, I want my final placement recorded correctly at game end, including when I'm eliminated, so that my history is accurate.
24. As the player, I want a concede to be detected and my placement marked as estimated, so that an abandoned game isn't recorded wrongly.
25. As the player, I want the displayed state to stay in sync with the game's animations, never ahead of them, so that the overlay never spoils what's about to happen.

### Lobby tribes
26. As the player, I want the app to read the lobby's tribes from the hero-pick banner, so that tribe-aware stats and advice are exact from turn 0.
27. As the player, I want the app to also infer the tribes from what appears in shops and on opponent boards, so that tribes are still known if screen reading fails.
28. As the player, I want a small warning when the screen reading and the inference disagree, with inference used as the fallback, so that a misread never silently corrupts the data.
29. As the player, I want to see the lobby's tribes on the overlay, with a confidence indicator while they're still being inferred, so that I know which minions can appear.

### Hero pick
30. As the player, I want each offered hero to show average placement, a tier letter (S–E), top-4 % and win %, so that I can pick well.
31. As the player, I want to hover a hero to see its full placement chart, so that I can judge its risk.
32. As the player, I want hero stats adjusted for the lobby's tribes (leaving out tribes that are in every lobby this patch), so that the numbers reflect this lobby.
33. As the player, I want stats from the current meta (the last three days, all players) with an automatic fallback for heroes with little data, so that numbers are both current and reliable.
34. As the player, I want a "stale" badge when the stats data is old, so that I know how much to trust it.
35. As the player, I want skinned heroes to show the base hero's stats, so that skins never show "no data".
36. As the player, I want rerolled hero offers to update the stats immediately, so that the display always matches what's on screen.

### Opponent info
37. As the player, I want to hover an opponent's leaderboard portrait and see their last-seen board, with the turn it was seen, their tier and triples, so that I can scout without guessing.
38. As the player, I want each opponent's likely build shown, detected from their last-seen board, so that I know what they're going for.
39. As the player, I want my next opponent highlighted on the leaderboard, with a compact preview of their last-seen board, so that I can prepare for the fight.
40. As the player, I want opponents I haven't fought yet clearly marked as "not seen", so that missing data isn't mistaken for an empty board.

### Build guidance
41. As the player, I want the app to detect the one or two builds my board and hand are leaning into, so that I get a clear direction.
42. As the player, I want shop cards that fit my detected build highlighted, with core cards styled differently from add-ons, so that I can spot good buys instantly.
43. As the player, I want a short tips card for my detected build (key cards, when to commit, what it needs), so that I can play it properly.
44. As the player, I want build data refreshed automatically from current meta sources, with a bundled fallback and my own override file for tribes the sources don't cover yet, so that guidance stays current, including for new tribes like Aberrations.

### Combat odds
45. As the player, I want win/tie/loss % shown at the start of each combat, so that I know what to expect.
46. As the player, I want expected damage dealt and taken, with a range, so that I understand the stakes.
47. As the player, I want a lethal warning when the coming combat could eliminate me, so that I'm never blindsided.
48. As the player, I want a live odds preview during my shop turn, comparing my current board to the next opponent's last-seen board and updating as I buy, sell and reposition, so that I can test changes before committing.
49. As the player, I want the odds to account for the Deity, trinkets, hero powers, quests and counters, so that they're accurate.
50. As the player, I want odds to appear quickly and refine in place instead of blocking, so that the overlay never feels laggy.

### Advisor
51. As the player, I want the advisor to rank the best 2–3 actions each shop turn (buy, sell, level, roll, freeze, reposition, spend spells), so that I make stronger decisions.
52. As the player, I want each suggestion to carry a one-line reason, such as "+11% vs next opponent" or "completes Undead core", so that I understand and can learn from it.
53. As the player, I want suggested actions highlighted on the actual shop cards, board minions and buttons, with rank badges, so that I can act without reading.
54. As the player, I want a compact ranked list that I can collapse, so that I can get details when I want them.
55. As the player, I want the advisor to weigh this turn's combat, strength against the rest of the lobby, progress toward my build, and economy (gold and levelling timing) one or two turns ahead, so that its advice isn't short-sighted.
56. As the player, I want a confidence level on the advice, and "no strong recommendation" when options are close or data is thin, so that I don't over-trust it.
57. As the player, I want the advisor to update as the shop and board change within the turn, so that advice is always current.
58. As the player, I want the advisor never to click or act for me, so that it stays within Blizzard's rules.

### Overlay behaviour
59. As the player, I want the overlay to sit exactly on Hearthstone's window in native fullscreen on my notched MacBook and in windowed mode, so that highlights line up with the cards.
60. As the player, I want the overlay to follow the window when it moves or resizes and during fullscreen transitions, so that it never drifts.
61. As the player, I want the overlay hidden when Hearthstone isn't the frontmost app, so that it never floats over my desktop.
62. As the player, I want the overlay to be click-through except on its own interactive parts, so that it never blocks my clicks in the game.
63. As the player, I want a minimal always-on display with details on hover, so that the screen stays clean.
64. As the player, I want a global hotkey to hide and show the whole overlay, so that I can clear the screen instantly.
65. As the player, I want a native macOS look (translucent dark panels, SF fonts, high-contrast numbers, colour only where it carries meaning), so that it's readable over a busy board.
66. As the player, I want the app to check once per game that the overlay is aligned with the game, and warn me if a patch moved things, so that misalignment is caught early.

### Feedback and debugging
67. As the player, I want a feedback hotkey (⌃⌥F) that bookmarks the exact moment (game, turn, full state and what the advisor showed) and lets me type a one-line note, so that my playtest reports can be reproduced exactly.
68. As the player, I want a debug window showing the raw reconstructed state and the event log, so that I can compare what the app thinks against the game.
69. As the developer, I want any recorded game to replay into the same timeline of outputs, so that every bug report becomes a regression test.

### Storage and retention
70. As the player, I want a compact permanent record of every game (keyed by game seed), so that history survives log cleanup.
71. As the player, I want old Hearthstone log sessions pruned automatically (keep 10 sessions under 2 GB by default), never touching the active session or games not yet recorded, so that logs don't grow forever.
72. As the player, I want the last 40 games' logs kept compressed for replay and bug reports, so that problems can be investigated later.
73. As the player, I want a hint when the current Power.log gets huge (800 MB or more), so that I know to restart Hearthstone.
74. As the player, I want the card data and art caches bounded (the current game version plus the two before it, and 1 GB of art), so that disk use stays predictable.
75. As the player, I want every retention limit adjustable in settings, so that I control disk use.

### Data freshness
76. As the player, I want card data matched to my exact Hearthstone version and downloaded once per game version, so that card details are always correct.
77. As the player, I want the live minion pool corrected for server-side changes, with a maintained override file and a per-game self-correction when the game shows a card as in the pool, so that removed or rotated minions never pollute guidance.
78. As the player, I want everything to keep working offline from cached data, with stale indicators, so that a network blip never breaks the overlay.
79. As the developer, I want the combat simulator version pinned and upgraded deliberately on patch days, after the golden tests pass, so that unreviewed code never runs.

## Implementation Decisions

- **Platform:** native Swift app for macOS 26 only, Apple Silicon. It's a personal build, signed with "Sign to Run Locally" or a free Apple ID for a stable identity so permissions stick. No sandbox, notarization, Sparkle or App Store. It's a menu-bar app (accessory activation policy) that the player opens manually.
- **Package structure:** a Swift package with separate modules and a thin app target:
  - **HSLog:** discovers the Hearthstone install and the newest `Logs/Hearthstone_*` session folder. It manages `log.config` (only `[Power]` verbose and `[LoadingScreen]`) and `client.config` (`FileSizeLimit.Int=-1`), and reports "restart required". It tails files with DispatchSource plus a backup poll, reads from byte offsets, buffers partial lines and decodes tolerantly. It also handles log retention and pruning. It has no Battlegrounds knowledge.
  - **PowerParser:** turns lines into typed events such as game created, entity full/show/change/hide, tag change, block start/end, game metadata, choices, and spectator start/end. Tags are kept numeric, with names from generated enums, and unknown tags are tolerated. It parses `PowerTaskList` for state, plus `GameState.DebugPrintGame` and the choice lines for metadata and hero-pick options.
  - **EntityStore:** a generic, deterministic reducer of events into entities, tags, zones and controllers. It resets on game creation. It detects a reconnect as a new game created with the same `GAME_SEED` and keeps the history.
  - **BGState:** a pure projection from the entity store to a Battlegrounds snapshot, plus an event-driven history layer: last-seen opponent boards, per-turn records, combat-start snapshots, final placement and concede handling. It encodes the validated rules from the research:
    - Shop vs opponent board is told apart by the bartender slot's combat-player tag.
    - Board queries require the PLAY zone, which excludes preview copies.
    - Minions are tracked by card and position, not entity ID.
    - The lobby is de-duplicated by player ID.
    - The combat snapshot is taken on tag 2022 going 1→0, with the shopping-turn guard.
  - **HSData:**
    - enums generated at build time from HearthstoneJSON's `enums.json`, with an unknown fallback
    - a card DB pinned to the running build, read from the Hearthstone bundle version
    - the minion pool built from the card data, plus HSReplay's live meta-period overrides, plus a maintained override file, plus per-game self-correction from the in-game pool flag
    - an art cache
    - Firestone hero stats (past three days, all players, with fallbacks) and build stats and strategies, fetched on launch and every 6 hours with ETags and cached, with stale detection
  - **BGIntel:**
    - **Tribe resolver:** screen banner reading, with inference from sightings as fallback and cross-check.
    - **Build detector:** matches card sets against build definitions from Firestone data plus the override file.
    - **Shop highlighter.**
    - **Hero-pick stats:** Firestone's approach, with tribe impacts summed and the tribes forced into every lobby left out.
    - **Simulator adapter:** turns a snapshot into the simulator's battle input, using the validated field mapping, including the Deity stats and per-player counters.
    - **Advisor:** generates candidate actions, scores each with simulations plus build, lobby and economy terms over a 1–2 turn horizon, and applies a rule-based sanity layer and confidence estimate.
  - **TavernEngine:** the headless composition root. It takes log lines, screen readings, a clock and data providers, and emits a timeline of overlay view states and game records. Everything except UI and OS integration lives behind it.
  - **App:**
    - Hearthstone process detection (bundle ID `unity.Blizzard Entertainment.Hearthstone`) and window tracking (CGWindowList by PID plus AX for frame and fullscreen)
    - ScreenCaptureKit region capture and Vision text recognition for the hero-pick tribe banner and alignment checks
    - overlay panels, the menu-bar item, settings, the debug window, hotkeys and the feedback bookmark
- **Overlay windows:** `NSPanel`, borderless and non-activating, at level normal+1, joining all Spaces as a fullscreen auxiliary, with `hidesOnDeactivate` off and a clear background. It hides and re-shows on fullscreen transitions and is visible only while Hearthstone (or Tavern Lens) is frontmost. It's click-through by default, with separate small interactive panels or cursor-tracked interactive regions. Content is SwiftUI in `NSHostingView`, using Observation.
- **Layout model:** a pure geometry function from the window content frame to element rects. All sizes scale with window height. Board x positions are relative to a centred 4:3 region; Hearthstone's own interface elements anchor to the window edges. It handles the notch (position from the AX frame, not the screen frame) and the windowed title bar. Constants come from the measured coordinate research, and are versioned so they can be corrected after patches.
- **Combat simulator:** Firestone's MIT `@firestone-hs/simulate-bgs-battle`, bundled with esbuild at a pinned version and run in a dedicated `JSVirtualMachine` and `JSContext` on a background thread. The card DB is loaded once per session. There is a simulation budget per request, and results refine progressively. The embedder calls the simulator's card-data initialisation with the lobby's tribes and anomalies.
- **Timing rule:** display state is derived only from the synced (`PowerTaskList`) stream. The early `GameState` stream is never used for anything displayed, except game metadata and choices.
- **Threading:** log reading, parsing and reducing run on background actors in strict order. Simulation and advice run on their own queue and can be cancelled when state changes. View state is published to the main actor, coalesced per task-list batch and capped at about 10 Hz.
- **Persistence:** a per-game record keyed by `GAME_SEED`, holding per-turn snapshots, opponent boards seen, the result, advisor outputs and feedback bookmarks. It's stored in Application Support. Optionally, compressed per-game log slices are kept as replays.
- **Retention defaults, all configurable:**
  - Hearthstone log sessions: 10 sessions, 2 GB cap
  - replays: 40 games
  - art cache: 1 GB
  - card DBs: the current game version plus the two before it
  - Power.log size hint: 800 MB
  - The active session, and any folder whose games aren't journaled yet, are never deleted.
- **Rules of engagement:** no memory reading. No input automation. No client, network or file modification of Hearthstone beyond its two log config files and pruning its old log folders.
- **Delivery stages:**
  1. log housekeeping, parsing, state, per-game record and debug window
  2. overlay shell and leaderboard opponent info

  Playtesting starts after stages 1 and 2.
  3. tribes, build detection, highlights, tips and hero-pick stats
  4. combat odds (combat start and live preview)
  5. advisor

  Each stage after 2 is playtested before the next.
- **Research reference:** detailed, cited findings behind these decisions live in the repo's research notes: logs, validation, edge cases, simulator mapping, overlay coordinates, minion pool, hero stats and meta. Implementers should read the relevant note before each module.

## Testing Decisions

- **What a good test is:** it tests external behaviour at a seam. A test feeds inputs and asserts outputs a user would see: the timeline of overlay view states, layout rects, or files kept and deleted. It never asserts internal structure, tag handling order or private types. Tests are deterministic, need no network (data providers are stubbed or fixture-backed) and no Hearthstone.
- **Seam 1: headless engine replay (primary; most tests live here).** `TavernEngine` is fed a recorded log, optional screen readings and pinned data fixtures. The emitted timeline is compared to expected golden JSON at chosen checkpoints. Initial golden cases come from the two captured games:
  - **Full game:** game detected as solo Battlegrounds; hero pick shows the 4 offered heroes with the stats join working; next opponent matches the actual combat opponent in all 16 combats; turn 11 combat odds are about a 74% loss with a range covering the actual 10 damage; final placement is 4th, set once at game end.
  - **Truncated game:** it stops mid-game without crashing and the partial record is kept.
  - **Tribe inference:** it resolves the correct 5 tribes by turn 4.
  - **Other scenarios:** reconnect (same seed), concede, mid-game attach, the midnight rollover and non-Battlegrounds games are added as captures arrive, with synthetic fixtures derived from real logs meanwhile.
  - **Feedback bookmarks** from playtests become new golden cases.
- **Seam 2: layout geometry.** A pure function from the window frame and mode to element rects, checked against the measured reference frames:
  - 1710×1073 notched fullscreen
  - 1920×1080
  - 1440×900 windowed
  - 21:9

  Tolerances follow the measurement uncertainty.
- **Seam 3: log housekeeping.** Session discovery, config repair and retention run against a temporary directory tree that mimics the Hearthstone install. Assertions cover: the newest session chosen, configs repaired and "restart required" reported, only journaled and inactive folders pruned, and limits respected.
- **Everything else** is validated by the player's playtests and feedback bookmarks: window tracking, ScreenCaptureKit and Vision capture, panel behaviour and visual design.
- **Prior art:** none in this repo yet (it's greenfield). The research phase's throwaway Python replay and simulator scripts give reference behaviour and expected values for the first golden tests. Private fixture logs contain BattleTags and stay out of git; any committed fixture must be redacted.

## Out of Scope

- Duos-specific UI. Solo only; Duos games may be detected and ignored.
- Constructed, Arena, Mercenaries and other non-Battlegrounds modes.
- A Hearthstone-themed visual style (possible later).
- A tier or minion browser, a session recap screen, rating/MMR tracking, and trinket and quest pick stats.
- Memory reading, input automation, client modification, and network interception or manipulation.
- Distribution to others: notarization, auto-update, App Store, onboarding for other users.
- A backend service of any kind.
- Using the early `GameState` stream for anything displayed.

## Further Notes

- **Log config:** the logging setup has already been proven on this Mac. The default log size cap silently stopped all logging mid-game until `client.config` removed it. `Zone.log` must not be enabled.
- **Log volume:** one full game produces about 36 MB of Power.log and about 270k lines. A naive Python parser replays it in under 1 s, so performance headroom is large.
- **Data sources:** HearthstoneJSON (card data and enums), HSReplay's live meta-period endpoint (pool overrides), Firestone's static stats and strategies (personal, non-commercial use allowed by its terms) and the MIT simulator. Firestone's MIT C# log converter is a porting reference for the simulator input mapping.
- **Patch day** is the main ongoing risk. Unnamed tags (2022, 3533, 3148, 3479) may change, and the pool, coordinates and simulator all need refreshing. There will be a documented patch-day checklist: capture one game, run the golden tests, update the pool overrides, bump the simulator, and re-check alignment.
- **Aberrations** are forced into every lobby until about 2026-10-06. The tribe logic and hero-stat adjustment must handle forced tribes that have an end date.
