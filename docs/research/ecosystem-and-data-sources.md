# Open-source ecosystem for a native macOS Hearthstone Battlegrounds companion (Swift)

Researched 2026-09-22. Sources are primary: GitHub repos (via `gh api`), shallow clones, npm registry metadata, the vendors' own docs. Commit dates come from the GitHub API on the research date. Local evidence lives in `scratchpad/eco/` (HSTracker clone, Firestone clone, npm tarballs, and a JavaScriptCore spike).

---

## 0. TL;DR

- **HSTracker is not abandoned, and it already covers most of Battlegrounds on macOS.** HearthSim/HSTracker is MIT-licensed, written in Swift, and got a release (3.6.12) on 2026-09-22. It ships Bob's Buddy combat odds, hero/trinket/quest pick stats (Tier7), a session recap, a minion browser, comp guides and more. On features alone the macOS gap is small. The gap is in openness and independence: its two BG workhorses, **BobsBuddy** and **HearthMirror**, are closed-source binaries. Tier7 stats are a paid HSReplay service.
- **BobsBuddy is not open source.** It is a .NET Standard 2.0 DLL marked "Copyright HearthSim 2023", downloaded from `libs.hearthsim.net`. HSTracker runs it by embedding the Mono runtime. A new app cannot legally redistribute it without permission.
- **Firestone's combat simulator can be reused.** `@firestone-hs/simulate-bgs-battle` is on npm under the **MIT** license. It was updated on 2026-09-22, has 751 published versions, and implements about 830 cards. **I bundled it with esbuild and ran it in macOS's JavaScriptCore: 8,000 simulations in about 0.3 s**, with only a two-line `process`/`performance` shim. Embedding it via JavaScriptCore is feasible and much cheaper than porting.
- **Card data comes from HearthstoneJSON** (CC0 wrapper, Blizzard-copyright data; build-versioned URLs) or from hsdata's `CardDefs.Bacon.xml`. **Enum values come from python-hearthstone `enums.py`.** It is also published as `api.hearthstonejson.com/v1/enums.json`, which suits Swift codegen.
- **Blizzard's official API is a poor fit.** It needs an OAuth client secret, which cannot ship in a desktop binary. Its ToS bans paid or premium features, bans Blizzard trademarks in the app's title, and allows at most 30-day data retention.
- **Policy:** log reading has long been tolerated ("any app that duplicates what you can do with a pencil and paper already is fine", Ben Brode, 2014). The EULA prohibits "any unauthorized process or software that intercepts, collects, reads, or 'mines' information", with a carve-out that Blizzard "may... allow the use of certain third-party user interfaces". Memory reading (HearthMirror) is therefore grey. Automation, injection (HsMod/BepInEx) and network-disconnect "reconnect" tricks are the risky tier.

---

## 1. HSTracker (HearthSim/HSTracker)

| Fact | Value | Source |
|---|---|---|
| Language | Swift (1,877 `.swift` files; 147 import SwiftUI; 26 `.xib`) | clone of https://github.com/HearthSim/HSTracker |
| License | MIT ("Copyright (c) HearthSim / Copyright (c) 2015-2017 Benjamin Michotte") | https://github.com/HearthSim/HSTracker/blob/master/LICENSE |
| Last commit / release | 2026-09-22 "Version 3.6.12"; 3.6.11 on 2026-09-17 | https://github.com/HearthSim/HSTracker/releases |
| Deployment target | macOS 10.15, Swift 5 | `HSTracker.xcodeproj/project.pbxproj` |
| Stars | 1,257 | GitHub API |
| Status | **Actively maintained**, near-daily commits in Sept 2026 (e.g. Deity/Aberration support for patch 36.6) | https://github.com/HearthSim/HSTracker/commits/master |

