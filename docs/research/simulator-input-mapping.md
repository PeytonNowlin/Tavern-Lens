# Simulator input mapping: Power.log → `BgsBattleInfo`

Researched 2026-09-22 against Hearthstone 36.6.0 (build 251952) and `@firestone-hs/simulate-bgs-battle` **1.1.755** (with `@firestone-hs/reference-data` 3.0.211). This is a field-by-field spec for building the simulator's input from our own `EntityStore`. Every rule was checked against two real captures (§8).

Related notes: [battlegrounds-macos-feasibility.md](battlegrounds-macos-feasibility.md), [logs-and-extractable-state.md](logs-and-extractable-state.md), [ecosystem-and-data-sources.md](ecosystem-and-data-sources.md).

## Overview

- **Firestone's real Power.log → board parser is MIT-licensed.** The Firestone app repo is unlicensed. But the code that turns log entities into the simulator's board payload lives in [`Zero-to-Heroes/hs-game-converter-csharp-port`](https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/tree/6586ae1bb07443ecc47d2683d114a65bdfed1b00) (C#, **MIT**), in `BattlegroundsPlayerBoardParser.cs`. That repo was last pushed 2026-03-25 (patch 35.0), so newer mechanics such as Deity, Dark Gifts and the newer counters are missing from it. We can port its logic directly. The TypeScript glue in the app (`buildBgsEntity`, `buildBgsBoardInfo`) is thin, and this spec restates it.
- **Snapshot moment:** the `PowerTaskList` line `TAG_CHANGE Entity=GameEntity tag=2022 value=0` (the 1→0 edge; Firestone calls tag 2022 `BG_BATTLE_STARTING`). Firestone and HDT both use it. In the real logs it comes **after** the opponent's board has been copied in and **before** any Start of Combat trigger. Start of Combat hero powers and minions fire just after it (§3).
- **Two captured combats reproduce correctly.** Our mapping, run through the real simulator:
  - late game: 74% loss, 7–13 damage; actual result was a loss for 10
  - early game: 96% loss, 3–4 damage; actual result was a loss for 3
- **The traps, in order of impact:**
  1. **Deity stats.** Dropping them turns a 74% loss into a 78% win in the example.
  2. **Mixed tag naming.** Many BG counters are printed as bare numbers.
  3. **Opponent counters.** Read them from the opponent-slot Player entity, or from its `Bacon_TagTransferPlayerE`.
  4. **Placeholder trinkets.** They must be filtered out.
  5. **`validTribes`.** It is not in the log, so infer it from single-tribe pool minions.
  6. **`CardsData.inititialize(validTribes, anomalies)`.** It must be called by the embedder. `simulateBattle` does not read the tribe pool itself.
- **Damage cap:** the simulator computes its own cap from `currentTurn` and `numberOfPlayersAlive` when `options.applyDamageCap` is set. Its formula (5/10/15, none at ≤4 alive, Duos 15) matched `BACON_COMBAT_DAMAGE_CAP` at every change in both logs.

---

## 1. Sources

| Source | Version / commit | Licence | Role here |
|---|---|---|---|
| `@firestone-hs/simulate-bgs-battle` | 1.1.755 (npm, published 2026-09-22T19:37Z). `.d.ts` plus `.js.map` with `sourcesContent`; the TS source was recovered from the maps | MIT (package.json) | The input contract, and what the simulator actually reads |
| `@firestone-hs/reference-data` | 3.0.211 | MIT | `GameTag` and `Race` numeric enums used in `tags` maps and `validTribes` |
| Zero-to-Heroes/hs-game-converter-csharp-port | `6586ae1bb07443ecc47d2683d114a65bdfed1b00` (2026-03-25) | **MIT** | Firestone's log → board builder. **Portable** |
| Zero-to-Heroes/firestone | `0a30f066eb77a417637d95cec86444456f607ba1` (current HEAD) | none (reference only) | TS mapping from the C# payload to `BgsBattleInfo` |
| HearthSim/Hearthstone-Deck-Tracker | `ef8ab6e8380a647d757eec203d310395d6b97ae0` | All Rights Reserved (reference only) | BobsBuddy input: timing, counters, reconnects. Used as a cross-check |
| Local captures (read-only) | `Hearthstone_2026_09_22_20_33_28/Power.log` (truncated, 4 combats); `fixtures/private-logs/Hearthstone_2026_09_22_21_08_40/Power.log` (full game, 12 combats) | private | Verification |

---

## 2. The input contract (what the simulator reads)

Field lists come from the recovered TypeScript. "Read" means the simulator code actually uses the field; I grepped all 918 recovered source files outside the type files. "Set by sim" fields are derived internally, so don't send them.

### 2.1 `BgsBattleInfo`
| Field | Type | Req | Read | Notes |
|---|---|---|---|---|
| `playerBoard` | `BgsBoardInfo` | yes | yes | Local player; `friendly = true` is forced |
| `opponentBoard` | `BgsBoardInfo` | yes | yes | |
| `playerTeammateBoard`, `opponentTeammateBoard` | `BgsBoardInfo?` | Duos only | yes | Setting either one makes `isDuos` true |
| `options` | `BgsBattleOptions` | yes | yes | |
| `gameState` | `BgsGameState` | yes | yes | |
| `heroHasDied` | `boolean?` | no | passthrough only | Unused |
| `debugState` | `BgsDebugState?` | no | debug | Forces attack order and random picks. Never send it |

### 2.2 `BgsGameState`
| Field | Type | Req | Read | Notes |
|---|---|---|---|---|
| `currentTurn` | `number` | yes | yes | BG turn, not the raw `TURN` tag. Feeds the damage cap and turn-scaled cards |
| `validTribes` | `Race[]?` | no | yes | Random-summon pools. **Also passed to `cardsData.inititialize()`** by the embedder ([simulate-bgs-battle.ts L199](#c-sim)) |
| `anomalies` | `string[]?` | no | yes (273 refs) | Card IDs. Falsy entries are filtered out |
| `numberOfPlayersAlive` | `number?` | no | yes | Damage cap only; ignored unless `applyDamageCap` |

### 2.3 `BgsBattleOptions`
| Field | Type | Default | Notes |
|---|---|---|---|
| `numberOfSimulations` | `number` (req) | 8000 | |
| `maxAcceptableDuration` | `number?` | 8000 ms | Hard stop. The late-game example took about 1.6 s per 8000 sims in Node |
| `intermediateResults` | `number?` | 200 | The generator yields every N sims. Useful for progressive UI |
| `includeOutcomeSamples` | `boolean?` | **true** | Re-runs up to 500 sims to record replays. **Set false** unless we show replays |
| `damageConfidence` | `number?` | 0.9 | Percentile for `damageWonRange`/`damageLostRange` |
| `applyDamageCap` | `boolean?` | false | Requires `gameState.numberOfPlayersAlive` |
| `applyIceBlock` | `boolean?` | false | Full-game-env only; leave false for odds |
| `skipInfoLogs` | `boolean` (req) | | Set true |
| `validTribes` | `Race[]?` | | Deprecated. Use `gameState.validTribes` |
| `hideMaxSimulationDurationWarning` | `boolean?` | false | |

### 2.4 `BgsBoardInfo`
`{ player: BgsPlayerEntity; board: BoardEntity[]; secrets?: BoardSecret[] }`. Board order is left to right. `secrets` here is a fallback for `player.secrets`.

### 2.5 `BgsPlayerEntity`
| Field | Type | Req | Read | Notes |
|---|---|---|---|---|
| `cardId` | `string` | yes | yes | Hero. Replaced by `TB_BaconShop_HERO_KelThuzad` when `hpLeft <= 0` (ghost) |
| `hpLeft` | `number` | yes | yes | Clamped to ≥1. Used for lethal% |
| `tavernTier` | `number` | yes | yes | Minimum face damage |
| `heroPowers` | `BgsHeroPower[]` | yes | yes | Falls back to the deprecated `heroPowerId`, `heroPowerUsed`, `heroPowerInfo*` fields if empty |
| `entityId` | `number?` | no | yes | 0 is invalid; the simulator makes one up |
| `questEntities` | `BgsQuestEntity[]` | yes | yes | `{CardId, RewardDbfId, ProgressCurrent, ProgressTotal}` (PascalCase) |
| `questRewards` | `string[]?` | no | yes | Card IDs |
| `questRewardEntities` | `{CardId, ScriptDataNum1}[]?` | no | yes | **PascalCase in input.** The simulator remaps it to camelCase and assigns entityIds ([auras.ts L196-L210](#c-sim)) |
| `hand` | `BoardEntity[]?` | no | yes (83 refs) | Summon-from-hand, discard and "cards in hand" effects |
| `secrets` | `BoardSecret[]?` | no | yes | Includes the Deity sigil |
| `trinkets` | `BoardTrinket[]?` | no | yes (114 refs) | Placeholders must be removed; the list is sorted by entityId |
| `globalInfo` | `BgsPlayerGlobalInfo?` | no | yes | See §6. Missing keys default to 0 |
| `enchantments` | `BoardEnchantment[]?` | no | barely | Compatibility only |
| `friendly`, `startOfCombatDone`, `deadEyeDamageDone`, `rapidReanimation*` | | | set by sim | Don't send |

### 2.6 `BgsHeroPower`
| Field | Type | Read by | Source |
|---|---|---|---|
| `cardId` | `string` | all | hero-power entity CardID |
| `entityId` | `number` | all | entity id |
| `used` | `boolean` | about 20 HP impls (`heroPower.used && …`) | §5.3 |
| `info` | `number \| string \| BoardEntity` | Reborn Rites (target entityId), Embrace Your Rage (created cardId), Lock and Load / Rapid Reanimation (a `BoardEntity`), Ozumat (Tentacular size), Runic Empowerment | `TAG_SCRIPT_DATA_NUM_1`, plus special cases |
| `info2` … `info6` | `number` | Aim Left/Right/Low/High, Runic Empowerment, Wax Warband (`info3`) | `TAG_SCRIPT_DATA_NUM_2..6` |
| `scoreValue1..3` | `number?` | `scoreValue2` = avenge progress (`avengeCurrent = avenge − scoreValue2`) | `SCORE_VALUE_1..3` |
| `locked` | `number?` | 31 refs | `LOCK_VISUAL` (4414) |
| `ready`, `activated`, `avengeCurrent/Default` | | set by sim | Don't send |

### 2.7 `BoardEntity` (minions on board and cards in hand)
| Field | Type | Read | Notes |
|---|---|---|---|
| `entityId` | `number` | yes | Log entity id |
| `cardId` | `string` | yes | Current card ID, after any `CHANGE_ENTITY` |
| `attack`, `health` | `number` (req) | yes | **Current** stats. The log values already include all buffs and auras; health = `HEALTH − DAMAGE` |
| `maxHealth` | `number?` | 116 refs | `HEALTH` |
| `maxAttack` | `number?` | 85 refs | Firestone doesn't send it. The simulator derives it where needed |
| `taunt`, `divineShield`, `poisonous`, `venomous`, `reborn`, `windfury`, `stealth` | `boolean?` | yes | Keywords. `cleave` and `cantAttack` are hard-coded by card ID in the simulator ([utils.ts L706](#c-sim)) |
| `strongDivineShield`, `extraDivineShieldCharges` | | set by sim | |
| `enchantments` | `BoardEnchantment[]` | yes | §5.5 |
| `scriptDataNum1..6` | `number?` | 178/47/4/4/0/9 refs | `TAG_SCRIPT_DATA_NUM_1..6`. **For board minions, `cardsData.defaultScriptDataNum(cardId)` overrides `scriptDataNum1` whenever the default is non-zero** ([input-sanitation.ts L196](#c-sim)) |
| `locked` | `boolean?` | 31 refs | `UNPLAYABLE_VISUALS` or `LITERALLY_UNPLAYABLE` (cards in hand) |
| `tags` | `{[num]: num}?` | 31 refs | Numeric GameTag keys. Firestone only sends `BACON_YAMATO_CANNON` (4036) |
| `additionalCards` | `string[]?` | 17 refs | Build-An-Undead and Zilliax modules, from `MODULAR_ENTITY_PART_1/2` (dbfIds → card IDs, excluding self). Zilliax Assembled also uses `BACON_TRIPLED_BASE_MINION_ID{,2,3}` |
| `dynamicInfo` | `any[]?` | 1 ref | C#-side extras. Ignore |
| `hadDivineShield`, `definitelyDead`, `hasAttacked`, `immuneWhenAttackCharges`, `frenzyChargesLeft`, `pendingAttackBuffs`, `inInitialState`, `friendly`, `gildedInCombat`, `memory`, … | | set by sim | Firestone sends `definitelyDead:false` and `immuneWhenAttackCharges:0`; both are harmless |
| `tavernTier` | `number?` | 79 refs (mostly via card DB) | Optional; `TECH_LEVEL` |

### 2.8 `BoardEnchantment`, `BoardSecret`, `BoardTrinket`
- `BoardEnchantment { cardId; originEntityId?; tagScriptDataNum1?; tagScriptDataNum2?; timing; repeats?; value?; memory? }`. Send `timing: 0` and the simulator assigns `entityId + index + 1`. A numeric `cardId` is treated as a **dbfId** and resolved to its enchantment ([enchantments.ts L4](#c-sim)). Firestone uses this for Polarizing Beatboxer and Clunker Junker (§5.5).
- `BoardSecret { entityId; cardId; triggered?; scriptDataNum1/2/3/6?; triggersLeft?; tags? }`.
- `BoardTrinket { cardId; entityId; scriptDataNum1; scriptDataNum2?; scriptDataNum6?; tags?; rememberedMinions?; avengeDefault?; avengeCurrent? }`.
  - If `scriptDataNum1` is null/undefined, the simulator substitutes the card default; an explicit 0 is kept.
  - Tags read on trinkets: `TRIGGER_VISUAL` (32), `ADDITIONAL_HERO_POWER_INDEX` (3919) and `TAG_SCRIPT_DATA_NUM_6` (2921; Replica Cathedral).

---

## 3. Snapshot timing

Measured on the full-game capture (12 combats) and the truncated one (4 combats). All markers are on `GameEntity`, in `PowerTaskList`:

| Step | Marker | What happens |
|---|---|---|
| Combat phase starts | `TURN` → even value, `BOARD_VISUAL_STATE=2` | BG turn = `(TURN+1)/2` (HDT `GetTurnNumber`). Combats are always on even `TURN` |
| Board copy | `3533` 0→1 | Opponent hero, hero power, trinkets, Deity sigil and minion copies are `FULL_ENTITY`'d into SETASIDE with their enchantments |
| Setup | `STEP=MAIN_START_TRIGGERS`, then `2022` 0→1 inside the `TB_BaconShop_8P_PlayerE` trigger | Copies move to PLAY; the opponent slot's `HERO_ENTITY` is repointed; the Deity sigil is placed in SECRET; `3533` goes 1→0. Late-game setups run 1–10k lines |
| **Snapshot** | **`2022` 1→0** (right after `STEP=MAIN_ACTION`) | Both boards are complete and nothing has attacked yet |
| Start of Combat | first blocks after the snapshot | Observed: `Swatting Insects` hero power (`TB_BaconShop_HP_086`, lines 13950 and 152187) and `N'raqi Sapper` (223038) fire **after** 2022→0. So the snapshot is pre-SoC, which matches the simulator running SoC itself |

Rules:
1. Trigger on the `PowerTaskList` 2022 1→0 edge. Don't use `GameState`: the whole combat result is in `GameState` about 16–18 s earlier, and entity state there is ahead of the UI. Firestone's C# parser uses PTL ([BattlegroundsPlayerBoardParser.cs L46-L65](#c-fsc)), and so does HDT ([TagChangeActions.cs L179, L203-L228](#c-hdt)).
2. **Guard against spurious combats.** Only accept the edge when GameEntity `TURN` is greater than the `TURN` at the last shopping start. HDT does this because an extra "combat" occasionally appears inside a shopping turn.
3. **Debounce.** HDT snapshots immediately, then waits `StateChangeDelay = 500` ms and aborts if the state left combat. It waits an extra `LichKingDelay = 2000` ms when Reborn Rites is armed, so the target is known ([BobsBuddyInvoker.cs L31-L38, L195-L265](#c-hdt)). With a pure fold over PTL we can take the snapshot synchronously at the edge. Keep a short debounce only for UI.
4. **Reconnects.** `LoadingScreen.log` `MulliganManager.HandleGameStart() - IsPastBeginPhase()=True` marks a reconnect; a normal start prints `=False` (seen in the fixture). HDT bumps `_reconnectCounter` and discards any combat snapshot taken before it ([BobsBuddyInvoker.cs L71-L79](#c-hdt); [LoadingScreenHandler.cs L153-L157](#c-hdt)). After a reconnect the client re-sends `CREATE_GAME` with every entity. Rebuild state and don't simulate the combat in progress. Firestone also skips local intermediate sims while `reconnectOngoing`.
5. **Duos:** the 3533 1→0 edge is where HDT snapshots each teammate pass. Our entity store can only see a teammate's board once it becomes the active fighter (§7).

---

## 4. Entity selection (who is on which side)

BG has exactly two Player entities: the local player, and an **opponent slot** shared by Bob and the current opponent. Everything is keyed by `CONTROLLER` (or `LETTUCE_CONTROLLER` if present), which is the Player's `PlayerID`, not its entity id.

| Item | Rule | Source |
|---|---|---|
| Local PlayerID | `GameState.DebugPrintGame() - PlayerID=N, PlayerName=…` for the local account (6 in the full log, 2 in the truncated one). The other one is the slot (14 / 10) | log |
| Player-name references | The slot Player entity is named after **the current opponent**, and the name changes every combat. Resolve any `TAG_CHANGE Entity=<name>` that isn't the local name to the slot Player entity. 177 references in the truncated log needed this | observed |
| Hero | Prefer `HERO_ENTITY` on the Player entity. Otherwise use the last HERO in PLAY with that controller, excluding Bob (`TB_BaconShopBob*`) and `TB_BaconShop_HERO_PH`. If it is a ghost (`TB_BaconShop_HERO_KelThuzad`, `…_Deathwhisper`), take the newest non-ghost hero with the same `PLAYER_ID` | FS C# L162-L213 |
| Real opponent PlayerID | The hero's `PLAYER_ID` tag (7 in the example; the slot is 14) | observed |
| Board | CONTROLLER = slot, ZONE=PLAY, CARDTYPE ∈ {MINION, LOCATION, BATTLEGROUND_SPELL}, ordered by `ZONE_POSITION`. **For the opponent, also require `NUM_TURNS_IN_PLAY <= 1`** (treat absent as 0): this drops ghost and reconnect artefacts | FS C# L224-L235 |
| Hand | CONTROLLER = slot, ZONE=HAND, ordered by `ZONE_POSITION`. Both sides' hands are visible at combat (5 opponent minions in the example) | FS C# L246-L265 |
| Secrets | ZONE=SECRET, excluding `QUEST=1`, `SIDE_QUEST=1` and `BACON_IS_BOB_QUEST=1`. The Deity sigil `BG_OldGod` is here | FS C# L236-L245 |
| Quests | ZONE=SECRET, CARDTYPE=SPELL, `QUEST=1` | FS C# L291-L304 |
| Quest rewards | ZONE=PLAY, CARDTYPE=`BATTLEGROUND_QUEST_REWARD` | FS C# L273-L290 |
| Hero powers | ZONE=PLAY, CARDTYPE=`HERO_POWER` (there can be several; HDT takes at most 2) | FS C# L311-L341 |
| Trinkets | ZONE=PLAY, CARDTYPE=`BATTLEGROUND_TRINKET`, ordered by `TAG_SCRIPT_DATA_NUM_6` (1 = lesser, 2 = greater). **Drop the placeholders `BG30_Trinket_1st` / `BG30_Trinket_2nd`**, which appear until the trinket is picked (seen at BG turn 4). Once picked, the same slot entity shows the real card | FS C# L373-L397; observed |
| Enchantments on X | Entities with `ATTACHED = X.id` and ZONE ≠ REMOVEDFROMGAME. For each enchantment with `MAGNETIC=1`, add the `MAGNETIC=1` enchantments of its `CREATOR` (recursive) | FS C# L746-L808 |
| Player enchantments | Enchantments with `ATTACHED = Player entity id`, ZONE=PLAY. In Duos, filter to in-PLAY; the teammate's copies sit in SETASIDE | HDT BobsBuddyInvoker.cs L700-L712 |

---

## 5. Field mapping

Confidence levels:
- **H**: both references agree, and the value was verified in a real capture.
- **M**: one reference, or not exercised in our captures.
- **L**: inferred.

### 5.1 `BgsBattleInfo` / `gameState` / `options`
| Simulator field | Type | Power.log source | Notes / edge cases | Conf |
|---|---|---|---|---|
| `gameState.currentTurn` | number | GameEntity `TURN` → `(TURN+1)/2` | Firestone uses its own turn counter, which has the same value. TURN 22 → turn 11 | H |
| `gameState.anomalies` | string[] | GameEntity `BACON_GLOBAL_ANOMALY_DBID` (2897) → card ID via the card DB | Absent in both captures (no anomaly). Firestone gets it from its game-settings event, which also reads 2897 ([TavernPrizesParser](#c-fsc)) | M |
| `gameState.validTribes` | Race[] | **Not in logs** | Infer it (§7). Firestone and HDT both read it from memory | L |
| `gameState.numberOfPlayersAlive` | number | Count distinct `PLAYER_ID`s over HERO entities with `PLAYER_LEADERBOARD_PLACE > 0`. For each, take the newest entity; alive if `HEALTH + ARMOR − DAMAGE > 0` | Example: 6 alive at turn 11 (places 7 and 8 dead) | M |
| `options.applyDamageCap` | bool | GameEntity `BACON_COMBAT_DAMAGE_CAP_ENABLED` (3403) = 1 | The simulator derives the cap value itself (`<4`: 5, `<8`: 10, else 15; Duos 15; none at ≤4 alive). **Log values:** `BACON_COMBAT_DAMAGE_CAP` = 5 from turn 1, 10 from turn 4 (TURN 7), 15 from turn 8 (TURN 15), which matches. HDT passes the log value (`input.DamageCap`). Firestone's app leaves the cap off. If the log cap ever disagrees with the formula (a new anomaly, a patch), patch `getCombatDamageCap` in our bundle to take the log value | H |
| `options.*` | | — | Use `numberOfSimulations` 8000, `maxAcceptableDuration` about 1500–2000, `includeOutcomeSamples:false`, `skipInfoLogs:true` | — |
| `playerTeammateBoard` / `opponentTeammateBoard` | | Duos only | §7 | L |

### 5.2 `BgsPlayerEntity`
| Field | Type | Source | Notes | Conf |
|---|---|---|---|---|
| `cardId` | string | Hero entity `CardID` (§4) | Keep skin IDs (e.g. `…_SKIN_B4`); the simulator normalises them via the card DB. For a ghost opponent, send the real hero with `hpLeft<=0` and the simulator swaps in Kel'Thuzad | H |
| `entityId` | number | Hero entity id | | H |
| `hpLeft` | number | hero `HEALTH + ARMOR − DAMAGE` | Firestone and HDT agree. Example: 30+0−14 = 16 | H |
| `tavernTier` | number | hero `PLAYER_TECH_LEVEL` (fallback: Player entity `PLAYER_TECH_LEVEL`, then 1) | | H |
| `heroPowers` | `BgsHeroPower[]` | §5.3 | | H |
| `questEntities` | `{CardId, RewardDbfId, ProgressCurrent, ProgressTotal}[]` | quest: `CardID`, `QUEST_REWARD_DATABASE_ID`, `QUEST_PROGRESS`, `QUEST_PROGRESS_TOTAL` | Quests are not active this season (none in captures) | M |
| `questRewards` | string[] | reward entity `CardID`s | | M |
| `questRewardEntities` | `{CardId, ScriptDataNum1}[]` | reward `CardID`, `TAG_SCRIPT_DATA_NUM_1` | PascalCase. HDT also sends `TAG_SCRIPT_DATA_NUM_2` | M |
| `hand` | `BoardEntity[]` | §5.4, for hand entities | Opponent hand: Firestone re-derives pre-combat stats from **tag history**, because a minion summoned from hand gets a `SHOW_ENTITY` with combat-buffed stats (`OverrideTagWithHistory`, FS C# L659-L717). At the 2022→0 snapshot nothing has been summoned yet, so current tags are correct | M |
| `secrets` | `BoardSecret[]` | §5.6 | | H |
| `trinkets` | `BoardTrinket[]` | §5.7 | | H |
| `globalInfo` | object | §6 | | M–H |

### 5.3 `BgsHeroPower`
| Field | Source | Notes | Conf |
|---|---|---|---|
| `cardId`, `entityId` | HP entity | | H |
| `used` | Firestone: `BACON_HERO_POWER_ACTIVATED (1398) == 1`. HDT: `EXHAUSTED \|\| BACON_HERO_POWER_ACTIVATED`, except Duos Embrace Your Rage, which uses `EXHAUSTED` only | In the full game, 1398 is only ever set on the combat-armed `TB_BaconShop_HP_086`. George's Boon of Light has `EXHAUSTED=1` without 1398. The simulator only checks `used` for combat-relevant HPs, so HDT's OR rule is safe. **Use `1398==1 \|\| EXHAUSTED==1`** | H |
| `info` | `TAG_SCRIPT_DATA_NUM_1` (0 if absent), with overrides: **Reborn Rites**: if used and info ≤ 0, the HP's `CARD_TARGET`. **Embrace Your Rage**: if used, the CardID of the newest MINION with `CREATOR` = HP id. **Lock and Load** (`BG22_HERO_000p_Alt`): if used, that created minion as a full `BoardEntity` with enchantments, stats from before `COPIED_FROM_ENTITY_ID`. HDT uses `TAG_SCRIPT_DATA_ENT_1` for L&L. **Rapid Reanimation / Glorious Gloop**: HDT finds the minion carrying `TeronGorefiend_ImpendingDeath` / `FlobbidinousFloop_InTheGloop` via `ATTACHED` | FS C# L501-L596; HDT L526-L600 | M |
| `info2..info6` | `TAG_SCRIPT_DATA_NUM_2..6` | | H (tags present) |
| `scoreValue1..3` | `SCORE_VALUE_1..3` | `scoreValue2` = avenge progress | M |
| `locked` | `LOCK_VISUAL` (4414) | | M |

### 5.4 `BoardEntity` (Firestone `buildBgsEntity`)
| Field | Source | Notes | Conf |
|---|---|---|---|
| `entityId` | entity id | | H |
| `cardId` | current CardID | HDT uses `LatestCardId` because of in-place `CHANGE_ENTITY` transforms (e.g. Lockbox → minion). Our store should overwrite CardID on `SHOW_ENTITY` and `CHANGE_ENTITY` | H |
| `attack` | `ATK` | | H |
| `health` | `HEALTH − DAMAGE` | Reborn-in-shop minions can carry DAMAGE | H |
| `maxHealth` | `HEALTH` | | H |
| `taunt`, `divineShield`, `poisonous`, `venomous`, `reborn`, `stealth` | tag `== 1` | HDT uses `HasTag` (i.e. > 0) | H |
| `windfury` | `WINDFURY ∈ {1,3}` or `MEGA_WINDFURY == 1` | HDT keeps mega-windfury separate. Firestone folds it in | M |
| `scriptDataNum1..6` | `TAG_SCRIPT_DATA_NUM_1..6` (0 if absent) | Remember the default-override in §2.7 | H |
| `locked` | `UNPLAYABLE_VISUALS == 1` or `LITERALLY_UNPLAYABLE == 1` | Matters for hand cards (can they be summoned) | M |
| `tags` | `{4036: BACON_YAMATO_CANNON}` if present | Battlecruiser only | M |
| `additionalCards` | `MODULAR_ENTITY_PART_1/2` dbfIds → card IDs, minus self (plus `BACON_TRIPLED_BASE_MINION_ID{,2,3}` for Zilliax Assembled) | Firestone flags stitched and Zilliax-enchantment boards as "unsupported" ([bgs-utils.ts `isSupportedScenario`](#c-fs)) | M |
| `enchantments` | §5.5 | | H |
| special cases | **Lovesick Balladist**: `TAG_SCRIPT_DATA_NUM_1` = the latest `LovesickBalladist_SerenadedEnchantment` (CREATOR = this) sdn1, halved if golden. **Timewarped Nellie's Ship**: custom enhancer | FS C# L613-L657 | M |

Tags present on every board minion at the snapshot, in both captures: `ATK`, `HEALTH`, (`DAMAGE`), `ZONE_POSITION`, `TECH_LEVEL`, `CARDRACE`, the keyword flags that apply, `PREMIUM` (golden) and `TAG_SCRIPT_DATA_NUM_*` where the card uses them.

### 5.5 `BoardEnchantment`
| Field | Source | Notes | Conf |
|---|---|---|---|
| `cardId` | enchantment CardID | | H |
| `originEntityId` | the **enchantment's own entity id** (what Firestone's C# sends as `EntityId`) | Not the CREATOR | H (parity) |
| `tagScriptDataNum1/2` | enchantment `TAG_SCRIPT_DATA_NUM_1/2` | Carries the buff amount. Example: Hammer of Twilight's aura enchantment `BG36_MagicItem_403e` = 34/17; Death's Embrace `BG36_MidGameEffect_000t29e` sdn2 = 24 | H |
| `timing` | 0 | The simulator assigns it | H |
| extra entries | For `PolarizingBeatboxer_PolarizedEnchantment` and `ClunkerJunker_ClunkyEnchantment_BG29_503e`, add `{cardId: "<dbfId>", originEntityId: CREATOR}`, where dbfId = the creator's `ENTITY_AS_ENCHANTMENT`, else the enchantment's `CREATOR_DBID` | [BattlegroundsActivePlayerBoardParser.cs L494-L511](#c-fsc) | M |

Why enchantments matter: several effects exist **only** as enchantments, such as Dark Gifts like `Jaws of Death` (SoC: trigger deathrattles) and `Death's Embrace`, and trinket auras. Dropping all enchantments moved the example from 73.9% to 76.1% loss.

### 5.6 `BoardSecret` (incl. Deity)
| Field | Source | Notes | Conf |
|---|---|---|---|
| `entityId`, `cardId` | secret entity | For opponent secrets with an empty CardID, Firestone looks up the CardID "from the future" in `GameState` (`BuildEntityWithCardIdFromTheFuture`). In BG, opponent secrets are normally revealed at combat | M |
| `scriptDataNum1/2/3/6` | `TAG_SCRIPT_DATA_NUM_1/2/3/6` | | H |
| **Deity (`BG_OldGod`)** | sdn1 = Aberration deaths still needed (3), sdn2 = attack, sdn3 = health, sdn6 = deity dbfId (130610 = C'Thun `BGFYM_000`; 132532 = Y'Shaarj `BGFYM_011`; same as GameEntity `BACON_GLOBAL_OLD_GOD_DBID` 4902 and the sigil's `BACON_EVOLUTION_CARD_ID`). **Also set `tags: {4914: Player.BACON_OLD_GOD_ATTACK, 4915: Player.BACON_OLD_GOD_HEALTH}`** from the owning Player entity | The simulator reads `tags[4914/4915] ?? sdn2/sdn3 ?? 1` ([deity.ts](#c-sim)). In the example, local 236/222 and opponent 230/338; the Player tags matched sdn2/sdn3 exactly. **Zeroing these flipped 73.9% loss to 78% win.** Firestone's public C# parser predates Deity, so this row is our addition | H |

### 5.7 `BoardTrinket`
| Field | Source | Notes | Conf |
|---|---|---|---|
| `cardId` | trinket entity CardID (latest) | Skip `BG30_Trinket_1st/2nd`. HDT: a Crystal Ball that copied a trinket keeps its old token CardID, so use the latest revealed card | H |
| `entityId` | id | | H |
| `scriptDataNum1`, `scriptDataNum2` | `TAG_SCRIPT_DATA_NUM_1/2` | Current buff values. Example: Corrupted Baton 4/4 (lesser), 10/10 (greater); Hammer of Twilight 34/17 (grown by discards) | H |
| `scriptDataNum6` | `TAG_SCRIPT_DATA_NUM_6` | Slot: 1 lesser, 2 greater. Firestone sorts by it; the simulator re-sorts by entityId | H |
| `tags` | optional: `TRIGGER_VISUAL` (32), `ADDITIONAL_HERO_POWER_INDEX` (3919) | Replica Cathedral: HDT reads tag 4696 into sdn1 | M |

---

## 6. Counters (`globalInfo`)

Read these from the **owning Player entity**, which is the local Player or the opponent slot:
- "tag" rows read the Player entity's tag.
- "ench" rows read `TAG_SCRIPT_DATA_NUM_1/2` of a named enchantment attached to (controlled by) that Player, in ZONE=PLAY.

**Opponent side:** each combat the game attaches a `Bacon_TagTransferPlayerE` to the slot Player carrying the opponent's per-game counters under the same tag ids. HDT prefers it, because a dead (ghost) opponent's own tags can be stale. In the example both sources agreed; for instance 3088 = 32 and 4212 = 101 on both. **Read the transfer enchantment first, then the Player entity.** Also zero stale per-opponent values when `NEXT_OPPONENT_PLAYER_ID` changes (HDT does this for `TAVERN_SPELL_*_INCREASE` and `BACON_BLOODGEMBUFF*VALUE`).

**Name vs number:** the client prints a tag by name only if it knows the name. Most of these were printed as bare numbers in both captures (`3088`, `4212`, `4639`, `4799`, `4768`, `3873`, `3236`, `2717`, `2878`). Normalise to numeric IDs on parse.

| `globalInfo` key | Source | Tag id | Used by (sim) | Conf |
|---|---|---|---|---|
| `EternalKnightsDeadThisGame` | ench `BG25_008pe` sdn1 (HDT also reads sdn3 as the "legion" counter) | — | Eternal Knight | H (FS+HDT) |
| `EternalKnightAttackBuff/HealthBuff` | HDT: `EternalPortrait_GreaterEternalPortraitPlayerEnchDnt` sdn1, or legion enchant sdn1 / 4 | — | Eternal Portrait | L |
| `SanlaynScribesDeadThisGame` | ench `BGDUO31_208pe` sdn1 | — | San'layn Scribe | H |
| `UndeadAttackBonus` / `UndeadHealthBonus` | ench `BG25_011pe` sdn1 / sdn2 (FS only sends attack) | — | undead summons | H |
| `HauntedCarapaceAttackBonus/HealthBonus` | ench `BG33_112pe` sdn1/sdn2 | — | | H |
| `GoldrinnBuffAtk/Health` | ench `BGS_018pe` + `BG34_Giant_362pe` (Timewarped), sdn1/sdn2 summed | — | beast summons | H |
| `AstralAutomatonsSummonedThisGame` | ench `BG_TTN_401pe` sdn1 | — | | H |
| `BeetleAttackBuff/HealthBuff` | ench `BG31_808pe` sdn1/sdn2 | — | | H |
| `DeepBluesPlayed` | ench `BG26_502pe` sdn1 | — | | M |
| `WhelpAttackBuff/HealthBuff` | ench `BG34_402pe` sdn1/sdn2 | — | | H |
| `BloodGemAttackBonus/HealthBonus` | max(ench `BG26_159pe` sdn1/sdn2, tag `BACON_BLOODGEMBUFFATKVALUE` / `…HEALTHVALUE`) | 1844 / 2827 | blood gems | H (HDT max rule) |
| `ChoralAttackBuff/HealthBuff` | `BG26_354e` attached to a board minion: sdn1/sdn2, halved if its CREATOR is `PREMIUM` | — | Choral Mrrrglr | M |
| `TavernSpellsCastThisGame` | tag | 3088 `TAVERN_SPELLS_PLAYED_THIS_GAME` | many | H |
| `SpellsCastThisGame` | tag | 1780 `NUM_SPELLS_PLAYED_THIS_GAME` | | M (not set on the opponent slot) |
| `FrostlingBonus` | tag | 2878 `BACON_ELEMENTALS_PLAYED_THIS_GAME` | Flourishing Frostling | H |
| `PiratesPlayedThisGame` | tag | 2358 `BACON_PIRATES_PLAYED_THIS_GAME` (HDT names this "PiratesSummonCounter") | | M |
| `PiratesSummonedThisGame` | tag | 3685 | | M |
| `BeastsSummonedThisGame` | tag | 3962 | | H |
| `MagnetizedThisGame` | tag | 3670 `BACON_NUM_MAGNETIZE_THIS_GAME` | | H |
| `ElementalAttackBuff/HealthBuff` | tag | 4002 / 4001 | | H |
| `TavernSpellAttackBuff/HealthBuff` | tag on the Player entity first (the game re-writes it after the transfer), else the transfer enchant | 3989 / 3990 | | H |
| `GoldSpentThisGame` | tag | 4212 `BACON_GOLD_SPENT_THIS_GAME` (equals `NUM_RESOURCES_SPENT_THIS_GAME` for the local player). For the opponent, HDT derives it from Malorne if the tag is missing | Malorne | H |
| `BattlecriesTriggeredThisGame` | tag | Firestone reads 3873 `BATTLECRIES_TRIGGERED_THIS_GAME`; **HDT reads 3236 (unnamed)**. Both were 5 on the opponent in the example | | M |
| `DeathrattlesTriggeredThisGame` | tag | 4639 `DEATHRATTLES_TRIGGERED_THIS_GAME` (4640 always had the same value) | Death's Embrace, Falling Sky Golem | M (in reference-data, not in FS C#) |
| `FriendlyMinionsDeadLastCombat` | tag | 2717 `NUM_FRIENDLY_MINIONS_THAT_DIED_LAST_TURN` | | H |
| `VolumizerAttackBuff/HealthBuff` | tag | 4468 / 4469 | | M |
| `GoldenMinionsPlayedThisGame` | tag | 4799 `BACON_GOLDEN_MINIONS_PLAYED_THIS_GAME` | Maritime Extortionist | M |
| `CardsDiscardedThisGame` | tag | 4768 `CARDS_DISCARDED_THIS_GAME` (opponent 16 in the example) | Parasitic Fleshling, discard | M |
| `TastyLobstersBuff` | tag | 4803 `BACON_TASTY_LOBSTER_BUFF` | | M |
| `TavernSpellsCastThisTurn`, `CardsPlayedThisTurn`, `ElementalsPlayedThisTurn` | tags `SPELLS_PLAYED_THIS_TURN` (3491), `NUM_CARDS_PLAYED_THIS_TURN`; no clear elemental-this-turn tag | | Roving Sailor, Brazen Buccaneer, Conflagration | L |
| `MrrgltonsPlayedThisGame`, `BackToBackCastThisGame`, `LastTavernSpellCardId`, `PirateAttackBonus`, `MechAttackBonus`, `MutatedLasher*`, `AdditionalAttack` | no known log source. HDT updates Back to Back from its enchantment sdn1/2 mid-combat. `LastTavernSpellCardId` could be tracked from the last BATTLEGROUND_SPELL played | — | | L |
| `HighestTavernMinion*`, `PiratesPlayedThisGame` (FS), `fodderPerRefresh` | not read by the simulator (0 refs) | — | | — |
| `BeastsSummonedThisCombat`, `RallyMinionAttacksThisCombat`, `FreeRefreshesGainedThisCombat`, `fodderRefreshes`, `maxGoldBonus`, `DiremuckPendingSummons` | combat-internal or write-back; send 0 or omit | — | | — |

The simulator backfills missing keys with 0 ([auras.ts L230-L250](#c-sim)), so omitting a counter only loses precision on the cards that read it.

---

## 7. Not in the logs, and fallbacks

| Needed | Status | Fallback |
|---|---|---|
| `validTribes` (lobby tribes) | Memory only (Firestone `AvailableRaces`, HDT `GetAvailableRaces`) | **Infer from single-tribe pool minions seen**: CARDTYPE=MINION, `IS_BACON_POOL_MINION=1`, card DB `isBattlegroundsPoolMinion`, exactly one race. Collect over the game. Full log: Aberration, Elemental, Quilboar, Dragon, Undead. Truncated log, by turn 4: Aberration, Dragon, Elemental, Demon, Mechanical. Both give 5 clean tribes. Ignore dual-tribe cards (they showed up as Demon/Pirate/Naga noise). Before 5 tribes are known, send `undefined` (all tribes). Map to reference-data `Race` values: BEAST 20, DEMON 15, DRAGON 24, ELEMENTAL 18, MECH 17, MURLOC 14, NAGA 92, PIRATE 23, QUILBOAR 43, UNDEAD 11, ABERRATION 126. Only random-summon pools depend on it |
| Duos teammate boards | Partly: a teammate's board is only in the log while it is the active fighter. Firestone reads the **player's** teammate board from memory, and approximates the opponent's teammate from pending board snapshots | v1: solo only. For Duos, snapshot each 3533 1→0 pass (HDT pattern) and flag results as approximate when a teammate side is missing |
| Opponent board between combats | Only at combat (by design) | Not needed; the simulator runs at combat |
| Hidden opponent secrets | Normally revealed in BG combat | Firestone takes the CardID from GameState ("the future") when the PTL entity is still blank. For us that would mean reading GameState ahead of PTL. Acceptable for the snapshot only |
| Some globalInfo counters (§6 L rows) | No known tag | Default 0; accept small errors on those cards |
| Exact card behaviour | Simulator coverage | 827 implemented cards. HDT refuses to run on unknown or changed cards. Do the same: if a board card has no `cardMappings` entry and has text, mark the result "unsupported". Firestone also flags stitched and Zilliax cases |

---

## 8. Worked example (real captures)

Method:
1. A throwaway Python replayer folded every `PowerTaskList` line up to the snapshot line into an entity/tag store.
2. It handled `CREATE_GAME`, `FULL_ENTITY`, `SHOW_ENTITY`, `CHANGE_ENTITY`, `HIDE_ENTITY` and `TAG_CHANGE`, with name → entity resolution as in §4.
3. It applied §4–§6 to build the input.
4. The input was run through `@firestone-hs/simulate-bgs-battle` 1.1.755 in Node, with the same bundle inputs as the JSC spike and Firestone's `cards_enUS` DB.

### 8.1 Full game, BG turn 11 (TURN 22), `2022` 1→0 at line 223038
- Local: George the Fallen, tier 6, 16 HP, 7 Aberration-heavy minions, hero power `EXHAUSTED`, 2 trinkets (Corrupted Baton lesser and greater), C'Thun sigil at 236/222.
- Opponent: Drest'agath, tier 4, 27 HP, 7 minions, 5 revealed hand minions, Corrupted Baton plus Hammer of Twilight (34/17 aura), C'Thun sigil at 230/338.
- GameEntity: `BACON_COMBAT_DAMAGE_CAP=15`, `…_ENABLED=1`, no anomaly, 6 alive.

**Present at the snapshot for both sides:**
- minion `ATK`/`HEALTH`/`DAMAGE`/keywords, `TAG_SCRIPT_DATA_NUM_*` and attached enchantments with sdn1/sdn2
- hero `HEALTH`/`DAMAGE`/`ARMOR`/`PLAYER_TECH_LEVEL`/`PLAYER_ID`
- hero power entity with `EXHAUSTED`
- trinket entities with sdn1/2/6
- Deity sigil in SECRET with sdn1/2/3/6
- Player-entity counters (numeric tags) and `Bacon_TagTransferPlayerE`
- damage cap

Input (player names and BattleTags never appear; card and entity IDs are game data; zero-valued `globalInfo` keys trimmed for length):

```jsonc
{
  "playerBoard": {
    "player": {
      "cardId": "TB_BaconShop_HERO_15",
      "entityId": 108,
      "hpLeft": 16,
      "tavernTier": 6,
      "heroPowers": [{"cardId": "TB_BaconShop_HP_010", "entityId": 122, "used": true, "info": 0}],
      "trinkets": [{"cardId": "BG36_MagicItem_404", "entityId": 348, "scriptDataNum1": 4, "scriptDataNum2": 4, "scriptDataNum6": 1}, {"cardId": "BG36_MagicItem_404t", "entityId": 349, "scriptDataNum1": 10, "scriptDataNum2": 10, "scriptDataNum6": 2}],
      "secrets": [{"entityId": 351, "cardId": "BG_OldGod", "scriptDataNum1": 3, "scriptDataNum2": 236, "scriptDataNum3": 222, "scriptDataNum6": 130610, "tags": {"4914": 236, "4915": 222}}],
      "questEntities": [], "questRewards": [], "questRewardEntities": [],
      "hand": [
        {"entityId": 15766, "cardId": "BG36_301t", "attack": 0, "health": 0, "enchantments": [{"cardId": "TB_BaconShopBadsongE", "originEntityId": 15767, "timing": 0}], "scriptDataNum1": 1, "scriptDataNum2": 1}
      ],
      "globalInfo": {"TavernSpellsCastThisGame": 20, "SpellsCastThisGame": 20, "GoldSpentThisGame": 86, "DeathrattlesTriggeredThisGame": 24, "GoldenMinionsPlayedThisGame": 2, "CardsDiscardedThisGame": 2}
    },
    "board": [
      {"entityId": 14638, "cardId": "BG36_102", "attack": 21, "health": 21, "maxHealth": 21, "divineShield": true, "enchantments": [{"cardId": "BG28_838e", "originEntityId": 15030, "tagScriptDataNum1": 20, "tagScriptDataNum2": 20, "timing": 0}, {"cardId": "BG_OG_221e", "originEntityId": 15057, "timing": 0}, {"cardId": "BG36_301te", "originEntityId": 15122, "tagScriptDataNum1": 1, "tagScriptDataNum2": 1, "timing": 0}]},
      {"entityId": 13345, "cardId": "BG36_113", "attack": 81, "health": 11, "maxHealth": 11, "reborn": true, "scriptDataNum1": 2, "scriptDataNum2": 1, "enchantments": [{"cardId": "BG36_MidGameEffect_000t74e", "originEntityId": 13346, "timing": 0}, {"cardId": "BG36_MidGameEffect_000t74e2", "originEntityId": 13347, "tagScriptDataNum1": 69, "timing": 0}, {"cardId": "BG36_301te", "originEntityId": 13348, "tagScriptDataNum1": 6, "tagScriptDataNum2": 6, "timing": 0}, {"cardId": "BG28_168e", "originEntityId": 13349, "tagScriptDataNum1": 2, "tagScriptDataNum2": 2, "timing": 0}, {"cardId": "BG28_897e", "originEntityId": 13350, "tagScriptDataNum1": 2, "tagScriptDataNum2": 2, "timing": 0}]},
      {"entityId": 13351, "cardId": "BG36_101_G", "attack": 106, "health": 18, "maxHealth": 18, "divineShield": true, "enchantments": ["…8 enchantments: BG36_301te ×2, BG28_168e ×2, BG36_MidGameEffect_000t74e/74e2 (sdn1 90), BG_OG_221e, BG31_880te2 (1/3)"]},
      {"entityId": 13362, "cardId": "BG36_106", "attack": 67, "health": 67, "maxHealth": 67, "divineShield": true, "scriptDataNum1": 4, "scriptDataNum2": 4, "enchantments": [{"cardId": "BG36_MidGameEffect_000t29e", "originEntityId": 13363, "tagScriptDataNum2": 24, "timing": 0}, {"cardId": "BG36_106e", "originEntityId": 13364, "tagScriptDataNum1": 8, "tagScriptDataNum2": 8, "timing": 0}, "…BG36_301te, BG_OG_221e, BG28_168e"]},
      {"entityId": 13368, "cardId": "BG36_098_G", "attack": 14, "health": 12, "maxHealth": 12, "divineShield": true, "enchantments": ["…BG_OG_221e, BG36_301te (6/6), BG28_168e (2/2)"]},
      {"entityId": 13372, "cardId": "BG35_123", "attack": 14, "health": 18, "maxHealth": 18, "divineShield": true, "enchantments": ["…BG_OG_221e, BG36_301te (6/6), BG28_168e (2/2)"]},
      {"entityId": 13376, "cardId": "BG25_354", "attack": 5, "health": 11, "maxHealth": 11, "divineShield": true, "enchantments": ["…BG_OG_221e, BG36_301te (2/2), BG28_168e (2/2)"]}
    ]
  },
  "opponentBoard": {
    "player": {
      "cardId": "BG36_HERO_000",
      "entityId": 16482,
      "hpLeft": 27,
      "tavernTier": 4,
      "heroPowers": [{"cardId": "BG36_HERO_000p", "entityId": 16090, "used": true, "info": 0}],
      "trinkets": [{"cardId": "BG36_MagicItem_404", "entityId": 16092, "scriptDataNum1": 4, "scriptDataNum2": 4, "scriptDataNum6": 1}, {"cardId": "BG36_MagicItem_403t", "entityId": 16093, "scriptDataNum1": 34, "scriptDataNum2": 17, "scriptDataNum6": 2}],
      "secrets": [{"entityId": 16091, "cardId": "BG_OldGod", "scriptDataNum1": 3, "scriptDataNum2": 230, "scriptDataNum3": 338, "scriptDataNum6": 130610, "tags": {"4914": 230, "4915": 338}}],
      "questEntities": [], "questRewards": [], "questRewardEntities": [],
      "hand": [
        {"entityId": 16096, "cardId": "BG36_102", "attack": 4, "health": 8, "maxHealth": 8},
        {"entityId": 16098, "cardId": "BG36_102", "attack": 4, "health": 8, "maxHealth": 8},
        {"entityId": 16101, "cardId": "BG36_106", "attack": 4, "health": 4, "maxHealth": 4},
        {"entityId": 16103, "cardId": "BG36_115", "attack": 7, "health": 4, "maxHealth": 4},
        {"entityId": 16105, "cardId": "BG36_311", "attack": 3, "health": 4, "maxHealth": 4}
      ],
      "globalInfo": {"TavernSpellsCastThisGame": 32, "GoldSpentThisGame": 101, "BattlecriesTriggeredThisGame": 5, "DeathrattlesTriggeredThisGame": 13, "GoldenMinionsPlayedThisGame": 1, "CardsDiscardedThisGame": 16}
    },
    "board": [
      {"entityId": 16485, "cardId": "BG36_103", "attack": 43, "health": 21, "maxHealth": 21, "enchantments": [{"cardId": "BG36_MidGameEffect_000t16e", "originEntityId": 16486, "timing": 0}, {"cardId": "BG31_880te", "originEntityId": 16487, "tagScriptDataNum1": 3, "tagScriptDataNum2": 1, "timing": 0}, {"cardId": "BG36_MagicItem_403e", "originEntityId": 16488, "tagScriptDataNum1": 34, "tagScriptDataNum2": 17, "timing": 0}]},
      {"entityId": 16489, "cardId": "BG36_115", "attack": 44, "health": 25, "maxHealth": 25, "taunt": true, "enchantments": ["…BG28_520e2, BG28_520e (1/2), BG36_301te (2/2), BG36_MagicItem_403e (34/17)"]},
      {"entityId": 16494, "cardId": "BG36_113_G", "attack": 58, "health": 43, "maxHealth": 43, "taunt": true, "reborn": true, "scriptDataNum1": 4, "scriptDataNum2": 2, "enchantments": ["…BG36_624e (4/8), BG36_301te (8/8), BG28_168e (1/1), BG28_825e (7/7), BG36_MagicItem_403e (34/17)"]},
      {"entityId": 16500, "cardId": "BG36_311", "attack": 46, "health": 30, "maxHealth": 30, "enchantments": ["…BG36_301te (8/8), BG28_168e (1/1), BG36_MagicItem_403e (34/17)"]},
      {"entityId": 16504, "cardId": "BG36_108", "attack": 76, "health": 117, "maxHealth": 117, "scriptDataNum1": 1, "scriptDataNum2": 3, "enchantments": ["…BG36_108e (30/90), BG36_301te (8/8), BG28_168e (1/1), BG36_MagicItem_403e (34/17)"]},
      {"entityId": 16509, "cardId": "BG36_108", "attack": 75, "health": 112, "maxHealth": 112, "taunt": true, "scriptDataNum1": 1, "scriptDataNum2": 3, "enchantments": ["…BG28_966e (1/2), BG36_108e (27/81), BG36_301te, BG28_168e, BG28_520e2, BG28_520e, BG36_MagicItem_403e"]},
      {"entityId": 16517, "cardId": "BG36_101", "attack": 44, "health": 30, "maxHealth": 30, "taunt": true, "enchantments": ["…BG36_301te (8/8), BG28_503e (sdn2 3), BG28_168e (1/1), BG36_MagicItem_403e (34/17)"]}
    ]
  },
  "options": {"numberOfSimulations": 8000, "maxAcceptableDuration": 2000, "skipInfoLogs": true, "includeOutcomeSamples": false, "applyDamageCap": true},
  "gameState": {"currentTurn": 11, "anomalies": [], "numberOfPlayersAlive": 6}
}
```

(`"…"` entries summarise enchantments that were built the same way: the full input has every one as a `BoardEnchantment` object. Boolean false, zero `scriptDataNum*` and empty `tags` are omitted. `N'raqi Sapper` carries the Dark Gift `Jaws of Death` (`BG36_MidGameEffect_000t16e`), which is the SoC trigger seen right after 2022→0.)

**Result vs reality:**

| Run | won / tied / lost | avg dmg lost (90% range) |
|---|---|---|
| Full mapping | 8.2 / 17.9 / **73.9** | **8.8 (7–13)** |
| **Actual combat** | **lost** | **10** (hero `DAMAGE` 14→24; `DAMAGE_DEALT_TO_HERO_LAST_TURN=10`) |
| No enchantments | 7.4 / 16.5 / 76.1 | 8.9 |
| No secrets (no Deity) | 1.6 / 3.6 / 94.8 | 10.6 |
| Deity without stats (health falls back to 1) | **78.0** / 15.3 / 6.7 | 7.8 |
| No trinkets | 10.0 / 21.2 / 68.8 | 8.7 |
| Bare (no enchantments, secrets, trinkets, hand or globalInfo) | 6.3 / 8.2 / 85.5 | 9.7 |

8000 sims took about 1.6 s in Node for this 7v7 late board, so budget `maxAcceptableDuration` accordingly (the small-board JSC spike took about 0.3 s).

### 8.2 Truncated capture, BG turn 4 (TURN 8), `2022` 1→0 at line 36936
- Local: Kith'ix `BG36_HERO_002`, tier 2, 30 HP + 4 armour, 5 minions (golden Unwilling Slacker, Crackling Cyclone with Taunt/DS/WF, Joyous, Dune Dweller, Underrot Spawn). Hero power `BG36_HERO_002p` has sdn3=2. Trinkets are **still placeholders** (`BG30_Trinket_1st/2nd`, filtered). Y'Shaarj sigil sdn2/3 = 3/3.
- Opponent: Farseer Nobundo `BG31_HERO_003`, tier 2, 30 + 9 armour, 3 minions carrying `BG35_951e` (1/2) and `BG28_503e` (Fortification) enchantments, Y'Shaarj sigil 5/5.
- GameEntity `BACON_COMBAT_DAMAGE_CAP=10`, set at TURN 7. The simulator formula also gives 10 at turn 4.
- **Simulated 95.6% loss, 3.2 avg damage (range 3–4). Actual: loss, 3 damage** (armour 4→1).

---

## 9. Known gaps and risks

1. **Patch drift in unnamed and numeric tags.** 2022, 3533, 3236, 4639, 4768, 4799, 4803, 4914/4915 and others print as numbers or carry recent names. reference-data 3.0.211 already names most of them, so vendor its `GameTag` map with the bundle so both sides agree. Keep a capture per patch and re-run §8 as a golden test.
2. **The MIT C# parser lags the live game** (last update 35.0, March 2026). Deity (§5.6), Dark Gifts and newer counters (4639, 4768, 4799, 4803) come from reference-data and simulator reads, not from Firestone's public parser. Watch the simulator changelog; it updates almost daily.
3. **`defaultScriptDataNum` override** on board minions (§2.7) can mask a real log sdn1. This is Firestone's intended behaviour; reproduce it rather than fight it.
4. **Opponent counters when facing a ghost:** use the TagTransfer enchantment (§6). Not exercised in our captures.
5. **Reborn Rites, Lock and Load, Embrace Your Rage, Rapid Reanimation targets** need the special cases in §5.3. HDT delays 2 s for Reborn Rites. Not exercised in our captures.
6. **Opponent hand stats** are safe at the snapshot. Anything captured later (e.g. after a Bassgill-style summon) needs Firestone's tag-history rewind.
7. **Battlecry counter disagreement:** Firestone reads 3873 and HDT reads 3236. They agreed in the captures; prefer 3873 (the name is in reference-data) and log a warning if they diverge.
8. **validTribes inference** is heuristic before about turn 3. Wrong tribes only skew random summons.
9. **Duos** is incomplete from logs alone (§7).
10. **Performance:** late boards take about 1.5 s per 8000 sims. Use the generator's intermediate yields, and run on a dedicated `JSVirtualMachine` thread.
11. **Licensing:** the simulator is MIT per package.json but the tarball has no LICENSE file. The C# parser is MIT with a LICENSE file. The Firestone app and HDT code are reference only: this doc restates their behaviour; no code was copied.

---

## 10. Citations

<a id="c-sim"></a>**Simulator (`@firestone-hs/simulate-bgs-battle@1.1.755`, sources recovered from `dist/**/*.js.map`):** https://www.npmjs.com/package/@firestone-hs/simulate-bgs-battle/v/1.1.755
- `dist/bgs-battle-info.d.ts`, `bgs-board-info.d.ts`, `bgs-player-entity.d.ts`, `board-entity.d.ts`, `board-secret.d.ts`, `bgs-battle-options.d.ts`: the type contract (§2)
- `simulate-bgs-battle.ts` L199 (`cardsData.inititialize(validTribes, anomalies)` in the Lambda handler), L221 `simulateBattle`, L360–L412 `runSingleBattle` (reads `currentTurn`, `numberOfPlayersAlive`, `applyDamageCap`, `validTribes`, `anomalies`)
- `input-sanitation.ts` L12 `buildFinalInput`, L117–L170 per-player sanitation (ghost → Kel'Thuzad, `hpLeft` clamp, trinket filter and sort), L196 `sanitizeEntity` (default sdn1 override)
- `simulation/auras.ts` L12 `setMissingAuras`, L169–L250 `setImplicitDataHero` (avenge from `scoreValue2`, questRewardEntities remap, globalInfo defaults)
- `simulation/enchantments.ts` L4 `fixEnchantments` (dbfId `cardId`, timing)
- `simulation/damage-cap.ts` (cap formula); `simulation/deity.ts` (Deity tags 4914/4915, sdn1/2/3/6)
- `cards/cards-data.ts` L150 `inititialize`, L264 `defaultScriptDataNum`; `utils.ts` L706 `addImpliedMechanics`
- `cards/impl/trinket/hammer-of-twilight.ts`, `corrupted-baton.ts`, `cards/impl/enchantments/jaws-of-death.ts`, `deaths-embrace.ts`: examples of trinket and enchantment sdn reads

**reference-data 3.0.211** (`dist/enums/game-tags.js`, `dist/enums/race.js`): https://www.npmjs.com/package/@firestone-hs/reference-data/v/3.0.211

<a id="c-fsc"></a>**Firestone C# log parser (MIT)**, commit `6586ae1bb07443ecc47d2683d114a65bdfed1b00`:
- `BattlegroundsPlayerBoardParser.cs`: https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/BattlegroundsPlayerBoardParser.cs
  - L46–L65: trigger on PTL `BG_BATTLE_STARTING` = 0
  - L152–L371: `CreateProviderFromAction`
  - L373–L397: trinkets
  - L399–L499: `BuildGlobalInfo`
  - L501–L596: HP special cases
  - L613–L717: entity enhancers and hand rewind
  - L746–L808: enchantments and magnetic recursion
- `BattlegroundsActivePlayerBoardParser .cs` L494–L511 (`BuildAdditionalEnchantments`): https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays/Events/Parsers/BattlegroundsActivePlayerBoardParser%20.cs#L494-L511
- `ReplayData/Entities/BaseEntity.cs` L68–L98 (`TakesBoardSpace`, `GetEffectiveController`); `Events/Parsers/Utils/BgsUtils.cs` L11–L25 (ghost, bartender); `Enums.cs` (`BG_BATTLE_STARTING = 2022`); `BattlegroundsTavernPrizesParser.cs` L55 (anomaly from 2897): https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/tree/6586ae1bb07443ecc47d2683d114a65bdfed1b00/HearthstoneReplays
- LICENSE: https://github.com/Zero-to-Heroes/hs-game-converter-csharp-port/blob/6586ae1bb07443ecc47d2683d114a65bdfed1b00/LICENSE

<a id="c-fs"></a>**Firestone app (unlicensed, reference only)**, commit `0a30f066eb77a417637d95cec86444456f607ba1`:
- `libs/game-state/src/lib/services/game-events/event-parser/battlegrounds/bgs-player-board-parser.ts`: https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/services/game-events/event-parser/battlegrounds/bgs-player-board-parser.ts
  - L298–L313: `BgsBattleInfo` assembly
  - L561–L638: `buildBgsBoardInfo` (hpLeft, tier, globalInfo)
  - L672–L734: hero power payload
- `libs/game-state/src/lib/models/battlegrounds/bgs-player.ts` L136–L193 `buildBgsEntity`, L222–L243 `buildEnchantments`: https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/libs/game-state/src/lib/models/battlegrounds/bgs-player.ts#L136-L243
- `libs/game-state/src/lib/services/game-events/event-parser/battlegrounds/bgs-global-info-update-parser.ts` L78 (races from memory); `libs/game-state/src/lib/services/battlegrounds/bgs-utils.ts` L333–L380 (`isSupportedScenario`); `libs/electron-edge-libs/game-events-edge.js` (loads `HearthstoneReplays.dll`): https://github.com/Zero-to-Heroes/firestone/tree/0a30f066eb77a417637d95cec86444456f607ba1/libs

<a id="c-hdt"></a>**HDT (All Rights Reserved, reference only)**, commit `ef8ab6e8380a647d757eec203d310395d6b97ae0`:
- `Hearthstone Deck Tracker/BobsBuddy/BobsBuddyInvoker.cs`: https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyInvoker.cs
  - L31–L38: constants (10,000 iterations, 500 ms, 1500 ms, LichKingDelay 2000)
  - L71–L79: reconnect counter
  - L195–L265: `StartCombat`
  - L454–L884: `SetupInputPlayer` (hero HP, HPs, quests, trinkets, sigil, hand, TagTransfer, counters)
  - L886–L983: `SnapshotBoardState` (`DamageCap` from 2089/3403, anomaly, turn)
- `BobsBuddy/BobsBuddyUtils.cs` L35–L79 (`GetMinionFromEntity`), L439–L461 (`GetTrinketFromEntity`), L488–L497 (`WasHeroPowerActivated`): https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/BobsBuddy/BobsBuddyUtils.cs
- `LogReader/Handlers/TagChangeActions.cs` L179–L184, L203–L228 (2022/3533 handlers, TURN guard): https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/TagChangeActions.cs#L179-L228
- `LogReader/Handlers/LoadingScreenHandler.cs` L153–L157 (reconnect detection): https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/LogReader/Handlers/LoadingScreenHandler.cs#L153-L157
- `Hearthstone/GameV2.cs` L530–L535 (`GetTurnNumber`): https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/Hearthstone/GameV2.cs#L530-L535

**Local captures (read-only):** `/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_33_28/Power.log` (lines 29826–36936 for §8.2) and `fixtures/private-logs/Hearthstone_2026_09_22_21_08_40/Power.log` (lines 209608–223038 for §8.1; SoC evidence at 13950, 152187, 223038).
