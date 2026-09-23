#!/usr/bin/env python3
"""Apply the simulator-input-mapping spec to a replay snapshot -> BgsBattleInfo JSON.
Usage: build_input.py snap.json LOCAL_PID cards.json > input.json"""
import json, sys

snap = json.load(open(sys.argv[1]))
LOCAL = int(sys.argv[2])
cards = {c["id"]: c for c in json.load(open(sys.argv[3]))}
by_dbf = {c.get("dbfId"): c for c in cards.values()}
E = {int(k): v for k, v in snap["ents"].items()}
G = E[snap["gameEntity"]]["tags"]
P2E = {int(k): v for k, v in snap["pidToEnt"].items()}

# Tags the client may print either by name or by number. Normalise to one key.
NUM = {"BACON_OLD_GOD_ATTACK": 4914, "BACON_OLD_GOD_HEALTH": 4915, "BACON_YAMATO_CANNON": 4036}
def tag(e, name, num=None, default=0):
    t = e["tags"]
    if name in t:
        return t[name]
    if num is not None and str(num) in t:
        return t[str(num)]
    return default

ctrl = lambda e: e["tags"].get("LETTUCE_CONTROLLER", e["tags"].get("CONTROLLER"))
zone = lambda e: e["tags"].get("ZONE")
ctype = lambda e: e["tags"].get("CARDTYPE")
PLACEHOLDER_TRINKETS = {"BG30_Trinket_1st", "BG30_Trinket_2nd"}

def attached(eid, allow_removed=False):
    return [(i, e) for i, e in sorted(E.items())
            if e["tags"].get("ATTACHED") == eid and (allow_removed or zone(e) != "REMOVEDFROMGAME")]

def enchantments(eid):
    return [{"cardId": e["cardId"], "originEntityId": i,
             "tagScriptDataNum1": tag(e, "TAG_SCRIPT_DATA_NUM_1"), "tagScriptDataNum2": tag(e, "TAG_SCRIPT_DATA_NUM_2"),
             "timing": 0} for i, e in attached(eid)]

def minion(i, e):
    atk, hp, dmg = tag(e, "ATK"), tag(e, "HEALTH"), tag(e, "DAMAGE")
    wf = tag(e, "WINDFURY")
    out = {"entityId": i, "cardId": e["cardId"], "attack": atk, "health": hp - dmg, "maxHealth": hp,
           "taunt": tag(e, "TAUNT") == 1, "divineShield": tag(e, "DIVINE_SHIELD") == 1,
           "poisonous": tag(e, "POISONOUS") == 1, "venomous": tag(e, "VENOMOUS") == 1,
           "reborn": tag(e, "REBORN") == 1, "stealth": tag(e, "STEALTH") == 1,
           "windfury": wf in (1, 3) or tag(e, "MEGA_WINDFURY") == 1,
           "locked": tag(e, "UNPLAYABLE_VISUALS") == 1 or tag(e, "LITERALLY_UNPLAYABLE") == 1,
           "enchantments": enchantments(i)}
    for n in range(1, 7):
        out[f"scriptDataNum{n}"] = tag(e, f"TAG_SCRIPT_DATA_NUM_{n}")
    yam = tag(e, "BACON_YAMATO_CANNON", 4036, None)
    out["tags"] = {str(NUM["BACON_YAMATO_CANNON"]): yam} if yam is not None else {}
    parts = [tag(e, "MODULAR_ENTITY_PART_1"), tag(e, "MODULAR_ENTITY_PART_2")]
    extra = [by_dbf[p]["id"] for p in parts if p and p in by_dbf and by_dbf[p]["id"] != e["cardId"]]
    if extra:
        out["additionalCards"] = extra
    return out

def player_ench(pent, card_id):
    for i, e in attached(pent):
        if e["cardId"] == card_id and zone(e) == "PLAY":
            return e
    return None

