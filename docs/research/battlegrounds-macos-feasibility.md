# Battlegrounds Companion for macOS: feasibility and architecture

Researched 2026-09-22 against Hearthstone 36.6.0 (build 251952), macOS 26.5, Apple Silicon. This is a personal-use build that will not be distributed.

This is the synthesis. Every claim is cited in one of three detailed notes:

- [logs-and-extractable-state.md](logs-and-extractable-state.md): log config, Power.log grammar, what Battlegrounds state is extractable, and pitfalls
- [ecosystem-and-data-sources.md](ecosystem-and-data-sources.md): HSTracker, HDT/BobsBuddy, Firestone, HearthSim libraries, HearthstoneJSON, and Blizzard policy
- [macos-overlay-and-platform.md](macos-overlay-and-platform.md): overlay windows, window tracking, process detection, log tailing, and signing

## Verdict

**The idea is feasible, and every hard piece has already been proven by someone.**

- Nearly all in-game Battlegrounds state is in `Power.log` in a form we can parse deterministically.
- An overlay over native-fullscreen Hearthstone works on current macOS; HSTracker does it today.
- Combat odds can come later from Firestone's simulator, which is MIT-licensed. We embed it in JavaScriptCore instead of porting it. A spike ran 8k simulations in about 0.3 s.

Nothing in v1 needs memory reading, a backend, or special entitlements.

## Findings

### 1. The logs cover almost everything
- **Enabling the logs:** create `~/Library/Preferences/Blizzard/Hearthstone/log.config` with `[Power]` set to `Verbose=true`, plus `[LoadingScreen]`. The game reads it only at launch. Also write `/Applications/Hearthstone/client.config` with `[Log] FileSizeLimit.Int=-1` to remove the log size cap. Both are now in place on this Mac.
- **Where logs go:** every launch gets a new folder, `/Applications/Hearthstone/Logs/Hearthstone_YYYY_MM_DD_HH_MM_SS/`. We pick the newest one. HSTracker gets the folder from memory reading; we don't need to.
- **Which stream to parse:** use `PowerTaskList.DebugPrintPower` for state; it is in sync with the on-screen animations. `GameState.*` is only for game metadata and choices. `GameState` runs 1–50 s ahead of what is shown, and the lead grows with combat length (the game result appeared 45 s early; see [log-validation-2026-09-22.md](log-validation-2026-09-22.md)), so using it for display would leak the outcome early.
- **Detection:**
  - Start: `CREATE_GAME`
  - Mode: `GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS`. Duos types are 37–41, and `BACON_DUO_TEAM_ID` also marks Duos.
  - End: `STATE=COMPLETE`
  - Placement: `PLAYER_LEADERBOARD_PLACE`
  - Lobby scene: `LoadingScreen currMode=BACON`

| Available from logs | Needs memory reading (out of scope) |
|---|---|
| Hero options and pick, hero and hero powers, HP/armor/damage, gold (incl. cap), tavern tier, triples, turn and phase, own board and hand with full stats and keywords, Bob's shop, freeze, every opponent's hero/HP/tier/placement, next opponent, opponent board **at combat** (keep the last one seen), anomaly, Deity/Dark Gifts, damage cap, quests, trinkets, tavern spells, buddies, Duos teammate identity, opponent display names (without the `#1234` suffix; seen when you fight them) | Available/banned tribes (can be inferred heuristically from shop minions), rating/MMR, full BattleTags of the lobby, Duos teammate's board during recruit, UI hover state |

**Fragile spots:**
- The phase markers are **unnamed numeric tags**: 2022 (combat start), 3533 (combat setup, toggles in solo too), 3148 (gold cap) and 3479 (concede).
- Entity IDs are **re-created every shop refresh and every combat**.
- The bartender and the current opponent share one Player slot.
- Timestamps have no date.
- The logs are big: one full game produced a 35.8 MB Power.log, with late turns adding 4–5.7 MB each.
- Parser traps confirmed on real logs (nested brackets in entity names, stale `zone`/`player` fields in entity brackets, flat indentation in PowerTaskList, opponent preview copies under the local player): see [log-validation-2026-09-22.md](log-validation-2026-09-22.md). Throwaway Python replay scripts are in `validation-scripts/`.
- A reconnect re-sends the whole game state.

### 2. What to reuse

| Need | Use | How |
|---|---|---|
| Parser semantics, entity model, window tracking, overlay pattern | HSTracker (MIT, Swift, active) | Port the ideas and code selectively; don't fork it. It is huge and coupled to globals |
| Reference parser and test fixtures | python-hslog, hsreplay-test-data | Reference / test data |
| GameTag and other enums | `api.hearthstonejson.com/v1/enums.json` (from python-hearthstone) | Generate Swift from it, with an `unknown(Int)` fallback |
| Card data | HearthstoneJSON `v1/<build>/enUS/cards.json`, pinned to the running build (read from Hearthstone.app `CFBundleVersion`) | Download once per build and cache in Application Support |
| Art | `art.hearthstonejson.com` (`/v1/bgs/latest/…` BG renders, `/v1/tiles/…`) | Fetch lazily and cache on disk |
| Combat simulator (later) | `@firestone-hs/simulate-bgs-battle` (MIT, npm, about 830 cards) | esbuild bundle, run in `JSContext` |
| Meta and comp stats (later, optional) | Firestone static endpoints | Their ToS allows personal, non-commercial use, which fits this build |
| Avoid | HearthMirror (closed, memory reading), BobsBuddy (proprietary), HDT code (All Rights Reserved), Blizzard Game Data API (server-side secret), network or client mods (EULA §1.C.ii) | — |

