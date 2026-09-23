# Power.log validation against real Battlegrounds captures (2026-09-22)

This note checks the claims in [battlegrounds-macos-feasibility.md](battlegrounds-macos-feasibility.md) and [logs-and-extractable-state.md](logs-and-extractable-state.md) against two real logs from this Mac (build 251952, solo `GT_BATTLEGROUNDS`). A throwaway Python replay parser produced the evidence. BattleTags are shown as `LocalPlayer`. Opponent account names are redacted as `Opp-P<PlayerID>`.

| Fixture | Role | Size | What it covers |
|---|---|---|---|
| `fixtures/private-logs/Hearthstone_2026_09_22_21_08_40/Power.log` | **Primary** | 35.8 MB, 270,004 lines | A complete game: 12 BG turns, `STATE=COMPLETE`. LocalPlayer is PlayerID 6 as George the Fallen and finished 4th. |
| `/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_33_28/Power.log` | Secondary | 5.9 MB, 46,045 lines | The first game, cut off during the BG turn 5 recruit phase by the log size cap. LocalPlayer is PlayerID 2 as Kith'ix. |

## Scripts

All scripts are in `/private/tmp/claude-501/-Volumes-Crucial-X9-GitHub-HS-Battlegrounds-Companion/c7b517d4-0301-459b-9c27-936ce0e65e97/scratchpad/validate/`:

- `powerlog.py`: the line tokenizer and entity/tag store. It handles `CREATE_GAME`, `GameEntity`/`Player`, `FULL_ENTITY` (both Creating and Updating), `SHOW_ENTITY`, `CHANGE_ENTITY`, `HIDE_ENTITY`, `TAG_CHANGE`, `DebugPrintGame` and choices. Tags are canonicalised to ints through `enums.json`, and numeric tags are accepted. `python3 powerlog.py <Power.log>` prints stats for both streams.
- `timeline.py`: derives Battlegrounds state for each turn. It snapshots at end of recruit (the moment `TURN` becomes even) and at combat (tag 2022 1→0), and records the lobby after combat, deaths and game end. `--json out.json` writes the result.
- `events.py [GameState|PowerTaskList]`: dumps the phase-tag timeline. `lead.py`: measures how far GameState runs ahead of PowerTaskList. `table.py`: renders the tables below. `bench.py`: the timing baseline.
- Cached data: `cards.json` (HearthstoneJSON 251952 enUS, 36,022 cards) and `enums.json`. Outputs: `full.json`, `out.json`, `full_table.md`, `partial_table.md`.

## Verdict

**The core claim holds.** All v1 snapshot fields can be derived deterministically from `PowerTaskList.DebugPrintPower` alone, plus `GameState.DebugPrintGame` and the choice lines:

- hero and HP+armor
- gold
- tier
- turn and phase
- own board with keywords and golden flag
- hand
- shop, with frozen state
- all 8 lobby heroes with HP, tier, place and triples
- next opponent
- the opponent's board at every combat
- deaths, final placement and game end

The data mapped cleanly every time we checked. `NEXT_OPPONENT_PLAYER_ID` matched the next combat's opponent in 16/16 combats. Tag 2022/3533 toggled exactly once per combat.

The doc needs several corrections. They are listed below and none of them block v1:

- 3533 is not Duos-only.
- The GameState lead can reach about 50 s, not 16–18 s.
- Opponent display names are in the log.
- Tavern spells in hand are `SPELL`.
- `CLEAVE` is not a tag.
- There are duplicate hero entities at death.
- The client also creates "preview" copies of the opponent's board under the local controller.

## Claims that held