def side(slot_pid, is_local):
    pent_id = P2E[slot_pid]
    pent = E[pent_id]
    heroes = [(i, e) for i, e in E.items() if ctype(e) == "HERO" and zone(e) == "PLAY" and ctrl(e) == slot_pid
              and not e["cardId"].startswith("TB_BaconShopBob")]
    hero_id, hero = max(heroes)  # reconnect can leave several; take the newest
    # Counters: opponent -> prefer the TagTransferPlayerEnchant attached to the slot Player entity (HDT rule)
    transfer = None if is_local else player_ench(pent_id, "Bacon_TagTransferPlayerE")
    def counter(name, num):
        src = transfer if transfer is not None else pent
        v = tag(src, name, num, None)
        return v if v is not None else tag(pent, name, num, 0)
    def ench_sdn(card_id, n=1):
        e = player_ench(pent_id, card_id)
        return tag(e, f"TAG_SCRIPT_DATA_NUM_{n}") if e else 0

    board = sorted([(i, e) for i, e in E.items() if ctrl(e) == slot_pid and zone(e) == "PLAY"
                    and ctype(e) in ("MINION", "LOCATION", "BATTLEGROUND_SPELL")], key=lambda x: tag(x[1], "ZONE_POSITION"))
    hand = sorted([(i, e) for i, e in E.items() if ctrl(e) == slot_pid and zone(e) == "HAND"], key=lambda x: tag(x[1], "ZONE_POSITION"))
    hps = [(i, e) for i, e in sorted(E.items()) if ctrl(e) == slot_pid and zone(e) == "PLAY" and ctype(e) == "HERO_POWER"]
    trinkets = sorted([(i, e) for i, e in E.items() if ctrl(e) == slot_pid and zone(e) == "PLAY"
                       and ctype(e) == "BATTLEGROUND_TRINKET" and e["cardId"] not in PLACEHOLDER_TRINKETS],
                      key=lambda x: tag(x[1], "TAG_SCRIPT_DATA_NUM_6"))
    secret_zone = [(i, e) for i, e in sorted(E.items()) if ctrl(e) == slot_pid and zone(e) == "SECRET"]
    quests = [(i, e) for i, e in secret_zone if tag(e, "QUEST") == 1 and ctype(e) == "SPELL"]
    secrets = [(i, e) for i, e in secret_zone if tag(e, "QUEST") != 1 and tag(e, "SIDE_QUEST") != 1 and tag(e, "BACON_IS_BOB_QUEST") != 1]
    rewards = [(i, e) for i, e in E.items() if ctrl(e) == slot_pid and zone(e) == "PLAY" and ctype(e) == "BATTLEGROUND_QUEST_REWARD"]

    def secret(i, e):
        s = {"entityId": i, "cardId": e["cardId"]}
        for n in (1, 2, 3, 6):
            s[f"scriptDataNum{n}"] = tag(e, f"TAG_SCRIPT_DATA_NUM_{n}")
        if e["cardId"] == "BG_OldGod":  # Deity: stats live on the Player entity, not on the secret
            s["tags"] = {str(NUM["BACON_OLD_GOD_ATTACK"]): tag(pent, "BACON_OLD_GOD_ATTACK", 4914, 1),
                         str(NUM["BACON_OLD_GOD_HEALTH"]): tag(pent, "BACON_OLD_GOD_HEALTH", 4915, 1)}
        return s

    blood_atk = max(ench_sdn("BG26_159pe", 1), tag(pent, "BACON_BLOODGEMBUFFATKVALUE", 1844))
    blood_hp = max(ench_sdn("BG26_159pe", 2), tag(pent, "BACON_BLOODGEMBUFFHEALTHVALUE", 2827))
    global_info = {
        "EternalKnightsDeadThisGame": ench_sdn("BG25_008pe", 1),
        "UndeadAttackBonus": ench_sdn("BG25_011pe", 1), "UndeadHealthBonus": ench_sdn("BG25_011pe", 2),
        "HauntedCarapaceAttackBonus": ench_sdn("BG33_112pe", 1), "HauntedCarapaceHealthBonus": ench_sdn("BG33_112pe", 2),
        "GoldrinnBuffAtk": ench_sdn("BGS_018pe", 1) + ench_sdn("BG34_Giant_362pe", 1),
        "GoldrinnBuffHealth": ench_sdn("BGS_018pe", 2) + ench_sdn("BG34_Giant_362pe", 2),
        "AstralAutomatonsSummonedThisGame": ench_sdn("BG_TTN_401pe", 1),
        "BeetleAttackBuff": ench_sdn("BG31_808pe", 1), "BeetleHealthBuff": ench_sdn("BG31_808pe", 2),
        "SanlaynScribesDeadThisGame": ench_sdn("BGDUO31_208pe", 1),
        "DeepBluesPlayed": ench_sdn("BG26_502pe", 1),
        "WhelpAttackBuff": ench_sdn("BG34_402pe", 1), "WhelpHealthBuff": ench_sdn("BG34_402pe", 2),
        "BloodGemAttackBonus": blood_atk, "BloodGemHealthBonus": blood_hp,
        "TavernSpellsCastThisGame": counter("TAVERN_SPELLS_PLAYED_THIS_GAME", 3088),
        "SpellsCastThisGame": counter("NUM_SPELLS_PLAYED_THIS_GAME", 1780),
        "FrostlingBonus": counter("BACON_ELEMENTALS_PLAYED_THIS_GAME", 2878),
        "PiratesPlayedThisGame": counter("BACON_PIRATES_PLAYED_THIS_GAME", 2358),
        "PiratesSummonedThisGame": counter("BACON_PIRATES_SUMMONED_THIS_GAME", 3685),
        "BeastsSummonedThisGame": counter("BACON_BEASTS_SUMMONED_THIS_GAME", 3962),
        "MagnetizedThisGame": counter("BACON_NUM_MAGNETIZE_THIS_GAME", 3670),
        "ElementalAttackBuff": counter("BACON_ELEMENTAL_BUFFATKVALUE", 4002),
        "ElementalHealthBuff": counter("BACON_ELEMENTAL_BUFFHEALTHVALUE", 4001),
        "TavernSpellAttackBuff": tag(pent, "TAVERN_SPELL_ATTACK_INCREASE", 3989, None) if tag(pent, "TAVERN_SPELL_ATTACK_INCREASE", 3989, None) is not None else counter("TAVERN_SPELL_ATTACK_INCREASE", 3989),
        "TavernSpellHealthBuff": tag(pent, "TAVERN_SPELL_HEALTH_INCREASE", 3990, None) if tag(pent, "TAVERN_SPELL_HEALTH_INCREASE", 3990, None) is not None else counter("TAVERN_SPELL_HEALTH_INCREASE", 3990),
        "GoldSpentThisGame": counter("BACON_GOLD_SPENT_THIS_GAME", 4212),
        "BattlecriesTriggeredThisGame": counter("BATTLECRIES_TRIGGERED_THIS_GAME", 3873),
        "DeathrattlesTriggeredThisGame": counter("DEATHRATTLES_TRIGGERED_THIS_GAME", 4639),
        "FriendlyMinionsDeadLastCombat": counter("NUM_FRIENDLY_MINIONS_THAT_DIED_LAST_TURN", 2717),
        "VolumizerAttackBuff": counter("BACON_VOLUMIZER_ATTACK_BUFF", 4468),
        "VolumizerHealthBuff": counter("BACON_VOLUMIZER_HEALTH_BUFF", 4469),
        "GoldenMinionsPlayedThisGame": counter("BACON_GOLDEN_MINIONS_PLAYED_THIS_GAME", 4799),
        "CardsDiscardedThisGame": counter("CARDS_DISCARDED_THIS_GAME", 4768),
        "TastyLobstersBuff": counter("BACON_TASTY_LOBSTER_BUFF", 4803),
    }
    # Choral Mrrrglr: enchantment on a board minion; halve when the creator is golden
    for i, e in board:
        for j, en in attached(i):
            if en["cardId"] == "BG26_354e":
                src = E.get(tag(en, "CREATOR"))
                div = 2 if src and tag(src, "PREMIUM") == 1 else 1
                global_info["ChoralAttackBuff"] = tag(en, "TAG_SCRIPT_DATA_NUM_1") // div
                global_info["ChoralHealthBuff"] = tag(en, "TAG_SCRIPT_DATA_NUM_2") // div
    player = {
        "cardId": hero["cardId"],
        "entityId": hero_id,
        "hpLeft": tag(hero, "HEALTH") + tag(hero, "ARMOR") - tag(hero, "DAMAGE"),
        "tavernTier": tag(hero, "PLAYER_TECH_LEVEL") or tag(pent, "PLAYER_TECH_LEVEL") or 1,
        "heroPowers": [{"cardId": e["cardId"], "entityId": i,
                        "used": tag(e, "BACON_HERO_POWER_ACTIVATED") == 1 or tag(e, "EXHAUSTED") == 1,
                        "info": tag(e, "TAG_SCRIPT_DATA_NUM_1"), "info2": tag(e, "TAG_SCRIPT_DATA_NUM_2"),
                        "info3": tag(e, "TAG_SCRIPT_DATA_NUM_3"), "info4": tag(e, "TAG_SCRIPT_DATA_NUM_4"),
                        "info5": tag(e, "TAG_SCRIPT_DATA_NUM_5"), "info6": tag(e, "TAG_SCRIPT_DATA_NUM_6"),
                        "scoreValue1": tag(e, "SCORE_VALUE_1"), "scoreValue2": tag(e, "SCORE_VALUE_2"),
                        "scoreValue3": tag(e, "SCORE_VALUE_3"), "locked": tag(e, "LOCK_VISUAL", 4414)} for i, e in hps],
        "questEntities": [{"CardId": e["cardId"], "RewardDbfId": tag(e, "QUEST_REWARD_DATABASE_ID"),
                           "ProgressCurrent": tag(e, "QUEST_PROGRESS"), "ProgressTotal": tag(e, "QUEST_PROGRESS_TOTAL")} for i, e in quests],
        "questRewards": [e["cardId"] for i, e in rewards],
        "questRewardEntities": [{"CardId": e["cardId"], "ScriptDataNum1": tag(e, "TAG_SCRIPT_DATA_NUM_1")} for i, e in rewards],
        "hand": [minion(i, e) for i, e in hand],
        "secrets": [secret(i, e) for i, e in secrets],
        "trinkets": [{"cardId": e["cardId"], "entityId": i, "scriptDataNum1": tag(e, "TAG_SCRIPT_DATA_NUM_1"),
                      "scriptDataNum2": tag(e, "TAG_SCRIPT_DATA_NUM_2"), "scriptDataNum6": tag(e, "TAG_SCRIPT_DATA_NUM_6")} for i, e in trinkets],
        "globalInfo": global_info,
    }
    return {"player": player, "board": [minion(i, e) for i, e in board]}

