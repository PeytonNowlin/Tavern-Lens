#!/usr/bin/env python3
"""Project a replay snapshot into both BG sides (Firestone-parser style selection rules)."""
import json, sys

d = json.load(open(sys.argv[1]))
E = {int(k): v for k, v in d["ents"].items()}
ctrl_of = lambda e: e["tags"].get("LETTUCE_CONTROLLER", e["tags"].get("CONTROLLER"))
KEYS = ["ATK", "HEALTH", "DAMAGE", "ZONE_POSITION", "PREMIUM", "TECH_LEVEL", "TAUNT", "DIVINE_SHIELD",
        "REBORN", "POISONOUS", "VENOMOUS", "WINDFURY", "MEGA_WINDFURY", "STEALTH", "CARDRACE",
        "TAG_SCRIPT_DATA_NUM_1", "TAG_SCRIPT_DATA_NUM_2", "TAG_SCRIPT_DATA_NUM_3", "NUM_TURNS_IN_PLAY",
        "COPIED_FROM_ENTITY_ID", "SCORE_VALUE_2", "MODULAR_ENTITY_PART_1", "MODULAR_ENTITY_PART_2"]


def attached(eid):
    return [(i, e) for i, e in sorted(E.items()) if e["tags"].get("ATTACHED") == eid and e["tags"].get("ZONE") != "REMOVEDFROMGAME"]


def ench_list(eid):
    return [{"entityId": i, "cardId": e["cardId"], "sdn1": e["tags"].get("TAG_SCRIPT_DATA_NUM_1"),
             "sdn2": e["tags"].get("TAG_SCRIPT_DATA_NUM_2"), "zone": e["tags"].get("ZONE"),
             "creator": e["tags"].get("CREATOR")} for i, e in attached(eid)]


out = {}
for pid, pent in d["pidToEnt"].items():
    pid = int(pid)
    pl = E[pent]
    side = {"playerId": pid, "playerEntity": pent}
    heroes = [(i, e) for i, e in E.items() if e["tags"].get("CARDTYPE") == "HERO" and e["tags"].get("ZONE") == "PLAY" and ctrl_of(e) == pid]
    side["heroesInPlay"] = [{"id": i, "cardId": e["cardId"], **{k: e["tags"].get(k) for k in ("HEALTH", "DAMAGE", "ARMOR", "PLAYER_TECH_LEVEL", "PLAYER_ID", "PLAYER_LEADERBOARD_PLACE", "NUM_TURNS_IN_PLAY")}} for i, e in heroes]
    side["heroEntityTag"] = pl["tags"].get("HERO_ENTITY")
    def pick(pred):
        return [(i, e) for i, e in sorted(E.items()) if ctrl_of(e) == pid and pred(e)]
    board = pick(lambda e: e["tags"].get("ZONE") == "PLAY" and e["tags"].get("CARDTYPE") in ("MINION", "LOCATION", "BATTLEGROUND_SPELL"))
    board.sort(key=lambda x: x[1]["tags"].get("ZONE_POSITION", 0))
    side["board"] = [{"id": i, "cardId": e["cardId"], **{k: e["tags"][k] for k in KEYS if k in e["tags"]}, "enchantments": ench_list(i)} for i, e in board]
    side["heroPowers"] = [{"id": i, "cardId": e["cardId"], **{k: e["tags"].get(k) for k in ("BACON_HERO_POWER_ACTIVATED", "EXHAUSTED", "TAG_SCRIPT_DATA_NUM_1", "TAG_SCRIPT_DATA_NUM_2", "TAG_SCRIPT_DATA_NUM_3", "TAG_SCRIPT_DATA_ENT_1", "SCORE_VALUE_1", "SCORE_VALUE_2", "LOCK_VISUAL", "4414", "ADDITIONAL_HERO_POWER_INDEX", "3919")}} for i, e in pick(lambda e: e["tags"].get("ZONE") == "PLAY" and e["tags"].get("CARDTYPE") == "HERO_POWER")]
    side["trinkets"] = [{"id": i, "cardId": e["cardId"], **{k: e["tags"].get(k) for k in ("TAG_SCRIPT_DATA_NUM_1", "TAG_SCRIPT_DATA_NUM_2", "TAG_SCRIPT_DATA_NUM_6", "BACON_TRINKET")}} for i, e in pick(lambda e: e["tags"].get("ZONE") == "PLAY" and e["tags"].get("CARDTYPE") == "BATTLEGROUND_TRINKET")]
    side["secretZone"] = [{"id": i, "cardId": e["cardId"], "CARDTYPE": e["tags"].get("CARDTYPE"), **{k: e["tags"].get(k) for k in ("QUEST", "SIDE_QUEST", "SECRET", "BACON_IS_BOB_QUEST", "QUEST_PROGRESS", "QUEST_PROGRESS_TOTAL", "QUEST_REWARD_DATABASE_ID", "TAG_SCRIPT_DATA_NUM_1", "TAG_SCRIPT_DATA_NUM_2", "TAG_SCRIPT_DATA_NUM_6", "BACON_OLD_GOD_ATTACK", "BACON_OLD_GOD_HEALTH", "BACON_EVOLUTION_CARD_ID")}} for i, e in pick(lambda e: e["tags"].get("ZONE") == "SECRET")]
    side["questRewards"] = [{"id": i, "cardId": e["cardId"], "sdn1": e["tags"].get("TAG_SCRIPT_DATA_NUM_1")} for i, e in pick(lambda e: e["tags"].get("ZONE") == "PLAY" and e["tags"].get("CARDTYPE") == "BATTLEGROUND_QUEST_REWARD")]
    side["hand"] = [{"id": i, "cardId": e["cardId"], "CARDTYPE": e["tags"].get("CARDTYPE"), "ATK": e["tags"].get("ATK"), "HEALTH": e["tags"].get("HEALTH")} for i, e in pick(lambda e: e["tags"].get("ZONE") == "HAND")]
    side["playerEnchantments"] = ench_list(pent)
    out[pid] = side
json.dump(out, sys.stdout, indent=1)