### Architecture (from the source tree)
- **Log reading**: `HSTracker/Logging/LogReaderManager.swift` and `LogReader.swift` tail `Power.log`, `Rachelle`, `Arena` and `LoadingScreen` logs, polling every 0.05 s. The Power reader filters on `PowerTaskList.DebugPrintPower`, `GameState.` and `PowerProcessor.EndCurrentTaskList`. HSTracker writes `~/Library/Preferences/Blizzard/Hearthstone/log.config` itself (`LogLevel=1`, `FilePrinting=true`, `Verbose=true` for Power) in `CoreManager.swift` and `LogLineZone.swift`. The per-session log directory is obtained through HearthMirror (`mirror.getLogSessionDir()`, `HearthMirror/MirrorHelper.swift`). The user-configured Hearthstone path is the fallback (`Core/Settings.swift`).
- **Parsers and game state**: `Logging/Parsers/PowerGameStateParser.swift`, `TagChangeHandler.swift`, `TagChangeActions.swift`; `Logging/Game.swift`, `Entity.swift`, `Player.swift`.
- **Enums**: `Logging/Enums/*.swift` (GameTag, Race, CardType, SpellSchool, Zone, Step, ...). These are **hand-maintained**: `GameTag.swift` is 556 lines, while `enums.py` is 2,945 lines.
- **Card DB**: build phases download `CardDefs.xml`, **`CardDefs.Bacon.xml`** (Battlegrounds) and `CardDefs.Lettuce.xml` from `github.com/HearthSim/hsdata/raw/<build>/`, pinned by `HSTracker/cards-version.txt` (`251952`). A build-time tool, `Tools/CardDefsCompiler/main.swift`, transcodes them into a binary blob (`Database/CardDefsBinary.swift`). A comment warns that without Bacon.xml, "BG hero and minion entities then resolve to dbfId 0". `scripts/cards_download.sh` also fetches `api.hearthstonejson.com/v1/latest/<lang>/cards.json` for 14 locales.
- **Memory reading**: `HearthMirror.framework` is a closed binary downloaded from `https://libs.hearthsim.net/hstracker/<sha1>/HearthMirror.framework.zip`, pinned by `HearthMirror-version.txt`. The HearthSim/HearthMirror repo returns 404, so it is private. The API surface (`MirrorHelper.swift`) includes `getBattlegroundsLobbyInfo`, `getBattlegroundsLeaderboardHoveredEntityId`, `getBattlegroundsRatingInfo`, `getBattlegroundsTeammateBoardState`, `getAvailableBattlegroundsRaces`, `getSelectedBattlegroundsGameMode`, `getSpecialShopChoiceState` and more. It relies on `acquireTaskportRight()` and entitlements `com.apple.security.cs.debugger`, `disable-library-validation`, `allow-jit`, `allow-dyld-environment-variables` (`HSTracker.entitlements`). The app is not sandboxed.
- **"HearthWatcher"** polls HearthMirror for BG state (`BaconWatcher`, `BattlegroundsLeaderboardWatcher`, `BattlegroundsLobbyInfoWatcher`, `BattlegroundsTeammateBoardStateWatcher`, `ChoicesWatcher`, ...).
- **BobsBuddy integration**: `HSTracker/BobsBuddy/BobsBuddyInvoker.swift` plus about 50 Swift proxy classes in `HSTracker/Mono/*.swift`. These cover MinionProxy, TrinketProxy, AnomalyProxy, SimulatorProxy and others, and they drive the .NET object model through the Mono embedding API (`mono_field_get_value_object`, ...). Build phases download `Microsoft.NETCore.App.Runtime.Mono.osx-x64/arm64` (version `8.0.29`, `mono-version.txt`) from nuget.org, `lipo` the two into a universal binary, and download `https://libs.hearthsim.net/hdt/BobsBuddy.zip` and `HearthDb.zip`.
- **BG UI** (`HSTracker/UIs/Battlegrounds/`): BobsBuddy panel, Composition popularity, Guides (Anomalies, Comps, Heroes, Minions, Quests, Trinkets), HeroPicking, Inspiration, MinionPinning, Notifications, QuestPicking, **Session** (session recap / last games / final board tooltip), **Tier7** (HSReplay premium pre-lobby and trial), TrinketPicking, `BattlegroundsTierTriplesView`, `BattlegroundsTurnCounterView`, and opponent-dead-for.
- **SPM dependencies** (pbxproj): Sparkle ≥2.6.4, realm-cocoa (RealmSwift) ≥10.32.3, sentry-cocoa ≥8.38, mixpanel-swift, PromiseKit 6, OAuthSwift 2, fmdb, GzipSwift, BigInt, swift-atomics, sindresorhus/Preferences, SwiftyBeaver, TextAttributes, CustomToolTip, AppMover. Binary deps: HearthMirror.framework, Mono (`libmonosgen-2.0`, `libcoreclr`), and optionally `kotlin_hslog.framework`, built from HearthSim/Arcane-Tracker (`scripts/compile_hslog.sh`).

