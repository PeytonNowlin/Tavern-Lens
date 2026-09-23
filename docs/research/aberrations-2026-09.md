# Aberrations in Battlegrounds (patch 36.6.1): what exists on how to play them

Research date: **2026-09-22** (local; some UTC timestamps below are 2026-09-23). Companion to [meta-comps-2026-09.md](./meta-comps-2026-09.md). That doc's "Aberrations (new in 36.6.1): no comp data yet" section (section 4) and its watch-list YAML (section 7) are the starting point. This doc replaces that watch-list with the fuller picture below and doesn't repeat that doc's pool-change or non-Aberration nerf lists.

> **Read this first.** On day 1 there is still **no data-backed Aberration comp**. Firestone has no Aberration archetype, HSReplay/hsguru returned 403, and no written guide exists yet. What does exist:
> 1. Firestone **per-card** stats that already include a few tens of thousands of 36.6.1 games (section 5).
> 2. A small sample of 69 Firestone final boards that contain Aberrations.
> 3. Streamer preview videos (titles and descriptions only; no transcripts could be fetched).
> 4. Around 25 Reddit and Blizzard-forum threads from launch day.
>
> The comps in section 4 are **emerging hypotheses**, each labelled with its evidence. Treat everything here as provisional. Blizzard has already tuned four Aberrations before launch, and Reddit and forum posters widely expect nerfs.

---

## 1. Snapshot metadata

