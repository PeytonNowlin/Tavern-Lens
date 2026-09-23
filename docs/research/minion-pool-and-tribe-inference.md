# Live Battlegrounds minion pool (36.6.1) and lobby-tribe inference

Research date: **2026-09-22** (local EDT; some sources are timestamped in UTC on 2026-09-23). This follows on from [meta-comps-2026-09.md](meta-comps-2026-09.md), [aberrations-2026-09.md](aberrations-2026-09.md), [ecosystem-and-data-sources.md](ecosystem-and-data-sources.md) and [log-validation-2026-09-22.md](log-validation-2026-09-22.md). Scripts are in [validation-scripts/pool/](validation-scripts/pool/); run `fetch.sh` first. No BattleTags appear below.

## TL;DR

- **No client card data describes the 36.6.1 pool.** 36.6.1 was a server-side change. The newest build is still **251952**: the newest HearthstoneJSON build directory, hsdata commit `5212f4e178` "Update to patch 36.6.0.251952" (2026-09-15), and `BuildNumber=251952` in both local logs. In that build, `IS_BACON_POOL_MINION` (tag 1456) shows the **36.6.0 pool with the Aberrations added**:
  - all 35 removed minions are still flagged;
  - all 24 Naga cards are still flagged;
  - 24 of the 25 returning minions are unflagged;
  - 9 of the 10 new non-Aberration minions are unflagged;
  - 3 tavern spells are wrong.
- **HDT and HSTracker patch it at runtime** from an HSReplay endpoint, `https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/`. On 2026-09-22 it returned `"name":"Real 36.6.1"`. It lists the tribes in rotation (`minion_types`, no Naga) and 58 per-card `tag_overrides` on tag 1456. This is the best machine-readable source, but it is **incomplete**:
  - it misses 2 removals (Auto Assembler, Mama Mrrglton);
  - it misses 9 new minions and 2 new Duos minions, and Heroic Broodmother and Hopebringer from that list both appeared in the local game;
  - it has no spell overrides.
- **Recommendation:** use three layers, applied in this order: build card DB, then the HSReplay live meta period, then **our own override file** checked into the repo. Add two safety nets:
  - a CI cross-check against the hsbg.cards pool API and patch-diff API;
  - a runtime self-heal. The server stamps `IS_BACON_POOL_MINION=1` on the pool-minion entities it sends in Power.log, and that stamp matched the live pool for all 13 cards that build 251952 gets wrong.
- **The resulting pool:** 251 solo minions (T1 21, T2 34, T3 43, T4 59, T5 49, T6 33, T7 12) plus 28 Duos-only minions, and 76 tavern spells. Every minion seen in both local games is in it, at the tier the server reported.
- **Tribes:** a lobby has **5 tribes**, and until about 2026-10-06 one of them is always Aberration. That leaves 4 of the other 9, so there are C(9,4) = 126 possible lobbies. Nothing in the log names the lobby's tribes. A Bayesian filter over the 126 lobbies, fed shop draws, opponent boards and discover options, identified the correct lobby **by BG turn 4 in both local games** (10–14 shop minions seen). A simulation over random lobbies gives:
  - median turn 4 (p90 turn 5–7) for typical play;
  - median turn 6 (p90 turn 9) for the worst case: no rerolls and shop evidence only.

  No simulated lobby was ever resolved to the wrong answer.

---

## Part A: sources for the pool

### A.1 hsdata / HearthstoneJSON (build 251952)

| Check | Result | Evidence |
|---|---|---|
| Is there a build newer than 251952? | **No.** The newest `/v1/` directories are `…251332, 251951, 251952`, and `latest/enUS/cards.json` has `last-modified: Wed, 16 Sep 2026 11:00:45 GMT`. The latest hsdata commits are `5212f4e178` (2026-09-15, 36.6.0.251952), `e5df710473` (09-08, 36.4.2.251951) and `dee8a641ef` (09-03). `/v1/latest/CardDefs.Bacon.xml` returns 404; CardDefs are only on hsdata. | https://api.hearthstonejson.com/v1/ ; https://api.github.com/repos/HearthSim/hsdata/commits |
| Pool tags in `CardDefs.Bacon.xml` (`<CardDefs build="251952">`, 15.8 MB) | `IS_BACON_POOL_MINION` enumID **1456**: 301 cards with value 1, all of which also have `TECH_LEVEL`. `IS_BACON_POOL_SPELL` enumID **3081**: 77. There is no tag named `*REMOVED*`, `*ROTATED*` or `*BANNED*`. | https://github.com/HearthSim/hsdata/raw/5212f4e178/CardDefs.Bacon.xml |
| `BACON_SUBSET_<TRIBE>` tags (e.g. `BACON_SUBSET_ABERRATION` = 4757, `_NAGA`, `_MECH` …) | Pool cards carry 276 of these tags between them (dual-types have two), **and they are also on unflagged returning cards** such as Hot-Air Surveyor and all the Volumizers. They are tribe-group tags (hero powers, Discover), not pool markers. `BACON_SUBSET_ABERRATION` is absent on Oozeling Gladiator, although that card is typed Aberration. | same file |
| Duos-only | `IS_BACON_DUOS_EXCLUSIVE` is on 28 pool cards. HearthstoneJSON exposes it as `isBattlegroundsDuosExclusive`. | same file |
| Raw value vs bool | HDT/HSTracker check `IS_BACON_POOL_MINION == 1` because "Rot Hide Gnoll has 2 but is not in the pool". HearthstoneJSON's `isBattlegroundsPoolMinion` is a bool, so use the raw XML value, or HSJSON plus that exception. | `HSTracker/Database/Models/Card.swift:71`; `HDT/Hearthstone/BattlegroundsDb.cs` |
| Correct for 36.6.1? | **No.** See the table below. The build has the Aberrations and the new tavern spells flagged, and it already has 36.6.1's tier changes (Bronze Warden T2, Ghastcoiler T5). Everything else still flags the 36.6.0 pool. | `validation-scripts/pool/parse_bacon_xml.py` output |

State of the 36.6.1 changes in build 251952:

| 36.6.1 change (Blizzard) | Count | Flag in build 251952 |
|---|---|---|
| Removed minions | 35 | all still `1` |
| Naga rotated out | 24 Naga-typed cards (22 pure Naga + Ominous Seer, Firescale Hoarder) | all still `1` |
| Returning minions | 25 | 24 unflagged. Geomagus Roogug is already `1` |
| New non-Aberration minions | 10 | 9 unflagged. Holy Vanguard is already `1` |
| New Aberrations (25 + 2 Deities) | 27 | the 25 shop Aberrations are `1`; C'Thun and Y'Shaarj are not flagged, which is correct because they are not shop cards |
| Removed spells (Mounting Avalanche `BG33_899`, Deepwater Clan `BG35_149`) | 2 | still `IS_BACON_POOL_SPELL` |
| Returning spell Seafood Stew `BG32_337` | 1 | `false` |
| New spells (Sludge Corrosion, Corrupted Coin, Energizing Chamber) | 3 | `true` (correct) |

**Verdict:** hsdata/HSJSON is the right source for card identity, text, tier, races and the Duos flag. It **cannot** be the pool source for a server-side patch. hsdata will only change with the next client build.

### A.2 Firestone (`@firestone-hs/reference-data`, static.zerotoheroes.com)

- The reference-data repo is current. Recent commits: `8d8fdd4d91` "update enums for 251952" (2026-09-22T12:03Z), `e6c3238a72` "update reference cards for 251952" (09-20), and `203286efc0` "add ABERRATION to valid BG races" (09-18). https://github.com/Zero-to-Heroes/hs-reference-data/commits
- **Card JSON:** `static.zerotoheroes.com/data/cards/cards_enUS.gz.json` has `last-modified: Sun, 20 Sep 2026 20:20:50 GMT`. Its `isBaconPool` **copies the stale build flag**:
  - Fire-forged Evoker, Warpwing, Fauna Whisperer and Oozeling Gladiator are `true`;
  - Dune Dweller, Hot-Air Surveyor, Heroic Broodmother, Bronze Warden and the Volumizers have no `isBaconPool`, and no `techLevel` either.