### 3. The macOS platform
- **Detecting the game:** the bundle ID is `unity.Blizzard Entertainment.Hearthstone`, and the game runs arm64-native. Use NSWorkspace notifications for launch, terminate, activate, deactivate and Space changes.
- **Hearthstone's window:**
  - It uses **native fullscreen** on its own Space.
  - On notched Macs its frame starts 34 pt below the top of the screen, so position from the measured window frame.
  - `CGWindowListCopyWindowInfo` gives its bounds **without Screen Recording**; pick the largest layer-0 window owned by the Hearthstone PID.
  - Accessibility (`AXFullScreen`, AXObserver move/resize) makes tracking more accurate. Grant it once; it's optional.
- **Overlay window:**
  - `NSPanel`, `[.borderless, .nonactivatingPanel]`, level `.normal + 1`
  - `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  - `hidesOnDeactivate = false`, clear background
  - Hide and re-show it on fullscreen transitions. Show it only while Hearthstone or our app is frontmost.
- **Click-through:** `ignoresMouseEvents` is per window. v1 uses one click-through panel plus small interactive panels. HSTracker's cursor-tracking trick can come later if needed.
- **Layout:** work in points. Scale by `height / 1080`, and place board-relative elements inside the centred 4:3 board region.
- **Tailing the logs:** use a DispatchSource on `Logs/` for new session folders, and a DispatchSource on `Power.log` (`.extend/.write/.delete/.rename`) plus a backup poll of about 250 ms. Read from a byte offset and buffer partial lines. Decode as UTF-8 and tolerate garbage bytes.
- **Signing:** for personal use, a local Xcode build signed with your own Apple ID is enough. There is no sandbox, notarization or Sparkle to deal with. JavaScriptCore JIT isn't an issue without hardened runtime.
- **Stack:** AppKit window shell plus SwiftUI content via `NSHostingView`. `@Observable` means targeting macOS 14 or later; macOS 15 or 26 only is fine for personal use.

## Recommended architecture

A Swift package with separate modules and a thin app target. State is **event-sourced**: live state is a pure fold over parsed log events, so any saved log replays to the same state. That makes recorded logs our test suite.

```
HSLog  ──lines──▶  PowerParser  ──PowerEvent──▶  EntityStore  ──▶  BGState (projection)  ──snapshot──▶  Overlay UI
(discover,          (tokenise,                    (generic          (hero, gold, tier,              (AppKit panels +
 tail, config)       typed events)                 entities/tags)    board, lobby, phase)             SwiftUI)
                                                        ▲                     │
                                         HSData ────────┘                     └──▶ BGIntel (later: sim via JSC,
                                   (enums codegen, card DB,                          comps, board strength)
                                    art cache, build pinning)
