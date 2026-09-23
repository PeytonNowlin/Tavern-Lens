# Hearthstone Battlegrounds meta compositions, September 2026

Researched 2026-09-22 (all URLs below retrieved 2026-09-22). Target client: patch 36.6.0, build 251952. Primary sources: Firestone's public stats JSON (zerotoheroes), Firestone's curated comp strategies, Blizzard's official patch notes and hotfix post, and HearthstoneJSON build 251952 for card IDs. Community sites are used only as secondary colour and are marked as such. Local evidence (raw JSON, analysis scripts) is in `scratchpad/meta/`.

---

## 0. TL;DR (read this first)

- **The data describes the meta that just ended.** Firestone's `last-patch` window starts at its `currentBattlegroundsMetaPatch` = **251332 (36.4.2, 2026-09-03)** and runs to 2026-09-22/23. Patch **36.6.1**, a server-side update on **2026-09-22** (the research date), added **Aberrations**, rotated **Naga** out, removed 35 minions and nerfed five meta cards. Almost none of the Firestone sample was played after 36.6.1: Aberration shows up in roughly 0.8% of hero-stat games.
- **The three best comps in the data are gone or gutted:** Naga End of Turn (avg 3.01) is unavailable, Dragon Evoker (3.15) lost Fire-forged Evoker and Warpwing, and Elemental Boost (3.16) lost Moat Custodian, Glowing Cinder and Unleashed Mana Surge.
- **Pre-36.6.1 comps that survive** (best avg placement first): Murloc Handbuff 3.43 (intact), Beast Beetle 3.47 (Scorpid nerfed), Demon Boost Shop 3.48 (Distractor nerfed), Beast Leviathan 3.49 (Scorpid nerfed), Undead Butcher 3.50 (Butcher nerfed), Demon Self Damage 3.56, Pirate Discover 3.60 (the most popular comp at 12.1%; Escapee nerfed), Beast Lobster 3.82 (intact).
- **There is no data-backed Aberration comp yet.** Firestone has no Aberration archetype. Re-run the refresh commands in section 8 after about a week of 36.6.1 games.

---

## 1. Snapshot metadata

| Item | Value | Source |
|---|---|---|
| Research / retrieval date | 2026-09-22 | - |
| Client build | 251952 = "36.6" (2026-09-15) | https://static.zerotoheroes.com/hearthstone/data/patches.json |
| Firestone BG stats window | `currentBattlegroundsMetaPatch: 251332` (36.4.2, 2026-09-03) to now, so the window covers 36.4.2 and 36.6.0 plus the first hours of 36.6.1 | same |
| Comp stats file | `comp-stats/last-patch`, `lastUpdateDate` 2026-09-23T00:10:30Z, **728,692** comp-tagged games, 21 archetypes (3 with n<10 ignored) | https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json |
| Hero stats file | `hero-stats/mmr-100/last-patch`, 1,485,466 games, 115 heroes, updated 2026-09-22T15:10Z; `mmr-10` file: 150,231 games | https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/last-patch/overview-from-hourly.gz.json |
| Trinket stats file | `trinket-stats/last-patch`, 2,821,274 data points, 250 trinkets, updated 2026-09-22T12:10Z | https://static.zerotoheroes.com/api/bgs/trinket-stats/last-patch/overview-from-hourly.gz.json |
| Curated strategies | 18 comps, all written by "slyders", dated 2026-08-10 to 2026-08-13, `patchNumber` 248022 (36.2) | https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json |
| MMR brackets | Firestone percentile buckets: 100 = all, 50/25/10/1 = top 50/25/10/1%. From the hero-stats file, top 10% ≈ MMR 7,025+ and top 1% ≈ 9,007+ | hero-stats `mmrPercentiles` |
| Card IDs | HearthstoneJSON build 251952 (latest listed build on the research date) | https://api.hearthstonejson.com/v1/251952/enUS/cards.json |
| Not usable | ~~`past-7` and `past-3` return 403~~ **Correction:** those slugs don't exist. The real ones are `past-seven` and `past-three`, and S3 returns 403 for any missing key. See [hero-pick-stats.md](hero-pick-stats.md). HSReplay `/battlegrounds/comps/` returns 403 (Cloudflare challenge) to curl and WebFetch. hsbattlegrounds.help/meta-comps returns 402. | curl, 2026-09-22 |

**How to read the numbers**
- `averagePlacement` is only over games whose **final board** Firestone classified as that archetype. Players who die before their board takes shape are under-represented, so every comp averages better than 4.5. Compare comps with each other, not with 4.5.
- `placementDistribution` totals do not match `dataPoints`. For example, pirate_discover has n=88,198 but its distribution sums to 267,778, and the mean of the distribution (3.66) differs from `averagePlacement` (3.60). This probably comes from summing hourly buckets. Win% and top-4% below are therefore approximate, and the doc uses `averagePlacement` as the headline number.
- The per-comp `heroStats[].finalBoards` is a **sample** (about 380 boards per hero-comp cap; 544-1,039 boards per comp). The "core card" percentages below come from that sample.

---

## 2. Current Battlegrounds context (36.6 / 36.6.1)