| Claim | Evidence |
|---|---|
| The line grammar `^[DWE] HH:MM:SS.fffffff Method() - payload` | Every line in both files matches, except 17 lines in the full game where the method is `PowerSpellController [taskListId=N].InitPowerSpell()`. It contains a space and brackets, so a `[\w.]+` method regex rejects it; python-hslog's `[^(]+` accepts it. There were no CRs, no control bytes and no non-ASCII bytes in either file. The longest line is 373 bytes. |
| Game detection with `CREATE_GAME`, then `GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS`, `BuildNumber=251952`, `FormatType=FT_WILD` | Both files. **Note:** `DebugPrintGame` exists **only** in the GameState stream, and it arrives *after* the GameState `CREATE_GAME` but *before* the PowerTaskList `CREATE_GAME`. A parser that resets on the PTL `CREATE_GAME` must keep the metadata it has already parsed. |
| The game ends with `TAG_CHANGE Entity=GameEntity tag=STATE value=COMPLETE`; placement is `PLAYER_LEADERBOARD_PLACE` on `Player.HERO_ENTITY` | Full game, PTL line 269962. Hero 108 (the one `HERO_ENTITY` points to) gets `PLAYER_LEADERBOARD_PLACE=4` in the same batch as COMPLETE. The sequence is: local hero HP ≤ 0 at 21:33:09, `PLAYSTATE` PLAYING→LOSING at 21:33:13, then LOSING→LOST, the other slot → WON, and then `STATE=COMPLETE` at 21:33:14. |
| LoadingScreen scene flow | `prevMode=HUB currMode=BACON`, then `OnScenePreUnload prevMode=BACON nextMode=GAMEPLAY`, then `Gameplay.Start()`. After the game: `prevMode=GAMEPLAY nextMode=BACON`, `Gameplay.OnDestroy()` (about 20 s after the PTL COMPLETE), then `currMode=BACON`. LoadingScreen.log also carries `Gameplay.OnPowerHistory() - powerList=N` and `MulliganManager.*` lines. |
| Use PowerTaskList for state and GameState only for metadata and choices | In the complete game both streams carry identical packet content: 58,640 `TAG_CHANGE` and 2,313 `FULL_ENTITY` each. PTL is a delayed replay of GameState. |
| GameState learns the combat result early | Confirmed, and the lead is **much larger** than the doc says (see Surprises). |
| Hero pick uses `DebugPrintEntityChoices ChoiceType=MULLIGAN` with 4 heroes in HAND, then `DebugPrintEntitiesChosen` | Both files. Two of the four options carry `BACON_LOCKED_MULLIGAN_HERO=1` (they are locked, not pickable). After the pick, the Player's `HERO_ENTITY` changes from the placeholder `TB_BaconShop_HERO_PH` (id 27) to the chosen hero. The unpicked options move to GRAVEYARD. |
| HP = `HEALTH − DAMAGE + ARMOR` | This matches the in-game numbers: Kith'ix starts at 30+8 = 38 and George the Fallen at 30+15 = 45. Armor absorbs damage first; for example Kith'ix went 38 → 34 as `ARMOR` went 8 → 4 while `DAMAGE` stayed 0. |
| Gold: `RESOURCES` for the turn, `RESOURCES_USED`, `TEMP_RESOURCES`; tag 3148 is the gold cap; `MAXRESOURCES` = 99 | `RESOURCES` goes 3, 4, … 10 (the cap). At each turn start `RESOURCES_USED` resets to 0. Tag 3148 is set **once** (value 10) on turn 1. `MAXRESOURCES` is 99. `TEMP_RESOURCES` appeared only once in 12 turns (2→0). |
| Tavern tier is `PLAYER_TECH_LEVEL` on hero entities | Yes. For the local player it is also mirrored on the **Player** entity. |
| Turn: `GameEntity TURN` odd = recruit, even = combat; BG turn = (TURN+1)/2 | Yes. Each Player entity also has its own `TURN`, which counts BG turns. |
| Tag 2022 1→0 marks combat start (the BobsBuddy trigger) | Yes. 2022 1→0 comes immediately before the first `BLOCK_START BlockType=ATTACK`, and the opponent board is complete at that point. We saw 12 of 12 combats (full game) and 4 of 4 (partial). There were **no** spurious toggles, so HDT's guard never had anything to reject. |
| Bob's shop is the other Player slot, `ZONE=PLAY`; spells are `BATTLEGROUND_SPELL`; freeze is `FROZEN`; `IS_BACON_POOL_MINION`, `TECH_LEVEL` | Yes (see the tables below; FRZ = frozen shop). |
| All lobby heroes carry `PLAYER_LEADERBOARD_PLACE`, `PLAYER_TECH_LEVEL`, `PLAYER_TRIPLES`, `DAMAGE`, `ARMOR` | 8 rows every turn until the local player dies (then there are 9; see Surprises). Opponent heroes are `SETASIDE` and controlled by the bartender slot. Each carries **`PLAYER_ID` = that player's lobby PlayerID** (1–8), which is the join key. |
| `NEXT_OPPONENT_PLAYER_ID` on both the local Player and the local hero | The value is already present in `CREATE_GAME` on the Player, and on the hero from turn 1. It changes at the end of each combat, before `TURN` becomes odd, so it is known for the whole recruit phase. It equaled the next combat's `BACON_CURRENT_COMBAT_PLAYER_ID` on the bartender slot, and the `PLAYER_ID` of the combat opponent's hero, in **16/16** combats. |
| The opponent board is available only at combat and has full stats and keywords | Yes. Minions are created as `FULL_ENTITY` directly in `ZONE=PLAY` with `CONTROLLER=<slot>` and `COPIED_FROM_ENTITY_ID`. |
| Entity IDs are re-created on every refresh and every combat, and they are never reused | Yes. We saw no `FULL_ENTITY` for an ID that already existed, and no reference to an entity that had never been created. |
| Hidden entities show as `UNKNOWN ENTITY [cardType=INVALID]` with an empty `cardId` | Yes (931 occurrences in the partial log). |
| When a tag has no name, the client prints the number | Yes. Every **named** tag in both logs resolves through `enums.json` (0 unknown names). Unnamed tags seen include 2022, 3533, 3148, 1640, 3085, 4901, 1068, 1453, 2753, 3245, 937 and more. |
| The size cap stops logging | Confirmed. In the partial capture, Power.log, LoadingScreen.log (only 20 KB) and Hearthstone.log all stop at 20:41:03.34 in the same instant. The complete game (after `client.config` was written) reached 35.8 MB with no truncation. |
| GameEntity config tags | `BACON_GLOBAL_OLD_GOD_DBID=132532` (Y'Shaarj), `BACON_BARTENDER_CARD_ID=118385` (`TB_BaconShopBob_SKIN_AN` "Zeratul"), `BACON_TRINKETS_ACTIVE`, `BACON_DARK_GIFTS_ACTIVE`, `BACON_MULLIGAN_HERO_REROLL_ACTIVE`. `BACON_GLOBAL_ANOMALY_DBID` is absent. `BACON_COMBAT_DAMAGE_CAP` goes 2 → 5 → 10 → 15. |
| Trinkets | `BG30_Trinket_1st` / `_2nd` placeholders are present. The trinket offers are `ChoiceType=GENERAL` with **4** `BG3x_MagicItem_*` options. Dark Gift discovers (source `BG36_MidGameEffect_010`) and triple rewards (source `TB_BaconShop_Triples_01`) are `GENERAL` with 3 options. The choice `Source=` line identifies which one it is. |

## Claims that did not hold, or need correcting

1. **Tag 3533 is not Duos-only.** In solo it toggles in **every** combat: 0→1 in the same batch as `TURN` becoming even, then 1→0 just before 2022 1→0. The observed order is in "Turn and phase boundaries" below. HDT keys Duos logic on it, so a solo parser must not treat 3533 as "Duos detected".
2. **The GameState lead is up to about 50 s, not 16–18 s.** The lead is the PTL `TURN` odd timestamp minus the GameState one:
   - Full game: 0.9, 7.9, 15.0, 28.3, 28.3, 32.9, 33.8, 43.4, 42.2, 38.9, 47.3 and 50.1 s for turns 1–12.
   - Partial game: 0.8, 18.1, 16.5, 23.1 and 48.1 s.
   - `PLAYSTATE LOST` and `STATE=COMPLETE` appear in GameState **45 s** before PTL.

   The lead grows with combat length.
3. **Opponent display names are in the log, not only in memory.** The bartender Player slot has no fixed name. It is printed under whatever name the client currently gives that slot:
   - At `CREATE_GAME` and `DebugPrintGame` it has a placeholder name (redacted). That name belongs to none of the 7 opponents and appears only once.
   - During recruit it is the bartender skin's name ("Zeratul").
   - **During combat** it is the current opponent's account display name, without the `#1234` suffix.

   Each of the 7 opponent names first appeared inside exactly one combat window, and that window's `BACON_CURRENT_COMBAT_PLAYER_ID` gave its PlayerID. This produced a clean name → PlayerID → hero map for every opponent you have fought (7/7 in the full game). You never learn the names of players you haven't fought.
4. **Tavern spells in hand are `CARDTYPE=SPELL`, not `BATTLEGROUND_SPELL`.** On purchase, the client sends `TAG_CHANGE ... tag=CARDTYPE value=SPELL DEF CHANGE`. `DEF CHANGE` appears 42 times in the full game, always on these CARDTYPE changes.
5. **`CLEAVE` is not a GameTag** in `enums.json`, so drop it from the keyword list. The other keywords are real tags: `TAUNT`, `DIVINE_SHIELD`, `REBORN`, `POISONOUS`, `VENOMOUS`, `WINDFURY`, `MEGA_WINDFURY`, `STEALTH`, `DEATHRATTLE`, `BATTLECRY`, `AVENGE`, `MAGNETIC`, `BACON_RALLY` and `FROZEN`.
6. **"Collect all heroes with `PLAYER_LEADERBOARD_PLACE`" gives 9 rows at game end.** When the local hero dies (hero 108 → GRAVEYARD, place 4), the client creates another `George the Fallen` entity (19119) in SETASIDE with a stale `PLAYER_LEADERBOARD_PLACE=3` and HP 30. You must deduplicate by `PLAYER_ID`: for the local player use `Player.HERO_ENTITY`, and for opponents use the lobby hero.
7. **Timing note for the "6 MB in one game" claim.** 6 MB was actually reached by **BG turn 5**. A full 12-turn game is 35.8 MB, and the late turns produce 4–5.7 MB each (see Performance).

## Surprises and parsing hazards

### Entity reference formats (all seen in PTL)
- `GameEntity`, bracket form, bare numeric id, or a player name. In PTL the bare ids are rare: 102 `TAG_CHANGE Entity=<n>` in the full game, 7 in the partial one. GameState uses bare ids more often, and it uses `Entity=4` for GameEntity inside some blocks.
- **Nested brackets in entityName:** `[entityName=UNKNOWN ENTITY [cardType=INVALID] id=254 zone=SETASIDE zonePos=0 cardId= player=2]` and `[entityName=Battlegrounds Dark Gift [DNT] id=1766 ...]`. Names also contain commas and apostrophes (`Malchezaar, Prince of Dance`, `Kith'ix`). A `\[[^\]]*\]` tokenizer breaks. Anchor on the tail instead: `id=(\d+) zone=\w+ zonePos=\d+ cardId=\S* player=\d+\]$`.
- **The bracket's `zone`/`zonePos`/`player` fields are stale.** They describe the entity *before* the line applies. For example, `TAG_CHANGE Entity=[... zone=PLAY ...] tag=ZONE value=REMOVEDFROMGAME` still says `zone=PLAY`. Take only `id` from brackets, and read zone and controller from the store.
- **The bracket's entityName is the base name, not the card's name.** A skinned hero shows `entityName=Ysera` for `TB_BaconShop_HERO_53_SKIN_F` ("Ardenweald Ysera"), and the placeholder hero shows `BaconPHhero`. Resolve display names from `cardId` through HearthstoneJSON.
- **Player names:** the local BattleTag stays constant. The bartender slot is referred to by an unannounced, changing name (see correction 3). Rule: any player-name token that isn't the local BattleTag (from `DebugPrintGame PlayerID=<local>`) is the other Player entity. There are exactly two Player entities.
- `BLOCK_START ... EffectCardId=System.Collections.Generic.List`1[System.String]` is a .NET `ToString()` leak (1,136 lines in the partial log). It contains brackets and a backtick. Use a non-greedy match up to ` EffectIndex=`.
- Trailing spaces are common: `TAG_CHANGE` lines end with `value=X ` (a trailing space) or `value=X DEF CHANGE`.

### Indentation is not reliable nesting in PTL
- In PowerTaskList, **every `BLOCK_START` is at column 0**, top-level payloads are at 4, and nested `FULL_ENTITY`/`TAG_CHANGE` inside a sub-block are at 8. `SUB_SPELL_END` appears at both 0 and 4. GameState uses true nested indentation instead, down to 16+ spaces.
- A parser should ignore indentation. A line starting with `tag=` continues the most recent `FULL_ENTITY`/`SHOW_ENTITY`/`CHANGE_ENTITY`/`GameEntity`/`Player` header. Any other line ends that header. This rule produced 0 orphan `tag=` lines.
- `Info[n] = …`, `Source = …` and `Targets[n] = …` lines follow `META_DATA` / `SUB_SPELL_START` and can be ignored for v1.
- `BLOCK_END` may appear twice in a row (nested blocks closing). There are no other consecutive duplicate PTL lines. No task list was printed twice: the 1,209 and 5,961 `DebugDump ID=` values are all unique. `PowerTaskList.DebugDump() - Block Start=(null)` is always `(null)`.

### The bartender slot: telling the shop from the opponent board
- One Player entity (`GameAccountId=[hi=0 lo=0]`, `BACON_DUMMY_PLAYER=1`) owns both. Its PlayerID was 10 when the local player was 2, and 14 when the local player was 6, so it looks like local+8. That is only two samples; always read it from `CREATE_GAME`.
- **Recruit:** `slot.HERO_ENTITY` = the Bob skin hero (entity 50 / 74, `TB_BaconShopBob_SKIN_AN`). `slot.BACON_CURRENT_COMBAT_PLAYER_ID` = 0. Slot minions and `BATTLEGROUND_SPELL`s in PLAY are the **shop**.
- **At `TURN` becoming even (same batch):** every shop entity gets `ZONE=REMOVEDFROMGAME` and its stats are zeroed (`ATK=0`, `HEALTH=0`, …).
- **Combat:** `slot.HERO_ENTITY` switches to a new copy of the opponent's hero, which carries `PLAYER_ID` = the opponent's PlayerID (but *no* `PLAYER_LEADERBOARD_PLACE`). `BACON_CURRENT_COMBAT_PLAYER_ID` is set on both Players (local = own PlayerID, slot = opponent PlayerID). Slot minions in PLAY are the **opponent board**.
- **Discriminator:** `BACON_CURRENT_COMBAT_PLAYER_ID != 0` on the slot, or `slot.HERO_ENTITY != Bob`, or `BOARD_VISUAL_STATE == 2`. Don't rely on `IS_BACON_POOL_MINION`, which is also set on combat copies.
- **Preview copies under the *local* controller:** right after `TURN` becomes even, **before** the real combat entities exist, the client creates copies of the opponent hero and board in `ZONE=SETASIDE` with `CONTROLLER=<local>`. Examples are 520 Ysera and 527 Glim Guardian, plus `UNKNOWN ENTITY` 525/526/529. The real combat minions later point to them via `COPIED_FROM_ENTITY_ID`, and all of them go to REMOVEDFROMGAME after combat. A filter like "controller == me" without `ZONE == PLAY` would put enemy minions on your own board.
- **Your own board is re-created every turn.** At combat start the client makes `SETASIDE` copies of your minions (e.g. 528 from 462). Combat is fought with the recruit-phase entities, which go to REMOVEDFROMGAME at combat end, and the copies move into PLAY for the next recruit. Own-minion IDs therefore change every turn: in the partial game Crackling Cyclone was 462 → 528 → 863 → 1306 → 2003. Carry identity across turns by card and position, not by ID.

### Turn and phase boundaries (observed order, identical in every combat)
1. `GameEntity TURN` becomes even, `BOARD_VISUAL_STATE=2` and `3533 0→1` all arrive in one batch. At the same moment shop minions go to REMOVEDFROMGAME, the own-board copies are made, and the opponent preview copies are created.
2. About 1.5 s later: `2022 0→1`, `BACON_CURRENT_COMBAT_PLAYER_ID` is set on both Players, and the slot's name changes to the opponent's. The slot's `HERO_ENTITY` becomes the combat hero copy, and the opponent minions are `FULL_ENTITY`'d in PLAY.
3. `3533 1→0`, then `2022 1→0`. **Start-of-combat state is final here, so snapshot the opponent board at this point.**
4. `ATTACK` / `DEATHS` blocks. Hero `DAMAGE`/`ARMOR` updates.
5. `BOARD_VISUAL_STATE 2→1`, the slot's `HERO_ENTITY` goes back to Bob, and `NEXT_OPPONENT_PLAYER_ID` changes (on the Player, then on the hero). About 3 s later `TURN` becomes odd, which starts the recruit phase. `RESOURCES` is set and `RESOURCES_USED` resets to 0; the new shop is `FULL_ENTITY`'d one minion at a time.

Before the first combat, `BOARD_VISUAL_STATE`, 2022 and 3533 are **absent**, so treat them as 0. The first recruit phase is identified by `TURN=1` alone.

Tag 1640 flips to 1 when a hero dies (and sometimes back to 0), but it is unreliable. Use HP ≤ 0 instead. Dead opponents keep negative HP and their final place. A slot `PLAYSTATE` of PLAYING→LOSING→PLAYING happens when the *combat opponent* dies, so it does **not** mean the game ended.

### Other
- **Batch timestamps.** Every line in a task list shares one timestamp: in the full game, 4,730 consecutive lines have 21:29:56.31. Timestamps are useful only for pacing, never for ordering. Neither game crossed midnight.
- **Server-wide ID space.** IDs reach 19,227, but only 2,316 entities ever appear. The server allocates IDs for all 8 players' shops and combats, and you see only your own.
- **Shop stats settle after the minion is created.** A shop Crackling Cyclone is created at 2/1 and then buffed to 3/2 in the same task list by a shop-wide buff. Snapshot the shop at task-list boundaries (`PowerProcessor.EndCurrentTaskList`), not on each `FULL_ENTITY`.
- **Golden:** the Dark Gift discover produced a `CHANGE_ENTITY ... CardID=BG36_101_G` and set `PREMIUM=1`. Both the `_G` card ID and `PREMIUM` mark a golden minion.
- **`HIDE_ENTITY - Entity=… tag=ZONE value=PLAY`** (1,049 in the full game, almost all enchantments) is always followed by a real `TAG_CHANGE … ZONE`. Treat it as "hidden", not as a zone move.
- **Encoding:** no corrupt bytes appeared in 316 k lines, but still decode with replacement and never crash on a line.

## Per-turn timeline, complete game (primary)

The own board, hand and shop are taken when `TURN` becomes even (end of recruit). The opponent board is taken at 2022 1→0. Minions are shown as `Name ATK/HP-left [keywords]`, where `*` = golden. Keywords: T taunt, DS divine shield, R reborn, WF windfury, DR deathrattle, BC battlecry, MAG magnetic, V venomous, RALLY, FRZ frozen. Gold is `RESOURCES (RESOURCES_USED)` at end of recruit, so available gold = RESOURCES − USED + TEMP. HP includes armor.

| BG turn | Recruit start (PTL) | Hero HP (start → after combat) | Gold | Tier | Own board at end of recruit | Hand | Shop at end of recruit | Opponent (PlayerID → hero) | Opponent board at combat (tag 2022 1→0) | Place after combat |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 21:10:12 | 45 → 45 | 3 (used 3) | 1 | Zoatroid 3/2 | — | Harmless Bonehead 1/1 [DR]; Tusked Camper 2/3 [RALLY]; Fortify 0/0 | P5 → Ragnaros the Firelord | Scarlet Survivor 3/3 | 2 |
| 2 | 21:11:07 | 45 → 42 | 4 (used 4) | 2 | Zoatroid 3/2 | — | Scarlet Survivor 3/3 [FRZ]; Zoatroid 3/2 [FRZ]; Razorfen Geomancer 2/1 [BC,FRZ]; Enchanted Lasso 0/0 [FRZ] | P2 → Al'Akir | Risen Rider 2/1 [T,R] | 4 |
| 3 | 21:12:02 | 42 → 37 | 5 (used 5) | 2 | Unwilling Slacker 7/1 [DR]; Zoatroid 3/2; Zoatroid 3/2 | — | Scarlet Survivor 3/3; Razorfen Geomancer 2/1 [BC]; Snow Baller 3/4 | P1 → Sir Finley Mrrgglton | Tusked Camper 2/3 [RALLY]; Risen Rider 2/1 [T,R]; Aberrant Tentacle 0/2 [T]; Prodigious Tusker 2/5 | 6 |
| 4 | 21:13:16 | 37 → 33 | 6 (used 6) | 3 | Unwilling Slacker 7/1 [DS,DR]; Zoatroid 3/2; Zoatroid 3/2 | Tavern Coin | Eternal Knight 4/2; Intrepid Botanist 3/4; Sellemental 3/3; Electric Synthesizer 3/4 [BC]; Strike Oil 0/0 | P8 → Kith'ix | Roadboar 5/7 [RALLY]; Decoy Conjurer 3/4; Suspicious Prisonguard 3/3; Prodigious Tusker 5/8 | 7 |
| 5 | 21:14:38 | 33 → 25 | 7 (used 7) | 4 | Unwilling Slacker 14/4 [DS,DR]; Zoatroid 3/2 [DS]; Zoatroid 3/2 | — | Zoatroid 3/2 [FRZ]; Fetid Corroder 3/3 [BC,FRZ]; Waveling 5/1 [DR,FRZ]; Fire Baller 4/3 [FRZ]; Might of Stormwind 0/0 [FRZ] | P4 → Tockatus | Roadboar 3/5 [RALLY]; Tusked Camper 2/3 [RALLY]; Gem Rat 6/6; Prodigious Tusker 2/5; Unwilling Slacker 2/5 [T,DR] | 7 |
| 6 | 21:16:20 | 25 → 25 | 8 (used 8) | 4 | Unwilling Slacker 30/5 [DS,DR]; Drifting Sacrifice 6/2 [R,DR]; Zoatroid* 7/5 [DS]; Cataclysmic Harbinger 7/11 [DS] | Sludge Corrosion | Fetid Corroder 3/3 [BC]; Waveling 5/1 [DR]; Fire Baller 4/3; Might of Stormwind 0/0; Leyline Surfacer 4/6 [DR,BC] | P3 → Mystical Mentor Nguyen | Wildfire Elemental 24/37; Mangled Bandit 3/3 [RALLY]; Tusked Camper 2/3 [RALLY]; Decoy Conjurer 3/4; Briarback Drummer 5/3 [BC]; Hot-Air Surveyor 3/7 | 6 |
| 7 | 21:18:25 | 25 → 25 | 9 (used 9) | 4 | Drifting Sacrifice 20/4 [R,DR]; Unwilling Slacker 3/3 [DR]; Unwilling Slacker 44/7 [DS,DR]; Cutthroat K'Thir 22/22; Brain Rotter 5/6; Zoatroid* 9/7 [DS]; Cataclysmic Harbinger 9/13 [DS] | Leaf Through the Pages | Hot-Air Surveyor 3/7; Friendly Geist 6/3 [DR]; Fruit Vendor 3/6; Glim Guardian 1/4 [RALLY]; Sky-hatch Runaway 4/7; Shiny Ring 0/0 | P7 → Drest'agath | Abyssal Envoy 3/4; Vicious Mindslasher 8/16; Vicious Mindslasher 6/9; Unwilling Slacker 1/1 [DR]; Drifting Sacrifice 6/9 [R,DR]; Unwilling Slacker 7/10 [DR] | 4 |
| 8 | 21:20:38 | 25 → 25 | 10 (used 10) | 5 | Drifting Sacrifice 27/5 [R,DR]; Unwilling Slacker 4/4 [DR]; Brain Rotter 6/7; Unwilling Slacker 51/8 [DS,DR]; Cutthroat K'Thir 35/35 [DS]; Zoatroid* 10/8 [DS]; Cataclysmic Harbinger 10/14 [DS] | Sludge Corrosion | Mindbending Recruiter 6/2; Scarlet Survivor 3/3; Scarlet Survivor 3/3; Holy Vanguard 5/5 [DS]; Roadboar 2/4 [RALLY]; Defender's Rites 0/0 | P5 → Ragnaros the Firelord | Tarecgosa 19/18; Glim Guardian* 19/20 [RALLY]; Scarlet Survivor 18/15 [DS]; Bronze Warden 14/10 [DS,R]; Brann Bronzebeard 5/6; Sky-hatch Runaway 13/15; Roaring Recruiter 17/22 | 4 |
| 9 | 21:22:51 | 25 → 25 | 10 (used 9) | 5 | Drifting Sacrifice 41/7 [R,DR]; Unwilling Slacker 6/6 [DR]; Unwilling Slacker 65/10 [DS,DR]; Cutthroat K'Thir 43/43 [DS]; Zoatroid* 12/10 [DS]; Cataclysmic Harbinger 12/16 [DS]; Titus Rivendare 3/9 [DS] | Shiny Ring | Unwilling Slacker 1/1 [DR,FRZ]; Mummifier 5/2 [DR,FRZ]; Kalecgos, Arcane Aspect 4/12 [FRZ]; Tavern Tempest 2/2 [BC,FRZ]; Refreshing Anomaly 4/5 [BC,FRZ]; Tomb Turning 0/0 [FRZ] | P2 → Al'Akir | Unbound Tempest 55/72; Waveling 15/11 [DR]; Leyline Surfacer 4/6 [DR,BC]; Leyline Surfacer 6/8 [DR,BC]; Living Azerite 17/16 [DS]; Air Revenant 3/6; Ichoron the Protector 3/1 [DS] | 3 |
| 10 | 21:25:30 | 25 → 16 | 10 (used 10) | 6 | Drifting Sacrifice 62/10 [R,DR]; Unwilling Slacker* 87/17 [DS,DR]; The Shadow of Doubt 7/9; Cutthroat K'Thir 56/56 [DS]; Zoatroid* 13/11 [DS]; Cataclysmic Harbinger 13/17 [DS]; Titus Rivendare 4/10 [DS] | Overconfidence | Mummifier 5/2 [DR]; Kalecgos, Arcane Aspect 4/12; Tavern Tempest 2/2 [BC]; Refreshing Anomaly 4/5 [BC]; Tomb Turning 0/0 | P8 → Kith'ix | De-volition-ist 67/59; Nightmare Corroder* 95/82 [T,DS,DR,RALLY]; Brain Rotter* 29/31 [DS]; Vicious Mindslasher 32/56; Mindbending Recruiter 18/14; Mindbender Ghur'sha 7/13; Parasitic Fleshling 20/22 [DS] | 2 |
| 11 | 21:28:09 | 16 → 6 | 10 (used 10) | 6 | De-volition-ist 21/21 [DS]; Drifting Sacrifice 81/11 [R,DR]; Unwilling Slacker* 106/18 [DS,DR]; Cutthroat K'Thir 67/67 [DS]; Zoatroid* 14/12 [DS]; Cataclysmic Harbinger 14/18 [DS]; Titus Rivendare 5/11 [DS] | Sludge Corrosion | Heroic Broodmother 7/7 [RALLY]; Sly Infiltrator 4/5; Tusked Camper 2/3 [RALLY]; Dark Puppeteer 8/4 [DR]; Refreshing Anomaly 4/5 [BC]; Sin'dorei Straight Shot 3/4 [DS,WF,RALLY]; Contracted Corpse 0/0 | P7 → Drest'agath | N'raqi Sapper 43/21 [DR,BC]; Nightmare Corroder 44/25 [T,DR]; Drifting Sacrifice* 58/43 [T,R,DR]; Abyssal Envoy 46/30; Vicious Mindslasher 76/117; Vicious Mindslasher 75/112 [T]; Unwilling Slacker 44/30 [T,DR] | 3 |
| 12 | 21:30:47 | 6 → — | 10 (used 10) | 6 | De-volition-ist 24/24 [DS]; Faceless Converter 8/8 [DR]; Drifting Sacrifice 102/14 [DS,R,DR]; Unwilling Slacker* 127/21 [DS,DR]; Cutthroat K'Thir 80/80 [DS]; Zoatroid* 17/15 [DS]; Titus Rivendare 8/14 [DS] | — | Deadly Spore 1/1 [V]; Dune Dweller 3/3 [BC]; Holy Vanguard 20/20 [DS]; Flaming Enforcer 4/5; Prosthetic Hand 3/1 [R,MAG]; Fetid Corroder 3/3 [BC]; Golden Touch 0/0 | P3 → Mystical Mentor Nguyen | Sanguine Refiner 231/464 [RALLY]; Felboar 1967/3795; Mangled Bandit* 12/14 [RALLY]; Hot-Air Surveyor* 6/14; Hot-Air Surveyor* 14/28; Drakkari Enchanter 1/5 | — |

Lobby at STATE=COMPLETE (BG turn 12):

| Place | PlayerID | Hero | HP+armor | Tier | Triples | Hero entity / zone |
|---|---|---|---|---|---|---|
| 1 | 7 | Drest'agath | 16 | 4 | 4 | 181 / SETASIDE |
| 2 | 8 | Kith'ix | 15 | 6 | 3 | 242 / SETASIDE |
| 3 | 3 | Mystical Mentor Nguyen | 5 | 5 | 4 | 147 / SETASIDE |
| 3 | 6 | George the Fallen | 30 | 6 | 2 | 19119 / SETASIDE |
| 4 | 6 | George the Fallen | -4 | 6 | 2 | 108 / GRAVEYARD |
| 5 | 1 | Sir Finley Mrrgglton | -5 | 6 | 0 | 225 / SETASIDE |
| 6 | 4 | Tockatus | -2 | 5 | 1 | 163 / SETASIDE |
| 7 | 2 | Al'Akir | -2 | 5 | 2 | 210 / SETASIDE |
| 8 | 5 | Ragnaros the Firelord | -8 | 4 | 2 | 195 / SETASIDE |

Hero deaths (turn, PlayerID, hero, final place): T9 P2 Al'Akir (7), T9 P5 Ragnaros (8), T11 P1 Sir Finley (5), T11 P4 Tockatus (6), T12 P6 LocalPlayer George the Fallen (4). The two rows for PlayerID 6 above show the duplicate hero at death (correction 6).

Opponent names by PlayerID, learned only from combats: Opp-P5 (T1), Opp-P2 (T2), Opp-P1 (T3), Opp-P8 (T4), Opp-P4 (T5), Opp-P3 (T6), Opp-P7 (T7). All 7 names mapped.

Choices: hero (MULLIGAN) chose `TB_BaconShop_HERO_15` over `BG35_HERO_001`, `BG23_HERO_305` and `BG20_HERO_283`; `BG35_HERO_001` and `BG20_HERO_283` were locked. The `GENERAL` choices were 3 Dark Gift discovers (source `BG36_MidGameEffect_010`), 2 triple-reward discovers (source `TB_BaconShop_Triples_01`), each with 3 options, and 2 trinket offers (sources `BG30_Trinket_1st` / `_2nd`) with 4 options each.

## Per-turn timeline, truncated game (secondary)

| BG turn | Recruit start (PTL) | Hero HP (start → after combat) | Gold | Tier | Own board at end of recruit | Hand | Shop at end of recruit | Opponent (PlayerID → hero) | Opponent board at combat (tag 2022 1→0) | Place after combat |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 20:35:32 | 38 → 38 | 3 (used 3) | 1 | Crackling Cyclone 2/4 [T,DS,WF] | — | Scarlet Survivor 3/3; Lullabot 2/2 [MAG]; Dune Dweller 3/3 [BC] | P6 → Ardenweald Ysera | Glim Guardian 1/4 [RALLY] | 8 |
| 2 | 20:36:38 | 38 → 38 | 4 (used 4) | 2 | Crackling Cyclone 2/4 [T,DS,WF] | — | Ominous Seer 2/1 [BC]; Suspicious Prisonguard 3/3; Scarlet Survivor 3/3; A New Sprout 0/0 | P3 → Spelunker Holmes | Suspicious Prisonguard 3/3 | 8 |
| 3 | 20:37:29 | 38 → 34 | 5 (used 5) | 2 | Crackling Cyclone 2/4 [T,DS,WF]; Dune Dweller 3/3 [BC]; Underrot Spawn 2/2 [DR] | — | Tarecgosa 4/4; Bronze Warden 2/1 [DS,R]; Glim Guardian 1/4 [RALLY]; Alliance Flag 0/0 | P7 → Clockwork Mechano | Laboratory Assistant 5/6 [BC]; Laboratory Assistant 5/6 [WF,BC] | 8 |
| 4 | 20:38:42 | 34 → 31 | 6 (used 6) | 2 | Unwilling Slacker* 2/2 [DR]; Crackling Cyclone 2/4 [T,DS,WF]; Joyous 2/3 [BC]; Dune Dweller 3/3 [BC]; Underrot Spawn 2/2 [DR] | — | Crackling Cyclone 3/2 [DS,WF]; Zoatroid 3/2; Mechagnome Interpreter 3/1; Fortify 0/0 | P5 → Farseer Nobundo | Joyous 3/5 [BC]; Joyous 3/8 [T,BC]; Aberrant Tentacle 1/4 [T] | 7 |
| 5 (log ends mid-recruit) | 20:40:33 | 31 → — | 7 (used 7) | 3 | Unwilling Slacker* 2/2 [DR]; Crackling Cyclone 2/4 [T,DS,WF]; Joyous 2/3 [BC]; Dune Dweller 3/3 [BC]; Underrot Spawn 2/2 [DR] | Tavern Coin; Tavern Coin; Alliance Flag; Malchezaar, Prince of Dance | Fetid Corroder 3/3 [BC]; Roaring Recruiter 2/8; Suspicious Prisonguard 3/3; Lullabot 2/2 [MAG]; Robust Evolution 0/0 | P8 → Aranna Starseeker | — | — |

Lobby at end of log:

| Place | PlayerID | Hero | HP+armor | Tier | Triples | Hero entity / zone |
|---|---|---|---|---|---|---|
| 1 | 7 | Clockwork Mechano | 44 | 3 | 1 | 171 / SETASIDE |
| 2 | 4 | The Great Akazamzarak | 42 | 3 | 0 | 231 / SETASIDE |
| 3 | 6 | Ardenweald Ysera | 39 | 3 | 1 | 216 / SETASIDE |
| 4 | 5 | Farseer Nobundo | 39 | 3 | 0 | 186 / SETASIDE |
| 5 | 8 | Aranna Starseeker | 36 | 2 | 1 | 126 / SETASIDE |
| 6 | 1 | Time Twister Chromie | 35 | 2 | 0 | 154 / SETASIDE |
| 7 | 2 | Kith'ix | 31 | 3 | 0 | 89 / PLAY |
| 8 | 3 | Spelunker Holmes | 26 | 4 | 0 | 201 / SETASIDE |

The truncated file ends mid-recruit on BG turn 5, and the parser degrades cleanly: 3 blocks are left open, and the last row is taken from the end-of-file state. GameState is ahead of PTL at the cut: it already contains 10 more `TAG_CHANGE`s and 1 more `FULL_ENTITY`.

## Parse performance (naive Python baseline)

This is CPython 3.9.6 on an Apple M4, taking the median of 5 warm runs. Only PTL, `DebugPrintGame` and choice lines go to the store; other lines stop after the line regex.

| File | Read and decode | Entity store (PTL) | Store + BG derivation |
|---|---|---|---|
| Partial: 5.9 MB, 46 k lines | 4 ms | 66 ms (700 k lines/s, 91 MB/s) | 94 ms (490 k lines/s) |
| Full: 35.8 MB, 270 k lines | 25 ms | 401 ms (674 k lines/s, 89 MB/s) | 916 ms (295 k lines/s) |

The first cold run of the full file took about 0.9 s including disk. The derivation cost comes from rescanning every entity for the shop on each zone change, so it is O(entities) per event. A Swift implementation with a controller/zone index should stay close to the store number.

**Takeaway:** even naive Python replays a complete 12-turn game in under half a second. The live tail workload is trivial by comparison. Log volume per BG turn in the full game:

| BG turn | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MB | 0.79 | 0.77 | 1.56 | 1.48 | 1.92 | 2.82 | 3.75 | 3.71 | 3.78 | 4.16 | 5.67 | 5.12 |
| Lines | 5,991 | 5,873 | 11,820 | 11,267 | 14,761 | 21,370 | 28,017 | 27,675 | 27,795 | 31,729 | 42,886 | 37,820 |

About half the lines are GameState duplicates that the state reducer skips.

## Rules the Swift parser must implement

1. **Line split.** Split on `\n` only, keep a partial trailing line in a buffer, and decode UTF-8 lossily. Regex: `^([DWE]) (\S+) (.+?)\(\) - (.*)$`. The method may contain spaces and brackets, as in `PowerSpellController [taskListId=N].InitPowerSpell()`. Route by method prefix:
   - `PowerTaskList.DebugPrintPower` goes to the state reducer.
   - `GameState.DebugPrintGame` carries metadata and names.
   - `GameState.DebugPrintEntityChoices` / `DebugPrintEntitiesChosen` carry choices.
   - `PowerProcessor.EndCurrentTaskList` is the snapshot or coalescing boundary.
   - Drop everything else, including `GameState.DebugPrintPower`, unless you want the early result on purpose.
2. **Indentation-agnostic payload.** Strip leading spaces and the trailing spaces or `DEF CHANGE`. A line starting with `tag=` belongs to the current header; any other line clears the header.
3. **Entity refs:** `GameEntity`, then digits, then the bracket form (take `id` from the anchored tail regex and ignore the other fields), then a player name. Names map to the two Player entities: the local BattleTag comes from `DebugPrintGame PlayerID=<local>`, and **every other name is the other slot**. Bind new names on first sight, and record `(name, BACON_CURRENT_COMBAT_PLAYER_ID)` during combat for the opponent-name feature.
4. **Local player** = the Player whose `GameAccountId` ≠ `[hi=0 lo=0]`. The other slot has `BACON_DUMMY_PLAYER=1`. Never hard-code PlayerIDs 2/10.
5. **Tags:** accept a name or a number, and normalise to an Int through the generated enum with an `unknown(Int)` case. Values are an Int or an enum string (`ZONE`, `CARDTYPE`, `STATE`, `PLAYSTATE`, `STEP`, `CARDRACE`, …); store both forms.
6. **`CREATE_GAME` resets the store** but must keep the `DebugPrintGame` metadata already parsed from GameState.
7. **`FULL_ENTITY - Updating`** in PTL (never `Creating`) always carries a new ID. `SHOW_ENTITY` / `CHANGE_ENTITY` replace the `cardId` and apply the following `tag=` lines. `HIDE_ENTITY` only marks the entity hidden.
8. **Phase:** recruit = `TURN` odd. Combat setup = `TURN` even (with `BOARD_VISUAL_STATE=2` and `3533=1`). Combat live = `2022 1→0`. Combat visually over = `BOARD_VISUAL_STATE 2→1`. Treat missing tags as 0. Never infer Duos from 3533; use `GameType` or `BACON_DUO_TEAM_ID`.
9. **Board queries** always filter by `CONTROLLER` + `ZONE == PLAY` + `CARDTYPE`, and sort by `ZONE_POSITION`:
   - The shop is the slot's `MINION` and `BATTLEGROUND_SPELL` entities during recruit.
   - The opponent board is the slot's `MINION`s while `slot.BACON_CURRENT_COMBAT_PLAYER_ID != 0`.
   - The hand is `ZONE == HAND` for the local controller; spells there are `SPELL`.
10. **Lobby:** hero entities with `PLAYER_LEADERBOARD_PLACE`, **deduplicated by `PLAYER_ID`**. For the local player prefer `Player.HERO_ENTITY`; for opponents prefer the non-combat copy (SETASIDE, has place). HP = `HEALTH − DAMAGE + ARMOR`, and dead = HP ≤ 0. Next opponent = the lobby hero whose `PLAYER_ID == local.NEXT_OPPONENT_PLAYER_ID`.
11. **Last-seen opponent boards:** snapshot at `2022 1→0`, keyed by `slot.BACON_CURRENT_COMBAT_PLAYER_ID`, and keep the card ID, stats, keywords and golden flag, not the entity ID.
12. **Game end:** on `GameEntity STATE=COMPLETE`, read the final place from `Player.HERO_ENTITY`'s `PLAYER_LEADERBOARD_PLACE` (it is written in the same batch). Local `PLAYSTATE` LOST/WON is authoritative. Ignore `PLAYSTATE` on the bartender slot.
13. **Coalescing:** emit snapshots at `PowerProcessor.EndCurrentTaskList`, so shop buffs and multi-line entity creation settle first.
14. **Truncation or mid-game attach:** tolerate open blocks at EOF. A game with no `STATE=COMPLETE` is "in progress or truncated". Replay from the last `CREATE_GAME`.

## Not tested here
Duos (`GT_BATTLEGROUNDS_DUO*`, `BACON_DUO_TEAM_ID`), reconnects or a second `CREATE_GAME`, concede (tag 3479, never seen), anomalies, midnight rollover, and corrupt-byte lines. We need a Duos capture and a reconnect capture before relying on those paths.