### How HSTracker builds overlays on macOS
- **Finding the HS window**: `Core/SizeHelper.swift` calls `CGWindowListCopyWindowInfo(.excludeDesktopElements)` and filters by owner name, `kCGWindowLayer == 0` and on-screen, taking the largest window. It then asks the Accessibility API (`AXUIElementCreateApplication(pid)`, `kAXFocusedWindowAttribute`, `kAXPositionAttribute`/`kAXSizeAttribute`, `"AXFullScreen"`) for the real frame, because "kCGWindowBounds can return a stale Mission Control thumbnail rect". Without the AX permission it falls back to the CG bounds, treating a frame that equals a screen frame as fullscreen. It flips Y against `NSScreen.screens.first`. The base design resolution is 1440×922.
- **HS process**: `NSWorkspace.shared.runningApplications` with bundle id `unity.Blizzard Entertainment.Hearthstone` (`CoreManager.swift`). It listens for `activeSpaceDidChangeNotification` and `didActivateApplicationNotification`.
- **Window level**: `UIs/Trackers/WindowManager.swift` sets overlays to `CGWindowLevelForKey(.normalWindow) + 1`, "just above Hearthstone (normal level) but below any system UI level". The style mask is `.borderless, .nonactivatingPanel`. Fullscreen uses `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, behind the setting `Settings.canJoinFullscreen`. Tooltips use `.floating + 1`.
- **Click-through**: in 3.6.x, `UIs/Overlay/Root/RootOverlayWindow.swift` hosts a single SwiftUI `NSHostingView` spanning the HS client area with `ignoresMouseEvents = true`. Global and local `NSEvent` mouse-moved monitors toggle `ignoresMouseEvents` only while the cursor is over a child that has reported itself interactive through a SwiftUI preference key. This pattern is directly reusable.

### What is reusable from HSTracker (MIT)
- **Port or copy with attribution**: the LogReader and Power parser, the Entity/Game model, `SizeHelper` window tracking, the overlay window pattern, `CardDefsCompiler`, and the BG view models (for logic reference).
- **Do not depend on**: HearthMirror (closed, private), BobsBuddy and the Mono proxies (closed simulator), and HSReplay/Tier7 APIs (commercial service).
- **Caveat**: the codebase is large, AppKit/SwiftUI hybrid, and tightly coupled to globals (`Settings`, `CoreManager`). Extracting modules takes real work, but the licence allows it.

---

## 2. Hearthstone Deck Tracker (HDT) and BobsBuddy

| Fact | Value | Source |
|---|---|---|
| HDT language | C# / WPF (Windows) | https://github.com/HearthSim/Hearthstone-Deck-Tracker |
| HDT license | **"Copyright © HearthSim. All Rights Reserved."**: source-available, **not open source**; GitHub reports no SPDX license | README "License" section, https://github.com/HearthSim/Hearthstone-Deck-Tracker#license |
| Last commit | 2026-09-22 (v1.58.1) | GitHub API |
| BobsBuddy source | **Not public.** `HearthSim/BobsBuddy` → 404. HDT references `..\lib\BobsBuddy.dll` (csproj) | https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/master/Hearthstone%20Deck%20Tracker/Hearthstone%20Deck%20Tracker.csproj |
| BobsBuddy binary | `https://libs.hearthsim.net/hdt/BobsBuddy.zip` (last-modified 2026-09-22) contains `BobsBuddy.dll` (1.6 MB) and `BobsBuddy.Common.dll`. Assembly metadata: `.NETStandard,Version=v2.0`, `LegalCopyright: Copyright HearthSim 2023` | local inspection in `scratchpad/eco/bb/` |
| Users asking where the source is | Issue #4063; no maintainer answer on the page | https://github.com/HearthSim/Hearthstone-Deck-Tracker/issues/4063 |

**HDT BG code structure** (repo tree):
- `Hearthstone Deck Tracker/BobsBuddy/`: `BobsBuddyInvoker.cs`, `BobsBuddyUtils.cs`, `CombatResult.cs`, `LethalResult.cs`, `MinionHeroPowerTrigger.cs`. HSTracker's `HSTracker/BobsBuddy/*.swift` mirrors these one-for-one.
- `Hearthstone/`: `BattlegroundsBoardState.cs`, `BattlegroundsDb.cs`, `BattlegroundsDuosBoardState.cs`, `BattlegroundsHeroPickState.cs`, `BattlegroundsTrinketPickState.cs`, `BattlegroundsDeityState.cs`, `BattlegroundsUtils.cs`.
- `HearthWatcher/`: `BattlegroundsLeaderboardWatcher`, `BattlegroundsLobbyInfoWatcher`, `BattlegroundsTeammateBoardStateWatcher`, backed by memory providers.
- `Controls/Overlay/Battlegrounds/`, `BobsBuddyPanel.xaml.cs`, `Windows/BattlegroundsSessionWindow.xaml.cs`, `Utility/Battlegrounds/BattlegroundsLastGames.cs`, `BattlegroundsDbSingleton.cs`.

**Can Swift use BobsBuddy?** Technically yes; HSTracker proves it with an embedded Mono runtime (about 50 hand-written proxy classes, JIT entitlements, around 100 MB of runtime). Legally, the DLL has no licence grant, so redistributing it in a third-party app needs HearthSim's permission. **Treat it as "reference only"** and use Firestone's MIT simulator instead.

---

## 3. Firestone (Zero-to-Heroes)