| Item | Value | Source (retrieved 2026-09-22) |
|---|---|---|
| Patch | 36.6.1, server-side on top of client build **251952** (36.6). Rollout was regional on 2026-09-22: JeefHS "Abberations Are Out Already?!" published 14:00Z; a Reddit post says "Aberration just hit EU servers" at 22:03Z | https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon ; https://www.youtube.com/watch?v=V0ZyTYC9gr8 ; https://www.reddit.com/r/BobsTavern/comments/1wnnh6f/i_hate_aberration_meta/ |
| Card data | HearthstoneJSON `latest` = build dir **251952** (the build listing at https://api.hearthstonejson.com/v1/ has 251332, 251951, 251952 as the newest; there's no newer dir for 36.6.1). Firestone `cards_enUS.gz.json` has the same 66 Aberration-typed entries and includes `tags.TAG_SCRIPT_DATA_NUM_*`, which fills in the `{0}/{1}` numbers | https://api.hearthstonejson.com/v1/latest/enUS/cards.json ; https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json |
| hsdata | Latest commit is "Update to patch 36.6.0.251952" (2026-09-15). No 36.6.1 commit | https://api.github.com/repos/HearthSim/hsdata/commits |
| Race enum | `Race.ABERRATION = 126` (JSON string `"ABERRATION"`). Pool-subset tag `BACON_SUBSET_ABERRATION = 4757` | python-hearthstone `hearthstone/enums.py` |
| **Numbers are pre-hotfix in the card JSON** | Build 251952 still has the pre-hotfix values for Aph'lass, Shadow of Doubt, Ghur'sha and Faceless Converter. The live values (36.6.1 hotfix) are used in section 3 | https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846 |
| Firestone stats | `card-stats/mmr-{100,10}/last-patch` updated **2026-09-23T00:10Z**. `trinket-stats/last-patch` updated 2026-09-22T12:10Z. `hero-stats/mmr-100/last-patch` updated 2026-09-22T15:10Z. `comp-stats/last-patch` updated 2026-09-23T00:10Z (21 archetypes, **none Aberration**) | https://static.zerotoheroes.com/api/bgs/card-stats/mmr-100/last-patch/overview-from-hourly.gz.json (etc.) |
| Firestone patch marker | `patches.json` has no 36.6.1 entry. `currentBattlegroundsMetaPatch` is still **251332** (36.4.2), so every "last-patch" file mixes pre- and post-36.6.1 games | https://static.zerotoheroes.com/hearthstone/data/patches.json |
| **Returned 403 / unusable** | Firestone `past-1`, `past-3`, `past-7`, `current-patch` paths for card/comp/hero/trinket stats (S3 AccessDenied). reddit.com `.json` search and listing endpoints (403; the `.rss` equivalents worked but hit 429 rate limits for some threads). hsguru.com/battlegrounds (403). liquipedia.net (403). hsreplay.net/battlegrounds/comps and /minions (403). playnews.gg guide (403). YouTube auto-captions (empty response, so no transcripts). bgknowhow.com redirects to its GitHub repo (no Aberration strategy content) | curl / WebFetch, 2026-09-22 |

---

## 2. What Aberrations are

**Official description** (Blizzard, https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon):
- "Each time a friendly Aberration dies, it advances your Deity's progress." After three sacrifices, the Deity joins the fight.
- "There are two Deities, C'Thun and Y'Shaarj, but only one will answer your call. Which Deity answers is chosen at random at the start of each game."
- Aberrations are "built around discard synergies". They appear in **every lobby for the first two weeks** (2026-09-22 to about 2026-10-06), and Naga rotate out.

**How it works, from card data** (build 251952):
- Every player gets a hidden **`BG_OldGod` "Secret Deity [DNT]"**: "After 3 friendly Aberrations die **each combat**, awaken a 1/1 [Deity]." The counter therefore resets every combat. You need 3 Aberration deaths *in that fight*. The local Power.log confirms this entity sits in the `SECRET` zone for the player and for opponents (appendix A).
- The Deity is a 1/1 (golden 2/2) Tier-3 Aberration that is **not on your board**. Cards that say "give your **Deity** +X/+Y" buff it permanently between turns. Nearly every scaling Aberration feeds the Deity rather than the board.
  - **C'Thun** `BGFYM_000`: "After this awakens, give this minion's stats split amongst your other minions." Golden: "double this minion's stats". It turns Deity stats into board stats when it awakens mid-combat.
  - **Y'Shaarj** `BGFYM_011`: "Deathrattle: Summon your first 2 Aberrations that died this combat with their maximum stats (except Deities)." Golden summons 4.
- **Discard** is the tribe's core action. You discard a card from hand through Activate minions, hero powers, "When you play one, discard the other" generators, or Mysterious K'Thir's end-of-turn effect. Discard payoffs trigger on it, and the three new Tavern spells get **stronger when discarded** than when cast ("If you discard this, cast it twice").
- **Hero bans** (Blizzard post; also hsbg.cards): always banned in Aberration lobbies are Morchie, Murozond Unbounded and Sylvanas Windrunner. With Y'Shaarj as the Deity, The Curator, The Lich King, Teron Gorefiend and N'Zoth are also banned.
- **Duos-only Aberrations** exist (hsbg.cards marks them `isDuosOnly`): Voidpriest Cloner `BGDUO_700` and C'Thrax Wrecker `BGDUO_701`.

---

## 3. Full card list

Stats and text come from the Firestone/HearthstoneJSON build 251952 files, with the placeholders filled from `TAG_SCRIPT_DATA_NUM_*`. Tiers and the solo pool come from the Blizzard post and the hsbg.cards API (`/api/v1/cards?tribe=aberration&pool=true`, 2026-09-22), which match each other. **Bold** marks the 36.6.1 hotfix values (Blizzard forum post above).

### 3.1 Solo-pool Aberration minions (25 shop minions + 2 Deities + the Tentacle token; hsbg.cards says "27 Total")

| Tier | Name | cardId (golden) | Stats (golden) | Text (normal) | Golden text if different |
|---|---|---|---|---|---|
| 1 | Joyous | `BG36_110` (`_G`) | 2/3 (4/6) | Battlecry: Give your Deity +2/+2. | +4/+4 |
| 1 | Zoatroid | `BG36_098` (`_G`) | 3/2 (6/4) | When you sell this, get a 0/2 Tentacle with Taunt. | two Tentacles |
| 1 (token) | Aberrant Tentacle | `BGFYM_002t` (`_G`) | 0/2 (0/4) | Taunt | - |
| 2 | Brain Rotter | `BG36_099` (`_G`) | 3/4 (6/8) | Activate (0): Discard a card to give your Deity +2/+2. | +4/+4 |
| 2 | Underrot Spawn | `BG36_116` (`_G`) | 2/2 (4/4) | Deathrattle: Summon a 0/2 Tentacle with Taunt. Give your minions +1 Attack. | two Tentacles, +2 Attack |
| 2 | Unwilling Slacker | `BG36_101` (`_G`) | 1/1 (2/2) | Deathrattle: Get a random 1-Cost Tavern spell. | two spells |
| 3 | C'Thun (Deity) | `BGFYM_000` (`_G`) | 1/1 (2/2) | Deity. After this awakens, give this minion's stats split amongst your other minions. | double this minion's stats |
| 3 | Y'Shaarj (Deity) | `BGFYM_011` (`_G`) | 1/1 (2/2) | Deity. Deathrattle: Summon your first 2 Aberrations that died this combat with their maximum stats (except Deities). | first 4 |
| 3 | Abyssal Envoy | `BG36_311` (`_G`) | 3/4 (6/8) | Activate (0): Discard a card to get a random Tavern spell. | 2 spells |
| 3 | Drifting Sacrifice | `BG36_113` (`_G`) | 2/1 (4/2) | Reborn. Deathrattle: Give your Deity +2/+1. | +4/+2 |
| 3 | Fetid Corroder | `BG36_112` (`_G`) | 3/3 (6/6) | Battlecry: Get a Sludge Corrosion. | 2 |
| 3 | Vicious Mindslasher | `BG36_108` (`_G`) | 3/1 (6/2) | Whenever you cast a Tavern spell, give this and your Deity +1/+3. | +2/+6 |
| 3 | Wandering Willbreaker | `BG36_100` (`_G`) | 1/3 (2/6) | When you sell this, get 2 random Tavern spells. When you play one, discard the other. | get 4, play two, discard the others |
| 4 | Cutthroat K'Thir | `BG36_106` (`_G`) | 4/4 (8/8) | Whenever you discard a card, give this and your Deity +4/+4. | +8/+8 |
| 4 | Faceless Operative | `BG36_308` (`_G`) | 4/2 (8/4) | When you sell this, get 2 random Aberrations. When you play one, discard the other. | get 4 / play two |
| 4 | Mindbending Recruiter | `BG36_312` (`_G`) | 6/2 (12/4) | Activate (0): Discard a card to get a random Aberration. | 2 Aberrations |
| 4 | Nightmare Corroder | `BG36_115` (`_G`) | 7/4 (14/8) | Deathrattle: Get a Sludge Corrosion. | 2 |
| 4 | Parasitic Fleshling | `BG36_114` (`_G`) | 4/6 (8/12) | At the end of your turn, give your left-most minion +2/+2. (Improved by each card you've discarded this game!) | +4/+4 base |
| 5 | De-volition-ist | `BG36_102` (`_G`) | 4/8 (8/16) | After this attacks, deal damage equal to this minion's Attack to the highest-Health enemy minion. | double its Attack |
| 5 | Faceless Converter | `BG36_318` (`_G`) | 5/5 (10/10) | Deathrattle: Give your Deity **+2/+2** (was +1/+1). (Improved by each Tavern spell you've cast this game!) | **+4/+4** (was +2/+2) |
| 5 | Mindbender Ghur'sha | `BG36_097` (`_G`) | 3/9 (6/18) | Whenever you discard a card, give your other minions **+4/+4** (was +3/+3). | **+8/+8** (was +6/+6) |
| 5 | Mysterious K'Thir | `BG36_320` (`_G`) | 8/8 (16/16) | At the end of your turn, discard your 3 left-most Tavern spells. Gain +8/+8 for each discarded. | +16/+16 each |
| 5 | N'raqi Frostcaller | `BG36_300` (`_G`) | 6/3 (12/6) | Activate (0): Discard a card for your Tavern spells to give an extra +1/+1 this game. | +2/+2 |
| 5 | N'raqi Sapper | `BG36_103` (`_G`) | 6/3 (12/6) | Battlecry and Deathrattle: Get an Energizing Chamber. | 2 |
| 6 | Dark Puppeteer | `BG36_104` (`_G`) | 8/4 (16/8) | Deathrattle: Your Tavern spells give an extra +4 Health this game. | +8 |
| 6 | Harbinger Aph'lass | `BGFYM_005` (`_G`) | 3/6 (6/12) | Whenever you discard a card, give your Deity **+2/+1** (was +1/+1) and improve this. | **+4/+2** (was +2/+2) |
| 6 | The Shadow of Doubt | `BG36_109` (`_G`) | 6/8 (12/16) | Whenever a card is added to your hand, give your Deity **+5/+5** (was +3/+4). | **+10/+10** (was +6/+8) |
| 7 | Sha of Fear | `BG36_111` (`_G`) | 9/12 (18/24) | Whenever you cast a Tavern spell, give your minions and Deity +4/+3. | +8/+6 |

"Activate (0)" comes from the data file (`TAG_SCRIPT_DATA_NUM_3 = 0`). Mindbending Recruiter's cost tag is missing from the file. So the data shows the Activate cost as 0, but check it in game (the gold cost may be set dynamically).

### 3.2 Other Aberration-typed cards (not in the solo shop pool)

| cardId | Name | Stats | Text | Status |
|---|---|---|---|---|
| `BGDUO_700` | Voidpriest Cloner | T3, 4/5 (8/10) | Whenever you discard a card, Pass a copy of it. (2 times per turn.) Golden passes 2 copies | **Duos only** (hsbg.cards) |
| `BGDUO_701` | C'Thrax Wrecker | T5, 8/8 (16/16) | Battlecry, Deathrattle, and Rally: Give your team's Deities +4/+4 (+8/+8) | **Duos only** |
| `BG27_002` | Oozeling Gladiator | T2, 2/2 | Battlecry: Get two Slimy Shields that give +1/+1 and Taunt | Retyped Aberration **and** on Blizzard's removed list. Not in hsbg.cards' current pool |
| `BG_EX1_564` | Faceless Manipulator | 3/3 | Battlecry: Choose a minion and become a copy of it | Aberration-typed, not a shop-pool minion per hsbg.cards. It does appear in Firestone card-stats (n=33,605 plays), so it is generated somehow. The source wasn't verified |
| `BG23_015` | Orgozoa, the Tender | 3/7 | Spellcraft: Discover a Naga | Aberration-typed. Presumably inactive while Naga are out (not in hsbg.cards pool) |

Blizzard also lists "Faceless Taverngoer" as converted, but no card by that name exists in build 251952.

### 3.3 Related non-Aberration cards

**Tavern spells** (Blizzard post; the IDs are in the Firestone pool):

| cardId | Name | Tier/Cost | Text |
|---|---|---|---|
| `BG36_301t` | Sludge Corrosion | T4 / 1 | Give your minions +1/+1. If you discard this, cast it twice. |
| `BG36_303` | Corrupted Coin | T5 / 2 | Gain 2 Gold. If you discard this, increase your maximum Gold by 2. |
| `BG36_371` | Energizing Chamber | T5 / 1 | Give your Deity +7/+7. If you discard this, cast it twice. |

**Heroes:**

| cardId | Hero | Hero power | Firestone hero-stats (mmr-100, last-patch, 15:10Z) |
|---|---|---|---|
| `BG36_HERO_000` | Drest'agath | `BG36_HERO_000p` Incubate (1): Discard a card to get a random Aberration. | **not present** in the file |
| `BG36_HERO_002` | Kith'ix | `BG36_HERO_002p` Dark Ritual (2): Get 2 random minions. When you play one, discard the other. | **not present** |
| `BG36_HERO_101` | Tras'tath, Soul Parasite | Void Power: start of game, Discover a Tier 5 minion with a Dark Gift; unlocks Turn 7 | n=33,135, avg 3.80 (not Aberration-specific) |
| `BG36_HERO_105` | Nightmare Lord Xavius | Feel Devastation: every 4 turns, Discover a minion with a Dark Gift | n=36,437, avg 3.81 (not Aberration-specific) |
| (any) | A Tale of Kings hero power | `TB_BaconShop_HP_041l` King of Aberrations: Discover an Aberration. Swaps type each turn. | - |

In build 251952, Drest'agath and Kith'ix have `battlegroundsHero` unset. They were playable on 2026-09-22: Kith'ix appears in the local log, and Shadybunny's preview videos are "Drestagath" games.

**Aberration trinkets** (hsbg.cards tags these 15 as `minionTypes: ["Aberration"]`). Stats come from Firestone `trinket-stats/last-patch`, updated 2026-09-22T12:10Z, so they cover only the first hours of 36.6.1. `averagePlacement` is over games where the trinket was picked.

| cardId | Name | Cost | Text | n | pick rate | avg place |
|---|---|---|---|---|---|---|
| `BG36_MagicItem_400` | Corrupted Coin Portrait | - | Get 2 Corrupted Coins. | 2,400 | 0.46 | 3.61 |
| `BG36_MagicItem_402` | Mindslasher Portrait | 5 | Get a Vicious Mindslasher. Your Mindslashers also give stats to adjacent minions. | 1,183 | 0.36 | 3.64 |
| `BG36_MagicItem_403` / `403t` | Hammer of Twilight | 1 | Your minions have +1 Attack (+2/+1 upgraded). Improved by each card discarded. | 179 / 527 | 0.14 / 0.21 | 3.66 / 3.41 |
| `BG36_MagicItem_404` / `404t` | Corrupted Baton | 1 | After you cast a Tavern spell, give your Deity +4/+4 (+10/+10 upgraded). | 1,323 / 916 | 0.39 / 0.38 | 3.47 / 3.54 |
| `BG36_MagicItem_406` | Shath'Yar Shrine | 4 | After you discard a spell, get a random Aberration. | 1,101 | 0.49 | 3.53 |
| `BG36_MagicItem_416` | Evil Experiment | - | After your Deity awakens, give it Reborn. | 712 | 0.31 | 3.47 |
| `BG36_MagicItem_417` | Makeshift Master | - | Spellcraft: Choose a minion. After it gains stats outside combat this turn, your Deity also gains them. | 547 | 0.23 | 3.51 |
| `BG36_MagicItem_418` | Tome of the Ancients | - | After you discard 3 cards, your Tavern spells give an extra +1/+1 this game. | 1,406 | 0.27 | 3.66 |
| `BG36_MagicItem_430` | **Sludge Portrait** | 2 | Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion. | 1,075 | 0.45 | **2.84** |
| `BG36_MagicItem_600` | Converter Portrait | 4 | Get a Faceless Converter. Start of Combat: Give your Faceless Converters Reborn. | 825 | 0.35 | 3.71 |
| `BG36_MagicItem_602` | Mask of Ancient Ones | 3 | Make your Deity Golden this game. | 1,079 | 0.45 | 3.57 |
| `BG36_MagicItem_606` | Writhing Tentacles | 1 | After you discard your first minion each turn, get a copy of it with double stats. | 185 | 0.08 | 4.33 |
| `BG36_MagicItem_852` | Willbreaker Sticker | 1 | Get 2 random Tavern spells; play one, discard the other; repeat each turn. | 1,989 | 0.39 | 3.51 |

Other discard-relevant cards: Mangled Bandit `BG28_582` (returning, reworked: "Activate (0): Discard a card to get 3 Blood Gems"); Conductor Portrait `BG30_MagicItem_402` and Snarling Conductor `BG28_585` (spell discard for gold; the portrait isn't flagged pool); Timewarped Bandit `BG34_PreMadeChamp_078`. Mid-game "Desecration" `BG36_MidGameEffect_000t88` scales with cards discarded, and "Worship" `..._t89` says "Start of Combat: Gain the stats of your Deity". Their availability wasn't verified.

**Anomalies:** Firestone `anomalies-list.gz.json` and the card data have no anomaly that mentions Aberration, Deity or discard.

**Dark Paradox** `BG36_360`: 5 variants (the ID suffix is not the tier; tiers are from the Blizzard post): `t3` T2 2/4 "Whenever you play a card, gain +2 Attack"; `t6` T3 2/2 "+2/+2 per Battlecry triggered"; `t5` T4 2/6 "Rally: get a random minion of your most common type"; `t4` T5 8/4 Divine Shield that takes 3 hits; `t9` T6 10/2 "Deathrattle: summon a Golem with this minion's stats". The hotfix stops the T5 and T6 versions from appearing in Y'Shaarj lobbies.

---

## 4. Synergies and emerging comps

### 4.1 C'Thun vs Y'Shaarj: what the card text implies

This is derived from card text, not from data.

| | C'Thun | Y'Shaarj |
|---|---|---|
| What the Deity's stats do | Its stats are **split among your other minions** when it awakens. A big Deity turns into a big board, and "permanently keep stats gained in combat" effects (Persistent Poet `BG29_813`, Tarecgosa `BG21_015`) could keep them (community claim, 4.2 D). | Its own stats matter only as a body. Its Deathrattle **re-summons your first 2 dead Aberrations at max stats**, so the value is in *which* Aberrations die first. |
| What you want dying first | Cheap Aberrations (Tentacles, Zoatroid tokens, Drifting Sacrifice, Underrot Spawn) to reach 3 deaths fast. | Your **best** Aberrations, or ALL-type minions such as Gatekeeper Amalgam that count as Aberrations (community claim, 4.2 A), so they come back at full stats. |
| Hero bans | general bans only | also bans Curator, Lich King, Teron, N'Zoth, which suggests Blizzard saw Deathrattle/Reborn/Deity loops with those heroes |
| Pairs with | Energizing Chamber, Corrupted Baton, Shadow of Doubt, Aph'lass, K'Thir (Deity scaling), Mask of Ancient Ones (golden = double split) | Evil Experiment (Reborn Deity), Converter Portrait (Reborn Converters), Titus/Baron Deathrattle doublers (community, 4.2 A) |

**Cross-tribe hooks** (community reports):
- **ALL-type ("Menagerie"/Amalgam) minions count toward Deity progress.** Several Reddit comments describe "1 good amalgam unit with reborn and 1 small Aberration" as the way strong players use the tribe (https://www.reddit.com/r/BobsTavern/comments/1wnm1lg/, 2026-09-22).
- **Tavern-spell tribes and builds** (Balinda `BG35_883` + Gatekeeper Amalgam `BG36_640` tea-set, Quilboar gems, Brann spell generators) feed Mindslasher, Sha of Fear, Corrupted Baton, Faceless Converter and Dark Puppeteer or Frostcaller spell buffs.
- **Deathrattle builds** (Titus Rivendare `BG25_354`, Baron Rivendare, Deathstrider) double Aberration Deathrattles: Converter, Drifting Sacrifice, Nightmare Corroder, Sapper. One Firestone sampled final board (tagged `beast_lobster`) has golden Faceless Converter x2, Deathstrider x2 and golden Titus. A Reddit post titled "Deathstrider goes hard with this comp" (image only, not viewed) is at https://www.reddit.com/r/BobsTavern/comments/1wnofuh/.
- **End-of-turn** doublers (Drakkari Enchanter `BG26_ICC_901`) combine with Parasitic Fleshling and Mysterious K'Thir (Reddit comment in 1wnm1lg; a bug report says golden Fleshling + Drakkari "doesn't always respawn with max stats": https://www.reddit.com/r/BobsTavern/comments/1wnf0el/).

### 4.2 Emerging comps (hypotheses; evidence level stated)

**A. Tea-Set / Amalgam + Deity** (`aberration_tea_set_deity`). *Evidence: strongest of the four. Firestone final boards plus several community posts.*
- **What it is:** Firestone's existing Neutral Tea Set (Gatekeeper Amalgam + Balinda, see meta-comps section 4.10) with Aberration spell-buff pieces splashed in. The Amalgam counts as an Aberration for Deity progress.
- **Data:** of 14,650 sampled Firestone final boards, 69 contain a non-Oozeling Aberration. **27 of the 69 are `neutral_tea_set`.** The most common co-cards on those 69 boards: Gatekeeper Amalgam (63), Balinda (49), Felfire Conjurer (18), Drakkari (18), Brann (18). The most common Aberrations: Dark Puppeteer (23), De-volition-ist (13), N'raqi Frostcaller (9), The Shadow of Doubt (8), Sha of Fear (5). Many of these boards also have **Fauna Whisperer (Naga)**, so some are from the launch-hours window when Naga were reportedly still in lobbies (Reddit, 1wnjc49: "people were playing aberrations while nagas were in the lobby").
- **Community:** "the only truly viable build right now is Balinda / Gatekeeper Menagerie" (Reddit, 1wnjc49, opinion). The "1 good amalgam unit with reborn and 1 shitty small Aberration" meta (1wnm1lg, opinion). One forum poster calls Aberrations weak without luck "unless you … weave in other tribes. Using C'thun to buff Tarecgosa" (https://us.forums.blizzard.com/en/hearthstone/t/166026, opinion).
- **Core:** Gatekeeper Amalgam `BG36_640`, Balinda Stonehearth `BG35_883`, Dark Puppeteer `BG36_104`, N'raqi Frostcaller `BG36_300`.
- **Addons:** Brann `BG_LOE_077`, Felfire Conjurer `BG32_821`, De-volition-ist `BG36_102`, The Shadow of Doubt `BG36_109`, Sha of Fear `BG36_111`, Drifting Sacrifice `BG36_113`, Drakkari Enchanter `BG26_ICC_901`.
- **Commit signal (inferred):** Amalgam + Balinda, as in the original comp, plus 2 or more cheap Aberrations to reach 3 deaths. With Y'Shaarj, the Amalgam dying first gets re-summoned at max stats (community claim; not verified in logs).

**B. Discard → Deity scaling** (`aberration_discard_deity`). *Evidence: card design, a Shadybunny preview video ("this time with a Sludge strategy and Ysaarj reviving 2 of our minions every combat", https://www.youtube.com/watch?v=X5iHIVCcfmU), and Firestone's best trinket result (Sludge Portrait 2.84, n=1,075).*
- **Engine:** activators (Brain Rotter, Abyssal Envoy, Mindbending Recruiter, Frostcaller, Drest'agath's hero power) discard Sludge Corrosion, Energizing Chamber or Corrupted Coin, which "cast twice" when discarded. Discard payoffs: Cutthroat K'Thir, Aph'lass, Ghur'sha, Parasitic Fleshling.
- **Core:** Brain Rotter `BG36_099`, Cutthroat K'Thir `BG36_106`, Mindbender Ghur'sha `BG36_097`, Harbinger Aph'lass `BGFYM_005`.
- **Addons:** Abyssal Envoy `BG36_311`, Mindbending Recruiter `BG36_312`, Fetid Corroder `BG36_112`, Nightmare Corroder `BG36_115`, N'raqi Sapper `BG36_103`, Parasitic Fleshling `BG36_114`, Mysterious K'Thir `BG36_320`, Sludge Portrait `BG36_MagicItem_430`, Shath'Yar Shrine `BG36_MagicItem_406`.
- **Tempo vs scaling (inferred from text):** the early tempo pieces are Joyous, Zoatroid and Underrot Spawn (Deity progress and fodder) and Brain Rotter (T2 Deity scaling). The scaling pieces are Cutthroat K'Thir (T4), Ghur'sha (T5, whole-board buff per discard) and Aph'lass (T6, self-improving). Energizing Chamber discarded gives +14/+14 to the Deity.
- **Known issues:** discard via Activate is reported broken or unreliable **on mobile**: cards at the ends of the hand are hard to target (Blizzard forum https://us.forums.blizzard.com/en/hearthstone/t/166041, where a Blizzard rep says "being investigated"; Reddit 1wnj2mf, 1wnjd4o). "Activate twice doesn't work for aberrations that need to discard" (Reddit 1wnms97).

**C. Tavern-spell → Deity scaling** (`aberration_spell_deity`). *Evidence: card design, and Reddit "my dude that gives stats to C'Thun was like +500/+500 cause all the spells from second-tier dude" (https://www.reddit.com/r/BobsTavern/comments/1wnlkco/). Opinion or single anecdote.*
- **Core:** Vicious Mindslasher `BG36_108`, Faceless Converter `BG36_318`, Sha of Fear `BG36_111`, The Shadow of Doubt `BG36_109`.
- **Addons:** Unwilling Slacker `BG36_101`, Wandering Willbreaker `BG36_100`, Dark Puppeteer `BG36_104`, N'raqi Frostcaller `BG36_300`, Corrupted Baton `BG36_MagicItem_404`, Willbreaker Sticker `BG36_MagicItem_852`, Mindslasher Portrait `BG36_MagicItem_402`, Converter Portrait `BG36_MagicItem_600`, Titus Rivendare `BG25_354` (double Converter Deathrattle).
- Note: Faceless Converter was **buffed** in the hotfix (+2/+2 base per spell cast this game), so its payoff grows the more spells you cast over the whole game.

**D. C'Thun + Persistent Poet / Makeshift Master** (`aberration_cthun_poet`). *Evidence: one Reddit post only (https://www.reddit.com/r/BobsTavern/comments/1wnnh6n/, "CThun was 24k/28k", 2026-09-22). Community, single anecdote.*
- As described: C'Thun Deity, a Dragon lobby (plus Quilboar ideally), the Makeshift Master greater trinket, golden Persistent Poet next to an Amalgam, Balinda triple-casting spells on the Amalgam, and "3 aberrations in addition to amalgam". When the three die, C'Thun awakens and gives its stats to the Amalgam, and Poet keeps them.
- **Core:** Persistent Poet `BG29_813`, Gatekeeper Amalgam `BG36_640`, Balinda `BG35_883`, Makeshift Master `BG36_MagicItem_417`.
- **Addons:** N'raqi Frostcaller `BG36_300`, Dark Puppeteer `BG36_104`, Tarecgosa `BG21_015`.

**Best heroes or trinkets:** no source names Aberration-specific best heroes with data. Drest'agath and Kith'ix aren't in Firestone's hero file yet. Among trinkets, only Sludge Portrait stands out (avg 2.84, n=1,075). Writhing Tentacles looks bad (4.33, n=185), and Reddit reports a bug in it: "stopped doubling in health after it reached about 256" (https://www.reddit.com/r/BobsTavern/comments/1wnhmjl/). All trinket numbers come from only a few hours of 36.6.1 play.

---

## 5. Early stats (Firestone card-stats, mixed window; read the caveats)

Source: `https://static.zerotoheroes.com/api/bgs/card-stats/mmr-100/last-patch/overview-from-hourly.gz.json` (and `mmr-10`), `lastUpdateDate` 2026-09-23T00:10:33Z, retrieved 2026-09-22.

**How big the sample is (derived, approximate):**
- The card-stats file reports `dataPoints` 1,509,629 over the whole 36.4.2 → now window. The hero-stats file from 9 hours earlier had 1,485,466 games, 11,784 of them with Aberration in the lobby. So very roughly **~35k Aberration-lobby games** feed the Aberration rows below.
- Firestone doesn't publish that 35k figure; it is inferred from the difference between the two files.
- The `mmr-10` file reports the same `dataPoints` as `mmr-100`, so that field isn't per-bracket.
- `totalPlayed` counts **plays**, not games.

**Caveats:**
- `averagePlacement` is the average final placement of players who *played* the card. `averagePlacementOther` is everyone else in the window, and that includes ~1.47M pre-36.6.1 games, so the gap is **not** a card-strength measure.
- High-tier cards look good partly because only surviving players reach them. Compare cards within a tier, not across tiers.
- Oozeling Gladiator's row is almost all pre-36.6.1 (it was a pool minion before).
- The Deity rows are tiny because the Deity is summoned in combat, not played.

| Tier | Card | cardId | Plays (all MMR) | Avg place when played (all) | Plays (top 10%) | Avg place (top 10%) |
|---|---|---|---|---|---|---|
| 1 | Joyous | BG36_110 | 61,647 | 3.43 | 5,702 | 3.61 |
| 1 | Zoatroid | BG36_098 | 60,677 | 3.40 | 6,554 | 3.58 |
| 2 | Brain Rotter | BG36_099 | 55,595 | 3.22 | 5,459 | 3.53 |
| 2 | Unwilling Slacker | BG36_101 | 41,838 | 3.30 | 4,098 | 3.57 |
| 2 | Underrot Spawn | BG36_116 | 35,794 | 3.41 | 3,497 | 3.62 |
| 3 | Wandering Willbreaker | BG36_100 | 57,534 | 3.03 | 6,296 | 3.30 |
| 3 | Abyssal Envoy | BG36_311 | 57,466 | 3.01 | 6,398 | 3.36 |
| 3 | Fetid Corroder | BG36_112 | 55,169 | 3.08 | 5,789 | 3.39 |
| 3 | Vicious Mindslasher | BG36_108 | 36,681 | 3.28 | 3,624 | 3.52 |
| 3 | Drifting Sacrifice | BG36_113 | 32,820 | 3.40 | 3,474 | 3.66 |
| 4 | Faceless Operative | BG36_308 | 50,206 | 2.98 | 5,842 | 3.29 |
| 4 | Mindbending Recruiter | BG36_312 | 47,781 | 3.08 | 5,396 | 3.41 |
| 4 | Nightmare Corroder | BG36_115 | 33,808 | 3.25 | 3,359 | 3.61 |
| 4 | Parasitic Fleshling | BG36_114 | 30,805 | 3.29 | 3,103 | 3.66 |
| 4 | Cutthroat K'Thir | BG36_106 | 29,159 | 3.33 | 2,783 | 3.63 |
| 5 | N'raqi Frostcaller | BG36_300 | 37,885 | 2.88 | 4,238 | 3.22 |
| 5 | N'raqi Sapper | BG36_103 | 37,045 | 2.99 | 4,025 | 3.31 |
| 5 | Faceless Converter | BG36_318 | 29,346 | 3.08 | 3,004 | 3.40 |
| 5 | Mysterious K'Thir | BG36_320 | 24,131 | 2.91 | 2,381 | 3.27 |
| 5 | Mindbender Ghur'sha | BG36_097 | 22,656 | 3.12 | 2,239 | 3.51 |
| 5 | De-volition-ist | BG36_102 | 19,553 | 3.11 | 1,944 | 3.50 |
| 6 | The Shadow of Doubt | BG36_109 | 28,235 | 2.87 | 3,060 | 3.18 |
| 6 | Harbinger Aph'lass | BGFYM_005 | 26,985 | 2.91 | 2,688 | 3.25 |
| 6 | Dark Puppeteer | BG36_104 | 26,353 | 2.90 | 2,951 | 3.23 |
| 7 | Sha of Fear | BG36_111 | 2,836 | 2.82 | 314 | 3.06 |
| token | Aberrant Tentacle | BGFYM_002t | 46,069 | 3.34 | 5,266 | 3.51 |
| spell | Sludge Corrosion | BG36_301t | 116,934 | 2.83 | 12,459 | 3.07 |
| spell | Energizing Chamber | BG36_371 | 61,326 | 2.80 | 7,320 | 3.05 |
| spell | Corrupted Coin | BG36_303 | 14,610 | 2.72 | 1,973 | 2.87 |
| Deity | C'Thun / Y'Shaarj | BGFYM_000 / BGFYM_011 | 19 / 10 | (too small) | 2 / 1 | - |

What the table does and doesn't support:
- Within each tier, the "generate/convert" cards have the best average placement:
  - T3: Willbreaker 3.03 and Envoy 3.01 vs Mindslasher 3.28 and Drifting Sacrifice 3.40.
  - T4: Operative 2.98 and Recruiter 3.08 vs K'Thir 3.33.
  - T5: Frostcaller 2.88 and Mysterious K'Thir 2.91 vs Ghur'sha 3.12 (Ghur'sha is pre-buff in this window).
- This is a **correlation on day-1 data**, possibly driven by players using those cards to feed non-Aberration spell builds (see 4.2 A).
- No comp-level Aberration numbers exist.

---

## 6. Consensus vs disagreement (all community opinion, 2026-09-22)

**Broad agreement:**
- The tribe is **strong at launch and expected to be nerfed**. Examples: "Aberrations need some tuning" and "It'll get patched" (Reddit 1wnjc49, 1wnlkco); forum threads "Toxic overpower early/mid game" and "Aberrations are garbage" (https://us.forums.blizzard.com/en/hearthstone/t/166027, /166021).
- **Early Deities get big.** One claim: "Before even going level 4 most players have Dieties of like 800/800" (Reddit 1wnnpvh, forum 166027). Anecdotes of Deities at 2k/1.8k and 9k/9k, and C'Thun at 24k/28k.
- **Mobile discard is broken** (see 4.2 B).
- **Duos:** Voidpriest Cloner is "completely broken" when doubled (golden or 2 copies duplicate discarded cards; Reddit 1wnrfnr, 1wnksqo).

**Disagreement:**
- *Forced or not.* Some say "you're pretty much forced to play Aberrations because of the Deity". Others reply "Youre 100% not forced… minions with the ALL tag, especially with reborn, are your friend", or "the person not going for aberrations at all completely swept everybody because aberrations are still quite weak" (all in 1wnjc49). One poster says demons and murlocs "still pwn the abbs".
- *Deity scaling speed.* "Deity scalling feels way too slow compared to other tribe's combo" (1wnrmb4) vs "Seems pretty easy to build up an insane diety" (1wnjc49).
- *Whether committing matters.* One side: "You need to scale the deity, otherwise it's not worth summoning it". The other: "You do not need to scale y'shaarj or commit to aberrations to have 1 giant amalgam that gets resummoned" (1wnm1lg).
- *Build suggestions from the "What's the plan" thread (1wnponm):* "ignore the deity and focus on the discard at end of turn stuff and juice up their cleave minion" (De-volition-ist).

**Launch irregularity:** several Reddit users say Naga appeared alongside Aberrations early on launch day (1wnjc49, 1wnponm). The Firestone final-board sample fits this: Fauna Whisperer (Naga) shows up on many of the 69 Aberration boards. Early card-stats may therefore include a non-standard pool.

**Pre-release streamer previews** (titles and descriptions only; content not reviewed because captions couldn't be fetched):
- dogdog, "Aberrations And Deities Arrive in Battlegrounds And We're Finding The Best Strat" (2026-09-13). The description mentions Y'Shaarj, Mindbending Recruiter and Nightmare Corroder. https://www.youtube.com/watch?v=fjnZajiQhlo
- JeefHS, "The BEST WAY To Play NEW TRIBE ABBERATIONS!" (2026-09-13). https://www.youtube.com/watch?v=z9PfvDgMqAU
- JeefHS, "NEW HERO 1 Gold For Abberation Unit Each Turn!" (2026-09-14). https://www.youtube.com/watch?v=g8kCF5Z-UIs
- Shadybunny, "NEW Hero VS Other Streamers!" (Drest'agath, 2026-09-13). https://www.youtube.com/watch?v=U_49TC9DBCY
- Shadybunny, "NEW Minion Type, NEW Cards!" (Drest'agath, Sludge + Y'Shaarj, 2026-09-14). https://www.youtube.com/watch?v=X5iHIVCcfmU
- Shadybunny, "NEW Patch - NEW Minion Type! (100+ Changes)" (patch review; Aberrations chapter 0:13-28:30, 2026-09-17). https://www.youtube.com/watch?v=aLlrtb7k4bw
- Rdu, "Aberration First Look From BlizzCon" (2026-09-13). https://www.youtube.com/watch?v=Ry-Zn2sPP2k
- Post-launch: JeefHS, "Abberations Are Out Already?!" (2026-09-22). https://www.youtube.com/watch?v=V0ZyTYC9gr8
- News articles (Blizzard Watch https://blizzardwatch.com/2026/09/12/hearthstone-battlegrounds-aberrations/ ; HearthPwn https://www.hearthpwn.com/news/12657-hearthstone-battlegrounds-new-minion-type) restate the patch notes with **no strategy content**.

---

## 7. Open questions

1. Does an ALL-type minion (Gatekeeper Amalgam) really count toward Deity progress and get re-summoned by Y'Shaarj? Several community reports say yes. To verify, check a Power.log combat for the `BG_OldGod` counter and the Y'Shaarj summon.
2. What do the Activate cards actually cost in game? The data shows `(0)`.
3. When will Firestone add `aberration_*` archetypes, and what will they be called? Check `comp-stats` daily.
4. How much do the hotfix buffs (Aph'lass, Shadow, Ghur'sha, Converter) and the Naga-in-lobby launch issue distort the first-day card-stats?
5. Where do Drest'agath and Kith'ix land? They're missing from hero-stats as of 15:10Z.
6. Does C'Thun's stat split go to *all* other minions, including non-Aberrations, and does it happen before or after combat buffs? The card text says "your other minions".
7. How often is each Deity actually summoned? The Deity-play counts (19/10) aren't a summon rate. Firestone would need a new metric, or we'd derive it from logs.

---

## 8. Machine-friendly block (emerging comps)

The format matches `meta-comps-2026-09.md` section 7. These entries **supersede** that file's provisional `aberration_*` watch-list.

```yaml
# Aberration emerging comps (36.6.1, day 1). NOT Firestone archetypes; hypotheses from card text,
# 69 Firestone final boards, and community posts. evidence: data-sample | video | community | card-text.
# Card IDs resolved against HearthstoneJSON / Firestone build 251952.
deityCardIds: [BGFYM_000, BGFYM_011]   # C'Thun, Y'Shaarj
secretDeityCardId: BG_OldGod            # per-player hidden counter: "After 3 friendly Aberrations die each combat, awaken..."
comps:
  - id: aberration_tea_set_deity
    name: "Aberration Tea Set / Amalgam Deity"
    tribes: [Aberration, Neutral]
    status36_6_1: "EMERGING"
    evidence: [data-sample, community]
    coreCardIds: [BG36_640, BG35_883, BG36_104, BG36_300]  # Gatekeeper Amalgam, Balinda Stonehearth, Dark Puppeteer, N'raqi Frostcaller
    addonCardIds: [BG_LOE_077, BG32_821, BG36_102, BG36_109, BG36_111, BG36_113, BG26_ICC_901]  # Brann, Felfire Conjurer, De-volition-ist, The Shadow of Doubt, Sha of Fear, Drifting Sacrifice, Drakkari Enchanter
  - id: aberration_discard_deity
    name: "Aberration Discard Deity"
    tribes: [Aberration]
    status36_6_1: "EMERGING"
    evidence: [card-text, video, community]
    coreCardIds: [BG36_099, BG36_106, BG36_097, BGFYM_005]  # Brain Rotter, Cutthroat K'Thir, Mindbender Ghur'sha, Harbinger Aph'lass
    addonCardIds: [BG36_311, BG36_312, BG36_112, BG36_115, BG36_103, BG36_114, BG36_320, BG36_301t, BG36_371, BG36_303]  # Abyssal Envoy, Mindbending Recruiter, Fetid Corroder, Nightmare Corroder, N'raqi Sapper, Parasitic Fleshling, Mysterious K'Thir, Sludge Corrosion, Energizing Chamber, Corrupted Coin
    trinketCardIds: [BG36_MagicItem_430, BG36_MagicItem_406, BG36_MagicItem_418, BG36_MagicItem_403]  # Sludge Portrait, Shath'Yar Shrine, Tome of the Ancients, Hammer of Twilight
  - id: aberration_spell_deity
    name: "Aberration Tavern-Spell Deity"
    tribes: [Aberration]
    status36_6_1: "EMERGING"
    evidence: [card-text, community]
    coreCardIds: [BG36_108, BG36_318, BG36_111, BG36_109]  # Vicious Mindslasher, Faceless Converter, Sha of Fear, The Shadow of Doubt
    addonCardIds: [BG36_101, BG36_100, BG36_104, BG36_300, BG25_354]  # Unwilling Slacker, Wandering Willbreaker, Dark Puppeteer, N'raqi Frostcaller, Titus Rivendare
    trinketCardIds: [BG36_MagicItem_404, BG36_MagicItem_852, BG36_MagicItem_402, BG36_MagicItem_600]  # Corrupted Baton, Willbreaker Sticker, Mindslasher Portrait, Converter Portrait
  - id: aberration_cthun_poet
    name: "C'Thun Poet Amalgam"
    tribes: [Aberration, Dragon]
    status36_6_1: "EMERGING"
    evidence: [community]   # single Reddit post
    requiresDeity: BGFYM_000
    coreCardIds: [BG29_813, BG36_640, BG35_883, BG36_MagicItem_417]  # Persistent Poet, Gatekeeper Amalgam, Balinda Stonehearth, Makeshift Master (trinket)
    addonCardIds: [BG36_300, BG36_104, BG21_015]  # N'raqi Frostcaller, Dark Puppeteer, Tarecgosa
# Aberration fodder (count toward the 3 deaths; generic to all comps):
fodderCardIds: [BG36_110, BG36_098, BGFYM_002t, BG36_116, BG36_101, BG36_113, BG36_308]  # Joyous, Zoatroid, Aberrant Tentacle, Underrot Spawn, Unwilling Slacker, Drifting Sacrifice, Faceless Operative
duosOnlyCardIds: [BGDUO_700, BGDUO_701]  # Voidpriest Cloner, C'Thrax Wrecker
```

---

## 9. How to refresh

1. **Card data:** `curl https://api.hearthstonejson.com/v1/` and look for a build dir newer than 251952. Re-filter `races` containing `"ABERRATION"`. Fill in the numbers from Firestone `cards_enUS.gz.json` `tags.TAG_SCRIPT_DATA_NUM_{1,2,3}`. Pool membership: `https://hsbg.cards/api/v1/cards?tribe=aberration&pool=true&limit=100` (no key needed, 120 req/min).
2. **Firestone:**
   - Watch `patches.json` for a `currentBattlegroundsMetaPatch` past 251952.
   - Re-pull `comp-stats/last-patch` and grep `archetype` for `aberration`.
   - Re-pull `card-stats/mmr-{100,10}/last-patch`, `trinket-stats/last-patch` and `hero-stats/mmr-100/last-patch`, and look up `BG36_HERO_000` / `BG36_HERO_002`.
   - To repeat the section 4.2 A sample: count `compStats[].heroStats[].finalBoards[].finalComp.board[].cardID` hits against the Aberration IDs.
   - `past-N` paths return 403.
3. **Community:** use Reddit RSS rather than JSON: `https://www.reddit.com/r/BobsTavern/search.rss?q=aberration&restrict_sr=1&sort=new&t=month` and `/comments/<id>/.rss`. Space requests at least 40s apart or you'll get 429. Blizzard forums: `https://us.forums.blizzard.com/en/hearthstone/search.json?q=aberration%20order%3Alatest` and `/t/<id>.json`. YouTube: parse `ytInitialData` from `https://www.youtube.com/results?search_query=battlegrounds+aberrations`.
4. **Blizzard:** check https://hearthstone.blizzard.com/en-us/news for 36.6.2 or Aberration balance posts, and the forum hotfix thread pattern `/t/<ver>-hotfix-patch/`.

---

## Appendix A. Local log sightings (factual, read-only)

Logs read without modification: `/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_31_46/Power.log` (no Aberration entities) and `/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_33_28/Power.log` (1 BG game, `GT_BATTLEGROUNDS`, log last written 20:41 local, game likely still in progress).

Method:
- The bartender's PlayerID is the `GameAccountId=[hi=0 lo=0]` player (PlayerID 10 in this game).
- A PowerTaskList entity tagged `zone=PLAY … player=<bartender>` is counted as a "bartender PLAY" sighting. **This includes both Tavern shop slots and opponents' combat boards**, which the bartender PlayerID also controls. The two weren't separated.
- Counts are distinct entity IDs.

| cardId | Name | Bartender PLAY | Player PLAY | Player HAND | Graveyard (player / bartender) |
|---|---|---|---|---|---|
| BG36_110 | Joyous | 4 | 3 | 1 | 2 / 2 |
| BG36_098 | Zoatroid | 1 | - | - | - |
| BG36_116 | Underrot Spawn | 1 | 3 | 1 | 2 / - |
| BG36_101 / _G | Unwilling Slacker (golden seen) | - | 3 (golden) | 1 (golden) | 2 / - |
| BGFYM_002t | Aberrant Tentacle | 2 | 2 | - | 2 / 2 |
| BGFYM_011 | **Y'Shaarj** (this game's Deity) | 1 | 1 | - | 1 / 1 |
| BG36_112, BG36_311 | Fetid Corroder, Abyssal Envoy | SETASIDE only (probably Discover or hero-power offers) | | | |
| BG_OldGod | Secret Deity [DNT] | SECRET zone x4 (opponents) | SECRET x1 | | |
| BG36_HERO_002 / p | Kith'ix / Dark Ritual | the player's hero in this game | | | |

In this game, Y'Shaarj awakened for the player at least once and died (it reached PLAY, then GRAVEYARD). Opponents also reached their Deity. Sightings are low-tier (T1-T3) only, which fits an early-to-mid game.

## Sources (all retrieved 2026-09-22)

Official: https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon ; https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846 (posted 2026-09-18 by Tyrskorn, rollout 2026-09-22) ; https://us.forums.blizzard.com/en/hearthstone/t/166041 (Blizzard rep reply on mobile discard).
Data: https://api.hearthstonejson.com/v1/latest/enUS/cards.json ; https://static.zerotoheroes.com/data/cards/cards_enUS.gz.json ; https://static.zerotoheroes.com/api/bgs/card-stats/mmr-100/last-patch/overview-from-hourly.gz.json ; …/mmr-10/… ; https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json ; https://static.zerotoheroes.com/api/bgs/trinket-stats/last-patch/overview-from-hourly.gz.json ; https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/last-patch/overview-from-hourly.gz.json ; https://static.zerotoheroes.com/hearthstone/data/patches.json ; https://static.zerotoheroes.com/api/bgs/anomalies-list.gz.json ; https://hsbg.cards/api/v1/cards?tribe=aberration&pool=true ; https://hsbg.cards/api/v1/patches ; https://hsbg.cards/patch-notes/36.6.1 (secondary) ; https://api.github.com/repos/HearthSim/hsdata/commits.
Community (opinion): r/BobsTavern threads 1wnrmb4, 1wnrfnr, 1wnponm, 1wnp0hq, 1wnofuh, 1wnnyjj, 1wnnpvh, 1wnnh6n, 1wnnh6f, 1wnn7dr, 1wnms97, 1wnm1lg, 1wnlkco, 1wnksqo, 1wnjc49, 1wnjd4o, 1wnj2mf, 1wnhmjl, 1wnf0el (all `https://www.reddit.com/r/BobsTavern/comments/<id>/`); Blizzard forum threads 166021, 166026, 166027, 165609; YouTube videos listed in section 6.
