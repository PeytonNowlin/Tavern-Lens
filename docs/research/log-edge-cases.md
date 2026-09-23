# Battlegrounds log edge cases: Duos, concede, reconnect, anomalies, rollover, spectating, catch-up (2026-09-22)

Research only, no app code. This note designs the Swift parser for scenarios we have **not captured locally**. It follows [logs-and-extractable-state.md](logs-and-extractable-state.md) and [log-validation-2026-09-22.md](log-validation-2026-09-22.md).

Evidence comes from four places:
1. Tracker source code at pinned commits.
2. Public CC0 test data. **HearthSim/hsreplay-test-data** has real BG Duos games, but only as annotated HSReplay XML converted from Power.log. It has no raw Duos Power.log.
3. Our two local solo captures (build 251952, client 36.6.0). They were read-only, and the `GameNetLogger.log` / `Hearthstone.log` / `LoadingScreen.log` next to them were checked too.
4. Blizzard patch notes.

Each claim is marked with a confidence tag:
- **[seen]**: seen in a real log or XML.
- **[code]**: taken from tracker code.
- **[inferred]**: reasoned from the above. Needs a capture.

Redactions: BattleTags are shown as `<BattleTag>`, the bartender slot's placeholder name as `<SlotName>`, and GameAccountId hi/lo as `<HI>/<LO>`. Server IP, `client=` handle and `spectateKey=` are shown as `<IP>`, `<CLIENT>` and `<KEY>`.

## Pinned sources