```

| Module | Responsibility | Knows about BG? | Depends on |
|---|---|---|---|
| `HSLog` | Find the session folder, write log.config/client.config, tail files, split lines, filter by prefix | No | Foundation |
| `PowerParser` | Turn lines into `PowerEvent` (`createGame`, `fullEntity`, `showEntity`, `tagChange`, `blockStart/End`, `gameMeta`, `choices`, …). Keep tags numeric, with names from HSData | No | HSLog, generated enums |
| `EntityStore` | Deterministic reducer: `(Store, PowerEvent) -> Store`; entities, tags, zones, controllers; resets on `CREATE_GAME` | No | PowerParser |
| `BGState` | Pure projection `EntityStore -> BattlegroundsSnapshot`, plus a small event-driven layer for history (last-seen opponent boards, per-turn log, combat start signal) | **Yes** | EntityStore, HSData |
| `HSData` | Enums codegen, card DB keyed by CardID/dbfId, build detection, art cache | Some fields | Foundation |
| `BGIntel` | Later: JSContext simulator adapter (`BattlegroundsSnapshot -> BgsBattleInfo`), comp detection, recommendations | Yes | BGState, HSData |
| `App` | Hearthstone process and window tracking, overlay panels, settings window, menu-bar item | Uses snapshots only | All |

**Threading:** log reading and parsing run on a background actor. The store is applied in order on one actor. Snapshots go to the main actor, coalesced at one per `PowerTaskList` batch, capped at about 10 Hz.

**Testing:** the golden-file test is: given a `Power.log`, the final and per-turn snapshots must equal the expected JSON. Seed it with your own captured games and python-hslog's Battlegrounds fixtures.

## Storage and log retention (requirement)

With the size cap lifted, one game writes 35 MB or more to `Power.log`, and Hearthstone makes a new `Logs/Hearthstone_*` folder on every launch. Nobody documents whether it prunes old folders ([log-edge-cases.md §8](log-edge-cases.md)), so the app has to handle retention itself. The design:

1. **A per-game journal is the permanent record, not the raw logs.** When a game ends, write a compact record keyed by `GAME_SEED`: the per-turn snapshots, the opponent boards seen, the result, and card IDs only. Raw logs are then disposable.
2. **Prune Hearthstone's old session folders** under `/Applications/Hearthstone/Logs/`:
   - Never touch the active session, meaning the newest folder or any folder a Hearthstone process has files open in (`proc_listpidspath`, as HSTracker does).
   - Only prune folders whose games are already journaled.
   - Policy (configurable): keep the last **N sessions (default 10)** and stay under a **size cap (default 2 GB)**; delete the oldest first.
   - Run it at app launch and after each game end. Log what was deleted.
3. **Keep raw logs on request.** Before pruning, optionally save a game's own slice of the log (`CREATE_GAME` → `STATE=COMPLETE`), zstd- or gzip-compressed, to `~/Library/Application Support/<app>/replays/`. That's for bug repro and test fixtures, and has its own cap, for example the last 40 games. Text logs compress about 10×.
4. **One session can still grow large.** If Hearthstone stays open for many games, its current `Power.log` keeps growing. We can't safely truncate a file Hearthstone has open, so we just read it incrementally and show a hint in the menu bar ("Power.log is 800 MB; restart Hearthstone to rotate") past a threshold.
5. **Our own caches are bounded too.** Keep card DBs for the current build and the two previous; keep the art cache as an LRU with a cap (default 1 GB). The journal is small, a few KB to tens of KB per game, but offer "delete history older than…".

The retention settings (sessions to keep, size caps, whether to keep compressed replays) go in the app's settings window.

## v1 scope (proof of reliability)
1. Enable logging (log.config and client.config) and detect Hearthstone launch and quit, plus Battlegrounds game start and end, including Duos.
2. Tail and parse Power.log live, and also replay from a file for tests.
3. Snapshot:
   - hero, HP+armor, gold/max, tier, turn, phase
   - own board (stats, golden, keywords)
   - shop
   - lobby list (hero, HP, tier, placement, next opponent)
   - last-seen board for each opponent
4. Overlay: a leaderboard-side panel (last-seen board on hover or a toggle) and a small HUD with turn, phase and next opponent. A separate debug window shows the raw snapshot.
5. Card DB pinned to the build from HearthstoneJSON, cached locally.
6. Per-game journal keyed by `GAME_SEED`, plus pruning of old Hearthstone log folders with a configurable retention policy (see Storage and log retention).

**Later:** combat odds (Firestone via JSC), inferred tribes, comp detection, board-strength heuristics, session history and recommendations.

## Risks
- **Patches renumber or change unnamed tags.** Keep tag handling data-driven and keep a live log capture for every patch.
- **Reconnects and mid-game attach.** Rebuild from the full-state `CREATE_GAME`; replay from the last `CREATE_GAME` when the app starts mid-game.
- **Simulator input fidelity.** Enchantments, counters and hero-power state are the hard part. Firestone's log-to-board parser is MIT-licensed (`Zero-to-Heroes/hs-game-converter-csharp-port`) and can be ported, but it stops at patch 35.0. The mapping was checked on two real combats and both predictions matched the actual result; see [simulator-input-mapping.md](simulator-input-mapping.md). Deity stats (tags 4914/4915) are critical: dropping them flips a 74% loss into a 78% win.
- **Blizzard policy.** Reading logs is tolerated. We stay log-only and never automate or touch the client or network.

## Observed on this Mac: logging stops when the size limit is hit

During the first captured match (session `Hearthstone_2026_09_22_20_33_28`), **every log file stopped growing at 20:41:03 while the game was still going**. That includes Power.log (5.9 MB), Zone.log (10.25 MB) and Hearthstone.log. At that moment Zone.log was at about 10,000 KB, which points to the client's default `FileSizeLimit` of about 10 MB. It looks like once Zone.log reached the cap, all logging stopped. This is inferred from file sizes, not confirmed in Blizzard's docs.

Consequences:
- **`client.config` with `FileSizeLimit.Int=-1` is mandatory, not optional.**
- **Don't enable `Zone` or `Gameplay`.** They are noisy and unused.

log.config is now just `[Power]` and `[LoadingScreen]`; the old file is backed up as `log.config.bak`. `client.config` has been written. Both take effect on the next Hearthstone launch.

**Confirmed with a second game.** Session `Hearthstone_2026_09_22_21_08_40` ran with the new config and was captured in full: `GT_BATTLEGROUNDS`, 12 BG turns, `STATE=COMPLETE`, final place 4th. **That one game produced a 35.8 MB Power.log with about 270k lines.** So the parser must be incremental and filter by prefix, and replaying a whole session has to handle files of 50 MB or more.

Copies of both sessions are kept in `fixtures/private-logs/` as test fixtures. They contain BattleTags, so keep them out of git.

## Next step
Validate against your own captured match. That means confirming the v1 snapshot fields end to end on your `Power.log`: game detection, hero, gold, tier, board, lobby, opponent boards and the phase markers.