| Fact | Value | Source |
|---|---|---|
| App repo | Zero-to-Heroes/firestone, TypeScript/Angular, Nx monorepo | https://github.com/Zero-to-Heroes/firestone |
| App license | **None declared** (no LICENSE file; GitHub SPDX none). Default copyright applies, so treat as all rights reserved. `electron-builder.yml`: "Copyright © 2024 Sébastien Tromp"; `tos.md` limits use to "personal, non-commercial use" | repo root, https://github.com/Zero-to-Heroes/firestone/blob/master/tos.md |
| App master last commit | 2026-02-08 (release 16.12.8). The repo was pushed 2026-09-09 on other branches (many `copilot/*`) | GitHub API |
| Platform | Overwolf (Windows). An `ow-electron` port exists (`apps/electron-app`, `electron-builder.yml`), but its only target is `win: nsis x64` | `electron-builder.yml` |
| **Simulator package** | **`@firestone-hs/simulate-bgs-battle` 1.1.755, published 2026-09-22, `license: "MIT"`, 751 versions, only dependency `@firestone-hs/reference-data`** | https://www.npmjs.com/package/@firestone-hs/simulate-bgs-battle, registry JSON |
| Simulator source | Not on GitHub (`repository: {}`; `Zero-to-Heroes/bgs-simulator` → 404). **The npm tarball ships `.js`, `.d.ts` and `.js.map` with `sourcesContent`**, so the full TypeScript source can be recovered. No LICENSE file is in the tarball; the MIT claim is only the `package.json` field | local `scratchpad/eco/npm/package/` |
| Coverage | 827 card implementation JS files under `dist/cards/impl/` (minion ≈590, trinket ≈98, plus anomaly, bg-spell, enchantments, hero-power, quest-reward, secret), Duos teammate boards, anomalies, trinkets, quests, damage cap, seeded RNG | package contents |
| API | `simulateBattle(input: BgsBattleInfo, cards: AllCardsService, cardsData: CardsData): Generator<SimulationResult>`; `simulateSingleCombat(...)`; options `numberOfSimulations`, `maxAcceptableDuration`, `includeOutcomeSamples`, `damageConfidence`, `applyDamageCap` | `dist/simulate-bgs-battle.d.ts`, `bgs-battle-options.d.ts` |
| Also deployed as | AWS Lambda (`sam deploy ... SimulateBgsBattleStack` in package scripts) | package.json |
| `@firestone-hs/reference-data` | 3.0.211, 2026-09-22, MIT. TS enums (GameTag, Race, CardIds) plus `AllCardsService` with mirrors `https://static.zerotoheroes.com/data/cards` and `https://static.firestoneapp.com/data/cards` | npm, `dist/services/all-cards.service.js` |
| Reference-data repo | Zero-to-Heroes/hs-reference-data, last commit 2026-09-22 ("update enums for 251952"; "add ABERRATION to valid BG races"). No SPDX on GitHub; MIT on npm | https://github.com/Zero-to-Heroes/hs-reference-data |

### JavaScriptCore spike (done during this research)
- Bundled `@firestone-hs/simulate-bgs-battle` and its dependencies with `esbuild --bundle --format=iife --platform=neutral`. The result is a single 4.9 MB `bundle.js` (`scratchpad/eco/npm/spike/`).
- Ran it in the system `jsc` shell (`/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc`). The only shims needed were `var process={env:{}}`, `performance.now` and a no-op `console`.
- Loaded Firestone's card JSON (`https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json`, 41.9 MB uncompressed) through `AllCardsService.initializeCardsDbFromCards()`, with no network access from JavaScript.
- **Result: 8,000 simulations of a small board in about 265–300 ms**, including the card DB load, with output `{"won":100,"tied":0,"lost":0,"avgDmgWon":3.5}`. That was comparable to or faster than Node (338 ms) on the same machine.
- **Implications**:
  1. Embedding with `JSContext` from Swift is viable.
  2. Keep the card DB loaded once per game.
  3. Run it on a background thread with its own `JSVirtualMachine`.
  4. A hardened-runtime app probably needs `com.apple.security.cs.allow-jit` for JSC's JIT. HSTracker already sets it. Verify in the app target.
  5. The hard part is not running the simulator. It is **building a correct `BgsBattleInfo` from Power.log** (entity tags, enchantments, `scriptDataNum*`, hero power state, trinkets, quest rewards). Firestone's own board-state builder is in the unlicensed app repo, so it is reference only.
  6. Port vs. embed: porting about 830 card implementations to Swift and keeping pace with Firestone's roughly daily releases is a large permanent cost. Embedding lets you pin and upgrade versions from npm.