| Repo | Commit | Licence / use |
|---|---|---|
| HearthSim/HSTracker | `c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4` | MIT |
| HearthSim/Hearthstone-Deck-Tracker (HDT) | `ef8ab6e8380a647d757eec203d310395d6b97ae0` | reference only |
| Zero-to-Heroes/firestone | `0a30f066eb77a417637d95cec86444456f607ba1` | reference only (unlicensed) |
| Zero-to-Heroes/hs-game-converter-csharp-port (Firestone's C# Power.log parser) | `6586ae1bb07443ecc47d2683d114a65bdfed1b00` | MIT |
| HearthSim/python-hslog | `015c0dec197779c90cd3131ecda2c990292342b6` | MIT |
| HearthSim/python-hearthstone | `637eaa29c911d6b3000349713b8847b035205fb7` | MIT |
| HearthSim/hsreplay-test-data | `715d408e7047abdbde519313593f1be603916bec` | CC0. No git LFS (`.gitattributes` has only linguist rules) |

URL shorthands:
- `HST/` = `https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/`
- `HDT/` = `https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/`
- `FS/` = `https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/`
- `FSC/` = `https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/`
- `HSLOG/` = `https://github.com/HearthSim/python-hslog/blob/015c0dec197779c90cd3131ecda2c990292342b6/`
- `PYHS/` = `https://github.com/HearthSim/python-hearthstone/blob/637eaa29c911d6b3000349713b8847b035205fb7/`
- `TD/` = `https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/`

Tag IDs used below (from `PYHS/hearthstone/enums.py`):

| Tag | ID |
|---|---|
| `PLAYSTATE` | 17 |
| `STATE` | 204 |
| `STEP` | 19 |
| `HERO_ENTITY` | 27 |
| `TEAM_ID` | 31 |
| `NEXT_OPPONENT_PLAYER_ID` | 1360 |
| `PLAYER_LEADERBOARD_PLACE` | 1373 |
| `GAME_SEED` | 2042 |
| `BACON_GLOBAL_ANOMALY_DBID` | 2897 |
| `BACON_DUO_TEAMMATE_PLAYER_ID` | 2939 |
| `BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT` | 2975 |
| `NEXT_OPPONENT_TEAMMATE_PLAYER_ID` | 2988 |
| `BACON_CURRENT_COMBAT_PLAYER_ID` | 2989 |
| `BACON_COMBAT_PHASE_HERO` | 3048 |
| `BACON_DUO_TEAM_ID` | 3095 |
| `BACON_DUO_PASSABLE` | 3178 |
| `IS_USING_PASS_OPTION` | 3185 |
| `BACON_DUOS_PUNISH_LEAVERS` | 3494 |
| `TAG_PLAYER_CONCEDED_OR_DISCONNECTED` | 3479 |
| `BG_BATTLE_STARTING` | 2022 |

Notes on the table:
- 3479 is named in FSC `Enums.cs#L1244` but not in python-hearthstone.
- 2022 is named in FSC; the client prints it as `tag=2022`.
- Tag 3533 has no name anywhere.
- `PlayState`: `DISCONNECTED = 7`, `CONCEDED = 8`.

---

## 1. Duos

**Source:** the only real Duos data found anywhere is [`TD/hsreplaynet-tests/replays/battlegrounds_duos.annotated.xml`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/hsreplaynet-tests/replays/battlegrounds_duos.annotated.xml). It is 26 MB, build 198314 (2024-05-07), `<Game type="37">` = `GT_BATTLEGROUNDS_DUO`, and ends in 1st place. A second file, `battlegrounds_duos_trinkets.annotated.xml` (build 206605, 2024-09-10), ends in 4th. XML line numbers are cited as `duos.xml:L`. In the XML, a `TagChange`/`FullEntity` is the same packet as a Power.log `TAG_CHANGE`/`FULL_ENTITY`. The XML is built from the GameState stream, so the relative order holds, but PTL timing does not.

**GitHub search:** `gh search code` for `GT_BATTLEGROUNDS_DUO`, `BACON_DUO_TEAMMATE_PLAYER_ID` and `BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT` returns only enum and source files. The only `.log` fixtures with `BACON_DUO_TEAM_ID` (ZGarry/battlegrounds-vision-agent) are hand-written and synthetic. I searched about 18 HSTracker/HDT/Firestone issues about Duos, reconnect, spectate and concede; none had a log attachment.

### 1.1 Game type and detection
- `GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS_DUO` (37). The variants are `_VS_AI` 38, `_FRIENDLY` 39, `_AI_VS_AI` 40 and `_1_PLAYER_VS_AI` 41 ([PYHS enums.py#L2018-L2022](https://github.com/HearthSim/python-hearthstone/blob/637eaa29c911d6b3000349713b8847b035205fb7/hearthstone/enums.py#L2018)). **[code]**
- Two of the trackers leave out some variants:
  - HSTracker's `isBattlegroundsDuosMatch` covers only 37–40, so it omits 41 ([HST Game.swift#L2756-L2758](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L2756)).
  - Firestone's C# duo checks cover 37–40 in some places and only 37/39 in others ([FSC ParserState.cs#L488-L496](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/ParserState.cs#L488)).
  - **We treat all of 37–41 as Duos.**
- Cross-check with a Player entity that has `BACON_DUO_TEAM_ID > 0`. HDT/HSTracker use this only to fix a memory misread ([HDT GameV2.cs#L293-L318](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/GameV2.cs#L293)). For us the log GameType is authoritative, and team ID is a sanity check. **[code]**
- `BACON_DUOS_PUNISH_LEAVERS=1` is set on the GameEntity in **solo** games too (our 36.6 capture, `CREATE_GAME` line 30). **It is not a Duos signal.** **[seen]**
- Tag 3533 toggles in solo too (validation doc correction 1), so it is not a Duos signal either.

### 1.2 Entities: still two Player entities
**[seen]** `duos.xml:L32-L62`, `L63`:
```
<Player id="8" playerID="3" accountHi=<HI> accountLo=<LO> name="<BattleTag>">
  TEAM_ID(31)=3  HERO_ENTITY=29  NEXT_OPPONENT_PLAYER_ID=7
  BACON_DUO_TEAMMATE_PLAYER_ID(2939)=4
  BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT(2975)=1
  NEXT_OPPONENT_TEAMMATE_PLAYER_ID(2988)=8
  BACON_DUO_TEAM_ID(3095)=1
<Player id="9" playerID="11" accountHi="0" accountLo="0" name="<SlotName>">   (BACON_DUMMY_PLAYER=1)
```
- **There is no Player entity for the teammate.** The teammate (PlayerID 4) exists only as a lobby hero, like the opponents. The same holds in the trinkets game (local PlayerID 2, dummy PlayerID 10).
- So these solo rules carry over unchanged:
  - local = the Player with a non-zero GameAccountId;
  - the other slot is Bob, then the combat opponent;
  - the dummy PlayerID is local + 8.
- In Duos, `TEAM_ID` (31) on the Player equals the PlayerID. It is not the Duos team; use `BACON_DUO_TEAM_ID` (3095).

**Heroes [seen]:**
- The 7 non-local lobby heroes are `CONTROLLER=<dummy>` in SETASIDE. Each has `PLAYER_ID` and `BACON_DUO_TEAM_ID`, with values 4,3,2,4,3,2,1: two heroes for each opposing team, plus the teammate's hero on team 1.
- Teammate hero: `duos.xml:L763` ent 202 `TB_BaconShop_HERO_58`, `PLAYER_ID=4`, `BACON_DUO_TEAM_ID=1`.
- **The local hero entity has no `BACON_DUO_TEAM_ID`.** Take the local team from the Player entity. HDT's overlay compares a hero's team ID to `PlayerEntity`'s ([HDT OverlayWindow.Update.cs#L446-L454](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Windows/OverlayWindow.Update.cs#L446)).

### 1.3 Leaderboard: 4 teams, placement 1–4
- `PLAYER_LEADERBOARD_PLACE` is on 8 heroes, but it is the **team** place (1–4). Both teammates carry the same value. **[seen]**
  - Mid-game: `duos.xml:L182261-L182264` shows hero 80 (local) = 2, 185 = 3, 140 = 3, 202 (teammate) = 2.
  - Final: `L232101-L232104` shows 80 = 1, 202 = 1, 127 = 2, 172 = 2.
- **Leaderboard row** (1–8) is `PLAYER_LEADERBOARD_PLACE * 2 − BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT` on the hero. Firestone uses this formula for Duos ([FSC FullEntity.cs#L223-L230](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/ReplayData/Entities/FullEntity.cs#L223); [LocalPlayerLeaderboardPlaceChangedParser.cs#L24-L72](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/LocalPlayerLeaderboardPlaceChangedParser.cs#L24)). It also re-emits on changes to *either* tag. **[code]**
- Final placement: HSTracker caps it at 4 for Duos (`min(place, duos ? 4 : 8)`, [HST Game.swift#L2485-L2492](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L2485)). **[code]**
- End of game: dummy `PLAYSTATE=LOST`, local `PLAYSTATE=WON`, then `GameEntity STATE=COMPLETE` (`duos.xml:L262047-L262070`). In the trinkets game (4th place) it is local LOST, dummy WON, then COMPLETE. As in solo, the dummy's PLAYSTATE cycles LOSING/PLAYING whenever a team is knocked out. **[seen]**

### 1.4 Combat order: two sequential fights in one combat
**[seen]** This is the order of events in the first combat turn of `duos.xml` (XML lines, entity 7 = GameEntity, 8 = local Player, 9 = dummy):

| Line | Event | Meaning |
|---|---|---|
| 1947 | `3533 → 1` | combat setup, fight A |
| 2295 | `2022 → 1` | |
| 2297 / 2298 | `8.BACON_CURRENT_COMBAT_PLAYER_ID=3`, `9.…=7` | local (P3) vs opponent P7 |
| 2358 | `9.HERO_ENTITY=581` | opponent hero copy |
| 2468 | `3533 → 0` | **snapshot fight A** |
| 2499 | `2022 → 0` | combat live (fires once per combat) |
| 2730 | `3533 → 1` | setup, fight B |
| 2732 | `SUB_SPELL ReuseFX_Generic_OverrideSpawn_FromPortal_Super_Random_SuppressPlaySounds` | **teammate swap-in animation** |
| 2760–2792 | `FULL_ENTITY 634 TB_BaconShop_HERO_58 CONTROLLER=3 ZONE=PLAY`, `PLAYER_ID=4`, `COPIED_FROM_ENTITY_ID=466`, `LINKED_ENTITY=80`, then `8.HERO_ENTITY=634`, `634.BACON_COMBAT_PHASE_HERO=1` | **the local Player slot now fights with the teammate's hero and board** |
| 2990 | `9.HERO_ENTITY=638` | opponent's teammate swaps in |
| 3091 / 3092 | `8.BACON_CURRENT_COMBAT_PLAYER_ID=4`, `9.…=8` | P4 (teammate) vs P8 |
| 3117 | `3533 → 0` | **snapshot fight B** |
| 3461 | `8.HERO_ENTITY=80` | local hero restored after combat |

Rules that follow:
- **Fight boundaries are 3533 1→0 edges, not 2022.** In Duos, 2022 toggles once per combat and 3533 once per fight. That is 94 changes of 3533 over the game.
- **During fight B, "controller == local && ZONE=PLAY" is the teammate's board.**
  - The board owner is `local.BACON_CURRENT_COMBAT_PLAYER_ID`.
  - The opponent owner is `dummy.BACON_CURRENT_COMBAT_PLAYER_ID`.
  - Key every board snapshot by that PlayerID, never by "mine/theirs".
- A side swaps only if its first fighter is knocked out, so a combat may have one swap, two or none. HDT/HSTracker record each swap with `HERO_ENTITY` changes on the local or dummy Player (`DuosSetHeroModified`). Both reset on 3533 0→1. They snapshot the opponent board on 3533 1→0 only if the opponent hero was swapped, or if it is solo:
  - HDT: [TagChangeActions.cs#L230-L275](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/TagChangeActions.cs#L230)
  - HSTracker: [TagChangeActions.swift#L160-L210](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Parsers/TagChangeActions.swift#L160)
  - HDT's `BattlegroundsBoardState` keys snapshots by the opposing hero's `PLAYER_ID` ([BattlegroundsBoardState.cs#L19-L42](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/BattlegroundsBoardState.cs#L19)). **[code]**
- Firestone detects the swap from the `OverrideSpawn_FromPortal` sub-spell while `BOARD_VISUAL_STATE == 2` ([FSC BattlegroundsDuoTeammatePlayerBoardParser .cs#L30-L37](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/BattlegroundsDuoTeammatePlayerBoardParser%20.cs#L30)). We prefer `BACON_CURRENT_COMBAT_PLAYER_ID` changes, because the sub-spell prefab is cosmetic and can be renamed. **[code]**
- BobsBuddy in Duos starts on 3533 1→0. It waits for both teammates to be snapshotted, and runs a partial simulation when a hero attacks before the teammates are known (`MaybeRunDuosPartialCombat`, [HDT BobsBuddyInvoker.cs#L195-L300](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs#L195), [#L917-L950](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs#L917)). **[code]**

### 1.5 `BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT` (2975)
- Values are 0/1 only. It is set on the local Player, on the local hero and on every lobby hero (16 changes each).
- It flips at `MAIN_CLEANUP` of the recruit turn (`duos.xml:L3957-L3963`): player 8 → 0, hero 80 → 0, teammate hero 202 → 1. So it tells you **which teammate fights first in the next combat**, and it is known during recruit.
- It is also the tiebreak for the leaderboard row (§1.3). **[seen]**
- `NEXT_OPPONENT_TEAMMATE_PLAYER_ID` (2988) on the Player gives the second opponent of the next combat, next to `NEXT_OPPONENT_PLAYER_ID`. **[seen]**

### 1.6 Passing a card to the teammate
**[seen]** A pass is a `BlockType=DECK_ACTION` (type 13) block. There are 10 in the game. Example at `duos.xml:L54460-L54490`:
```
SendOption option=4 target=7935
BLOCK_START BlockType=DECK_ACTION Entity=[Tough Tusk id=7935 …]
  TAG_CHANGE <local Player> RESOURCES_USED=10          ← the pass costs gold
  TAG_CHANGE 7935 IS_USING_PASS_OPTION(3185)=1
  BLOCK_START BlockType=POWER (TB_BaconShop_DragBuy)
    FULL_ENTITY 8500 BG20_102 CONTROLLER=<local> ZONE=SETASIDE COPIED_FROM_ENTITY_ID=7935
    TAG_CHANGE 7935 ZONE=SETASIDE ; TRANSIENT_ENTITY=1
    TAG_CHANGE 202 (teammate hero) PLAYER_TRIPLES=2      ← teammate-side effects visible on their lobby hero
TAG_CHANGE 7935 IS_USING_PASS_OPTION=0
```
- `BACON_DUO_PASSABLE` (3178) toggles 0/1 on hand and shop cards: 844 set to 1 and 774 set to 0. It is a "can pass now" flag, **not** a pass event.
- Parser rule: **a hand card leaving HAND inside a `DECK_ACTION` block with `IS_USING_PASS_OPTION=1` is a pass.** It is not a sell or a play: exclude it from "cards played" counters and remove it from the local hand.
- **A card received from the teammate** has not been observed. It probably arrives as a `FULL_ENTITY` in the local HAND with `CREATOR` or `COPIED_FROM_ENTITY_ID` pointing at an entity we never saw. **[inferred]** Capture wanted.

### 1.7 Logs-only vs memory-only in Duos

| Data | Source |
|---|---|
| Team IDs, teammate PlayerID, teammate hero (card, HP, tier, triples, place) | **LOG** (lobby hero entity) |
| Who fights first next combat, next opponent pair | **LOG** (2975, 1360, 2988) |
| Teammate's board and hand **during recruit** | **MEM** only: HDT `GetBattlegroundsTeammateBoardState()` via `BattlegroundsTeammateBoardStateWatcher` ([HDT Watchers.cs#L377-L390, #L525-L529](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/Watchers.cs#L377)); Firestone `getBgsPlayerTeammateBoard()` |
| Teammate's board **at the fight where they swap in** | **LOG**: under the local controller while `local.BACON_CURRENT_COMBAT_PLAYER_ID == teammate` (§1.4) |
| Opponents' teammate boards | **LOG**, only when that opponent swaps in against us |
| Whether the user is currently viewing the teammate's board | **MEM** (`IsViewingTeammate`) |
| Cards passed by us | **LOG** (§1.6) |
| Cards passed to us | **LOG** probably (§1.6, inferred) |

---

## 2. Concede and leaving

### 2.1 Signatures
- **Constructed concede [seen]**, from [`TD/data/concede_mulligan_13740.log#L918-L926`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/data/concede_mulligan_13740.log#L918):
  ```
  D 22:02:07.5124967 GameState.DebugPrintPower() - TAG_CHANGE Entity=<BattleTag> tag=PLAYSTATE value=CONCEDED
  D 22:02:07.5124967 GameState.DebugPrintPower() - TAG_CHANGE Entity=<BattleTag> tag=PLAYSTATE value=LOST
  D 22:02:07.5124967 GameState.DebugPrintPower() - TAG_CHANGE Entity=<Opponent> tag=PLAYSTATE value=WON
  D 22:02:07.5124967 GameState.DebugPrintPower() - TAG_CHANGE Entity=GameEntity tag=STEP value=FINAL_WRAPUP
  ```
- **BG concede: no sample exists anywhere.** Tag 3479 and `TAG_PLAYER_CONCEDED_OR_DISCONNECTED` appear in none of the 102 test-data logs, the Duos XMLs or our captures. The trackers agree on the signature **[code]**:
  - HDT: `(GameTag)3479 //TAG_PLAYER_CONCEDED_OR_DISCONNECTED` → `BGsConcededChange` → `HandleConcede()` when value == 1. It **does not check which entity** ([TagChangeActions.cs#L45-L46, #L1188-L1198](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/TagChangeActions.cs#L1188)). `PLAYSTATE=CONCEDED` also calls `HandleConcede`, which only sets `WasConceded` ([GameEventHandler.cs#L301-L305](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L301)).
  - HSTracker: the same logic, `.gametag_3479` → `bgsConcededChange` ([TagChangeActions.swift#L31-L32, #L993-L1003](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Parsers/TagChangeActions.swift#L993)).
  - **Firestone treats local 3479=1 as GAME END in BG.** `GameEndParser` fires on `STATE=COMPLETE` **or** (`IsBattlegrounds() && tag 3479 == 1`), but only if `tagChange.Entity == LocalPlayer.Id` ([FSC GameEndParser.cs#L24-L50](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/GameEndParser.cs#L24)). `WinnerParser` then makes the opponent the winner ([WinnerParser.cs#L24-L105](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/WinnerParser.cs#L24)).
  - Firestone's catch-up treats `tag=TAG_PLAYER_CONCEDED_OR_DISCONNECTED value=1` as "game finished, discard", just like `STATE=COMPLETE` ([FS game-events.service.ts#L1830-L1839](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1830)).
  - Firestone string-matches the **named** form. On our client, unnamed tags print as numbers, so we must match both `tag=3479` and the name. Tag normalisation to Int handles this.

### 2.2 STATE=COMPLETE timing
- **Normal BG game end (solo, [seen] in our capture):**
  1. The local hero's HP drops to 0 or below.
  2. `PLAYSTATE` PLAYING → LOSING → LOST, and the slot → WON.
  3. `PLAYER_LEADERBOARD_PLACE` final on `Player.HERO_ENTITY`, then `STATE=COMPLETE`, in the same PTL batch.
  4. In GameState all of this arrives about 45 s earlier (validation doc).
  5. `GameNetLogger`/`Hearthstone.log`: `Network.DisconnectFromGameServer() - Reason: EndGameScreen` at 21:33:19.99.
  6. LoadingScreen: `Gameplay.OnDestroy()` about 20 s after the PTL COMPLETE, then `prevMode=GAMEPLAY … currMode=BACON`.
- **Events can follow STATE=COMPLETE.** In [`TD/hsreplaynet-tests/replays/battlegrounds_async_gameover.annotated.xml`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/hsreplaynet-tests/replays/battlegrounds_async_gameover.annotated.xml):
  - LOST/WON are at L90259-L90260, `STEP=FINAL_WRAPUP` follows, and `STATE=COMPLETE` is at L93223.
  - About 1,900 more lines of blocks (`ARTIFICIAL_PAUSE`) follow COMPLETE.
  - Don't treat COMPLETE as end of input; keep consuming until the next `CREATE_GAME` or the end of the file. **[seen]**
- **When you concede, the game keeps running for the other players, so your client may never log `STATE=COMPLETE` for it.** **[inferred]** from Firestone ending on 3479 and HDT's fallbacks. HDT copes as follows:
  - `LogIsComplete()` waits up to about 5.5 s for `STATE=COMPLETE` ([GameEventHandler.cs#L224-L240](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L224)).
  - Leaving GAMEPLAY in LoadingScreen forces `HandleInMenu()`, which calls `HandleGameEnd(false)` when the game end was not handled ([LoadingScreenHandler.cs#L90-L91](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/LoadingScreenHandler.cs#L90); [GameEventHandler.cs#L96-L108](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L96)). **[code]**

### 2.3 Placement when conceding or leaving
- There is no sample. Observed client behaviour (not verified here) is that a BG concede gives you the lowest remaining place. The log should reflect that on the local hero's `PLAYER_LEADERBOARD_PLACE` around the 3479 change, but it may be **absent** if the client disconnects first. **[inferred]**
- Rule:
  - Take `Player.HERO_ENTITY.PLAYER_LEADERBOARD_PLACE` as of the last PTL batch before the game closes.
  - If it was not updated after the concede, use `1 + count(heroes still alive with a better place)`. Alive means HP > 0 and not yet placed.
  - Mark the result `placementSource = .concedeEstimate`.
  - In Duos, the team place is what counts, and `BACON_DUOS_PUNISH_LEAVERS` may change it. Unknown.
- **Leaving without conceding** (quit, crash or network loss): the game continues server-side, and the hero keeps fighting with auto-ended turns **[inferred]**. The log just stops. If the user reconnects, §3 applies. If not, the game stays `inProgress` until the next `CREATE_GAME` with a different seed or an HS restart, and is then recorded as `abandoned` with no placement. Only memory reading or the post-game rating screen could give the true result (HDT `GetBaconRatingChangeData`).

---

## 3. Reconnect

A reconnect happens in one of two ways:
- **(a) in-client:** a network drop, where the client reconnects without restarting.
- **(b) restart:** the user quits and reopens HS mid-game. HS creates a **new** `Logs/Hearthstone_<ts>/` folder at every launch (§8), so the pre-restart history is in the previous folder.

### 3.1 What the new log looks like
- **Full-state `CREATE_GAME` resend [seen]**, from [`TD/data/reconnect.log`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/data/reconnect.log). It is a constructed game, PTL-only, and has 3 `CREATE_GAME`s at lines 1, 524 and 1502:
  ```
  1501 D 18:23:37.4578930 PowerTaskList.DebugPrintPower() - BLOCK_END
  1502 D 18:24:01.5632550 PowerTaskList.DebugPrintPower() -     CREATE_GAME
  1503 D 18:24:01.5632850 PowerTaskList.DebugPrintPower() -         GameEntity EntityID=1
  1504 …             tag=10 value=85
  1505 …             tag=STEP value=MAIN_ACTION
  1506 …             tag=TURN value=6
  1510 …             tag=STATE value=RUNNING
  1511 …         Player EntityID=2 PlayerID=1 GameAccountId=redacted
  ```
  - Nothing marks the break: the preceding line is an ordinary `BLOCK_END`, followed by a 24 s gap.
  - **Entity IDs are preserved.** GameEntity is 1, the Players are 2 and 3, `HERO_ENTITY` stays 66.
  - Every live entity is re-sent as `FULL_ENTITY - Updating` with its current tags (66, 67 and 74 FULL_ENTITYs before the first TAG_CHANGE/BLOCK in each section).
  - Timestamps just continue.
- **BG reconnect [seen, XML only]**, from [`TD/hsreplaynet-tests/replays/battlegrounds_reconnect.annotated.xml`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/hsreplaynet-tests/replays/battlegrounds_reconnect.annotated.xml) (2020):
  - The game starts at `STATE=RUNNING`, `TURN=13`, GameEntity id 10, with 514 FullEntity elements.
  - It has one real Player and Bob (`accountHi=0 accountLo=0`, named after the bartender skin).
  - So the post-reconnect `CREATE_GAME` carries the whole lobby (every hero with place, HP and tier), the current shop or board, and the hand. **History is not included:** no previous boards, no earlier choices, and no opponent names beyond the current combat.
- **The mulligan is skipped.** python-hslog notes that in "spectator mode, reconnects" the mulligan phase is not available ([HSLOG parser.py#L550-L555](https://github.com/HearthSim/python-hslog/blob/015c0dec197779c90cd3131ecda2c990292342b6/hslog/parser.py#L550)). So hero choice lines are missing after a restart, and the picked hero is simply `HERO_ENTITY`. HDT re-snapshots the hero pick on reconnect for exactly this reason ([GameEventHandler.cs#L760-L768](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L760)). **[code]**
- **`DebugPrintGame` re-emitted?** Probably yes, since it is printed on every GameState `CREATE_GAME` **[inferred]**. The only raw reconnect sample is PTL-filtered. Firestone's C# `CreatePlayerHandler` skips re-parsing Player lines "while reconnecting", which implies they are re-sent ([FSC CreatePlayerHandler.cs#L20-L21](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/Handlers/DataHandler/CreatePlayerHandler.cs#L20)). The parser must not rely on it: keep the previous metadata when the seed matches.

### 3.2 Side-channel signatures
- **LoadingScreen.log [code + partial seen]:** `MulliganManager.HandleGameStart() - IsPastBeginPhase()=True` marks a reconnect or a join after the mulligan. A normal start prints `IsPastBeginPhase()=False`, as seen in our capture (`LoadingScreen.log`, 20:34:33.15).
  - HDT: this line calls `BobsBuddyInvoker.OnGameReconnect()` and `HandleGameReconnect` ([LoadingScreenHandler.cs#L153-L161](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/LoadingScreenHandler.cs#L153)).
  - HSTracker does the same ([LoadingScreenHandler.swift#L145-L150](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Handlers/LoadingScreenHandler.swift#L145)).
  - `Gameplay.Start()` also precedes it (restart case), and both trackers **reset** their game on `Gameplay.Start`.
- **GameNetLogger.log / Hearthstone.log [seen field names; reconnect values inferred]:**
  ```
  I 21:09:23.0442390 Network.GotoGameServe() - gameConnectionDisconnected True, IsRestoringGameState: False
  I 21:09:23.0442390 Network.GotoGameServe() - address= <IP>:1119, game=668, client=<CLIENT>, spectateKey=<KEY> reconnecting=False
  I 21:09:38.0444370 GameMgr.OnGameSetup()
  I 21:33:19.9868370 Network.DisconnectFromGameServer() - Reason: EndGameScreen
  ```
  - On a reconnect we expect `reconnecting=True` and `IsRestoringGameState: True`, with the **same `game=` handle and address**. HDT keys its (unused) stored-log mechanism on this `GameHandle` from memory ([GameV2.cs#L507-L519](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/GameV2.cs#L507); `StoreGameState()` has **no callers** at this commit).
  - `game=` is a small per-server number (577 and 668 in our two sessions), so it is only unique **together with `address`**.
  - `GameNetLogger.log` is written without any `log.config` section. The same lines are mirrored into `Hearthstone.log` with a `[GameNetLogger]` prefix.
  - Firestone reads `Network.GotoGameServe.*address=` for its reconnector ([FS hs-logs-watcher.service.ts#L4](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/app/common/src/lib/services/logs/hs-logs-watcher.service.ts#L4)).
  - `spectateKey` is a join secret. **Never store or display it.**

### 3.3 How the trackers handle it
- **HDT [code]:**
  - `HandleGameReconnect` waits for GameEntity and GAMEPLAY mode. If `STEP > BEGIN_MULLIGAN` it sets `CurrentGameStats.IsReconnect`, restarts the memory watchers, and re-snapshots the hero pick ([GameEventHandler.cs#L719-L776](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L719)).
  - `ShouldSuppressLog = IsBattlegroundsMatch && IsReconnect` only logs "Reconnected Battlegrounds game detected; this log will likely be invalid." The upload still goes through `LogValidator` ([#L94, #L193-L215](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L193)).
  - The upload log is cut at the **second** `CREATE_GAME` (`TakeWhile(!(CREATE_GAME && count++ == 1))`). The first is the GameState copy and the second the PTL copy of the same game, so this drops any later reconnect section.
  - BobsBuddy discards a combat if `_reconnectCounter` changed since the snapshot ([BobsBuddyInvoker.cs#L76-L79](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs#L76)).
  - The last-seen opponent boards (`BattlegroundsBoardState`) are cleared by `GameV2.Reset()`, which runs on every `Gameplay.Start` ([GameV2.cs#L461-L486](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/GameV2.cs#L461)). **So HDT loses opponent history across a restart-reconnect.**
  - "Game was already in progress." sets `WasInProgress` when `STEP` changes before setup ([TagChangeActions.cs#L749-L766](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/TagChangeActions.cs#L749)).
  - `PowerHandler` simply `Reset()`s on any `CREATE_GAME` ([PowerHandler.cs#L1780-L1781](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/PowerHandler.cs#L1780)).
- **HSTracker [code]:** a direct port of the above. It has `handleGameReconnect` / `isReconnect` / `shouldSuppressLog` ([Game.swift#L1218-L1221, #L2008-L2046](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L2008)) and resets on `CREATE_GAME` ([PowerGameStateParser.swift#L1544-L1546](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Parsers/PowerGameStateParser.swift#L1544)).
- **Firestone [code]:** the best model for us, because it **keeps history**.
  - A new `CREATE_GAME` counts as a reconnect when the GameEntity's `GAME_SEED` equals the current game's seed (`IsReconnecting(seed)`, [FSC ParserState.cs#L525-L533](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/ParserState.cs#L525)). The seed is pre-extracted from the chunk because it follows the `CREATE_GAME` line ([ReplayParser.cs#L84-L90, #L494-L530](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/ReplayParser.cs#L494)).
  - On a reconnect it does **not** reset. It moves every known entity to `REMOVEDFROMGAME`, **deletes all MINION entities** in BG (they are all recreated anyway), sets `ReconnectionOngoing`, clears `Spectating`, and emits `RECONNECT_START` ([FSC NewGameHandler.cs#L27-L73](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/Handlers/DataHandler/NewGameHandler.cs#L27)).
  - The app then clears only the opponent's current board and `duoPendingBoards`, and keeps the rest of `bgState` ([FS reconnect-start-parser.ts#L11-L29](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/event-parser/reconnect-start-parser.ts#L11)).
  - Its catch-up deliberately does **not** drop lines before a later `CREATE_GAME`: "Don't do this, as it breaks reconnects" ([game-events.service.ts#L1814-L1818](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1814)).
  - Board parsers require `NUM_TURNS_IN_PLAY <= 1` on opponent minions to drop "reconnect artefacts", and note "When reconnecting, sometimes we have multiple heroes in play" ([FSC BattlegroundsPlayerBoardParser.cs#L172, #L230](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/BattlegroundsPlayerBoardParser.cs#L172)).
- **Our capture confirms `GAME_SEED` is in `CREATE_GAME` [seen]:** `GameState.DebugPrintPower() -         tag=GAME_SEED value=<n>` on the GameEntity (line 20 of the full capture, before any Player line). **Also [seen]:** the GameEntity's `EntityID` was **4** in one session and **16** in the other, so never hard-code it.

### 3.4 Stitching rule for us
1. **Game identity** = `GAME_SEED` (GameEntity, inside `CREATE_GAME`). The secondary key is `(server address, game handle)` from `GotoGameServe`. It is always stored hashed, and it is cross-checked when both sessions are readable.
2. **Seed matches an open game** (in-client reconnect in the same Power.log, or restart where we still hold the pre-restart game in memory or on disk):
   - Keep the game record: opponent name map, last-seen boards per PlayerID, hero pick, choices, per-turn timeline.
   - Clear the entity store and rebuild it from the resent full state; entity IDs are preserved, but do not depend on that.
   - Mark the game `reconnected = true` and record the gap (last line before, first line after).
   - Discard any combat whose start snapshot is before the reconnect.
   - Re-derive the current turn and phase from `TURN` and `BOARD_VISUAL_STATE`.
3. **Restart with no in-memory state** (app also restarted): look in the previous `Logs/Hearthstone_*` folder, the newest older than the current one. Take its **last** `CREATE_GAME` with the same `GAME_SEED` and no `STATE=COMPLETE` after it, replay it with UI suppressed (§7) to rebuild history, then continue in the new folder. Our own persisted per-game journal, keyed by seed, is the preferred source, because HS folder retention is not guaranteed (§8).
4. **The seed differs:** it is a new game. Close the old one as `abandoned` if it never completed.
5. An `IsPastBeginPhase()=True` LoadingScreen line without a matching seed (for example when LoadingScreen is read before Power) sets `expectReconnect` for the next `CREATE_GAME`. Only the seed decides.

---

## 4. Anomaly games

- **Signature [code]:** GameEntity `BACON_GLOBAL_ANOMALY_DBID` (2897) = the anomaly card's dbfId, sent in `CREATE_GAME`; 0 or absent means none.
  - HDT reads it ([BattlegroundsUtils.cs#L95-L101](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/BattlegroundsUtils.cs#L95)) and passes it to BobsBuddy as `input.Anomaly` ([BobsBuddyInvoker.cs#L957-L960](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs#L957)).
  - HSTracker reads it at [Game.swift#L2213](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L2213). Firestone's C# reads it in `BattlegroundsTavernPrizesParser`.
  - The anomaly card has `CARDTYPE=BATTLEGROUND_ANOMALY` (43); there are 112 such cards in the HearthstoneJSON data.
  - Constructed-mode anomalies are different tags (`ANOMALY1`/`ANOMALY2` = 3182/3183) and must not be confused with this one (`TD/hsreplaynet-tests/replays/anomalies.185749.annotated.xml`).
- **Effects that change what the parser or UI assumes** (HDT `GetAvailableTiers`, [BattlegroundsUtils.cs#L81-L93](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/BattlegroundsUtils.cs#L81)):

  | Anomaly | Available tiers |
  |---|---|
  | Big League | {3,4,5,6} |
  | How to Even | {2,4,6} |
  | Little League | {1,2,3,4} |
  | Secrets of Norgannon | {1..7}, tier 7 |
  | Valuation Inflation | {2..6} |
  | What Are the Odds | {1,3,5} |

  Other anomalies change starting gold or HP, shop size, free refreshes and so on. They show up **as ordinary tags** (`RESOURCES`, gold cap tag 3148, `BACON_MAX_PLAYER_TECH_LEVEL`, hero `HEALTH`). So a tag-driven parser needs no per-anomaly code, but UI assumptions do:
  - no hard-coded max tier of 6: use `BACON_MAX_PLAYER_TECH_LEVEL`, which was `6` in our capture's Player entity;
  - no gold cap of 10: use tag 3148;
  - no start HP of 30 or 40.

  `Bring in the Buddies` enables buddies. HDT flags `CurrentCombatMayHaveOpponentMalorne` for it ([BobsBuddyInvoker.cs#L973](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs#L973)).
- **Are anomalies active in 36.6.1?**
  - Blizzard removed anomalies at the start of Season 13 (April 2026) ([Blizzard, Season 13 announcement](https://news.blizzard.com/en-us/article/24244885/announcing-battlegrounds-season-13-cataclysm-calls)), and brought them back in 35.6 (June 2026) with 17 listed returning anomalies ([wallii 35.6 notes](https://www.wallii.gg/news/35-6-patch-notes)).
  - The [36.6 patch notes](https://hearthstone.blizzard.com/en-us/news/24294373/366-patch-notes) do not mention anomalies. They cover Aberrations and the Naga rotation.
  - **Both of our 36.6.0 captures have no `BACON_GLOBAL_ANOMALY_DBID`,** but they do have `BACON_GLOBAL_OLD_GOD_DBID` (Deity) and `BACON_DARK_GIFTS_ACTIVE`.
  - Status: **unconfirmed.** Anomalies may be off, or may appear only in some lobbies.
  - Also, no anomaly-carrying BG log exists in the test data (subagent scan). Treat anomaly support as tag-driven and generic, and ask for a capture.

---

## 5. Midnight rollover and timestamps

- **Format:** `HH:MM:SS.fffffff`, local time, no date. **[seen]**
- **Samples [seen]:**
  - [`TD/data/Derred.log#L2468-L2478`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/data/Derred.log#L2468):
    ```
    D 23:59:59.9872550 PowerTaskList.DebugPrintPower() - BLOCK_END
    D 00:00:01.8490680 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity tag=STEP value=MAIN_END
    ```
  - `TD/data/brawls/raven-idol-brawl.log#L57894-L57895`: `23:59:59.6258640 GameState.SendOption()` is followed by `00:00:00.1886140 PowerProcessor.EndCurrentTaskList()`.
- **Timestamps are monotonic in file order.** In our captures there are **0 backward steps** across all 316 k Power.log lines, including between interleaved GameState and PTL lines, and 0 in LoadingScreen.log, Hearthstone.log and Zone.log. The ~50 s GameState lead is in the *content*; each line is stamped when it is written. So "time went backwards" means rollover (or a clock change). **[seen]**
- **What the trackers do [code]:**
  - HDT maps each line to *today* and subtracts a day if the result is in the future ([HearthWatcher/LogReader/LogLine.cs#L25-L32](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogReader/LogLine.cs#L25)). HSTracker does the same ([LogLine.swift#L153-L157](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogLine.swift#L153)), and so does Firestone's catch-up (`extractTimestamp`, [game-events.service.ts#L1900-L1912](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1900)). Replaying an older log gives wrong dates this way, e.g. a log from yesterday 09:00 read today at 10:00 is dated today.
  - Both trackers merge lines from several files **by timestamp** (HDT `SortedList<DateTime,…>`, [LogWatcher.cs#L37-L66](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogWatcher.cs#L37); HSTracker `processMap` sorted by `LogDate`, [LogReaderManager.swift#L118-L148](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReaderManager.swift#L118)). A wrong date on one file would therefore reorder events.
  - python-hslog is the correct model: it syncs a start date once, then adds `timedelta(days=1)` whenever a timestamp falls before the last one ([HSLOG parser.py#L1048-L1092](https://github.com/HearthSim/python-hslog/blob/015c0dec197779c90cd3131ecda2c990292342b6/hslog/parser.py#L1048)). It has no rollover unit test; `tests/test_parser.py#L136-L176` covers parsing and repeated timestamps only.
- **Our rule:**
  - The date anchor is the **session folder name** `Hearthstone_YYYY_MM_DD_HH_MM_SS`, which is local time. It matched the first `Hearthstone.log` line to the second (21:08:40 → `I 21:08:40.66…`). Keep one running `dayOffset` **per file**.
  - If `t < prev − 12 h`, count it as a rollover: `dayOffset += 1`.
  - If `prev − 12 h ≤ t < prev`, it is a clock adjustment or DST fall-back: clamp to `prev` for ordering and keep the raw value for display.
  - Never use the wall clock to infer dates during replay.
  - Order events **within** a file by line order, never by timestamp; one task list shares a single timestamp (validation doc). Use timestamps only to merge files (Power + LoadingScreen + GameNetLogger) and for pacing.

---

## 6. Spectator mode

- **Signatures in Power.log [seen]**, from [`TD/data/spectate_2.log`](https://github.com/HearthSim/hsreplay-test-data/blob/715d408e7047abdbde519313593f1be603916bec/data/spectate_2.log) and `double_spectate.log` (constructed games; no BG spectate sample exists):
  ```
  1    D 10:24:47.2819610 ================== Begin Spectating 1st player ==================
  3    D 10:24:48.3880710 GameState.DebugPrintPower() - CREATE_GAME
  1706 D 10:25:13.2283580 ================== End Spectator Mode ==================
  1707 D 10:25:13.2644140 ================== End Spectator Game ==================
  1708 D 10:25:24.6270810 ================== Begin Spectating 1st player ==================
  1709 D 10:25:25.2607560 ================== Start Spectator Game ==================
  ```
  - There are five exact strings: `Start Spectator Game`, `Begin Spectating 1st player`, `Begin Spectating 2nd player`, `End Spectator Mode` and `End Spectator Game`. Each is wrapped in 18 `=` characters with **no `Method() -`** part ([HSLOG tokens.py#L70-L76](https://github.com/HearthSim/python-hslog/blob/015c0dec197779c90cd3131ecda2c990292342b6/hslog/tokens.py#L70); handler at [parser.py#L994-L1008, #L1110-L1114](https://github.com/HearthSim/python-hslog/blob/015c0dec197779c90cd3131ecda2c990292342b6/hslog/parser.py#L994)).
  - `End Spectator Game` / `End Spectator Mode` can come in either order (`double_spectate.log` L2126-L2127).
  - **Our line regex `^([DWE]) (\S+) (.+?)\(\) - (.*)$` rejects these lines.** Match the `==================` prefix before it.
- **What the trackers do [code]:**
  - HDT/HSTracker pass the lines through with contains-filters `"Begin Spectating", "Start Spectator", "End Spectator"` ([HDT LogWatcherManager.cs#L43-L47](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/LogWatcherManager.cs#L43); [HST LogReaderManager.swift#L76-L78](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReaderManager.swift#L76)).
  - `End Spectator` ends the game ([HDT PowerHandler.cs#L770-L771](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/PowerHandler.cs#L770); [HST PowerGameStateParser.swift#L727-L729](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Parsers/PowerGameStateParser.swift#L727)) and is a catch-up entry-point marker (§7).
  - The spectating **flag** itself comes from memory (HSTracker `MirrorHelper.isSpectating()` with a `dontTrackWhileSpectating` setting, [Game.swift#L1100-L1112, #L249-L250](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L1100)).
  - HSTracker skips recording BG stats while spectating ([Game.swift#L2485-L2487](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/Game.swift#L2485)).
  - Firestone's C# resets on the first `Begin Spectating` that isn't "2nd", and ends the game on `End Spectator Mode` ([FSC SpectatorHandler.cs#L18-L70](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/Handlers/DataHandler/SpectatorHandler.cs#L18)). It notes that spectating a BG game "partway through" gives entities with missing links ([LinkedEntityParser.cs#L42](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/LinkedEntityParser.cs#L42)).
  - Firestone's catch-up: "There is no automatic reconnect when spectating", and it re-inserts the last open `Begin Spectating` line before replaying ([game-events.service.ts#L1794-L1847](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1794)).
- **Hazard [inferred]:** while spectating a friend's BG game, the "local" Player (non-zero GameAccountId) is the **friend**, and `DebugPrintGame` reports the friend's BattleTag. A naive parser would record the friend's game as ours. A spectated game joined mid-way also looks exactly like a reconnect: full-state `CREATE_GAME`, `IsPastBeginPhase()=True`.
- **Our rule:**
  - Track `spectating` from the banner lines.
  - Also compare the local BattleTag with the account's own, learned from the user's non-spectated games (`DebugPrintGame` names) or from settings.
  - While spectating: parse normally so a live view is possible (optional in v1), but **never write stats or history**, never apply reconnect-stitching, and label the UI "Spectating <name>".
  - Clear the flag on `End Spectator Mode`, on the LoadingScreen leaving GAMEPLAY, and at the end of catch-up if no `Begin` line is open (Firestone's rule).

---

## 7. App starting mid-game (catch-up)

- **HSTracker [code]:**
  - `entryPoint()` = the later of the last `tag=STATE value=COMPLETE` / `End Spectator` in Power.log and the last `Gameplay.Start` in LoadingScreen.log ([LogReaderManager.swift#L177-L187](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReaderManager.swift#L177)).
  - `findEntryPoint` loads the **whole file into a String** and scans the reversed lines ([LogReader.swift#L45-L69](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReader.swift#L45)).
  - `findInitialOffset` then walks back in 4 KB chunks to the first line older than the entry point ([#L214-L260](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReader.swift#L214)), and lines older than it are dropped.
  - The entry point is a **timestamp** comparison, so it depends on the date logic in §5.
  - **HSTracker also deletes** a `<name>.log` that Hearthstone does not hold open when a reader is created ([LogReader.swift#L28-L43](https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/HSTracker/Logging/LogReader.swift#L28)), and it can truncate on stop. A user running HSTracker next to our app can lose our input. Detect a shrinking file (size < offset) and treat it as truncation (Firestone's `'truncated'`).
- **HDT [code]:** the same entry point ([LogWatcher.cs#L78-L83](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogWatcher.cs#L78)). It uses a reverse 4 KB chunk search ([LogFileWatcher.cs#L272-L359](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogReader/LogFileWatcher.cs#L272)) and caps the queue at 100,000 lines to survive "very late Battlegrounds matches, especially when restarting HDT" ([#L28-L34](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogReader/LogFileWatcher.cs#L28)). A `STEP` change before setup marks `WasInProgress`.
- **Firestone [code]:**
  - Existing lines are buffered as "existing". The buffer is cleared on every `STATE=COMPLETE`, `End Spectator Mode` or local-concede tag, but **not** on `CREATE_GAME`, to keep reconnect history.
  - At end of data the buffer is replayed only if the last line is less than **5 min** old or the scene is GAMEPLAY.
  - New live lines are held in `pendingLogLines` until catch-up finishes ([game-events.service.ts#L1720-L1885](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1720)).
  - It also surfaces `Truncating log, which has reached the size limit` as a critical error ([#L1734-L1737](https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/game-events.service.ts#L1734)).
- **[seen] The truncation banner is real, and it has no timestamp.** Our first session's `Zone.log` ends with:
  ```
  ==================================================================
  Truncating log, which has reached the size limit of 10000KB
  ==================================================================
  ```
  Power.log, LoadingScreen.log and Hearthstone.log all stop at the same instant (20:41:03.34). The per-file default cap is **10,000 KB**. The parser must accept undated lines, and should raise "logging stopped: write client.config / disable Zone" if it sees this banner in any file of the session.
- **Cost [seen, measured]:** on the 35.8 MB complete game, a Python `mmap.rfind` for the last `GameState… CREATE_GAME`, the last `STATE=COMPLETE`, `End Spectator` and the next `GAME_SEED` takes 225 ms total (43 ms on the 5.9 MB file). A Swift `memmem` or backwards chunked search should be well under 50 ms. The full replay from `CREATE_GAME` costs 0.4 s for the store and 0.9 s with the naive derivation in Python (validation doc). **Replaying from the last relevant `CREATE_GAME` is cheap enough that we do not need HSTracker's timestamp entry point.**
- **Our catch-up algorithm:**
  1. Pick the session folder (§8). Read `Power.log` as bytes.
  2. Find the offset of the **last** `GameState.DebugPrintPower() - CREATE_GAME`. Read its `GAME_SEED`, then walk **backwards** through earlier `CREATE_GAME`s while the seed is the same, and start at the **first** one of that seed. That covers in-file reconnects.
  3. If a `STATE=COMPLETE`, `End Spectator Mode`/`Game`, or local-player tag 3479=1 comes after the last `CREATE_GAME`, the game is finished. Import it into history if it is new (by seed) and start live tailing at EOF.
  4. Otherwise replay from that offset with **`mode = .catchUp`**:
     - the reducer runs normally;
     - no UI updates, no animations, no notifications, no sounds, no BobsBuddy/sim runs;
     - snapshots are recorded into the game journal but not published;
     - at EOF, publish one coalesced state, then switch to `.live`.
  5. Live lines arriving during catch-up are appended to the same sequential reader, so there is no gap and no double-processing. It is one byte-offset cursor.
  6. Combats whose 2022 1→0 happened during catch-up are marked `observedLate`, and no simulation runs for them. A combat still in progress at EOF can be simulated only if its start snapshot is complete (the opponent board is `FULL_ENTITY`'d before the first ATTACK).
  7. The seed exists in neither history nor the current file's earlier sections, but `IsPastBeginPhase()=True` or the first `CREATE_GAME` has `TURN > 1`: this is a restart-reconnect. Try the previous folder (§3.4 step 3).

---

## 8. Hearthstone restarts, multiple sessions per day, folder retention

- **[seen]** One folder per client launch: `/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_31_46`, `…_20_33_28` and `…_21_08_40`, three launches in about 40 minutes. All logs of a launch (every game, every mode) are appended to that folder's files. `LoadingScreen`, `GameNetLogger`, `Hearthstone.log` and others sit beside `Power.log`. The folder name timestamp equals the first log line's timestamp.
- **Finding the live folder:**
  - HDT picks the newest `CreationTime` and uses a Windows file-lock probe ([LogFileWatcher.cs#L40-L83](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogReader/LogFileWatcher.cs#L40)). The probe is useless on macOS.
  - HSTracker asks memory for the folder.
  - For us: take the newest `Hearthstone_*` by parsed name while the HS process runs. Re-check every 5 s and whenever the HS PID changes, and require `Power.log` or `Hearthstone.log` to be growing.
- **Retention: unknown.** I found no documentation (web search, tracker code, issues) on how many `Hearthstone_*` folders the client keeps or whether it prunes them. Three folders are on this Mac, none pruned yet. Do not rely on old folders: **journal every BG game into our own store as it is parsed**, keyed by `GAME_SEED`. Capture wanted: count folders after more than 10 launches.
- **Multiple games per session:** each game starts with its own GameState `CREATE_GAME` + `DebugPrintGame` + PTL `CREATE_GAME`. The entity ID space restarts per game. HDT's `FindEntryPoint` and Firestone's "trash on COMPLETE" both assume several games in one file. **[code]**

---

## 9. Non-BG games in the same session

- Every game, of any mode, goes through the same Power.log, and each is preceded by `DebugPrintGame GameType=`. Types include:

  | GameType | ID |
  |---|---|
  | `GT_RANKED` | 7 |
  | `GT_CASUAL` | 8 |
  | `GT_ARENA` | 5 |
  | `GT_VS_AI` | 1 |
  | `GT_VS_FRIEND` | 2 |
  | `GT_TAVERNBRAWL` / `GT_FSG_BRAWL*` | 16–22 |
  | `GT_PVPDR*` | 28/29 |
  | `GT_MERCENARIES_*` | 30–34 |
  | `GT_UNDERGROUND_ARENA*` | 42/45 |
  | `GT_ARENA_PLAYER_VS_AI` | 44 |

  Source: [PYHS enums.py#L1990-L2026](https://github.com/HearthSim/python-hearthstone/blob/637eaa29c911d6b3000349713b8847b035205fb7/hearthstone/enums.py#L1990). **[code]**
- Constructed specifics that the BG parser must survive without crashing:
  - `RESET_GAME` / rewind timelines (python-hslog `tests/test_parser.py#L369-L406`; Firestone's alternate-timeline skipping, [FSC ReplayParser.cs#L108-L300](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Parser/ReplayParser.cs#L108));
  - `SHUFFLE_DECK`, `CACHED_TAG_FOR_DORMANT_CHANGE`, mulligan choices and spectator banners;
  - adventure restarts, where HDT notes "The game end is not logged in PowerTaskList" ([GameEventHandler.cs#L778-L786](https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/GameEventHandler.cs#L778)).
- **Our rule:** a per-game **mode gate**.
  - Every GameState `CREATE_GAME` opens a new game context. The `DebugPrintGame GameType=` lines that follow classify it.
  - If the type is not in {23, 24, 35, 36, 37, 38, 39, 40, 41}, the context goes to an `IgnoredGame` sink. The sink tokenises lines to keep the line state machine sane, but it builds no entities and emits nothing. The sink closes at the next `CREATE_GAME`, `STATE=COMPLETE` or `End Spectator*`.
  - `DebugPrintGame` arrives between the GameState and PTL `CREATE_GAME`, so the gate is known before any PTL state line is reduced.
  - If `DebugPrintGame` is missing (possible after reconnect), fall back to the seed match. Failing that, look for BG markers in the `CREATE_GAME` block: GameEntity `BACON_*` tags, a Player with `BACON_DUMMY_PLAYER=1`, `TB_BaconShop_HERO_PH`. Otherwise ignore the game.
  - Never use LoadingScreen `currMode=BACON` alone. It is the lobby scene, and a Tavern Brawl could also be entered from HUB.

---

## Consolidated parser-rules checklist

**Lines and time**
- [ ] Accept four kinds of line:
  - `^[DWE] <ts> <method>() - <payload>`, where the method may contain spaces and brackets;
  - spectator banners `^[DWE] <ts> ={18} (Start Spectator Game|Begin Spectating (1st|2nd) player|End Spectator Mode|End Spectator Game) ={18}$`;
  - the **undated** `Truncating log…` banner;
  - blank or `=` separator lines.
  Never crash on anything else.
- [ ] Date each file from its session folder name, with a per-file `dayOffset`: +1 day when `t < prev − 12h`, and clamp small backward steps. Order within a file by line order. Merge files by resolved timestamp (Power, LoadingScreen, GameNetLogger).
- [ ] Detect truncation in two ways: file size below our offset, which means reopen from 0 with a new session, and the `Truncating log` banner in any file of the session, which means a user-facing "logging stopped" error.

**Game boundaries and identity**
- [ ] A GameState `CREATE_GAME` opens a *candidate* game. Buffer until the GameEntity block is read, then take `GAME_SEED`. Never hard-code the GameEntity `EntityID`; we saw 4 and 16.
- [ ] Take `DebugPrintGame` metadata (GameType, BuildNumber, ScenarioID, player names) between the GS and PTL `CREATE_GAME`. It is kept across the PTL `CREATE_GAME` reset.
- [ ] Mode gate: BG = GameType ∈ {23, 24, 35–41}, and Duos = 37–41. Everything else goes to the `IgnoredGame` sink.
- [ ] **Same seed as the open or last unfinished game means a reconnect.** Keep the game record, rebuild the entity store from the full-state resend, mark `reconnected`, invalidate the in-flight combat, and skip mulligan-dependent logic.
- [ ] A different seed starts a new game. Close the previous one as `abandoned` if it has no end.
- [ ] Game end, first match wins:
  - `GameEntity STATE=COMPLETE`;
  - local-Player tag 3479 (`TAG_PLAYER_CONCEDED_OR_DISCONNECTED`) = 1, which in BG counts as a concede or leave: `ended(.conceded)`;
  - local `PLAYSTATE ∈ {CONCEDED, LOST, WON, TIED}` followed by LoadingScreen leaving GAMEPLAY;
  - `End Spectator*`.
  Keep consuming lines after COMPLETE until the next `CREATE_GAME`.
- [ ] Ignore `PLAYSTATE` on the dummy or bartender slot; it cycles LOSING→PLAYING whenever an opponent or team dies. Ignore 3479 on any entity other than the local Player entity.

**Placement**
- [ ] Solo: `Player.HERO_ENTITY.PLAYER_LEADERBOARD_PLACE` at end, 1–8.
- [ ] Duos: the same tag is the **team** place, 1–4. Leaderboard row = `place*2 − BACON_DUO_PLAYER_FIGHTS_FIRST_NEXT_COMBAT`.
- [ ] Concede without a final place update: estimate `1 + alive-and-unplaced count` and flag it `concedeEstimate`.
- [ ] Deduplicate the lobby by `PLAYER_ID`. In Duos, group lobby heroes by `BACON_DUO_TEAM_ID` and take the local team from the **Player** entity, because the local hero lacks it.

**Duos combat**
- [ ] Fight boundary = tag 3533 1→0 (snapshot). Tag 2022 1→0 = combat start, once per combat.
- [ ] Board owner during a fight = `local.BACON_CURRENT_COMBAT_PLAYER_ID`; opponent = `dummy.BACON_CURRENT_COMBAT_PLAYER_ID`. Local-controller PLAY minions during fight B are the **teammate's**.
- [ ] Swap-in = a `HERO_ENTITY` change on the local or dummy Player during `BOARD_VISUAL_STATE=2`, plus a new combat PlayerID. The `OverrideSpawn_FromPortal` sub-spell is a secondary hint only.
- [ ] Store last-seen boards keyed by PlayerID for opponents **and** the teammate. Recruit-phase teammate boards are not in the log.
- [ ] Pass = hand entity leaves HAND inside `BlockType=DECK_ACTION` with `IS_USING_PASS_OPTION=1`. It costs gold. `BACON_DUO_PASSABLE` is only a capability flag.
- [ ] Next-combat preview: `NEXT_OPPONENT_PLAYER_ID` + `NEXT_OPPONENT_TEAMMATE_PLAYER_ID` + 2975 on heroes, which says who fights first.

**Anomalies**
- [ ] Read GameEntity `BACON_GLOBAL_ANOMALY_DBID` (2897) and resolve it through card data (`BATTLEGROUND_ANOMALY`). Read it again after a reconnect.
- [ ] Never hard-code max tier, gold cap or start HP. Use `BACON_MAX_PLAYER_TECH_LEVEL`, tag 3148 and hero HEALTH. Available tiers follow the anomaly table (§4).

**Spectating**
- [ ] Track `spectating` from the banners. While spectating, allow a live view only: no stats, no history, no stitching. Clear the flag on `End Spectator Mode`, on leaving GAMEPLAY, and at the end of catch-up when no `Begin` line is open.
- [ ] Guard: if the local BattleTag ≠ the user's known BattleTag, treat the game as spectate or foreign and never record it.

**Catch-up**
- [ ] Find the last GS `CREATE_GAME` by reverse byte search, then walk back to the first `CREATE_GAME` with the same seed.
- [ ] Finished (COMPLETE / End Spectator / local 3479 after it): import to history and tail from EOF. Unfinished: replay in `.catchUp` mode (no UI or sims), then publish once and go live on the same cursor.
- [ ] Restart-reconnect (first `CREATE_GAME` in the folder has `TURN > 1` or `STATE=RUNNING`, or LoadingScreen `IsPastBeginPhase()=True`): stitch from our journal by seed, else from the previous folder.
- [ ] Persist a per-game journal (seed, hashed server and game handle, name map, last-seen boards, timeline) incrementally. Do not rely on HS keeping old folders.

**Sessions and files**
- [ ] Newest `Logs/Hearthstone_*` by name while HS runs. Re-check every 5 s and on PID change. Never delete or truncate HS logs.
- [ ] Never store or display `spectateKey`, `client=` or the server IP. Hash `(address, game)` if kept.

---

## Captures still wanted (in priority order)

1. **Duos game, full, raw Power.log + LoadingScreen + GameNetLogger.** It confirms the raw-text form of everything in §1:
   - numeric vs named tags (`tag=2975`?),
   - PTL timing of the fight-B swap,
   - cards **received** from the teammate,
   - `BACON_DUO_TEAM_ID` on the local hero,
   - the order in which placement 1–4 is written at the end.
   Ideally both a top-2 and a bottom-2 finish.
2. **BG concede mid-game (solo).** Is 3479 logged, and on which entity? Is `PLAYSTATE=CONCEDED` logged? Is a final `PLAYER_LEADERBOARD_PLACE` written? Is `STATE=COMPLETE` ever written? Which `DisconnectFromGameServer() - Reason:` string appears, and what does the LoadingScreen sequence look like? Then the same in Duos, to see the effect of `BACON_DUOS_PUNISH_LEAVERS`.
3. **Reconnect via HS restart mid-game (quit → reopen, during recruit and again during combat).** Check:
   - a new folder;
   - first `CREATE_GAME` state;
   - `GAME_SEED` equality;
   - whether `DebugPrintGame` is re-emitted;
   - `GotoGameServe reconnecting=True` and the same `game=`;
   - `IsPastBeginPhase()=True`;
   - entity ID preservation;
   - the lobby and name data available after the reconnect.
4. **In-client reconnect** (drop the network for about 30 s mid-game): a second `CREATE_GAME` inside the same Power.log, and what precedes it.
5. **App (or parser) started mid-game** against a real in-progress 20 MB+ log. Measure Swift catch-up time end to end.
6. **Anomaly game**, if anomalies are live in 36.6.x (check a few lobbies for `BACON_GLOBAL_ANOMALY_DBID`). Ideally one of the tier-changing anomalies.
7. **Spectating a friend's BG game**, both joining at the start and joining mid-game. Check the banners, the local Player identity, and whether it looks like a reconnect.
8. **Midnight rollover** during a BG game: play across 00:00 local, and include a DST change if one is ever convenient.
9. **Folder retention:** list `Logs/` after 10 or more launches, or after a client update, to see if HS prunes.
10. **Non-BG game in the same session as BG games** (one ranked or brawl game between two BG games), to exercise the mode gate on real data.

---

## Test-data inventory (for fixtures)

- Real Duos, HSReplay XML: `TD/hsreplaynet-tests/replays/battlegrounds_duos.annotated.xml` and `battlegrounds_duos_trinkets.annotated.xml`. We could generate raw-format Duos fixtures from these by printing each `TagChange`/`FullEntity` as a Power.log line. The GameState-order caveat applies.
- BG reconnect (XML, 2020): `…/battlegrounds_reconnect.annotated.xml`. Events after COMPLETE: `…/battlegrounds_async_gameover.annotated.xml`.
- Raw constructed reconnect: `TD/data/reconnect.log`. Raw concede: `TD/data/concede_mulligan_13740.log`. Raw spectate: `TD/data/spectate_2.log`, `double_spectate.log`, `spectator.log`, `spectator_mode_same_game/`. Raw midnight rollover: `TD/data/Derred.log`, `TD/data/brawls/raven-idol-brawl.log`.
- Raw solo BG: `TD/hslog-tests/36393_battlegrounds.power.log`, `139963_battlegrounds_perfect_game.power.log`, plus our two private captures.
- Local copies from this research are in the scratchpad at `…/scratchpad/testdata/`.