**Timeline** (Blizzard, https://hearthstone.blizzard.com/en-us/news/24294373/366-patch-notes): 36.6 went live 2026-09-15 (build 251952). Its Battlegrounds content, **36.6.1**, went live 2026-09-22.

**Minion types in the pool**
- In the pre-36.6.1 data, all 10 tribes appear in about the same share of games (each tribe's `tribeStats` dataPoints ≈ 716k-739k of 1.485M games, which fits 5 random tribes per lobby): Beast, Demon, Dragon, Elemental, Mech, Murloc, Naga, Pirate, Quilboar, Undead. Aberration (race id 126) appears in only 11,784 games. (Source: hero-stats file above.)
- **From 36.6.1: Aberrations join, and "Aberrations will appear in every lobby during the first two weeks following their debut"** (2026-09-22 to about 2026-10-05). **"Naga will be rotated out of the minion pool. Naga-specific heroes and cards will be unavailable while Naga are out of the pool."** (https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon). hsbg.cards (secondary) says dual-type Naga stay (https://hsbg.cards/patch-notes/36.6.1).
- So the live pool is Aberration plus 9 other tribes, with Naga removed.

**Season mechanic: Deity and Aberrations** (Blizzard BlizzCon post above)
- "Each time a friendly Aberration dies, it advances your Deity's progress." After 3 sacrifices the Deity joins that combat. One Deity is chosen at random per game:
  - **C'Thun** `BGFYM_000` (Tier 3 Aberration Deity): "After this awakens, give this minion's stats split amongst your other minions."
  - **Y'Shaarj** `BGFYM_011`: "Deathrattle: Summon your first 2 Aberrations that died this combat with their maximum stats."
- Aberrations are built around **discard** synergies, plus new Tavern spells: Sludge Corrosion `BG36_301t`, Corrupted Coin `BG36_303`, Energizing Chamber `BG36_371`.
- **Dark Paradox** `BG36_360` is a random-tier minion with a different Dark Gift each game (variants `BG36_360t3`-`t9`, golden `_Gt*`). The Tier 5/6 Divine Shield and Golem variants no longer appear in Y'Shaarj lobbies (hotfix post below).
- New heroes: **Drest'agath** `BG36_HERO_000` (Incubate: discard a card to get a random Aberration) and **Kith'ix** `BG36_HERO_002` (Dark Ritual: get 2 random minions; when you play one, discard the other).
- Older minions converted to Aberration: Oozeling Gladiator `BG27_002`, Faceless Manipulator `BG_EX1_564`, Faceless Taverngoer, Orgozoa, the Tender `BG23_015`. Blizzard's removed-minion list also contains "Oozeling Gladiator".

**Pool changes that matter for comps** (Blizzard BlizzCon post; lists quoted verbatim)
- **Removed:** Ancestral Automaton, Auto Assembler, Breakout Mastermind, Captain Cookie, Clunker Junker, Cousin Errgl, Dancing Barnstormer, Deepwater Chieftain, Deflect-o-Bot, Dual-Wield Corsair, Dustbone Devastator, **Fire-forged Evoker**, **Glowing Cinder**, Ignition Specialist, Kangor's Apprentice, Mama Mrrglton, Metallic Hunter, Meteorite Crasher, **Moat Custodian**, Molten Rock, Motley Phalanx, Nomi Kitchen Nightmare, Oozeling Gladiator, Papa Mrrglton, Primitive Painter, Private Investigator, River Skipper, Sand Swirler, **Scrap Scraper**, Sly Raptor, Thousandth Paper Drake, **Unleashed Mana Surge**, Vigilant Bristlemane, Void Pup Trainer, **Warpwing**.
- **Returning:** Auto Accelerator, Blue/Green/Red Volumizer, Bronze Warden (T3 to T2), Bubble Gunner, Conveyor Construct, Dune Dweller (3/2 to 3/3), Elite Navigator, Firelands Fugitive, Geomagus Roogug, Ghastcoiler (T6 to T5), Gormling Gourmet, Hackerfin, Hot-Air Surveyor, Ichoron the Protector, Iron Groundskeeper (reworked), Leyline Surfacer, Living Azerite, Mangled Bandit (reworked), Nadina the Red, Relentless Deflector, Shoalfin Mystic, Ultraviolet Ascendant, Young Murk-Eye.
- **New non-Aberration minions:** Greedy Conniver `BG36_369`, Sacrificial Wrathguard `BG36_362`, Holy Vanguard `BG36_372`, Sewer Escapee `BG36_700`, Hopebringer `BG36_364`, Lichling Hoarder `BG36_848`, Resourceful Robot `BG36_366`, Auto Reveille `BG36_367`, Heroic Broodmother `BG36_849`, Victorious Geomant `BG36_370`. Several of these (Volumizers, Resourceful Robot, Auto Reveille) point at a new Volumizer Mech package.
- **Trinkets:** about 30 new trinkets. Removed include Assembler Portrait, Automaton Portrait, Errgl Sticker, Kaleidoscope, Amplifying Essence and Avalanche Sticker.

**36.6.1 balance hotfix** (official Blizzard forum post, https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846; also https://www.hearthpwn.com/news/12706-36-6-1-hotfix-patch-constructed-battlegrounds-bug)
- Nerfs to meta cores: **Unbound Tempest** (after you play 3 to **4** Elementals), **Devilish Distractor** (+2/+2 to **+1/+2**), **Ravaging Scorpid** (Beetles +5/+5 to **+4/+4**), **Drustfallen Butcher** (Avenge (3) to **(4)**), **Enterprising Escapee** (5 Gold to **6** Gold).
- Aberration buffs: Harbinger Aph'lass (+1/+1 to +2/+1), The Shadow of Doubt (+3/+4 to +5/+5), Mindbender Ghur'sha (+3/+3 to +4/+4), Faceless Converter (+1/+1 to +2/+2).
- Many trinket cost changes (not itemised here).

**Caution on card data:** in HearthstoneJSON 251952, removed cards such as Fire-forged Evoker still have `isBattlegroundsPoolMinion: true`, and Naga cards are still flagged. Pool membership after 36.6.1 is decided server-side, so **do not use that flag to detect the live pool.** Use the in-game available-races info, or the lists above.

---

## 3. Tier-ranked comp table (Firestone, last-patch window)

Ranked by overall `averagePlacement` (lower is better). "Data tier" is **derived here** from avg placement: A < 3.20, B < 3.50, C < 3.80, D ≥ 3.80. "Curated tier" is Firestone's `powerLevel` (written 2026-08, patch 36.2). Popularity is the share of the 728,692 comp-tagged games.

| # | Comp (Firestone id) | Tribe | Data tier | Curated tier / difficulty | Avg place (all) | Avg place top 25% / top 10% / top 1% | Popularity (n) | Status after 36.6.1 |
|---|---|---|---|---|---|---|---|---|
| 1 | Naga End Of Turn (`naga_end_of_turn`) | Naga | A | A / Easy | 3.01 | 3.37 / 3.40 / 3.18 (n=3,658 at top 10%) | 8.7% (63,759) | **UNAVAILABLE** |
| 2 | Dragon Evoker (`dragon_evoker`) | Dragon | A | B / Easy | 3.15 | 3.43 / 3.44 / 3.08 (n=2,365 at top 10%) | 6.4% (46,751) | **GUTTED** |
| 3 | Elemental Boost (`elemental_cycle`) | Elemental | A | S / Medium | 3.16 | 3.46 / 3.35 / 3.08 (n=3,121 at top 10%) | 7.4% (54,116) | **GUTTED** |
| 4 | Mech Automaton (`mech_automaton`) | Mech | B | C / Easy | 3.31 | 3.72 / 3.73 / 2.83 (n=161 at top 10%) | 0.6% (4,267) | **GUTTED** |
| 5 | Murloc Handbuff (`murloc_handbuff`) | Murloc | B | B / Hard | 3.43 | 3.65 / 3.59 / 3.04 (n=2,745 at top 10%) | 6.1% (44,782) | **INTACT** |
| 6 | Beast Beetle (`beast_beetle`) | Beast | B | A / Easy | 3.47 | 3.47 / 3.44 / 2.94 (n=2,124 at top 10%) | 5.1% (37,421) | **NERFED** |
| 7 | Demon Boost Shop (`demon_boost_shop`) | Demon | B | A / Medium | 3.48 | 3.67 / 3.65 / 3.14 (n=4,510 at top 10%) | 8.6% (62,475) | **NERFED** |
| 8 | Beast Leviathan (`beast_leviathan`) | Beast | B | A / Easy | 3.49 | 3.66 / 3.64 / 3.24 (n=1,377 at top 10%) | 2.4% (17,427) | **NERFED** |
| 9 | Undead Butcher (`undead_butcher`) | Undead | C | S / Hard | 3.50 | 3.71 / 3.67 / 3.10 (n=4,217 at top 10%) | 8.8% (64,026) | **NERFED** |
| 10 | Neutral Tea Set (`neutral_tea_set`) | Neutral (tribe-agnostic; Naga-heavy in pre-36.6.1 data) | C | A / Hard | 3.52 | 3.78 / 3.80 / 3.28 (n=1,508 at top 10%) | 2.7% (19,342) | **WEAKENED** |
| 11 | Demon Self Damage (`demon_self_damage`) | Demon | C | A / Medium | 3.56 | 3.96 / 3.85 / 3.24 (n=1,925 at top 10%) | 6.1% (44,482) | **NERFED** |
| 12 | Pirate Discover (`pirate_discover`) | Pirate | C | S / Hard | 3.60 | 3.81 / 3.80 / 3.28 (n=4,298 at top 10%) | 12.1% (88,198) | **NERFED** |
| 13 | Murloc Mrrglton (`murloc_mrrglton`) | Murloc | C | B / Medium | 3.62 | 3.97 / 4.18 / 3.62 (n=424 at top 10%) | 1.0% (6,935) | **GUTTED** |
| 14 | Mech Magnet (`mech_magnet`) | Mech | C | A / Medium | 3.78 | 4.20 / 4.21 / 3.65 (n=2,259 at top 10%) | 6.9% (50,027) | **WEAKENED** |
| 15 | Beast Lobster (`beast_lobster`) | Beast | D | B / Easy | 3.82 | 3.91 / 3.88 / 3.27 (n=3,075 at top 10%) | 6.8% (49,446) | **INTACT** |
| 16 | Quilboar Choose One (`quilboar_choose_one`) | Quilboar | D | B / Medium | 3.86 | 4.34 / 4.42 / 4.22 (n=1,063 at top 10%) | 4.2% (30,259) | **MOSTLY INTACT** |
| 17 | Dragon Kalecgos (`dragon_kalecgos`) | Dragon | D | C / Easy | 3.86 | 4.11 / 4.14 / 4.08 (n=1,750 at top 10%) | 4.2% (30,734) | **WEAKENED** |
| 18 | Naga Groundbreaker (`naga_groundbreaker`) | Naga | D | A / Medium | 3.96 | 4.39 / 4.22 / 3.59 (n=727 at top 10%) | 2.0% (14,235) | **UNAVAILABLE** |

**Viable-now ranking (pre-36.6.1 data, only comps that are INTACT or NERFED):** Murloc Handbuff 3.43 > Beast Beetle 3.47 > Demon Boost Shop 3.48 > Beast Leviathan 3.49 > Undead Butcher 3.50 > Demon Self Damage 3.56 > Pirate Discover 3.60 > Beast Lobster 3.82 > Quilboar Choose One 3.86. The nerfed comps will perform worse than these numbers show. By how much is unknown until new data arrives.

**At high MMR (top 10%)**, the order shifts. Among surviving comps, Beast Beetle (3.44) and Murloc Handbuff (3.59) lead, followed by Beast Leviathan (3.64), Demon Boost Shop (3.65), Undead Butcher (3.67), Pirate Discover (3.80), Demon Self Damage (3.85) and Beast Lobster (3.88). Quilboar Choose One (4.42) and Mech Magnet (4.21) do badly at high MMR.

**Counters:** none of the sources publish comp-vs-comp matchup data (Firestone's files hold no matchups, and HSReplay was unreachable). The doc gives no counter claims.

---

## 4. Per-comp notes

Each comp lists: curated cards (Firestone strategies file: CORE/ADDON/CYCLE), data-backed card frequency on sampled final boards (golden normalised to base), the heroes with the best average placement on that comp (from the comp file's `heroStats`, n≥200), curated "when to commit" signals and tips where present, and comps sharing a ≥60% card (pivot paths). Tiers are tavern tiers from HearthstoneJSON 251952.

### 4.1 Naga End Of Turn (`naga_end_of_turn`) - UNAVAILABLE

- **36.6.1 impact:** Naga rotated out; core Fauna Whisperer (93% of boards) is pure Naga.
- **Curated cards (Firestone strategies):** CORE: Fauna Whisperer (`BG32_837`, T6) - *ROTATED OUT (Naga) in 36.6.1*; ADDON: Felfire Conjurer (`BG32_821`, T5)
- **Core on final boards (>=60% of 1013 sampled boards):** Fauna Whisperer (`BG32_837`, T6, 93%) *[ROTATED OUT (Naga) in 36.6.1]*; Balinda Stonehearth (`BG35_883`, T6, 92%); Drakkari Enchanter (`BG26_ICC_901`, T5, 83%); Gatekeeper Amalgam (`BG36_640`, T6, 83%)
- **Common addons (20-59%):** Felfire Conjurer (`BG32_821`, T5, 47%); Torrential Ruiner (`BG36_622`, T6, 23%) *[ROTATED OUT (Naga) in 36.6.1]*; Tranquil Meditative (`BG32_835`, T5, 21%) *[ROTATED OUT (Naga) in 36.6.1]*; Seafloor Recruiter (`BG34_925`, T4, 20%) *[ROTATED OUT (Naga) in 36.6.1]*
- **Best heroes for this comp (hero sample n>=200, avg placement):** Rakanishu (`TB_BaconShop_HERO_75`) 2.67 (n=320); Drek'Thar (`BG22_HERO_002`) 2.71 (n=286); Sylvanas Windrunner (`BG23_HERO_306`) 2.73 (n=336)
- **When to commit (curated, slyders, 2026-08-13, patch 248022):** Fauna Whisperer + Tranquil meditative + Drakkari/Balinda
- **Strategy tip (curated):** Boost your Tavern Spells with Tranquil Meditative, then trigger Fauna Whisperer as much as you can with Drakkari Enchanter & Balinda Stonehearth
- **Pivot / shared core with:** `demon_boost_shop` via Balinda Stonehearth; `neutral_tea_set` via Balinda Stonehearth, Fauna Whisperer, Gatekeeper Amalgam; `naga_groundbreaker` via Balinda Stonehearth

### 4.2 Dragon Evoker (`dragon_evoker`) - GUTTED

- **36.6.1 impact:** Fire-forged Evoker (core, 76%) and Warpwing (77%) removed.
- **Curated cards (Firestone strategies):** CORE: Fire-forged Evoker (`BG32_822`, T6) - *REMOVED in 36.6.1*; ADDON: Warpwing (`BG24_004`, T6) - *REMOVED in 36.6.1*
- **Core on final boards (>=60% of 938 sampled boards):** Persistent Poet (`BG29_813`, T4, 86%); Warpwing (`BG24_004`, T6, 77%) *[REMOVED in 36.6.1]*; Fire-forged Evoker (`BG32_822`, T6, 76%) *[REMOVED in 36.6.1]*
- **Common addons (20-59%):** Crimson Vindicator (`BG36_241`, T6, 57%); Runic Arcanist (`BG36_245`, T4, 34%); Brann Bronzebeard (`BG_LOE_077`, T5, 28%); Felfire Conjurer (`BG32_821`, T5, 22%); Leeroy the Reckless (`BG23_318`, T5, 20%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Rakanishu (`TB_BaconShop_HERO_75`) 2.82 (n=306); Mister Clocksworth (`BG34_HERO_002`) 2.84 (n=258); Sylvanas Windrunner (`BG23_HERO_306`) 2.88 (n=298)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `dragon_kalecgos` via Persistent Poet, Warpwing

### 4.3 Elemental Boost (`elemental_cycle`) - GUTTED

- **36.6.1 impact:** Moat Custodian (curated core), Glowing Cinder (curated addon) and Unleashed Mana Surge (63%) removed; Unbound Tempest (85%) nerfed 3->4 Elementals.
- **Curated cards (Firestone strategies):** CYCLE: Gentle Djinni (`BGS_121`, T6); CORE: Moat Custodian (`BG36_351`, T6) - *REMOVED in 36.6.1*; ADDON: Glowing Cinder (`BG32_842`, T4) - *REMOVED in 36.6.1*
- **Core on final boards (>=60% of 982 sampled boards):** Unbound Tempest (`BG36_352`, T6, 85%) *[NERFED in 36.6.1]*; Brann Bronzebeard (`BG_LOE_077`, T5, 73%); Unleashed Mana Surge (`BG32_846`, T6, 63%) *[REMOVED in 36.6.1]*
- **Common addons (20-59%):** Tavern Tempest (`BGS_123`, T4, 44%); Moat Custodian (`BG36_351`, T6, 40%) *[REMOVED in 36.6.1]*; Wildfire Elemental (`BGS_126`, T3, 39%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Shudderwock (`TB_BaconShop_HERO_23`) 2.81 (n=340); Morchie (`BG34_HERO_004`) 2.85 (n=348); Sindragosa (`TB_BaconShop_HERO_27`) 2.85 (n=271)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `dragon_kalecgos` via Brann Bronzebeard; `murloc_mrrglton` via Brann Bronzebeard

### 4.4 Mech Automaton (`mech_automaton`) - GUTTED

- **36.6.1 impact:** Ancestral Automaton (curated core) and Kangor's Apprentice (64%) removed.
- **Curated cards (Firestone strategies):** CORE: Ancestral Automaton (`BG_TTN_401`, T2) - *REMOVED in 36.6.1*; ADDON: Falling Sky Golem (`BG35_342`, T6); CYCLE: Annoy-o-Module (`BG_BOT_911`, T3)
- **Core on final boards (>=60% of 121 sampled boards):** Falling Sky Golem (`BG35_342`, T6, 91%); Kangor's Apprentice (`BGS_012`, T5, 64%) *[REMOVED in 36.6.1]*; Titus Rivendare (`BG25_354`, T5, 60%)
- **Common addons (20-59%):** Ancestral Automaton (`BG_TTN_401`, T2, 31%) *[REMOVED in 36.6.1]*; Utility Drone (`BG26_152`, T6, 26%); Leeroy the Reckless (`BG23_318`, T5, 25%); Scrap Scraper (`BG26_148`, T5, 24%) *[REMOVED in 36.6.1]*; Polarizing Beatboxer (`BG26_149`, T7, 22%); Drone Duplicator (`BG36_506`, T4, 22%); Spark Snapper (`BG36_851`, T5, 20%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** no hero with n>=200
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `beast_lobster` via Titus Rivendare

### 4.5 Murloc Handbuff (`murloc_handbuff`) - INTACT

- **36.6.1 impact:** Only Captain Cookie (10%) removed; Sewer Escapee (new Murloc T4) added.
- **Curated cards (Firestone strategies):** CORE: Choral Mrrrglr (`BG26_354`, T6); ADDON: Magicfin Mycologist (`BG33_891`, T6); CYCLE: Tad (`BG22_202`, T2)
- **Core on final boards (>=60% of 877 sampled boards):** Choral Mrrrglr (`BG26_354`, T6, 70%); Diremuck Forager (`BG27_556`, T3, 66%); Bile Spitter (`BG33_318`, T5, 65%)
- **Common addons (20-59%):** Expert Aviator (`BG34_140`, T2, 43%); Costume Enthusiast (`BG34_142`, T5, 42%); Shamanic Tidecaller (`BG36_704`, T5, 36%); Brann Bronzebeard (`BG_LOE_077`, T5, 30%); Twilight Tidehunter (`BG36_703`, T4, 27%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Mister Clocksworth (`BG34_HERO_002`) 3.02 (n=314); George the Fallen (`TB_BaconShop_HERO_15`) 3.03 (n=266); Yogg-Saron, Hope's End (`TB_BaconShop_HERO_35`) 3.21 (n=286)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** no shared >=60% card with another comp

### 4.6 Beast Beetle (`beast_beetle`) - NERFED

- **36.6.1 impact:** Ravaging Scorpid Beetle buff +5/+5 -> +4/+4.
- **Curated cards (Firestone strategies):** CORE: Ravaging Scorpid (`BG36_209`, T6) - *NERFED in 36.6.1*; ADDON: Forest Rover (`BG31_801`, T2); CYCLE: Sprightly Scarab (`BG27_084`, T3)
- **Core on final boards (>=60% of 873 sampled boards):** Ravaging Scorpid (`BG36_209`, T6, 98%) *[NERFED in 36.6.1]*; Banana Slamma (`BG26_802`, T4, 86%); Turquoise Skitterer (`BG31_809`, T5, 82%)
- **Common addons (20-59%):** Buzzing Vermin (`BG31_803`, T1, 50%); Forest Rover (`BG31_801`, T2, 40%); Headhunter Gryphon (`BG36_204`, T4, 33%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Galakrond (`TB_BaconShop_HERO_02`) 2.88 (n=321); N'Zoth (`TB_BaconShop_HERO_93`) 3.08 (n=339); Tras'tath, Soul Parasite (`BG36_HERO_101`) 3.12 (n=318)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `beast_leviathan` via Banana Slamma, Ravaging Scorpid, Turquoise Skitterer

### 4.7 Demon Boost Shop (`demon_boost_shop`) - NERFED

- **36.6.1 impact:** Devilish Distractor (97%) +2/+2 -> +1/+2. Curated cycle card Oozeling Gladiator is listed as removed and is now typed Aberration in build 251952.
- **Curated cards (Firestone strategies):** CORE: Devilish Distractor (`BG36_762`, T5) - *NERFED in 36.6.1*; ADDON: Imp-lusionist (`BG36_731`, T4); CYCLE: Oozeling Gladiator (`BG27_002`, T2)
- **Core on final boards (>=60% of 1030 sampled boards):** Devilish Distractor (`BG36_762`, T5, 97%) *[NERFED in 36.6.1]*; Felboar (`BG28_633`, T5, 73%); Balinda Stonehearth (`BG35_883`, T6, 71%); Imp-lusionist (`BG36_731`, T4, 64%)
- **Common addons (20-59%):** Brann Bronzebeard (`BG_LOE_077`, T5, 38%); Twisted Wrathguard (`BG35_155`, T6, 30%); Leeroy the Reckless (`BG23_318`, T5, 29%); Ashen Corruptor (`BG32_873`, T4, 25%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Mister Clocksworth (`BG34_HERO_002`) 3.16 (n=295); Thorim, Stormlord (`BG27_HERO_801`) 3.19 (n=320); Trade Prince Gallywix (`TB_BaconShop_HERO_10`) 3.2 (n=221)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Devilish Distractor + Felboar
- **Strategy tip (curated):** The main card is Devilish Distractor, Cycle spell on it (blood gem, taunt spell etc.) with Balinda Stonehearth & Brann Bronzebeard then eat the shop with Felboar
- **Pivot / shared core with:** `demon_self_damage` via Devilish Distractor; `neutral_tea_set` via Balinda Stonehearth; `naga_end_of_turn` via Balinda Stonehearth; `naga_groundbreaker` via Balinda Stonehearth

### 4.8 Beast Leviathan (`beast_leviathan`) - NERFED

- **36.6.1 impact:** Ravaging Scorpid (77%) nerfed; Sly Raptor removed (7%).
- **Curated cards (Firestone strategies):** CORE: Lurking Leviathan (`BG35_602`, T5); ADDON: Turquoise Skitterer (`BG31_809`, T5); CYCLE: Snarky Shark (`BG36_206`, T4)
- **Core on final boards (>=60% of 682 sampled boards):** Banana Slamma (`BG26_802`, T4, 88%); Ravaging Scorpid (`BG36_209`, T6, 77%) *[NERFED in 36.6.1]*; Sewer Lord (`BG35_604`, T5, 70%); Lurking Leviathan (`BG35_602`, T5, 61%); Turquoise Skitterer (`BG31_809`, T5, 60%)
- **Common addons (20-59%):** Headhunter Gryphon (`BG36_204`, T4, 32%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** N'Zoth (`TB_BaconShop_HERO_93`) 3.02 (n=256); Galakrond (`TB_BaconShop_HERO_02`) 3.04 (n=209); Teron Gorefiend (`BG25_HERO_103`) 3.16 (n=252)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `beast_beetle` via Banana Slamma, Ravaging Scorpid, Turquoise Skitterer

### 4.9 Undead Butcher (`undead_butcher`) - NERFED

- **36.6.1 impact:** Drustfallen Butcher Avenge (3) -> (4).
- **Curated cards (Firestone strategies):** CORE: Drustfallen Butcher (`BG32_324`, T5) - *NERFED in 36.6.1*; ADDON: Friendly Geist (`BG32_880`, T4); CYCLE: Prosthetic Hand (`BG_DEEP_015`, T3)
- **Core on final boards (>=60% of 1031 sampled boards):** Drustfallen Butcher (`BG32_324`, T5, 97%) *[NERFED in 36.6.1]*; Snazzy Phantom (`BG36_515`, T6, 95%); Handless Forsaken (`BG25_010`, T3, 78%); Mummifier (`BG28_309`, T3, 77%); Dead Bellringer (`BG36_511`, T4, 75%)
- **Common addons (20-59%):** Friendly Geist (`BG32_880`, T4, 33%); Barrier Banshee (`BG36_514`, T5, 24%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** The Lich King (`TB_BaconShop_HERO_22`) 3.07 (n=365); The Great Akazamzarak (`TB_BaconShop_HERO_21`) 3.16 (n=336); Teron Gorefiend (`BG25_HERO_103`) 3.17 (n=373)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Deathrattle/reborn minions + Drustfallen Butcher
- **Strategy tip (curated):** Boost your tavern spells with Friendly Geist & Titus Rivendare. Generate Butchering with Drustfallen Butcher and play them with Balinda Stonehearth. Snazzy Phantom is VERY important because it give you HP on Butcher or Deathly Striker
- **Pivot / shared core with:** no shared >=60% card with another comp

### 4.10 Neutral Tea Set (`neutral_tea_set`) - WEAKENED

- **36.6.1 impact:** Fauna Whisperer (65%) and Tranquil Meditative rotated out with Naga; Warpwing removed; Enterprising Escapee nerfed.
- **Curated cards (Firestone strategies):** CORE: Gatekeeper Amalgam (`BG36_640`, T6); ADDON: Enterprising Escapee (`BG36_523`, T5) - *NERFED in 36.6.1*
- **Core on final boards (>=60% of 789 sampled boards):** Gatekeeper Amalgam (`BG36_640`, T6, 97%); Balinda Stonehearth (`BG35_883`, T6, 89%); Fauna Whisperer (`BG32_837`, T6, 65%) *[ROTATED OUT (Naga) in 36.6.1]*
- **Common addons (20-59%):** Felfire Conjurer (`BG32_821`, T5, 47%); Brann Bronzebeard (`BG_LOE_077`, T5, 42%); Warpwing (`BG24_004`, T6, 24%) *[REMOVED in 36.6.1]*
- **Best heroes for this comp (hero sample n>=200, avg placement):** Queen Azshara (`BG22_HERO_007`) 3.19 (n=201); Thorim, Stormlord (`BG27_HERO_801`) 3.22 (n=210); A. F. Kay (`TB_BaconShop_HERO_16`) 3.26 (n=257)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Brann + Gatekeeper Amalgam + Balinda Stonehearth
- **Strategy tip (curated):** Boost Tavernspell with Chromadrake generation and Brann Bronzebeard, Then play spell on Gatekeeper Amalgam with Balinda Stonehearth
- **Pivot / shared core with:** `demon_boost_shop` via Balinda Stonehearth; `naga_end_of_turn` via Balinda Stonehearth, Fauna Whisperer, Gatekeeper Amalgam; `naga_groundbreaker` via Balinda Stonehearth

### 4.11 Demon Self Damage (`demon_self_damage`) - NERFED

- **36.6.1 impact:** Devilish Distractor (67%) nerfed; Wrath Weaver/Ashen Corruptor/Eredar Escapist untouched.
- **Curated cards (Firestone strategies):** CORE: Wrath Weaver (`BGS_004`, T1); ADDON: Malchezaar, Prince of Dance (`BG26_524`, T3)
- **Core on final boards (>=60% of 890 sampled boards):** Ashen Corruptor (`BG32_873`, T4, 88%); Eredar Escapist (`BG36_733`, T6, 87%); Wrath Weaver (`BGS_004`, T1, 81%); Devilish Distractor (`BG36_762`, T5, 67%) *[NERFED in 36.6.1]*
- **Common addons (20-59%):** Balinda Stonehearth (`BG35_883`, T6, 43%); Malchezaar, Prince of Dance (`BG26_524`, T3, 35%); Brann Bronzebeard (`BG_LOE_077`, T5, 29%); Imp-lusionist (`BG36_731`, T4, 23%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Lord Jaraxxus (`TB_BaconShop_HERO_37`) 3.06 (n=384); Mister Clocksworth (`BG34_HERO_002`) 3.11 (n=300); Vanndar Stormpike (`BG22_HERO_003`) 3.26 (n=284)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `demon_boost_shop` via Devilish Distractor

### 4.12 Pirate Discover (`pirate_discover`) - NERFED

- **36.6.1 impact:** Enterprising Escapee (95%) now needs 6 Gold instead of 5.
- **Curated cards (Firestone strategies):** CORE: Hooktusk, Master Marauder (`BG36_344`, T6); ADDON: Locked-up Mutineer (`BG36_521`, T3); CYCLE: Patient Scout (`BG24_715`, T2)
- **Core on final boards (>=60% of 1039 sampled boards):** Hooktusk, Master Marauder (`BG36_344`, T6, 99%); Enterprising Escapee (`BG36_523`, T5, 95%) *[NERFED in 36.6.1]*; Blade Collector (`BG26_817`, T4, 66%)
- **Common addons (20-59%):** Sky Admiral Rogers (`BG33_823`, T6, 39%); Leeroy the Reckless (`BG23_318`, T5, 29%); Proud Privateer (`BG33_825`, T5, 23%); Brann Bronzebeard (`BG_LOE_077`, T5, 21%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Sylvanas Windrunner (`BG23_HERO_306`) 3.23 (n=366); Lord Barov (`TB_BaconShop_HERO_72`) 3.28 (n=322); Buttons (`BG32_HERO_002`) 3.29 (n=373)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Enterprising Escapee + Hooktusk Master Marauder
- **Strategy tip (curated):** Play with the most Enterprising Escapee as you can, when you find Hooktusk Master Marauder, cycle every gold & discover card
- **Pivot / shared core with:** no shared >=60% card with another comp

### 4.13 Murloc Mrrglton (`murloc_mrrglton`) - GUTTED

- **36.6.1 impact:** Cousin Errgl (core, 88%), Papa and Mama Mrrglton removed.
- **Curated cards (Firestone strategies):** CORE: Cousin Errgl (`BG35_142`, T5) - *REMOVED in 36.6.1*; ADDON: Kelp Keeper (`BG36_701`, T4); CYCLE: Primalfin Lookout (`BGS_020`, T5)
- **Core on final boards (>=60% of 417 sampled boards):** Brann Bronzebeard (`BG_LOE_077`, T5, 88%); Cousin Errgl (`BG35_142`, T5, 88%) *[REMOVED in 36.6.1]*; Kelp Keeper (`BG36_701`, T4, 75%)
- **Common addons (20-59%):** Papa Mrrglton (`BG35_141`, T3, 58%) *[REMOVED in 36.6.1]*; Bile Spitter (`BG33_318`, T5, 48%); Drakkari Enchanter (`BG26_ICC_901`, T5, 42%); Mama Mrrglton (`BG35_140`, T3, 41%) *[REMOVED in 36.6.1]*; Diremuck Forager (`BG27_556`, T3, 21%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Tras'tath, Soul Parasite (`BG36_HERO_101`) 3.16 (n=235); Fungalmancer Flurgl (`TB_BaconShop_HERO_55`) 3.25 (n=239); Dinotamer Brann (`TB_BaconShop_HERO_43`) 3.65 (n=263)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `dragon_kalecgos` via Brann Bronzebeard; `elemental_cycle` via Brann Bronzebeard

### 4.14 Mech Magnet (`mech_magnet`) - WEAKENED

- **36.6.1 impact:** Scrap Scraper (62%; the curated tip's magnet generator), Clunker Junker (curated cycle) and Deflect-o-Bot removed. Drone Duplicator reworded ("doubled" -> "happens an extra time").
- **Curated cards (Firestone strategies):** CORE: Drone Duplicator (`BG36_506`, T4); ADDON: Glambot (`BG36_853`, T4); CYCLE: Clunker Junker (`BG29_503`, T4) - *REMOVED in 36.6.1*
- **Core on final boards (>=60% of 879 sampled boards):** Spark Snapper (`BG36_851`, T5, 74%); Utility Drone (`BG26_152`, T6, 64%); Drone Duplicator (`BG36_506`, T4, 63%); Scrap Scraper (`BG26_148`, T5, 62%) *[REMOVED in 36.6.1]*
- **Common addons (20-59%):** Polarizing Beatboxer (`BG26_149`, T7, 58%); Glambot (`BG36_853`, T4, 40%); Deflect-o-Bot (`BGS_071`, T3, 35%) *[REMOVED in 36.6.1]*; Drakkari Enchanter (`BG26_ICC_901`, T5, 26%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Vanndar Stormpike (`BG22_HERO_003`) 3.13 (n=309); Drek'Thar (`BG22_HERO_002`) 3.18 (n=296); Thorim, Stormlord (`BG27_HERO_801`) 3.36 (n=375)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Scrap Scraper + Spark Snapper
- **Strategy tip (curated):** Generate Magnet with Scrap Scraper & Titus Rivendare, then boost your magnet with Spark Snapper and duplicate a magnet (if possible Accord-o-Tron)
- **Pivot / shared core with:** no shared >=60% card with another comp

### 4.15 Beast Lobster (`beast_lobster`) - INTACT

- **36.6.1 impact:** No core card changed.
- **Curated cards (Firestone strategies):** CORE: Tasty Lobster (`BG36_202`, T3); CYCLE: Snarky Shark (`BG36_206`, T4)
- **Core on final boards (>=60% of 995 sampled boards):** Tasty Lobster (`BG36_202`, T3, 99%); Deathstrider (`BG36_208`, T6, 97%); Titus Rivendare (`BG25_354`, T5, 97%); Headhunter Gryphon (`BG36_204`, T4, 83%)
- **Common addons (20-59%):** Hoarding Hyena (`BG36_210`, T4, 52%); Lurking Lionfish (`BG36_201`, T2, 21%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Al'Akir (`TB_BaconShop_HERO_76`) 3.43 (n=300); Teron Gorefiend (`BG25_HERO_103`) 3.48 (n=351); A. F. Kay (`TB_BaconShop_HERO_16`) 3.57 (n=372)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Tasty Lobster + Titus Rivendare
- **Strategy tip (curated):** You have to trigger Tasty Lobster as much as you can, so reborn it, play with Titus Rivendare etc. At the end, play with Deathstrider and windfury rally like Sin'dorei Straight Shot
- **Pivot / shared core with:** `mech_automaton` via Titus Rivendare

### 4.16 Quilboar Choose One (`quilboar_choose_one`) - MOSTLY INTACT

- **36.6.1 impact:** Vigilant Bristlemane (36%) removed; Victorious Geomant (new T6) and Geomagus Roogug (returning) added.
- **Curated cards (Firestone strategies):** CORE: Turbo Hogrider (`BG31_323`, T6); ADDON: Gem Rat (`BG31_326`, T3); CYCLE: Crater Miner (`BG31_320`, T2)
- **Core on final boards (>=60% of 829 sampled boards):** Turbo Hogrider (`BG31_323`, T6, 90%); Bramble Tunneler (`BG36_331`, T4, 80%)
- **Common addons (20-59%):** Sanguine Refiner (`BG33_885`, T5, 59%); Gem Rat (`BG31_326`, T3, 44%); Vigilant Bristlemane (`BG36_510`, T5, 36%) *[REMOVED in 36.6.1]*; Felboar (`BG28_633`, T5, 26%); Thorned Trailblazer (`BG31_327`, T4, 24%); Sanguine Champion (`BG23_017`, T6, 23%); Balinda Stonehearth (`BG35_883`, T6, 23%); Razorfen Vineweaver (`BG33_883`, T5, 20%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** George the Fallen (`TB_BaconShop_HERO_15`) 3.5 (n=224); Galakrond (`TB_BaconShop_HERO_02`) 3.54 (n=293); Buttons (`BG32_HERO_002`) 3.55 (n=307)
- **When to commit (curated, slyders, 2026-08-10, patch 248022):** Turbo Hogrider & Choose One generation
- **Strategy tip (curated):** Generate some Economy and gem boost early with Bramble Tunneler, When you find Turbo Hogrider, Cycle all Choose One card. At the end, use Gem Confiscation on Jailbird Juggernaut and protect it
- **Pivot / shared core with:** no shared >=60% card with another comp

### 4.17 Dragon Kalecgos (`dragon_kalecgos`) - WEAKENED

- **36.6.1 impact:** Warpwing (75% of boards) and Fire-forged Evoker (24%) removed.
- **Curated cards (Firestone strategies):** CORE: Kalecgos, Arcane Aspect (`BGS_041`, T5); ADDON: Persistent Poet (`BG29_813`, T4)
- **Core on final boards (>=60% of 719 sampled boards):** Warpwing (`BG24_004`, T6, 75%) *[REMOVED in 36.6.1]*; Brann Bronzebeard (`BG_LOE_077`, T5, 73%); Kalecgos, Arcane Aspect (`BGS_041`, T5, 66%); Persistent Poet (`BG29_813`, T4, 65%); Bronze Timewalker (`BG36_242`, T4, 65%)
- **Common addons (20-59%):** Crimson Vindicator (`BG36_241`, T6, 48%); Draconic Warden (`BG34_633`, T5, 31%); Sky-hatch Runaway (`BG36_243`, T4, 30%); Fire-forged Evoker (`BG32_822`, T6, 24%) *[REMOVED in 36.6.1]*; Leeroy the Reckless (`BG23_318`, T5, 20%)
- **Best heroes for this comp (hero sample n>=200, avg placement):** Mister Clocksworth (`BG34_HERO_002`) 3.45 (n=241); Tras'tath, Soul Parasite (`BG36_HERO_101`) 3.51 (n=348); Sylvanas Windrunner (`BG23_HERO_306`) 3.52 (n=247)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `dragon_evoker` via Persistent Poet, Warpwing; `elemental_cycle` via Brann Bronzebeard; `murloc_mrrglton` via Brann Bronzebeard

### 4.18 Naga Groundbreaker (`naga_groundbreaker`) - UNAVAILABLE

- **36.6.1 impact:** Naga rotated out; Groundbreaker/Seafloor Recruiter are pure Naga.
- **Curated cards (Firestone strategies):** CORE: Groundbreaker (`BG31_035`, T6) - *ROTATED OUT (Naga) in 36.6.1*; ADDON: Darkcrest Strategist (`BG31_920`, T5) - *ROTATED OUT (Naga) in 36.6.1*
- **Core on final boards (>=60% of 544 sampled boards):** Groundbreaker (`BG31_035`, T6, 97%) *[ROTATED OUT (Naga) in 36.6.1]*; Seafloor Recruiter (`BG34_925`, T4, 89%) *[ROTATED OUT (Naga) in 36.6.1]*; Balinda Stonehearth (`BG35_883`, T6, 75%)
- **Common addons (20-59%):** Torrential Ruiner (`BG36_622`, T6, 39%) *[ROTATED OUT (Naga) in 36.6.1]*; Darkcrest Strategist (`BG31_920`, T5, 25%) *[ROTATED OUT (Naga) in 36.6.1]*; Cagey Conjurer (`BG36_508`, T4, 24%) *[ROTATED OUT (Naga) in 36.6.1]*; Fauna Whisperer (`BG32_837`, T6, 23%) *[ROTATED OUT (Naga) in 36.6.1]*; Glowscale (`BG23_008`, T5, 22%) *[ROTATED OUT (Naga) in 36.6.1]*; Leeroy the Reckless (`BG23_318`, T5, 21%); Abyssal Bruiser (`BG35_921`, T4, 21%) *[ROTATED OUT (Naga) in 36.6.1]*
- **Best heroes for this comp (hero sample n>=200, avg placement):** Buttons (`BG32_HERO_002`) 3.47 (n=209); Lady Vashj (`BG23_HERO_304`) 3.62 (n=283); Ambassador Faelin (`BG22_HERO_201`) 3.82 (n=204)
- **Strategy tip:** none in the curated file for this comp.
- **Pivot / shared core with:** `demon_boost_shop` via Balinda Stonehearth; `neutral_tea_set` via Balinda Stonehearth; `naga_end_of_turn` via Balinda Stonehearth

### Aberrations (new in 36.6.1): no comp data yet

Firestone has no Aberration archetype, and no primary source has placement data for it yet. The official card list (Blizzard BlizzCon post) points to two engines that a future comp detector should watch. **This is a description of card text, not a performance claim:**
- **Discard / Deity scaling:** Brain Rotter `BG36_099`, Cutthroat K'Thir `BG36_106`, Mindbender Ghur'sha `BG36_097` (buffed), Harbinger Aph'lass `BGFYM_005` (buffed), N'raqi Frostcaller `BG36_300`, Mindbending Recruiter `BG36_312`, Abyssal Envoy `BG36_311`, Parasitic Fleshling `BG36_114`, The Shadow of Doubt `BG36_109` (buffed).
- **Tavern-spell / Deity scaling:** Vicious Mindslasher `BG36_108`, Sha of Fear `BG36_111` (T7), Faceless Converter `BG36_318` (buffed), Mysterious K'Thir `BG36_320`, Dark Puppeteer `BG36_104`, Fetid Corroder `BG36_112` / Nightmare Corroder `BG36_115` (Sludge Corrosion), N'raqi Sapper `BG36_103` (Energizing Chamber).
- **Deity progress / sacrifice fodder:** Joyous `BG36_110`, Zoatroid `BG36_098`, Underrot Spawn `BG36_116`, Unwilling Slacker `BG36_101`, Drifting Sacrifice `BG36_113`, Wandering Willbreaker `BG36_100`, Faceless Operative `BG36_308`, De-volition-ist `BG36_102`.
- Community colour (secondary, not data): hearthstone.wiki.gg and hsbg.cards describe the tribe but give no tier list (https://hearthstone.wiki.gg/wiki/Battlegrounds/Aberration, https://hsbg.cards/patch-notes/36.6.1). A YouTube video "Aberrations And Deities Arrive in Battlegrounds And We're Finding The Best Strat" exists but was not reviewed (https://www.youtube.com/watch?v=fjnZajiQhlo).

---

## 5. Top heroes (Firestone hero-stats, last-patch)

All MMR (n≥2,000), best 10 by `averagePosition`, with the same hero's top-10% figure. Pre-36.6.1: Naga-specific heroes are now unavailable, and some heroes are banned from Aberration lobbies (Morchie, Murozond Unbounded, Sylvanas Windrunner, The Curator; plus The Lich King, Teron Gorefiend and N'Zoth in Y'Shaarj games, per the Blizzard BlizzCon post).

| Hero | cardId | Avg place (all MMR) | n | Pick rate | Avg place (top 10%) | n (top 10%) |
|---|---|---|---|---|---|---|
| Lord Jaraxxus | `TB_BaconShop_HERO_37` | 3.57 | 12,687 | 40% | 3.63 | 1297 |
| Cariel Roame | `BG21_HERO_000` | 3.69 | 19,837 | 31% | 3.98 | 2331 |
| Patchwerk | `TB_BaconShop_HERO_34` | 3.73 | 21,045 | 33% | 3.88 | 2090 |
| Teron Gorefiend | `BG25_HERO_103` | 3.78 | 15,825 | 40% | 3.85 | 1855 |
| Tras'tath, Soul Parasite | `BG36_HERO_101` | 3.8 | 33,135 | 52% | 3.97 | 3421 |
| Buttons | `BG32_HERO_002` | 3.8 | 30,515 | 48% | 4.03 | 2968 |
| Yogg-Saron, Hope's End | `TB_BaconShop_HERO_35` | 3.8 | 20,464 | 32% | 4.03 | 2217 |
| Nightmare Lord Xavius | `BG36_HERO_105` | 3.81 | 36,437 | 57% | 4.14 | 4285 |
| The Jailer | `TB_BaconShop_HERO_702` | 3.81 | 8,061 | 26% | 4.11 | 793 |
| A. F. Kay | `TB_BaconShop_HERO_16` | 3.82 | 32,297 | 51% | 3.97 | 4322 |


In the top-10% file (n≥300), the best heroes are Lord Jaraxxus 3.63, Teron Gorefiend 3.85, Deathwing 3.86, Galakrond 3.86, The Great Akazamzarak 3.87, Patchwerk 3.88 and Captain Eudora 3.92.

## 6. Top trinkets (Firestone trinket-stats, last-patch)

Lesser and Greater are split using HearthstoneJSON `spellSchool` (`LESSER_TRINKET` / `GREATER_TRINKET`). Note that trinket costs changed in the 36.6.1 hotfix.

**Lesser trinkets (n>=3,000), best 8 by avg placement**

| Trinket | cardId | Avg place | Avg place top 10% (n) | n | Pick rate | 36.6.1 |
|---|---|---|---|---|---|---|
| Eternal Portrait | `BG30_MagicItem_301` | 3.28 | 3.68 (254) | 4,530 | 25% |  |
| Pilgrimp Sticker | `BG32_MagicItem_821` | 3.37 | 3.49 (599) | 7,171 | 34% |  |
| Conch Portrait | `BG35_MagicItem_305` | 3.42 | 3.81 (352) | 5,716 | 38% |  |
| Ophidian Staff | `BG35_MagicItem_872` | 3.43 | 3.43 (799) | 8,314 | 32% |  |
| Rewinder Portrait | `BG30_MagicItem_868` | 3.43 | 3.80 (472) | 7,437 | 35% |  |
| Scraper Sticker | `BG35_MagicItem_301` | 3.53 | 3.90 (684) | 11,992 | 52% |  |
| Nerglish Phrasebook | `BG30_MagicItem_914` | 3.54 | 3.60 (288) | 4,468 | 29% |  |
| Bleeding Heart | `BG30_MagicItem_713` | 3.56 | 3.94 (522) | 6,003 | 33% |  |

**Greater trinkets (n>=3,000), best 8 by avg placement**

| Trinket | cardId | Avg place | Avg place top 10% (n) | n | Pick rate | 36.6.1 |
|---|---|---|---|---|---|---|
| Assembler Portrait | `BG36_MagicItem_841` | 3.14 | 3.95 (275) | 7,430 | 31% | REMOVED |
| Eternal Portrait | `BG36_MagicItem_216` | 3.20 | 3.60 (139) | 3,579 | 20% |  |
| Dramaloc Sticker | `BG35_MagicItem_754` | 3.23 | 3.34 (250) | 3,643 | 35% |  |
| Flaming Portrait | `BG35_MagicItem_156` | 3.28 | 3.71 (524) | 12,525 | 33% |  |
| Beetle Band | `BG32_MagicItem_860t` | 3.31 | 3.17 (882) | 8,285 | 32% |  |
| Maldraxxus Dagger | `BG36_MagicItem_370` | 3.37 | 3.43 (1,186) | 9,186 | 49% |  |
| Sky Golem Portrait | `BG35_MagicItem_740` | 3.40 | 3.88 (558) | 7,901 | 10% |  |
| Maw Caster Portrait | `BG32_MagicItem_205` | 3.40 | 3.37 (1,409) | 8,846 | 50% |  |

---

## 7. Machine-friendly appendix (comp detection)

Each ID is a HearthstoneJSON base (non-golden) `id`. Firestone's final boards use `_G` / `TB_BaconUps_*` for golden cards, so normalise them via `battlegroundsNormalDbfId` (or strip `_G`) before matching. Suggested rule for a future detector: match on `coreCardIds` (at least 2 present, or the single signature card), and ignore `removedCardIds` in 36.6.1+ lobbies.

```yaml
# Generated from Firestone comp-stats (last-patch, retrieved 2026-09-22) + bgs-comps-strategies; card IDs resolved against HearthstoneJSON build 251952.
# coreCardIds = curated CORE + cards on >=60% of sampled final boards; addonCardIds = curated ADDON/CYCLE + cards on 20-59%.
# status36_6_1: INTACT | MOSTLY INTACT | NERFED | WEAKENED | GUTTED | UNAVAILABLE. removedCardIds are no longer in the pool after 36.6.1.
comps:
  - id: naga_end_of_turn
    name: "Naga End Of Turn"
    tribes: [Naga]
    status36_6_1: "UNAVAILABLE"
    coreCardIds: [BG32_837, BG35_883, BG26_ICC_901, BG36_640]  # Fauna Whisperer, Balinda Stonehearth, Drakkari Enchanter, Gatekeeper Amalgam
    addonCardIds: [BG32_821, BG36_622, BG32_835, BG34_925]  # Felfire Conjurer, Torrential Ruiner, Tranquil Meditative, Seafloor Recruiter
    removedCardIds: [BG32_837, BG36_622, BG32_835, BG34_925]
  - id: dragon_evoker
    name: "Dragon Evoker"
    tribes: [Dragon]
    status36_6_1: "GUTTED"
    coreCardIds: [BG32_822, BG29_813, BG24_004]  # Fire-forged Evoker, Persistent Poet, Warpwing
    addonCardIds: [BG36_241, BG36_245, BG_LOE_077, BG32_821, BG23_318]  # Crimson Vindicator, Runic Arcanist, Brann Bronzebeard, Felfire Conjurer, Leeroy the Reckless
    removedCardIds: [BG32_822, BG24_004]
  - id: elemental_cycle
    name: "Elemental Boost"
    tribes: [Elemental]
    status36_6_1: "GUTTED"
    coreCardIds: [BG36_351, BG36_352, BG_LOE_077, BG32_846]  # Moat Custodian, Unbound Tempest, Brann Bronzebeard, Unleashed Mana Surge
    addonCardIds: [BGS_121, BG32_842, BGS_123, BGS_126]  # Gentle Djinni, Glowing Cinder, Tavern Tempest, Wildfire Elemental
    removedCardIds: [BG36_351, BG32_846, BG32_842]
  - id: mech_automaton
    name: "Mech Automaton"
    tribes: [Mech]
    status36_6_1: "GUTTED"
    coreCardIds: [BG_TTN_401, BG35_342, BGS_012, BG25_354]  # Ancestral Automaton, Falling Sky Golem, Kangor's Apprentice, Titus Rivendare
    addonCardIds: [BG_BOT_911, BG26_152, BG23_318, BG26_148, BG26_149, BG36_506, BG36_851]  # Annoy-o-Module, Utility Drone, Leeroy the Reckless, Scrap Scraper, Polarizing Beatboxer, Drone Duplicator, Spark Snapper
    removedCardIds: [BG_TTN_401, BGS_012, BG26_148]
  - id: murloc_handbuff
    name: "Murloc Handbuff"
    tribes: [Murloc]
    status36_6_1: "INTACT"
    coreCardIds: [BG26_354, BG27_556, BG33_318]  # Choral Mrrrglr, Diremuck Forager, Bile Spitter
    addonCardIds: [BG33_891, BG22_202, BG34_140, BG34_142, BG36_704, BG_LOE_077, BG36_703]  # Magicfin Mycologist, Tad, Expert Aviator, Costume Enthusiast, Shamanic Tidecaller, Brann Bronzebeard, Twilight Tidehunter
    removedCardIds: []
  - id: beast_beetle
    name: "Beast Beetle"
    tribes: [Beast]
    status36_6_1: "NERFED"
    coreCardIds: [BG36_209, BG26_802, BG31_809]  # Ravaging Scorpid, Banana Slamma, Turquoise Skitterer
    addonCardIds: [BG31_801, BG27_084, BG31_803, BG36_204]  # Forest Rover, Sprightly Scarab, Buzzing Vermin, Headhunter Gryphon
    removedCardIds: []
  - id: demon_boost_shop
    name: "Demon Boost Shop"
    tribes: [Demon]
    status36_6_1: "NERFED"
    coreCardIds: [BG36_762, BG28_633, BG35_883, BG36_731]  # Devilish Distractor, Felboar, Balinda Stonehearth, Imp-lusionist
    addonCardIds: [BG27_002, BG_LOE_077, BG35_155, BG23_318, BG32_873]  # Oozeling Gladiator, Brann Bronzebeard, Twisted Wrathguard, Leeroy the Reckless, Ashen Corruptor
    removedCardIds: []
  - id: beast_leviathan
    name: "Beast Leviathan"
    tribes: [Beast]
    status36_6_1: "NERFED"
    coreCardIds: [BG35_602, BG26_802, BG36_209, BG35_604, BG31_809]  # Lurking Leviathan, Banana Slamma, Ravaging Scorpid, Sewer Lord, Turquoise Skitterer
    addonCardIds: [BG36_206, BG36_204]  # Snarky Shark, Headhunter Gryphon
    removedCardIds: []
  - id: undead_butcher
    name: "Undead Butcher"
    tribes: [Undead]
    status36_6_1: "NERFED"
    coreCardIds: [BG32_324, BG36_515, BG25_010, BG28_309, BG36_511]  # Drustfallen Butcher, Snazzy Phantom, Handless Forsaken, Mummifier, Dead Bellringer
    addonCardIds: [BG32_880, BG_DEEP_015, BG36_514]  # Friendly Geist, Prosthetic Hand, Barrier Banshee
    removedCardIds: []
  - id: neutral_tea_set
    name: "Neutral Tea Set"
    tribes: [Neutral]
    status36_6_1: "WEAKENED"
    coreCardIds: [BG36_640, BG35_883, BG32_837]  # Gatekeeper Amalgam, Balinda Stonehearth, Fauna Whisperer
    addonCardIds: [BG36_523, BG32_821, BG_LOE_077, BG24_004]  # Enterprising Escapee, Felfire Conjurer, Brann Bronzebeard, Warpwing
    removedCardIds: [BG32_837, BG24_004]
  - id: demon_self_damage
    name: "Demon Self Damage"
    tribes: [Demon]
    status36_6_1: "NERFED"
    coreCardIds: [BGS_004, BG32_873, BG36_733, BG36_762]  # Wrath Weaver, Ashen Corruptor, Eredar Escapist, Devilish Distractor
    addonCardIds: [BG26_524, BG35_883, BG_LOE_077, BG36_731]  # Malchezaar, Prince of Dance, Balinda Stonehearth, Brann Bronzebeard, Imp-lusionist
    removedCardIds: []
  - id: pirate_discover
    name: "Pirate Discover"
    tribes: [Pirate]
    status36_6_1: "NERFED"
    coreCardIds: [BG36_344, BG36_523, BG26_817]  # Hooktusk, Master Marauder, Enterprising Escapee, Blade Collector
    addonCardIds: [BG36_521, BG24_715, BG33_823, BG23_318, BG33_825, BG_LOE_077]  # Locked-up Mutineer, Patient Scout, Sky Admiral Rogers, Leeroy the Reckless, Proud Privateer, Brann Bronzebeard
    removedCardIds: []
  - id: murloc_mrrglton
    name: "Murloc Mrrglton"
    tribes: [Murloc]
    status36_6_1: "GUTTED"
    coreCardIds: [BG35_142, BG_LOE_077, BG36_701]  # Cousin Errgl, Brann Bronzebeard, Kelp Keeper
    addonCardIds: [BGS_020, BG35_141, BG33_318, BG26_ICC_901, BG35_140, BG27_556]  # Primalfin Lookout, Papa Mrrglton, Bile Spitter, Drakkari Enchanter, Mama Mrrglton, Diremuck Forager
    removedCardIds: [BG35_142, BG35_141, BG35_140]
  - id: mech_magnet
    name: "Mech Magnet"
    tribes: [Mech]
    status36_6_1: "WEAKENED"
    coreCardIds: [BG36_506, BG36_851, BG26_152, BG26_148]  # Drone Duplicator, Spark Snapper, Utility Drone, Scrap Scraper
    addonCardIds: [BG36_853, BG29_503, BG26_149, BGS_071, BG26_ICC_901]  # Glambot, Clunker Junker, Polarizing Beatboxer, Deflect-o-Bot, Drakkari Enchanter
    removedCardIds: [BG26_148, BG29_503, BGS_071]
  - id: beast_lobster
    name: "Beast Lobster"
    tribes: [Beast]
    status36_6_1: "INTACT"
    coreCardIds: [BG36_202, BG36_208, BG25_354, BG36_204]  # Tasty Lobster, Deathstrider, Titus Rivendare, Headhunter Gryphon
    addonCardIds: [BG36_206, BG36_210, BG36_201]  # Snarky Shark, Hoarding Hyena, Lurking Lionfish
    removedCardIds: []
  - id: quilboar_choose_one
    name: "Quilboar Choose One"
    tribes: [Quilboar]
    status36_6_1: "MOSTLY INTACT"
    coreCardIds: [BG31_323, BG36_331]  # Turbo Hogrider, Bramble Tunneler
    addonCardIds: [BG31_326, BG31_320, BG33_885, BG36_510, BG28_633, BG31_327, BG23_017, BG35_883, BG33_883]  # Gem Rat, Crater Miner, Sanguine Refiner, Vigilant Bristlemane, Felboar, Thorned Trailblazer, Sanguine Champion, Balinda Stonehearth, Razorfen Vineweaver
    removedCardIds: [BG36_510]
  - id: dragon_kalecgos
    name: "Dragon Kalecgos"
    tribes: [Dragon]
    status36_6_1: "WEAKENED"
    coreCardIds: [BGS_041, BG24_004, BG_LOE_077, BG29_813, BG36_242]  # Kalecgos, Arcane Aspect, Warpwing, Brann Bronzebeard, Persistent Poet, Bronze Timewalker
    addonCardIds: [BG36_241, BG34_633, BG36_243, BG32_822, BG23_318]  # Crimson Vindicator, Draconic Warden, Sky-hatch Runaway, Fire-forged Evoker, Leeroy the Reckless
    removedCardIds: [BG24_004, BG32_822]
  - id: naga_groundbreaker
    name: "Naga Groundbreaker"
    tribes: [Naga]
    status36_6_1: "UNAVAILABLE"
    coreCardIds: [BG31_035, BG34_925, BG35_883]  # Groundbreaker, Seafloor Recruiter, Balinda Stonehearth
    addonCardIds: [BG31_920, BG36_622, BG36_508, BG32_837, BG23_008, BG23_318, BG35_921]  # Darkcrest Strategist, Torrential Ruiner, Cagey Conjurer, Fauna Whisperer, Glowscale, Leeroy the Reckless, Abyssal Bruiser
    removedCardIds: [BG31_035, BG34_925, BG31_920, BG36_622, BG36_508, BG32_837, BG23_008, BG35_921]
```

```yaml
# Aberration watch-list (no Firestone archetype yet; card-text-based, NOT performance-backed)
  - id: aberration_discard_deity   # provisional, unverified
    tribes: [Aberration]
    deityCardIds: [BGFYM_000, BGFYM_011]   # C'Thun, Y'Shaarj
    candidateCardIds: [BG36_099, BG36_106, BG36_097, BGFYM_005, BG36_300, BG36_312, BG36_311, BG36_114, BG36_109]
  - id: aberration_spell_deity     # provisional, unverified
    tribes: [Aberration]
    candidateCardIds: [BG36_108, BG36_111, BG36_318, BG36_320, BG36_104, BG36_112, BG36_115, BG36_103]
```

---

## 8. Caveats and how to refresh

- **The meta shifts quickly, and this snapshot sits on a patch boundary.** Everything in sections 3 to 6 is from before 36.6.1. Re-run the steps below once Firestone's `currentBattlegroundsMetaPatch` moves past 251952 (check `patches.json`) or after about a week of 36.6.1 play. Expect new `aberration_*` archetypes and a new Volumizer Mech archetype to appear.
- The curated strategies are from August 2026 (patch 248022) and several reference removed cards. The file also contains blank placeholder entries (`compId` of whitespace) and `cardId: "#N/A"` for every card, so card IDs have to be resolved by name. Names needed normalising (for example "Kalecgos Arcane Aspect" is `BGS_041` "Kalecgos, Arcane Aspect").
- Firestone ToS: the data is used here for personal use, as the project brief allows.

**Refresh commands** (macOS, zsh):

```bash
D=scratchpad/meta; mkdir -p $D; cd $D
# which BG patch Firestone's "last-patch" currently means
curl -s --compressed https://static.zerotoheroes.com/hearthstone/data/patches.json \
  | jq '{bg: .currentBattlegroundsMetaPatch, latest: .patches[-1]}'
# comp stats (time slugs: last-patch | past-seven | past-three | all-time)
curl -s --compressed -o comp-last-patch.json \
  https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json
# curated strategies
curl -s --compressed -o strat.json \
  https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json
# hero stats (path needs mmr-<pct>; pct in 100,50,25,10,1)
curl -s --compressed -o hero-100.json \
  https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/last-patch/overview-from-hourly.gz.json
curl -s --compressed -o hero-10.json \
  https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-10/last-patch/overview-from-hourly.gz.json
# trinket stats (NO mmr segment; MMR breakdown is inside averagePlacementAtMmr)
curl -s --compressed -o trinket.json \
  https://static.zerotoheroes.com/api/bgs/trinket-stats/last-patch/overview-from-hourly.gz.json
# card DB (replace build when a new one ships; list at https://api.hearthstonejson.com/v1/)
curl -s --compressed -o cards.json https://api.hearthstonejson.com/v1/251952/enUS/cards.json
# comp ranking
jq -r '.compStats | sort_by(.averagePlacement)[] | select(.dataPoints>1000) |
  [.archetype, .dataPoints, (.averagePlacement*100|round/100),
   (.averagePlacementAtMmr[]|select(.mmr==10)|.placement*100|round/100)] | @tsv' comp-last-patch.json
```

The scratchpad scripts that produced this doc are `boards.py` (final-board card frequency), `gen.py` (name-to-ID resolution plus 36.6.1 flags), `frag.py` (heroes per comp, overlaps), `build.py` (tables and YAML) and `ht2.py` (hero and trinket tables).

## Sources (all retrieved 2026-09-22)

- Firestone comp stats: https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json
- Firestone curated strategies: https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json
- Firestone hero stats: https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/last-patch/overview-from-hourly.gz.json and `.../mmr-10/...`
- Firestone trinket stats: https://static.zerotoheroes.com/api/bgs/trinket-stats/last-patch/overview-from-hourly.gz.json
- Firestone patch map: https://static.zerotoheroes.com/hearthstone/data/patches.json
- HearthstoneJSON cards build 251952: https://api.hearthstonejson.com/v1/251952/enUS/cards.json
- Blizzard, 36.6 Patch Notes: https://hearthstone.blizzard.com/en-us/news/24294373/366-patch-notes
- Blizzard, Aberrations Join Battlegrounds at BlizzCon!: https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon
- Blizzard forums, 36.6.1 Hotfix Patch: https://us.forums.blizzard.com/en/hearthstone/t/3661-hotfix-patch/165846
- Secondary: HearthPwn 36.6.1 hotfix summary https://www.hearthpwn.com/news/12706-36-6-1-hotfix-patch-constructed-battlegrounds-bug ; hsbg.cards https://hsbg.cards/patch-notes/36.6.1 ; hearthstone.wiki.gg https://hearthstone.wiki.gg/wiki/Battlegrounds/Aberration
- Attempted, blocked: HSReplay https://hsreplay.net/battlegrounds/comps/ (403 Cloudflare); https://www.hsbattlegrounds.help/en/meta-comps (402); https://www.playnews.gg/... (403)