- **Pool logic** (`libs/battlegrounds/core/src/lib/services/cards-in-game.ts`, `getAllCardsInGame`). It keeps a card when all of these hold:
  - `isBaconPool` is set;
  - it is not Vanilla, not an `UPGRADE` spell school card, and not a buddy;
  - the Duos/Solo-exclusive mechanics match the mode;
  - it passes the timewarped, Darkmoon and trinket feature flags;
  - it passes per-card `cards_rules.json` (`bgsMinionTypesRules.needTypesInLobby` / `bannedWithTypesInLobby`);
  - `getTribesForInclusion(card)` intersects `availableTribes`.

  `availableTribes` comes from **memory reading**: `bgs-global-info-update-parser.ts` reads `game.AvailableRaces`. `bgs-utils.ts` hard-codes `ALL_BG_RACES`, which still includes NAGA and now ABERRATION, `TOTAL_RACES_IN_GAME = 5`, and a `NON_BUYABLE_MINION_IDS` exclusion list of tokens and hero-power minions. `getTribesForInclusion` also hard-codes neutral cards that are gated to a tribe. For example, Disguised Graverobber appears only when Undead are in the lobby, Nadina only with Dragons, and Majordomo and Master of Realities only with Elementals.
- `cards_rules.json` (1,301 entries) also has **hero** tribe rules, for example Ysera/Alexstrasza need DRAGON and Patches needs PIRATE (used in B.2). It has **no rules for the Aberration cards yet**.
- **Caveat:** the public app repo https://github.com/Zero-to-Heroes/firestone was last committed on 2026-02-08 (`0a30f066eb`), so the app code above is from that snapshot. The reference-data package is current.
- **Verdict:** Firestone has no automatable removed/rotated pool list. Its correctness comes from reading `AvailableRaces` from memory, not from the card data. It is useful for the tribe-gating rules only.

### A.3 HDT and HSTracker (reference only)

- HDT v1.58.1 (`ef8ab6e838`, 2026-09-22) and HSTracker 3.6.12 (`c723bfd4a7`, 2026-09-22) build the tier lists the same way, in `Hearthstone/BattlegroundsDb.cs` and `HSTracker/Utility/BattlegroundsDb.swift`:
  1. `baconCards` = every card with `TECH_LEVEL > 0 && IS_BACON_POOL_MINION == 1`, read through a `TagLookup` that applies **remote `tag_overrides`** (keyed by dbfId and tag).
  2. `Races` comes from the remote `minion_types`. If that isn't loaded yet, it falls back to every race in `baconCards`. The comment reads: "the card data can carry minions of a tribe that is not in rotation (yet), so the meta period decides which tribes exist".
  3. Cards are bucketed by tier and by primary + secondary race. Secondary races come from `RaceTagMap`. Solo and Duos are split with `IS_BACON_DUOS_EXCLUSIVE`, and spells with `IS_BACON_POOL_SPELL`.
- The remote endpoint is in `Utility/RemoteData/Remote.cs`: `https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/`, with `?region=<BnetRegion>` when the region is known. HDT's CardDefs come from `https://api.hearthstonejson.com/v1/latest/CardDefs.{key}.xml` (`CardDefsManager.cs`).
- The **lobby's** tribes come from memory: HSTracker's `game.availableRaces` "reads live from a game-memory mirror". Neither app infers tribes from the log.

### A.4 HSReplay live meta period (fetched 2026-09-22 ~21:50 EDT, unauthenticated, HTTP 200, 2,439 bytes)

```json
{"period_start":1790097494000,"name":"Real 36.6.1","season_number":14,
 "mechanics":["trinkets","dark_gifts","aberrations"],
 "minion_types":[20,24,15,18,17,14,23,43,11,126],
 "tag_overrides":[{"dbf_id":120021,"tag":1456,"value":0}, … 58 entries]}
```

- `period_start` is 2026-09-22T17:18:14Z. `minion_types` decodes to Beast, Dragon, Demon, Elemental, Mech, Murloc, Pirate, Quilboar, Undead and Aberration. **Naga (92) is absent.** `?region=REGION_US` and `REGION_EU` returned identical bodies.
- There are 58 overrides, all on tag 1456:
  - 33 set it to `0`: the Blizzard removed list minus Auto Assembler and Mama Mrrglton;
  - 25 set it to `1`: exactly the 25 returning minions.