### Firestone reference and BG meta data (static endpoints found in source; all responded 200 today)
- Cards: `https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json`, a superset of HSJSON with Firestone-specific fields. Card art: `https://static.zerotoheroes.com/hearthstone/cardart/256x/<id>.jpg`. Renders: `https://static.firestoneapp.com/cards/...`.
- BG comps and archetype stats: `https://static.zerotoheroes.com/api/bgs/comp-stats/<timePeriod>/overview-from-hourly.gz.json`. Keys include `compStats[]`, with `archetype` (e.g. `pirate_discover`), `averagePlacement`, `averagePlacementAtMmr` and `placementDistribution`.
- Comp strategies (curated): `https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json`, plus `bgs-hero-strategies`, `bgs-trinket-strategies`.
- Hero, card, quest and trinket stats: `.../api/bgs/hero-stats/<mmr>/<time>/overview-from-hourly.gz.json`, `card-stats`, `quest-stats`, `trinket-stats`, `anomalies-list.gz.json`, `leaderboards/global.gz.json`, plus Duos variants.
- **Terms**: these are undocumented endpoints behind Zero to Heroes' ToS ("personal, non-commercial use"; no automated high-rate access). Using them in a third-party app needs permission from Sébastien Tromp or Zero to Heroes. **Reference only unless you get a written OK.**

---

## 4. HearthSim libraries and canonical enums

| Library | Lang | License | Last commit | Role | Source |
|---|---|---|---|---|---|
| python-hearthstone | Python | MIT | 2026-09-15 "feat: update enums for 36.6.0" (v9.21.0) | **Canonical `enums.py`** (42 enum classes; GameTag and others; 221 `BACON*` entries), CardXML/DBF loaders, deckstrings | https://github.com/HearthSim/python-hearthstone/blob/master/hearthstone/enums.py |
| python-hslog | Python | MIT | 2026-08-15 | Reference Power.log parser (packet tree, exporters) | https://github.com/HearthSim/python-hslog |
| hsdata | XML | none declared (extracted game data, © Blizzard) | 2026-09-15 "Update to patch 36.6.0.251952" | `CardDefs.xml` (69 MB), **`CardDefs.Bacon.xml`** (15.8 MB, BG), `CardDefs.Lettuce.xml`, `BountyDefs.xml`, `MercenaryDefs.xml`, `RaceTagMap.xml`, `Strings/`. Tagged per build | https://github.com/HearthSim/hsdata |
| HearthDb | C# | MIT | 2026-09-16 v36.6.0 | .NET card DB. `HearthDb.EnumsGenerator` downloads **`https://api.hearthstonejson.com/v1/enums.cs`** and emits `Enums.cs` ("GENERATED ... DO NOT EDIT") | https://github.com/HearthSim/HearthDb/blob/master/HearthDb.EnumsGenerator/Program.cs |
| hearthstonejson-client | TS | ISC | 2026-08-13 | JS client for HSJSON | https://github.com/HearthSim/hearthstonejson-client |
| UnityPack | Python | MIT | **2022-01-06 (stale)** | Unity asset extraction; not needed for a companion | https://github.com/HearthSim/UnityPack |
| Arcane-Tracker / kotlin-hslog | Kotlin | (check) | — | Optional hslog framework used by an HSTracker script | `scripts/compile_hslog.sh` |

**Canonical source for GameTag/enum values**: `python-hearthstone/hearthstone/enums.py`. It gets updated on every patch, usually within a day or two; hsdata 36.6.0 landed 2026-09-15 and enums the same day. HearthstoneJSON republishes it as **`https://api.hearthstonejson.com/v1/enums.json`** (last-modified 2026-09-16; 40 enum groups; `GameTag` has 1,325 entries) and as `enums.cs`, which HearthDb consumes.

**Keeping Swift enums current (recommendation)**: add a small codegen step, either a Swift Package plugin or a `swift run` script. It fetches `v1/enums.json` for a pinned build, or parses `enums.py`, and emits `enum GameTag: Int, CaseIterable, Codable` and so on, with an `unknown(Int)` fallback so new tags never crash the parser. HSTracker's changelog notes it previously "quit when Hearthstone adds a screen, minion type... it does not know about yet". Pin the build number alongside `cards-version`, as HSTracker does with `cards-version.txt`.

---

## 5. Card data: HearthstoneJSON vs Blizzard Game Data API

### HearthstoneJSON (https://hearthstonejson.com)
- **Endpoints** (verified 200 today):
  - `https://api.hearthstonejson.com/v1/latest/enUS/cards.json` (9.9 MB, 36,022 cards; last-modified 2026-09-16)
  - `.../v1/latest/enUS/cards.collectible.json`
  - `.../v1/latest/all/cards.json` (all locales)
  - **build-pinned**: `.../v1/251952/enUS/cards.json`
  - `.../v1/enums.json`
  - The directory listing at `https://api.hearthstonejson.com/v1/` shows the builds.
  - Docs: https://hearthstonejson.com/docs/cards.html