opp_pid = [p for p in P2E if p != LOCAL][0]
# numberOfPlayersAlive: distinct PLAYER_IDs of leaderboard heroes with HP left
alive = {}
for i, e in E.items():
    if ctype(e) == "HERO" and tag(e, "PLAYER_LEADERBOARD_PLACE") > 0:
        alive[tag(e, "PLAYER_ID")] = (tag(e, "HEALTH") + tag(e, "ARMOR") - tag(e, "DAMAGE")) > 0
anomaly_dbf = tag(E[snap["gameEntity"]], "BACON_GLOBAL_ANOMALY_DBID", 2897)
battle = {
    "playerBoard": side(LOCAL, True),
    "opponentBoard": side(opp_pid, False),
    "options": {"numberOfSimulations": 8000, "maxAcceptableDuration": 2000, "skipInfoLogs": True,
                "includeOutcomeSamples": False, "applyDamageCap": tag(E[snap["gameEntity"]], "BACON_COMBAT_DAMAGE_CAP_ENABLED") == 1},
    "gameState": {"currentTurn": (tag(E[snap["gameEntity"]], "TURN") + 1) // 2,
                  "anomalies": [by_dbf[anomaly_dbf]["id"]] if anomaly_dbf and anomaly_dbf in by_dbf else [],
                  "numberOfPlayersAlive": sum(alive.values())},
}
json.dump(battle, sys.stdout, indent=1)
print(f"\n# log BACON_COMBAT_DAMAGE_CAP={tag(E[snap['gameEntity']], 'BACON_COMBAT_DAMAGE_CAP')}", file=sys.stderr)