- **Gaps:**
  - Auto Assembler `BG32_172` and Mama Mrrglton `BG35_140` are not overridden, so they stay in the pool by mistake.
  - The 9 unflagged new minions are not overridden. They are Greedy Conniver, Sacrificial Wrathguard, Sewer Escapee, Hopebringer, Lichling Hoarder, Resourceful Robot, Auto Reveille, Heroic Broodmother and Victorious Geomant.
  - The 2 new Duos minions are not overridden either (Voidpriest Cloner `BGDUO_700`, C'Thrax Wrecker `BGDUO_701`).
  - There are no spell (3081) overrides.

  Local evidence: Heroic Broodmother was in Bob's shop and Hopebringer was a discover option in the 21:08 game. Victorious Geomant also appeared in that game with the server's pool flag.
- **Risks:** the endpoint is undocumented, has no stated terms, and is built for HDT's own use. Treat it as best-effort.

### A.5 hsbg.cards (third party)

- `GET https://hsbg.cards/api/v1/cards?pool=true&limit=100&offset=N` returns `filters.pool = "current"` and 1,423 entries: 284 `minion`/`tavern`, 76 `spell`/`tavern`, 247 trinkets, and more. `GET /api/v1/patches` and `/api/v1/patches/36.4.2_36.6.1` (generated 2026-09-22T20:31Z) return a structured diff. It has sections for new Aberrations, Dark Paradox, new minions, returning (25), removed (35), **"Naga Rotated Out" (22)**, spells and trinkets, and every name matches the Blizzard post.
- Its current-pool list agrees with our final pool on every card except these 13:
  - It files the 3 Volumizers under `token`. **That is wrong for pool purposes:** a Red Volumizer was in Bob's shop, flagged pool=1 by the server, in the 20:33 game.
  - It lists Fishbait `BG36_205` as a tavern card. Fishbait is a token that Lurking Lionfish and Snarky Shark give, so this is probably wrong.
  - It omits Flourishing Frostling `BG26_537`. That card is not on any Blizzard 36.6.1 list, and both HSJSON and HSReplay keep it in the pool, so it is **unresolved**.
  - It lists the Deities C'Thun and Y'Shaarj and the 6 Dark Paradox variants as `tavern` cards.
- **Verdict:** this is the best patch-diff source (names plus dbf ids), and it is a good CI cross-check. It is not a primary source: it is third party, its licence is unknown, and it miscategorises a few cards.

### A.6 Blizzard official (cross-check)

- "Aberrations Join Battlegrounds at BlizzCon!" (dated 09/12/2026, "will go live with Patch 36.6.1 on September 22"): https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon. It lists:
  - 35 removed minions (reproduced in section A.9);
  - 25 returning minions;
  - 27 new Aberration minions, Dark Paradox and 10 other new minions;
  - "Naga will be rotated out of the minion pool. Naga-specific heroes and cards will be unavailable while Naga are out of the pool";
  - "Aberrations will appear in every lobby during the first two weeks … starting September 22";
  - hero bans (Morchie; Murozond, Unbounded; Sylvanas; plus 4 heroes in Y'Shaarj games only);
  - spells: removed Mounting Avalanche and Deepwater Clan, returning Seafood Stew, new Sludge Corrosion, Corrupted Coin and Energizing Chamber;
  - trinkets: 15 new Lesser, 16 new Greater, and the removed and returning ones;
  - Duos: Voidpriest Cloner and C'Thrax Wrecker.
- The 36.6.1 balance changes are in the hotfix post https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846 (see meta-comps §2). None of them are pool changes.
- The post doesn't state the tribe count per lobby. The 5-tribe count comes from Firestone's `TOTAL_RACES_IN_GAME = 5` and from the logs (B.1).

### A.7 Empirical check against the two local captures (read-only)

Timing: both logs report `BuildNumber=251952`, `GT_BATTLEGROUNDS`, `ScenarioID=3459`. The machine is on EDT, so the folders `…_20_33_28` and `…_21_08_40` are 00:33Z and 01:08Z on 2026-09-23. That is about 7 h after HSReplay's `period_start` for 36.6.1 and after the EU/US rollout reports in aberrations-2026-09.md.

The 20:33 game is also post-36.6.1 on content alone:
- its shop had Aberrations (Joyous, Zoatroid, Underrot Spawn);
- it had returning minions (Dune Dweller, Bronze Warden at T2, Red Volumizer);
- the local hero was Kith'ix.

Method (`tribe_events.py`): a **shop sighting** is an entity controlled by the bartender slot, in `ZONE=PLAY`, with `CARDTYPE=MINION`. It must be seen at a `PowerProcessor.EndCurrentTaskList` boundary, while `TURN` is odd and the slot's `BACON_CURRENT_COMBAT_PLAYER_ID == 0`. This is the discriminator from log-validation. Each entity counts once, and frozen minions carried into the next turn are de-duplicated against the previous end-of-recruit frozen set.

| Game | Shop minion slots (unique entities) | Frozen carry-overs removed | Distinct shop minions | Tavern-spell slots | Opp start-of-combat minions | Discover minion options |
|---|---|---|---|---|---|---|
| 20:33 (partial, BG turns 1–5) | 18 | 0 | 16 | 5 | 7 | 6 |
| 21:08 (complete, 12 turns) | 149 | 12 | 80 | 29 | 61 | 15 |

Sightings that each candidate pool says are **not in the pool** (shop, plus opponent/discover minions that carry the server pool flag):

| Candidate pool | 20:33 | 21:08 |
|---|---|---|
| HSJSON 251952 `isBattlegroundsPoolMinion` | Dune Dweller, Red Volumizer, Bronze Warden | Shop: Hot-Air Surveyor, Ultraviolet Ascendant, Dune Dweller, Leyline Surfacer, Firelands Fugitive, Heroic Broodmother. Opp/discover: Mangled Bandit, Living Azerite, Ichoron, Hopebringer, Bronze Warden |
| HSJSON + HSReplay overrides | — | Shop: **Heroic Broodmother**. Discover: **Hopebringer** |
| hsbg.cards `pool=true` tavern minions | **Red Volumizer** | — |
| **Final pool (this doc)** | — | — |

More findings from the logs:

- **The server's own flag is right.** Across both logs we saw 154 distinct minion and tavern-spell cardIds. The in-game entity tag `IS_BACON_POOL_MINION` was `1` on all 13 returning or new cards that build 251952 leaves unflagged: Bronze Warden, Dune Dweller, Firelands Fugitive, Heroic Broodmother, Hopebringer, Hot-Air Surveyor, Ichoron, Leyline Surfacer, Living Azerite, Mangled Bandit, Red Volumizer, Ultraviolet Ascendant and Victorious Geomant.
- **No removed card and no pure-Naga card appeared anywhere** in either log. The only Naga-typed card seen was Ominous Seer (Demon/Naga), in the 20:33 game, which had Demons in the lobby.
- **Tiers match:** every shop entity's in-log `TECH_LEVEL` equals the final table's tier (0 mismatches).
- **The shop spells** in both games are all in the final spell pool, and none of them is a removed spell.
- **Tribes seen**, counting single-tribe pool minions only:
  - 20:33: Aberration, Demon, Dragon, Elemental, Mech;
  - 21:08: Aberration, Dragon, Elemental, Quilboar, Undead.

  Across 149 shop slots the 21:08 game showed **no** single-tribe Beast, Demon, Mech, Murloc or Pirate minion. Its dual-types (Flaming Enforcer Demon/Elemental, Prosthetic Hand Mech/Undead, Timecap'n Hooktail Dragon/Pirate) each have one lobby tribe, so they fit.

### A.8 Recommendation

**Composition** (lowest precedence first). A card is in the solo pool when all of these hold:
- the build card DB (hsdata `CardDefs.Bacon.xml` for the client's `BuildNumber`, or HSJSON `/v1/<build>/`) has `TECH_LEVEL > 0` and raw `IS_BACON_POOL_MINION == 1`;
- the value stays `1` after the **HSReplay live meta period** `tag_overrides` are applied, and then **our override file** on top;
- at least one of its non-ALL races is in `minion_types`, or it has none;
- it is not Duos-exclusive, unless the mode is Duos;
- it is not in `NON_SHOP` (Deities, Fishbait, …).

Take tribes-in-rotation from the meta period and fall back to our file. Build the spell pool the same way from `IS_BACON_POOL_SPELL`, plus our spell overrides.

- **Primary:** card DB + HSReplay meta period, refreshed at app start and every 6 h. Cache the last good copy, keyed by `period_start`/`name`. This is what HDT and HSTracker ship, so it gets fixed quickly when it's wrong.
- **Our override file** (source of truth for disagreements), e.g. `Resources/bg-pool/overrides/36.6.1.json`:

```json
{
  "patch": "36.6.1", "client_build": 251952, "valid_from": "2026-09-22T17:18:14Z",
  "tribes_in_rotation": ["BEAST","DEMON","DRAGON","ELEMENTAL","MECHANICAL","MURLOC","PIRATE","QUILBOAR","UNDEAD","ABERRATION"],
  "tribes_per_lobby": 5,
  "forced_tribes": [{"tribe": "ABERRATION", "until": "2026-10-06T17:00:00Z"}],
  "minion_pool": {
    "BG32_172": 0, "BG35_140": 0,
    "BG36_369": 1, "BG36_362": 1, "BG36_700": 1, "BG36_364": 1, "BG36_848": 1,
    "BG36_366": 1, "BG36_367": 1, "BG36_849": 1, "BG36_370": 1,
    "BGDUO_700": 1, "BGDUO_701": 1
  },
  "spell_pool": { "BG33_899": 0, "BG35_149": 0, "BG32_337": 1 },
  "non_shop": ["BGFYM_000", "BGFYM_011", "BG36_205"],
  "special": { "BG36_360": "Dark Paradox: one ALL-type variant per game (t3..t9), tier varies; never tribe evidence" },
  "disputed": { "BG26_537": "Flourishing Frostling: HSJSON+HSReplay pool, hsbg.cards absent, not on Blizzard lists; keep, watch sightings" },
  "sources": ["https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon", "https://hsbg.cards/api/v1/patches/36.4.2_36.6.1"]
}
```

  The `forced_tribes.until` value is an estimate. Blizzard only says "first two weeks … starting September 22", so confirm the date when Blizzard announces it.
- **Fallback and cross-check:** a CI job (or a debug menu item) diffs the composed pool against the hsbg.cards `pool=true` tavern minions and the latest `/api/v1/patches/{prev}_{cur}` sections. Differences are **reported, never applied automatically**. The known false positives to allow-list are Volumizers, Fishbait, Deities, Dark Paradox and Flourishing Frostling.
- **Runtime self-heal:** in-game, any entity with `IS_BACON_POOL_MINION=1` whose cardId is missing from the composed pool is added to the pool for that session. Add it at the tier from its `TECH_LEVEL`, and log a "pool drift" diagnostic that the user can export. Tier-list UI and tribe inference then never silently lose a card. We haven't seen whether the server sends `0` on removed cards, because none appeared, so don't *remove* cards on that signal.
- **Offline:** ship the last composed pool in the app bundle, so it works with no network.

**Patch-day refresh procedure:**
1. Read `BuildNumber=` from Power.log `DebugPrintGame`. If it is new, fetch hsdata for that build (`api.github.com/repos/HearthSim/hsdata/commits`; the tags are per build) or HSJSON `/v1/<build>/`. Usually this lands about 1 day after the client patch.
2. Fetch the HSReplay meta period. If its `name`/`period_start` changed, rebuild the pool.
3. Read the Blizzard BG post and the hotfix thread. Also fetch `https://hsbg.cards/api/v1/patches` for the new `{prev}_{cur}` diff. Map the names to cardIds with `build_pool.py` and `render_tables.py`, and write `overrides/<patch>.json` covering:
   - removed, returning and new minions, including Duos-only;
   - rotated tribe(s) and forced tribes with their end date;
   - tribes per lobby;
   - spells, and the hero bans.
4. Run the CI diff against hsbg.cards, and replay the fixture logs. Every shop sighting must be in the pool with the same tier (`infer_tribes.py` prints `unknown shop cards`).
5. After the first real games on the patch, check the app's "pool drift" diagnostics and fold them into the override file.
6. When the next client build ships, check whether each override is now redundant (the card DB agrees). Drop the ones that are, so the file only ever holds the live delta.

### A.9 The 36.6.1 pool (solo), by tier and tribe

`*` = the value comes from an HSReplay override. `†` = the value comes from **our** override (it is wrong or missing in both the build and HSReplay). Untagged = build 251952 is already correct. Tiers are from build 251952, which already includes 36.6.1's tier changes. Dual-type rows count once, under their own row. A Naga dual-type stays only through its other tribe, and you can't tell whether that other tribe is in the lobby from the card alone. Tier 7 is reachable only through special effects. Not listed: **Dark Paradox** `BG36_360`, one of 6 ALL-type variants per game (`BG36_360`, `t3` T2, `t6` T3, `t5` T4, `t4` T5, `t9` T6; the T5 Divine Shield variant never appears with Undead, and per the hotfix the T5 and T6 variants don't appear in Y'Shaarj games). Also not listed: the Deities C'Thun `BGFYM_000` and Y'Shaarj `BGFYM_011`, which are Tier 3 but summoned, not bought.

### Solo pool (also in Duos)

| Tribe | T1 | T2 | T3 | T4 | T5 | T6 | T7 | Total |
|---|---|---|---|---|---|---|---|---|
| Aberration | Joyous `BG36_110`<br>Zoatroid `BG36_098` | Brain Rotter `BG36_099`<br>Underrot Spawn `BG36_116`<br>Unwilling Slacker `BG36_101` | Abyssal Envoy `BG36_311`<br>Drifting Sacrifice `BG36_113`<br>Fetid Corroder `BG36_112`<br>Vicious Mindslasher `BG36_108`<br>Wandering Willbreaker `BG36_100` | Cutthroat K'Thir `BG36_106`<br>Faceless Operative `BG36_308`<br>Mindbending Recruiter `BG36_312`<br>Nightmare Corroder `BG36_115`<br>Parasitic Fleshling `BG36_114` | De-volition-ist `BG36_102`<br>Faceless Converter `BG36_318`<br>Mindbender Ghur'sha `BG36_097`<br>Mysterious K'Thir `BG36_320`<br>N'raqi Frostcaller `BG36_300`<br>N'raqi Sapper `BG36_103` | Dark Puppeteer `BG36_104`<br>Harbinger Aph'lass `BGFYM_005`<br>The Shadow of Doubt `BG36_109` | Sha of Fear `BG36_111` | 25 |
| Beast | Buzzing Vermin `BG31_803`<br>Flittering Bat `BG36_200` | Forest Rover `BG31_801`<br>Humming Bird `BG26_805`<br>Lurking Lionfish `BG36_201` | Sprightly Scarab `BG27_084`<br>Tasty Lobster `BG36_202`<br>Wolf Pup `BG36_207` | Banana Slamma `BG26_802`<br>Cage Gnawer `BG36_211`<br>Headhunter Gryphon `BG36_204`<br>Hoarding Hyena `BG36_210`<br>Snarky Shark `BG36_206` | Ghastcoiler `BGS_008`*<br>Goldrinn, the Great Wolf `BGS_018`<br>Lurking Leviathan `BG35_602`<br>Sewer Lord `BG35_604`<br>Turquoise Skitterer `BG31_809` | Deathstrider `BG36_208`<br>Ravaging Scorpid `BG36_209` | Stalwart Kodo `BG34_322` | 21 |
| Demon | Wrath Weaver `BGS_004` | Laboratory Assistant `BG35_150`<br>Mind Muck `BG23_357`<br>Soul Rewinder `BG26_174` | Devout Hellcaller `BG33_155`<br>Malchezaar, Prince of Dance `BG26_524`<br>Trapped Clapper `BG36_730` | Ashen Corruptor `BG32_873`<br>Imp-lusionist `BG36_731`<br>Imposing Percussionist `BG26_525`<br>Sacrificial Wrathguard `BG36_362`†<br>Soulkeeping Jailer `BG36_503` | Deft Deserter `BG36_621`<br>Devilish Distractor `BG36_762`<br>Insatiable Ur'zul `BG21_004`<br>Tichondrius `BG26_523` | Eredar Escapist `BG36_733`<br>Twisted Wrathguard `BG35_155` | Champion of Sargeras `BG27_016` | 19 |
| Dragon | Glim Guardian `BG29_888`<br>Scarlet Survivor `BG35_814` | Bronze Warden `BGS_034`*<br>Electric Synthesizer `BG26_963`<br>Tarecgosa `BG21_015` | Amber Guardian `BG24_500`<br>Blue Whelp `BG33_924`<br>Hired Mount `BG36_240`<br>Roaring Recruiter `BG29_816` | Bronze Timewalker `BG36_242`<br>Persistent Poet `BG29_813`<br>Runic Arcanist `BG36_245`<br>Sky-hatch Runaway `BG36_243` | Draconic Warden `BG34_633`<br>Hopebringer `BG36_364`†<br>Kalecgos, Arcane Aspect `BGS_041` | Crimson Vindicator `BG36_241`<br>Heroic Broodmother `BG36_849`† | Obsidian Ravager `BG27_017` | 19 |
| Elemental | Crackling Cyclone `BGS_119`<br>Dune Dweller `BG31_815`* | Fire Baller `BG31_816`<br>Sellemental `BGS_115`<br>Snow Baller `BG31_818` | Waveling `BG34_856`<br>Wildfire Elemental `BGS_126` | Air Baller `BG36_181`<br>En-Djinn Blazer `BG34_865`<br>Ichoron the Protector `BG31_812`*<br>Leyline Surfacer `BG35_881`*<br>Living Prison `BG36_180`<br>Refreshing Anomaly `BGS_116`<br>Tavern Tempest `BGS_123` | Air Revenant `BG34_858`<br>Firelands Fugitive `BG35_882`*<br>Flourishing Frostling `BG26_537`<br>Living Azerite `BG28_707`* | Elemental of Surprise `BG26_175`<br>Ultraviolet Ascendant `BG31_810`*<br>Unbound Tempest `BG36_352` | Stone Age Slab `BG34_950` | 22 |
| Mech | Cord Puller `BG29_611`<br>Lullabot `BG26_146` | Blue Volumizer `BG34_170t2`*<br>Green Volumizer `BG34_170t3`*<br>Mechagnome Interpreter `BG31_177`<br>Red Volumizer `BG34_170t`* | Accord-o-Tron `BG26_147`<br>Annoy-o-Module `BG_BOT_911`<br>Auto Accelerator `BG34_170`*<br>Relentless Deflector `BG34_405`*<br>Rescue Bot `BG36_854` | Conveyor Construct `BG34_171`*<br>Drone Duplicator `BG36_506`<br>Enchanted Sentinel `BG35_341`<br>Glambot `BG36_853` | Charging Czarina `BG28_741`<br>Resourceful Robot `BG36_366`†<br>Spark Snapper `BG36_851` | Auto Reveille `BG36_367`†<br>Falling Sky Golem `BG35_342`<br>Utility Drone `BG26_152` | Polarizing Beatboxer `BG26_149` | 22 |
| Murloc | Bubble Gunner `BG31_149`*<br>Flighty Scout `BG32_330` | Expert Aviator `BG34_140`<br>Tad `BG22_202`<br>Very Hungry Winterfinner `BG29_300` | Diremuck Forager `BG27_556`<br>Shoalfin Mystic `BG32_860`* | Bream Counter `BG26_137`<br>Gormling Gourmet `BG32_336`*<br>Kelp Keeper `BG36_701`<br>Sewer Escapee `BG36_700`†<br>Twilight Tidehunter `BG36_703` | Bile Spitter `BG33_318`<br>Costume Enthusiast `BG34_142`<br>Hackerfin `BG31_148`*<br>Primalfin Lookout `BGS_020`<br>Shamanic Tidecaller `BG36_704` | Choral Mrrrglr `BG26_354`<br>Magicfin Mycologist `BG33_891`<br>Young Murk-Eye `BG22_403`* | Futurefin `BG34_145` | 21 |
| Pirate | Aureate Laureate `BG32_236`<br>Southsea Busker `BG26_135` | Bilgewater Breakout `BG36_520`<br>Clever Castaway `BG36_342`<br>Surfing Sylvar `BG32_235` | Azsharan Cutlassier `BG33_830`<br>Greedy Conniver `BG36_369`†<br>Locked-up Mutineer `BG36_521` | Bigwig Bandit `BG33_822`<br>Blade Collector `BG26_817`<br>Gunpowder Courier `BG26_810`<br>Lovesick Balladist `BG26_814`<br>Maritime Extortionist `BG36_524` | Elite Navigator `BG32_231`*<br>Enterprising Escapee `BG36_523`<br>Proud Privateer `BG33_825`<br>Shipwrecked Rascal `BG33_821` | Hooktusk, Master Marauder `BG36_344`<br>Silent Deliverer `BG36_343`<br>Sky Admiral Rogers `BG33_823` | Captain Sanders `BG25_034` | 21 |
| Quilboar | Razorfen Geomancer `BG20_100`<br>Tusked Camper `BG33_886` | Crater Miner `BG31_320`<br>Prodigious Tusker `BG33_430`<br>Roadboar `BG20_101` | Briarback Drummer `BG34_683`<br>Fearless Foodie `BG30_123`<br>Gem Rat `BG31_326`<br>Mangled Bandit `BG28_582`*<br>Sly Infiltrator `BG36_330`<br>Trench Fighter `BG34_684` | Bonker `BG20_104`<br>Bramble Tunneler `BG36_331`<br>Geomagus Roogug `BG28_583`*<br>Hot-Air Surveyor `BG30_121`*<br>Razorfen Flapper `BG34_682`<br>Snare Trapper `BG36_332`<br>Thorned Trailblazer `BG31_327` | Razorfen Vineweaver `BG33_883`<br>Sanguine Refiner `BG33_885` | Sanguine Champion `BG23_017`<br>Turbo Hogrider `BG31_323`<br>Veteran Brigand `BG36_341`<br>Victorious Geomant `BG36_370`† | Jailbird Juggernaut `BG36_333` | 25 |
| Undead | Harmless Bonehead `BG28_300`<br>Risen Rider `BG25_001` | Eternal Knight `BG25_008`<br>Nerubian Deathswarmer `BG25_011`<br>Scarlet Skull `BG25_022` | Cadaver Caretaker `BG30_125`<br>Handless Forsaken `BG25_010`<br>Mummifier `BG28_309` | Dead Bellringer `BG36_511`<br>Friendly Geist `BG32_880`<br>Maw Caster `BG32_340`<br>Plaguerunner `BG34_690` | Barrier Banshee `BG36_514`<br>Drustfallen Butcher `BG32_324`<br>Lichling Hoarder `BG36_848`† | Deathly Striker `BG31_835`<br>Eternal Summoner `BG25_009`<br>Forsaken Weaver `BG34_692`<br>Snazzy Phantom `BG36_515` | Stitched Salvager `BG31_999` | 20 |
| Beast/Pirate | - | - | Treasure Parrot `BG36_763` | - | - | - | - | 1 |
| Demon/Dragon | - | - | - | - | Felfire Conjurer `BG32_821` | - | - | 1 |
| Demon/Elemental | - | - | - | Flaming Enforcer `BG34_500` | - | - | - | 1 |
| Demon/Naga | Ominous Seer `BG31_330` | - | - | - | - | - | - | 1 |
| Demon/Quilboar | - | - | - | - | Felboar `BG28_633` | - | - | 1 |
| Dragon/Naga | - | - | - | - | Firescale Hoarder `BG32_820` | - | - | 1 |
| Dragon/Pirate | - | - | Timecap'n Hooktail `BG27_005` | - | - | - | - | 1 |
| Mech/Murloc | - | - | - | Gearfin `BG36_764` | - | - | - | 1 |
| Mech/Undead | - | - | Prosthetic Hand `BG_DEEP_015` | - | - | - | - | 1 |
| All-type (Menagerie) | - | - | - | - | Nightmare Par-tea Guest `BG32_111` | Gatekeeper Amalgam `BG36_640` | The Last One Standing `BG34_320` | 3 |
| Neutral | Suspicious Prisonguard `BG36_345` | Decoy Conjurer `BG36_354`<br>Intrepid Botanist `BG32_237`<br>Patient Scout `BG24_715` | Deadly Spore `BGS_131`<br>Disguised Graverobber `BG28_303`<br>Fruit Vendor `BG36_346`<br>Iron Groundskeeper `BG27_000`* | Boom-in-a-Box `BG36_620`<br>Heroic Underdog `BG34_604`<br>Holy Vanguard `BG36_372`<br>Humon'gozz `BG32_341`<br>Sin'dorei Straight Shot `BG25_016`<br>Tortollan Blue Shell `BG24_018` | Brann Bronzebeard `BG_LOE_077`<br>Cataclysmic Harbinger `BG35_123`<br>Drakkari Enchanter `BG26_ICC_901`<br>Leeroy the Reckless `BG23_318`<br>Rodeo Performer `BG28_550`<br>Titus Rivendare `BG25_354` | Balinda Stonehearth `BG35_883`<br>Nadina the Red `BGS_040`*<br>Tyrael `BG36_356` | Highkeeper Ra `BG34_319` | 24 |
| **Total** | **21** | **34** | **43** | **59** | **49** | **33** | **12** | **251** |

### Duos-exclusive minions (Duos only)

| Tier | Minions |
|---|---|
| T1 | Passenger `BGDUO_114` (Neutral) |
| T2 | Friendly Saloonkeeper `BGDUO_104` (Neutral); Gathering Stormer `BGDUO31_201` (Elemental); Generous Geomancer `BGDUO_111` (Quilboar); Wanderer Cho `BGDUO_100` (Neutral) |
| T3 | Bottom Feeder `BGDUO33_140` (Murloc); Doting Dracthyr `BGDUO_107` (Dragon); Jumping Jack `BGDUO_115` (All-type (Menagerie)); Orc-estra Conductor `BGDUO_119` (Neutral); Plunder Pal `BGDUO_118` (Pirate); Puddle Prancer `BGDUO_117` (Murloc); Voidpriest Cloner `BGDUO_700`† (Aberration); Wheeled Crewmate `BGDUO31_207` (Pirate) |
| T4 | Feisty Freshwater `BGDUO_110` (Elemental); Grave Narrator `BGDUO_112` (Undead); Mantid King `BGDUO31_212` (Neutral); Mirror Monster `BGDUO_108` (All-type (Menagerie)); San'layn Scribe `BGDUO31_208` (Undead); Shifty Snake `BGDUO31_203` (Beast) |
| T5 | C'Thrax Wrecker `BGDUO_701`† (Aberration); Man'ari Messenger `BGDUO_121` (Demon); Selfless Sightseer `BGDUO31_205` (Dragon); Support System `BGDUO_109` (Mech); Well Wisher `BGDUO_120` (Neutral) |
| T6 | Dark Dazzler `BGDUO33_150` (Demon); Loyal Mobster `BGDUO31_202` (Quilboar); Transport Reactor `BGDUO31_211` (Mech) |
| T7 | Sandy `BGDUO_125` (Neutral) |

Tavern spells after 36.6.1: 76, including the 3 marked (Duos). This is the build flag with our spell overrides; `†` = our override. Several spells are gated to a tribe in Firestone's list: Boon of Beetles (Beast), Cloning Conch (Murloc), Gem Confiscation (Quilboar), Butchering (Undead), Corrupted Cupcakes (Demon), and Spitescale Special (Naga, so it is presumably out of the pool now; unverified).

| Tier | Tavern spells |
|---|---|
| T1 | A New Sprout `BG33_101`; Alliance Flag `BG31_880`; Enchanted Lasso `BG28_512`; Fortify `BG28_503`; Recruit a Trainee `BG28_504`; Tavern Coin `BG28_810`; Tavern Dish Banana `BG28_897`; Them Apples `BG28_966` |
| T2 | Chef's Choice `BG28_518`; Hasty Excavation `BG28_571`; Leaf Through the Pages `BG28_827`; Might of Stormwind `BG35_951`; Search Through Time `BG34_330`; Strike Oil `BG28_805`; Winner's Bread `BG36_883` |
| T3 | Blood Gem Barrage `BG34_689`; Careful Investment `BG28_800`; Friendly Bounty `BG33_814`; Healthy Bounty `BG33_811`; Hostile Bounty `BG33_812`; Overconfidence `BG28_884`; Planar Telescope `BG28_521`; Portal in a Fountain `BG31_243` (Duos); Repair Job `BG36_624`; Robust Evolution `BG30_804`; Seafood Stew `BG32_337`†; Selfish Bounty `BG33_813`; Shiny Ring `BG28_168`; Staff of Enrichment `BG28_886`; Time Management `BG31_881`; Tricky Trousers `BG28_520`; Wealthy Bounty `BG33_815` |
| T4 | Boon of Beetles `BG28_603`; Boundless Potential `BG31_890`; Cloning Conch `BG28_601`; Defender's Rites `BG28_825`; Easterly Winds `BG34_444`; Eonar's Favor `BG35_912`; Gem Confiscation `BG28_698`; Methodical Madness `BG36_880`; Mighty Dragonbreath `BG36_246`; Misplaced Tea Set `BG28_888`; Natural Blessing `BG28_845`; Shifting Tide `BG32_815`; Sludge Corrosion `BG36_301t`; Spitescale Special `BG28_606`; Temperature Shift `BG31_819`; Tomb Turning `BG34_888`; Weapons Forge `BG36_884` |
| T5 | Armor Stash `BG28_500`; Bargain Bundle `BG31_242` (Duos); Brood of Nozdormu `BG34_889`; Butchering `BG28_604`; Channel the Devourer `EBG_Spell_032`; Contracted Corpse `BG28_882`; Corrupted Coin `BG36_303`; Corrupted Cupcakes `BG28_607`; Energizing Chamber `BG36_371`; Forest's Bounty `BG31_886`; Golden Touch `BG28_830`; Hired Headhunter `BG28_GIL_836`; Portal in a Crystal `BG31_244` (Duos); Queen's Command `BG35_922`; Saloon's Finest `BG28_849`; Unmasked Identity `EBG_Spell_037`; Upper Hand `BG28_573`; Wave of Gold `BG34_990` |
| T6 | Azerite Empowerment `BG28_169`; Eyes of the Earth Mother `EBG_Spell_017`; Fandral's Fortune `BG31_892`; Lost Staff of Hamuul `EBG_Spell_038`; Perfect Vision `BG28_838` |
| T7 | Hallowed Ritual `BG31_896`; Menagerie Tableware `BG34_272`; Sacred Gift `BG28_507`; Sharing is Caring `BG31_889` |

**Trinkets** have no pool flag in the card data. HSJSON has 420 `BATTLEGROUND_TRINKET` cards, split into 201 `LESSER_TRINKET` and 219 `GREATER_TRINKET` by `spellSchool`. The only machine-readable current trinket pool we found is hsbg.cards (247 `pool=true` trinkets), plus Blizzard's diff:
- New: 15 Lesser and 15 Greater. Several names exist in both tiers: Corrupted Baton, Hammer of Twilight, Volumizer Portrait, Kiri's Double Eclipse.
- Removed: Amplifying Essence, Avalanche Sticker, Assembler Portrait, Kaleidoscope, Automaton Portrait, Errgl Sticker. Blizzard and hsbg.cards disagree on which of these were Lesser and which Greater.
- Returning: Vibrant Bubble (Lesser), and the Surveyor, Azerite and Hackerfin Portraits (Greater).

Trinket offers are visible in the log as `ChoiceType=GENERAL` with 4 `BG3x_MagicItem_*` options, so the app doesn't need the trinket pool to show them. Use hsbg.cards plus our overrides only if we want "possible trinkets" UI. HSJSON `battlegroundsAssociatedRaces` gives trinket↔tribe links (see B.2).

### A.10 Removed and rotated-out cards (36.6.1)

Removed minions (Blizzard list). The "HSReplay override?" column shows whether the live meta period already sets the card to 0:

| Card | cardId | Tier | Type | HSReplay override? |
|---|---|---|---|---|
| Ancestral Automaton | `BG_TTN_401` | 2 | Mechanical | yes |
| Auto Assembler | `BG32_172` | 4 | Mechanical | **no (ours)** |
| Breakout Mastermind | `BG36_507` | 3 | Murloc | yes |
| Captain Cookie | `BG36_760` | 4 | Murloc/Pirate | yes |
| Clunker Junker | `BG29_503` | 4 | Mechanical | yes |
| Cousin Errgl | `BG35_142` | 5 | Murloc | yes |
| Dancing Barnstormer | `BG26_162` | 5 | Elemental | yes |
| Deepwater Chieftain | `BG35_143` | 4 | Murloc | yes |
| Deflect-o-Bot | `BGS_071` | 3 | Mechanical | yes |
| Dual-Wield Corsair | `BG31_824` | 5 | Pirate | yes |
| Dustbone Devastator | `BG33_323` | 3 | Undead | yes |
| Fire-forged Evoker | `BG32_822` | 6 | Dragon | yes |
| Glowing Cinder | `BG32_842` | 4 | Elemental | yes |
| Ignition Specialist | `BG28_595` | 6 | Dragon | yes |
| Kangor's Apprentice | `BGS_012` | 5 | Neutral | yes |
| Mama Mrrglton | `BG35_140` | 3 | Murloc | **no (ours)** |
| Metallic Hunter | `BG32_170` | 2 | Mechanical | yes |
| Meteorite Crasher | `BG31_843` | 3 | Elemental | yes |
| Moat Custodian | `BG36_351` | 6 | Elemental | yes |
| Molten Rock | `BGS_127` | 1 | Elemental | yes |
| Motley Phalanx | `BG27_080` | 4 | All | yes |
| Nomi, Kitchen Nightmare | `BGS_104` | 5 | Neutral | yes |
| Oozeling Gladiator | `BG27_002` | 2 | Aberration | yes |
| Papa Mrrglton | `BG35_141` | 3 | Murloc | yes |
| Primitive Painter | `BG33_893` | 6 | Murloc | yes |
| Private Investigator | `BG36_509` | 3 | Pirate | yes |
| River Skipper | `BG33_140` | 1 | Murloc | yes |
| Sand Swirler | `BG32_841` | 3 | Elemental | yes |
| Scrap Scraper | `BG26_148` | 5 | Mechanical | yes |
| Sly Raptor | `BG25_806` | 3 | Beast | yes |
| Thousandth Paper Drake | `BG29_810` | 2 | Dragon | yes |
| Unleashed Mana Surge | `BG32_846` | 6 | Elemental | yes |
| Vigilant Bristlemane | `BG36_510` | 5 | Quilboar | yes |
| Void Pup Trainer | `BG35_152` | 5 | Demon | yes |
| Warpwing | `BG24_004` | 6 | Dragon | yes |

Naga rotated out: the 22 pure Naga shop minions, per hsbg.cards' "Naga Rotated Out" section. These all get pool=0 through `minion_types` (no Naga), with no per-card override needed. Private Chef and Storm Splitter are Duos-only.

| Card | cardId | Tier | Type |
|---|---|---|---|
| Fleeing Fugitive | `BG36_921` | 1 | Naga |
| Mini-Myrmidon | `BG23_000` | 1 | Naga |
| Lava Lurker | `BG23_009` | 2 | Naga |
| Shell Collector | `BG23_002` | 2 | Naga |
| Thaumaturgist | `BG31_924` | 2 | Naga |
| Deep-Sea Angler | `BG23_004` | 3 | Naga |
| Waverider | `BG23_007` | 3 | Naga |
| Abyssal Bruiser | `BG35_921` | 4 | Naga |
| Cagey Conjurer | `BG36_508` | 4 | Naga |
| Private Chef | `BGDUO31_209` | 4 | Naga |
| Rimescale Priestess | `BG33_319` | 4 | Naga |
| Seafloor Recruiter | `BG34_925` | 4 | Naga |
| Zesty Shaker | `BG26_505` | 4 | Naga |
| Darkcrest Strategist | `BG31_920` | 5 | Naga |
| Glowscale | `BG23_008` | 5 | Naga |
| Showy Cyclist | `BG31_925` | 5 | Naga |
| Storm Splitter | `BGDUO_122` | 5 | Naga |
| Tranquil Meditative | `BG32_835` | 5 | Naga |
| Fauna Whisperer | `BG32_837` | 6 | Naga |
| Groundbreaker | `BG31_035` | 6 | Naga |
| Torrential Ruiner | `BG36_622` | 6 | Naga |
| Sea Witch Zar'jira | `BG27_514` | 7 | Naga |

Two Naga dual-types **stay** through their other tribe: Ominous Seer `BG31_330` (Demon/Naga, T1) and Firescale Hoarder `BG32_820` (Dragon/Naga, T5). Orgozoa, the Tender `BG23_015` and Faceless Manipulator `BG_EX1_564` are Aberration-typed, but they aren't shop pool cards in any source.

---

## Part B: inferring the lobby's tribes from the log

### B.1 What the log does and doesn't expose

We looked at every tag on `GameEntity` and on both `Player` entities, at game start and at game end, in both logs.

**There is no available-races tag:**
- `GameEntity` carries `BACON_GLOBAL_OLD_GOD_DBID` (the Deity: 132532 Y'Shaarj in the 20:33 game, 130610 C'Thun in the 21:08 game), `BACON_BARTENDER_CARD_ID`, `BACON_TRINKETS_ACTIVE`, `BACON_DARK_GIFTS_ACTIVE`, `BACON_CHOSEN_BOARD_SKIN_ID`, combat-speed tags and more.
- There is no `BACON_SUBSET_*` tag and no race value on the GameEntity or on either Player entity.

**Unnamed tag 4730 = 5** is set once, at `CREATE_GAME`, on GameEntity in both games (`D 21:09:40.34 … tag=4730 value=5`). It *might* be "tribes per lobby". It has no name in python-hearthstone `enums.py`, HearthDb or Firestone `game-tags.ts`. Only two samples exist and both are 5, so don't rely on it. It is worth watching after the Aberration fortnight, when a lobby could still be 5.

**Bob's bartender lines** are not in Power.log. Only the skin (`TB_BaconShopBob_SKIN_AN`) is logged. There are no VO or emote lines in the captured logs.

**Tribe count: 5 per lobby, with Aberration always present until about 2026-10-06:**
- Firestone `TOTAL_RACES_IN_GAME = 5`, and pre-36.6.1 tribe shares were about 50% of games for each of 10 tribes (meta-comps §2).
- Blizzard: "Aberrations will appear in every lobby" for 2 weeks, and Naga are out of rotation, so 9 other tribes remain.
- Logs: each game showed exactly 5 tribes (A.7).

So the hypothesis space is **{Aberration} ∪ 4 of 9 = 126 lobbies**. After the fortnight it becomes 5 of 10 = 252, still with no Naga, unless Blizzard changes rotation. Read `tribes_per_lobby`, `forced_tribes` and the rotation from the override file, not from code.

Log signals that **do** leak tribes, strongest first:

| Signal | Where in the log | Strength | Notes |
|---|---|---|---|
| Shop draws | bartender-slot `MINION`s in PLAY during recruit | likelihood | Draws are uniform over copies with tier ≤ your tavern tier. De-duplicate frozen carry-overs. Exclude minions put in the shop by effects (created inside a `BLOCK_START` from a local card rather than a refresh or turn start). |
| Opponent start-of-combat boards | slot `MINION`s in PLAY between `BACON_CURRENT_COMBAT_PLAYER_ID≠0` and the first `ATTACK` block | confirm-only | Only use entities with server `IS_BACON_POOL_MINION=1`, which filters tokens and hero-power minions. Boards are comp-skewed, so never use them as *absence* evidence. |
| Discover / Dark Gift / triple-reward options | `DebugPrintEntityChoices ChoiceType=GENERAL`, minion options | confirm-only | These are drawn from the lobby pool. 15 options were seen in the 21:08 game. |
| Minions entering your hand from "random minion" generators | e.g. Kith'ix *Dark Ritual* ("Get 2 random minions"), Unwilling Slacker spell | confirm-only | Not implemented here; add later. |
| Lobby heroes and your hero offer | 8 `PLAYER_LEADERBOARD_PLACE` heroes, and the 4 `MULLIGAN` options | confirm at turn 0 | Some heroes appear only with a tribe. Firestone `cards_rules.json` `needTypesInLobby`: Ysera/Alexstrasza need DRAGON, Jaraxxus/Lich Baz'hial DEMON, Patches/Cap'n Hoggarr PIRATE, Millificent/Jim Raynor/Artanis/Ini MECH, Flurgl MURLOC, Chenvaala ELEMENTAL, Blackthorn QUILBOAR, The Jailer/Putricide UNDEAD. Rules that need one of several tribes, such as N'Zoth, Onyxia and Teron (BEAST or UNDEAD), give weaker evidence. Resolve skins with `battlegroundsSkinParentId`. **Local example:** in the 20:33 lobby, *Ardenweald Ysera* (`TB_BaconShop_HERO_53_SKIN_F`, parent `TB_BaconShop_HERO_53`) implied Dragon at turn 0, and Dragon was indeed in that lobby. |
| Trinket offers | `GENERAL` choice with `BG3x_MagicItem_*` options, plus HSJSON `battlegroundsAssociatedRaces` | confirm (weak) | A tribe portrait (e.g. Accord-o-Tron Portrait = Mech) is presumably offered only when its tribe is in the lobby. The 21:08 offers were all tribe-neutral, so this is unverified. |
| Tribe-gated tavern spells or neutral minions | shop `BATTLEGROUND_SPELL`s; neutral minions such as Disguised Graverobber (Undead only) and Nadina (Dragon only) | confirm | Use `cards_rules.json` `needTypesInLobby` and Firestone `getTribesForInclusion`. The current code treats these cards as neutral, which is conservative. |
| Hero bans | the Aberration bans only | none | Aberration is in every lobby, so these bans don't discriminate. |

### B.2 Algorithm

```text
config  = overrides/<patch>.json           # tribes_in_rotation, tribes_per_lobby=5, forced_tribes=[ABERRATION until …]
pool    = compose_pool(build, hsreplay, config, mode)   # A.8; solo vs duos
W[tier] = copies per tier  (assumed 16/15/13/11/9/7 for T1..T6; only ratios matter,
                            results identical with uniform weights, see B.3)

live_tribes(card) = card.races ∩ config.tribes_in_rotation      # Demon/Naga -> {Demon}
gate(card)        = live_tribes(card) or rules.needTypesInLobby(card) or ∅
in_pool(card, H)  = gate(card) == ∅  or  gate(card) ∩ H ≠ ∅     # neutral / ALL-type always in

H_all   = { forced ∪ S : S ⊂ (rotation − forced), |S| = tribes_per_lobby − |forced| }   # 126 today
logP[H] = 0     (uniform prior; optionally seed from hero constraints at turn 0)
D[H][t] = Σ_{c ∈ pool, in_pool(c,H), c.tier ≤ t} W[c.tier]     # precompute, t = 1..6

on hero lobby known:
    for hero in lobby_heroes ∪ my_offer: for H: if hero needs tribes T and T ∩ H = ∅: logP[H] += log(ε_hero)

on shop_minion(card, my_tier)   # new entity, not a frozen carry-over, not effect-inserted
    if card ∉ pool: flag_pool_drift(card); treat as confirm-only if server IS_BACON_POOL_MINION==1
    for H: logP[H] += in_pool(card,H) ? log(W[card.tier] / D[H][my_tier]) : log(ε_shop)   # ε_shop≈1e-3

on confirm_minion(card)          # opp board / discover / generated, server pool flag == 1
    for H: if not in_pool(card,H): logP[H] += log(ε_conf)   # ε_conf≈0.02 (comp/effect noise)

posterior P(H) = softmax(logP);  P(tribe) = Σ_{H ∋ tribe} P(H)
state(tribe) = CONFIRMED if P ≥ 0.99, ABSENT if P ≤ 0.01, else LIKELY/UNLIKELY with the %
lobby resolved when every tribe is CONFIRMED or ABSENT
```

Notes:
- The cardinality constraint does most of the work. Once 4 non-forced tribes are confirmed, the other 5 are absent without any absence evidence. Absence evidence only matters while fewer than 4 are confirmed. In that phase the shop-draw likelihood rewards hypotheses that explain the draws with a *smaller* pool (a lobby without tribe X has a smaller denominator). This is the "N slots with zero sightings" effect, weighted by pool size per tier.
- A dual-type whose other tribe has rotated out acts as a single-tribe card. For example, Ominous Seer in the 20:33 game pushed P(Demon) to 0.95 by BG turn 2, before Wrath Weaver or Laboratory Assistant appeared.
- ALL-type (Menagerie) cards, Dark Paradox and neutral cards are never evidence, but they do count in the denominators.
- Keep ε > 0 and flag contradictions. If the MAP hypothesis has P < 0.5 after turn 6, or a pool-flagged minion has probability 0 under every hypothesis, show "tribes: uncertain" and log a diagnostic. This most likely means pool drift or a special lobby (an anomaly or a mode change).
- Duos: use the Duos pool, which includes Duos-exclusive cards. The teammate's shop and board are not in your log, so there is less evidence. Tribes per lobby in Duos is unverified; we have no Duos capture.
- Cost: 126 hypotheses × about 30 events per turn is trivial. The precomputed denominators are 126 × 6 integers.

### B.3 Results on the local logs (`infer_tribes.py`)

P(tribe) after the last event of each BG turn, for the 21:08 game with all evidence (shop + opponent boards + discovers). Aberration is 1.00 by construction:

| BG turn | Beast | Demon | Dragon | Elemental | Mech | Murloc | Pirate | Quilboar | Undead |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.18 | 0.18 | 0.95 | 0.18 | 0.18 | 0.18 | 0.18 | 0.97 | 0.97 |
| 2 | 0.17 | 0.17 | 1.00 | 0.17 | 0.17 | 0.17 | 0.17 | 1.00 | 1.00 |
| 3 | 0.03 | 0.03 | 1.00 | 0.87 | 0.03 | 0.03 | 0.03 | 1.00 | 1.00 |
| 4 | 0.00 | 0.00 | 1.00 | 1.00 | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 |

| Game | Evidence | First confirmation per tribe (BG turn, source, card) | Resolved (all tribes ≥0.99 or ≤0.01) | Answer |
|---|---|---|---|---|
| 20:33 | shop only | Dragon T1 Scarlet Survivor · Mech T1 Lullabot · Elemental T1 Dune Dweller · Demon T5 Wrath Weaver (P(Demon) = 0.95 from T2 via Ominous Seer) | BG turn **5**, 15th shop minion | Aberration, Demon, Dragon, Elemental, Mech (P = 0.998) |
| 20:33 | all | Demon T3 from the opponent's Laboratory Assistant | BG turn **4**, 14th shop minion | same (P = 1.000) |
| 21:08 | shop only | Undead T1 Harmless Bonehead · Quilboar T1 Tusked Camper · Dragon T2 Scarlet Survivor · Elemental T3 Snow Baller | BG turn **4**, 11th shop minion | Aberration, Dragon, Elemental, Quilboar, Undead (P = 1.000) |
| 21:08 | all | Dragon T1 from the opponent's Scarlet Survivor | BG turn **4**, 10th shop minion | same |
| 22:34 (added 2026-09-23, #13) | all | Mech T1 Lullabot · Murloc T2 Flighty Scout · Demon T2 Wrath Weaver · Pirate T3 Southsea Busker. The app's engine, which also applies hero rules, has P(Pirate) = 0.97 at turn 0 from the heroes | BG turn **4**, 11th shop minion | Aberration, Demon, Mech, Murloc, Pirate (P = 1.000) |

The resolution points are the same with uniform tier weights, so the unverified copy counts don't matter. The 20:33 game could also have used the turn-0 hero constraint: Ysera implied Dragon.

**Monte Carlo** (`simulate_resolution.py`, 1,500 random lobbies per row). The tavern-tier curve is 1,2,2,3,3,4,4,5,5,6,6,6. Shop sizes are 3/4/4/5/5/6 by tier (assumed). Draws use the copy weights. Rerolls count from turn 3.

| Scenario | Median BG turn resolved | p75 | p90 | p95 | Unresolved by T12 | Wrong answer |
|---|---|---|---|---|---|---|
| Shop only, no rerolls (worst case) | 6 | 8 | 9 | 11 | 1.1% | 0 |
| Shop only, 1 reroll/turn | 4 | 5 | 6 | 7 | 0 | 0 |
| Shop only, 2 rerolls/turn | 3 | 4 | 5 | 5 | 0 | 0 |
| No rerolls + opponent board (one tribe + neutrals, min(turn,7) minions) | 4 | – | 7 | 8 | 0.07% | 0 |
| 1 reroll + opponent board | 4 | – | 5 | 6 | 0 | 0 |

**UX takeaway:** show per-tribe probabilities from turn 1. Confirmations usually arrive on turn 1 or 2. Expect a stable "these 5 tribes" answer by **BG turn 4 in a typical game** (90% by turn 5–7), which is before most comps are committed. The worst case is about turn 9–11, for a player who never rolls and whose opponents' boards don't help.

### B.4 Open items

- Confirm whether the server sends `IS_BACON_POOL_MINION=0` on a removed card, for example a Faceless Manipulator copy of an old card. If it does, the runtime self-heal could also remove cards.
- Verify the copies per tier for 36.6.1 (16/15/13/11/9/7 is assumed), and the shop sizes.
- Get a Duos capture: tribes per lobby, the Duos pool, and whether 3533/`BACON_DUO_TEAM_ID` change anything here.
- Identify tag 4730 once lobbies vary, after Aberrations stop being forced.
- Resolve Flourishing Frostling `BG26_537` (keep it or remove it) from sightings.
- Confirm the end date of the Aberration fortnight.

## Citations

- hsdata commits: https://api.github.com/repos/HearthSim/hsdata/commits (`5212f4e178`, 2026-09-15). File: https://github.com/HearthSim/hsdata/raw/5212f4e178/CardDefs.Bacon.xml
- HearthstoneJSON: https://api.hearthstonejson.com/v1/ (newest build dir 251952) ; https://api.hearthstonejson.com/v1/251952/enUS/cards.json ; https://api.hearthstonejson.com/v1/enums.json
- HSReplay live meta period: https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/ (fetched 2026-09-22 ~21:50 EDT)
- HDT: https://github.com/HearthSim/Hearthstone-Deck-Tracker (`ef8ab6e838`, v1.58.1, 2026-09-22). Files: `Hearthstone Deck Tracker/Hearthstone/BattlegroundsDb.cs`, `Utility/RemoteData/Remote.cs`, `Utility/RemoteData/RemoteData.Config.cs`, `Utility/Assets/CardDefsManager.cs`
- HSTracker: https://github.com/HearthSim/HSTracker (`c723bfd4a7`, 3.6.12, 2026-09-22). Files: `HSTracker/Utility/BattlegroundsDb.swift`, `HSTracker/Database/Models/Card.swift`
- Firestone reference data: https://github.com/Zero-to-Heroes/hs-reference-data (`8d8fdd4d91`, 2026-09-22). Files: `src/services/bgs-utils.ts`, `src/cards_rules.json`, `src/models/reference-cards/reference-card.ts`. Card JSON: https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json (last-modified 2026-09-20)
- Firestone app (public snapshot `0a30f066eb`, 2026-02-08): https://github.com/Zero-to-Heroes/firestone. Files: `libs/battlegrounds/core/src/lib/services/cards-in-game.ts`, `libs/game-state/src/lib/services/game-events/event-parser/battlegrounds/bgs-global-info-update-parser.ts`
- hsbg.cards: https://hsbg.cards/api/v1/cards?pool=true ; https://hsbg.cards/api/v1/patches ; https://hsbg.cards/api/v1/patches/36.4.2_36.6.1 (generated 2026-09-22T20:31Z)
- Blizzard: https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon ; https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846
- Local evidence (read-only): `fixtures/private-logs/Hearthstone_2026_09_22_20_33_28/Power.log`, `fixtures/private-logs/Hearthstone_2026_09_22_21_08_40/Power.log`

## Addendum (2026-09-22): the game shows the tribes on screen

A screenshot the user took of the hero-pick screen shows the lobby's tribes as text under the "Choose a Hero" banner (for example "Aberrations, Demons, Elementals, Murlocs, Quilboar"). The client knows the tribes before the first shop; it just doesn't write them to Power.log. There are two ways to use this:
1. **Keep inference (the default).** It needs no permissions and settles by about turn 4.
2. **Optional OCR.** Capture that banner region with ScreenCaptureKit and read it with Vision's `VNRecognizeTextRequest` during hero pick. That gives exact tribes at turn 0. The cost is Screen Recording permission, which macOS 15+ re-prompts for monthly. It reads the screen, not memory, so it stays within "pencil and paper". Its position is in [overlay-coordinates.md](overlay-coordinates.md).