- **BG-relevant fields present in today's data**:
  - `set: "BATTLEGROUNDS"` covers 5,786 entities: MINION 2469, ENCHANTMENT 1157, HERO 796, BATTLEGROUND_TRINKET 420, SPELL 365, BATTLEGROUND_SPELL 208, HERO_POWER 172, BATTLEGROUND_ANOMALY 112, BATTLEGROUND_QUEST_REWARD 73, BATTLEGROUND_HERO_BUDDY 1.
  - `techLevel` (tavern tier), `isBattlegroundsPoolMinion` (302 true), `isBattlegroundsPoolSpell` (77 true), `battlegroundsPremiumDbfId` / `battlegroundsNormalDbfId` (golden↔normal), `races`/`race`, `battlegroundsHero`, `heroPowerDbfId`, `battlegroundsBuddyDbfId`, `isBattlegroundsBuddy`, `battlegroundsSkinParentId`, `battlegroundsAssociatedRaces`, `battlegroundsRelatedCard`, `isBattlegroundsDuosExclusive`, `battlegroundsDarkmoonPrizeTurn`, `battlegroundsTimewarpCard`, `isBattlegroundsDarkGift`, `spellSchool` (trinkets use `LESSER_TRINKET`/`GREATER_TRINKET`; tavern spells use `TAVERN`), `mechanics`, `referencedTags`.
  - Example: `BG20_100` Razorfen Geomancer, `techLevel:1`, `races:["QUILBOAR"]`, `battlegroundsPremiumDbfId:70150`.
- **Art** (docs: https://hearthstonejson.com/docs/images.html; all verified 200):
  - `https://art.hearthstonejson.com/v1/render/latest/<locale>/{256x|512x}/<id>.png` (full card render)
  - `.../v1/bgs/latest/<locale>/{256x|512x}/<id>.png` (**BG-style render with tier**; works, though not in the docs)
  - `.../v1/tiles/<id>.{png|jpg|webp}` (256×59 deck tile)
  - `.../v1/{256x|512x}/<id>.{jpg|webp}` (square art)
  - `.../v1/orig/<id>.png`
- **Terms**: "HearthstoneJSON.com is licensed CC0. The JSON files contain data that is Copyright © Blizzard Entertainment - All Rights Reserved. This website is not affiliated with Blizzard Entertainment." For images: "avoid direct embedding on high-traffic websites, and instead re-host the images"; commercial use requires contacting contact@hearthsim.net (https://hearthstonejson.com/docs/images.html).
- **Update cadence**: build-keyed data follows hsdata. For 36.6.0.251952, hsdata was committed 2026-09-15 and HSJSON `latest` was modified 2026-09-16, so about 1 day after the patch.
- **Note**: the old `HearthSim/HearthstoneJSON` generator repo returns 404 (private or moved). A legacy fork exists at `Zero-to-Heroes/HearthstoneJSON-legacy`.

### Blizzard Hearthstone Game Data API
- **Endpoint**: `https://{region}.api.blizzard.com/hearthstone/cards?locale=en_US&gameMode=battlegrounds`. BG params: `tier=1..6|hero`, `minionType=<slug>`. "Battlegrounds-specific information such as tavern tier or upgraded version will only be returned if your request includes `gameMode=battlegrounds`." Non-hero BG cards have "special images that show their numeric tavern tier." Source: https://community.developer.battle.net/documentation/hearthstone/guides/game-modes (content JSON at `/api/pages/content/documentation/hearthstone/guides/game-modes.json`).
- **Auth**: OAuth client-credentials (`curl -u {client_id}:{client_secret} -d grant_type=client_credentials https://oauth.battle.net/token`, token lasts about 24 h). Requires a Battle.net account with an authenticator and acceptance of the API ToS. Source: https://community.developer.battle.net/documentation/guides/using-oauth/client-credentials-flow and `/guides/getting-started`.
- **Throttling**: "36,000 requests per hour at a rate of 100 requests per second" (getting-started guide).
- **ToS** (https://www.blizzard.com/en-us/legal/a2989b50-5f16-43b1-abec-2ae17cc09dd6/blizzard-developer-api-terms-of-use):
  - no "Premium" or paid features using the APIs (§2.b)
  - keep the API key confidential (§2.l), so **a desktop app cannot embed the secret** and needs a server proxy
  - attribute Blizzard, and "shall not contain any of Blizzard's trademarks as a part of its title or URL" (§2.m). This is relevant to a name containing "HS" or "Hearthstone".
  - retain data no longer than 30 days (§2.r)
- **Tradeoffs**: it is official and has tier images. But it adds a server dependency and legal constraints on monetisation, and it lacks the rich BG tags (pool flags, buddy links, trinket types) that HSJSON/CardDefs expose. It is also keyed by Blizzard's slug IDs rather than the `CardID` strings found in Power.log. **Recommendation: use HSJSON / hsdata as primary and skip the Blizzard API.**

### Other
- **hsbg.cards public API** (https://hsbg.cards/api-docs) is a community-run BG card API with patch history. It allows 120 requests/min anonymously and has open CORS. It is a third-party dependency with unclear longevity; reference only.

---

## 6. Other macOS BG tools: where the gap is

| Tool | Status on macOS | Notes / Source |
|---|---|---|
| **HSTracker** | Yes; the only full-featured one | Bob's Buddy, Tier7 hero/trinket/quest pick stats, comps, session. Tier7: "All in-game Tier7 features are available for free twice a week... subscribe" for more (HSReplay Tier7 page, https://hsreplay.net/battlegrounds/tier7/) |
| **Firestone** | **No.** Overwolf is Windows-only | Overwolf dev docs cover developing on Mac but not running there (https://dev.overwolf.com/ow-native/guides/dev-tools/non-windows-dev/). TH.GL FAQ: macOS "not supported" (https://www.th.gl/faq/overwolf-on-linux-macos). Firestone's electron build only targets Windows |
| **HDT and HDT plugins** (e.g. BoonwinsBattlegroundsTracker, C#, updated 2026-09-20) | No (Windows/WPF) | https://github.com/boonwin/BoonwinsBattlegroundsTracker |
| **HSReplay.net BG web** | Web only (browser) | Stats site; overlays need HDT or HSTracker |
| Small Swift projects (GitHub search, Sept 2026) | Mostly tiny or new, 0–7 stars | `drdanrb/Hearthside` ("local-first, privacy-first macOS companion", 2026-09-15); `brandonwilliams33/lubian-tracker` (native SwiftUI/AppKit deck tracker, 2026-09-21); `davidyht/BGMMR` (menu-bar opponent MMR, 2026-07-15); `JulianeWeller/HearthstoneHotkeysMac`; `StarLard/HearthstoneKit` (Swift SDK for the official API, 2025-03) |
| "Reconnect" / skip-combat tools | Several on macOS | `kulibabkaaa/Hearthstone-Reconnect-MacOS`, `xyydcoldcold/TavernBlink` ("pauses and resumes Hearthstone Battlegrounds network traffic"), `miniLV/HSQuickReconnect`, `hezt/HSReconnect`. **These manipulate game networking to skip animations; I would treat this as an exploit and avoid it.** |
| HsMod (BepInEx) installers for Apple Silicon | exist (`leafall903/hsmod-macos-installer`) | Client modification; clearly against the EULA's "hacks" clause |

**Gap analysis**: macOS BG users have exactly one serious option, HSTracker. It is feature-rich but depends on two closed binaries (HearthMirror memory reading and the BobsBuddy/Mono runtime) and on a paid stats backend (Tier7). Openings for a new app:
1. a **fully open, log-only** tracker (no memory reading, which also makes Mac App Store distribution possible, though the sandbox and Accessibility permission need checking)
2. an **MIT combat simulator** (Firestone's, via JavaScriptCore)
3. a modern SwiftUI-first codebase
4. free or local stats and a session recap

What you would lose without memory reading: lobby info (available tribes before the game, MMR), leaderboard hover and teammate board in Duos, hero-pick screen detection pre-log, and the log session dir (resolve it by scanning for the newest `Logs/Hearthstone_*` folder instead). Firestone's comp and meta data would need licensing, or you build your own aggregation.

---

## 7. Blizzard policy on trackers and overlays

- **Ben Brode (then Hearthstone game director), 2014-09-14**: "any app that duplicates what you can do with a pencil and paper already is fine." https://twitter.com/bbrode/status/511151446038179840
- **Blizzard EULA** (https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement):
  - §1.C.ii bans cheats, **bots** ("any code and/or software, not expressly authorized by Blizzard, that allows the automated control of a Game") and **hacks** ("accessing or modifying the software... not expressly authorized").
  - §1.C.vi bans "any unauthorized process or software that intercepts, collects, reads, or 'mines' information generated or stored by the Platform; **provided, however, that Blizzard may, at its sole and absolute discretion, allow the use of certain third-party user interfaces**."
  - §4 says Blizzard may "monitor your computer... memory for unauthorized third party programs."
- **Practical reading**:
  - **Reading log files that Hearthstone writes to disk** (enabled via `log.config`) is the long-tolerated baseline. HDT, HSTracker and Firestone have operated openly for about 10 years.
  - **Memory reading** (HearthMirror, Firestone's unity-spy) is used by the major trackers and has not, publicly, led to bans. It falls literally under §1.C.vi, so it relies on Blizzard's discretionary tolerance. **Grey area.**
  - **Automation, input injection, client modification (HsMod/BepInEx), and network manipulation** are **not permitted** under §1.C.ii.
  - I found **no current (2024–2026) official Blizzard support article** that explicitly whitelists trackers. The strongest official statements are the 2014 Brode tweet and the EULA carve-out.

---

## 8. Reuse table

| Component | Project | License | Language | Reuse strategy |
|---|---|---|---|---|
| Power.log reader and tailing | HSTracker `Logging/LogReader*.swift` | MIT | Swift | **Port** (copy and adapt, keep attribution) |
| Power parser, entity/tag state machine | HSTracker `PowerGameStateParser`, `TagChangeHandler`, `Game.swift` | MIT | Swift | **Port** |
| Power parser (reference semantics, tests) | python-hslog | MIT | Python | Reference only |
| Test fixtures (replays/logs) | HearthSim/hsreplay-test-data | CC0 | XML | **Depend** (test data) |
| GameTag and other enums | python-hearthstone `enums.py` / HSJSON `v1/enums.json` | MIT / CC0 wrapper | Python/JSON | **Depend via codegen** (generate Swift at build time) |
| Card definitions (BG) | hsdata `CardDefs.Bacon.xml` + `CardDefs.xml` | none (© Blizzard data) | XML | **Depend** (pinned by build); optionally port HSTracker's `CardDefsCompiler` |
| Card JSON (BG fields) | HearthstoneJSON `v1/<build>/<locale>/cards.json` | CC0 site / © Blizzard data | JSON | **Depend** (download and bundle per build) |
| Card art, BG renders, tiles | art.hearthstonejson.com (`render`, `bgs`, `tiles`) | CC0 site; asks to re-host; commercial use needs contact | PNG/JPG | **Depend with caching or re-hosting**; ask HearthSim if monetised |
| HS window tracking and overlay window pattern | HSTracker `SizeHelper.swift`, `WindowManager.swift`, `RootOverlayWindow.swift` | MIT | Swift | **Port** |
| Combat simulator | `@firestone-hs/simulate-bgs-battle` | MIT (package.json) | TypeScript → JS | **Depend** (bundle with esbuild, run in JavaScriptCore; spike verified) |
| Simulator card helpers and TS enums | `@firestone-hs/reference-data` | MIT | TypeScript | **Depend** (transitively, inside the JS bundle) |
| Combat simulator (HearthSim) | BobsBuddy.dll | proprietary (© HearthSim) | C# (.NET Std 2.0) | Reference only (needs permission; Mono embedding shown in HSTracker) |
| Memory reader | HearthMirror.framework | proprietary, closed | (binary) | Reference only / avoid |
| BG meta stats (comps, heroes, trinkets) | Firestone `static.zerotoheroes.com/api/bgs/*` | undocumented; ZtH ToS personal non-commercial | JSON | Reference only unless licensed |
| BG meta stats | HSReplay Tier7 | commercial | API | Reference only / partnership |
| HDT BG logic (board state, hero pick, session) | Hearthstone-Deck-Tracker | All Rights Reserved | C# | Reference only (read for behaviour; do not copy code) |
| Firestone BG UI and board-state builder | Zero-to-Heroes/firestone | none declared | TypeScript | Reference only |
| Card data (official) | Blizzard Game Data API | Blizzard API ToS | REST | Avoid (secret, no premium, 30-day retention, trademark rule) |
| Auto-update | Sparkle | MIT | ObjC/Swift | **Depend** |
| Alternative simulators | twanvl/hearthstone-battlegrounds-simulator (C++, MIT, pushed 2026-09-17), utilForever/battlegrounds-rs (Rust, MIT) | MIT | C++/Rust | Reference only (card coverage far behind Firestone) |

---

## 9. Open questions to resolve before committing
1. Get written confirmation from Sébastien Tromp that the npm MIT license covers redistribution of `simulate-bgs-battle` inside a (possibly paid) macOS app. The tarball has no LICENSE file.
2. Decide on memory reading. If you stay log-only, verify which BG facts are recoverable from Power.log alone: available tribes (likely via `BACON_*` tags on the game entity), anomalies, trinkets offered, Duos teammate.
3. Test whether a `JSContext` in a hardened-runtime or sandboxed app gets JIT without `allow-jit`, and measure performance with JIT disabled.
4. Test whether the Accessibility permission is required for accurate window framing (HSTracker falls back to CGWindowList without it).
5. Choose an app name that avoids Blizzard trademarks if the Blizzard API is ever used (§2.m). Also check general trademark risk with "Hearthstone"/"HS" in the name.
