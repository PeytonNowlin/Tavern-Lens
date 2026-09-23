"""Derive per-BG-turn Battlegrounds state from Power.log (PowerTaskList stream).

python3 timeline.py <Power.log> [--json out.json]
Prints a per-turn timeline with BattleTags redacted.
"""
import json, os, sys
from powerlog import replay, TAG, tname

HERE = os.path.dirname(os.path.abspath(__file__))
CARDS = {c["id"]: c for c in json.load(open(os.path.join(HERE, "cards.json")))}
KW = ["TAUNT", "DIVINE_SHIELD", "REBORN", "POISONOUS", "VENOMOUS", "WINDFURY", "MEGA_WINDFURY",
      "STEALTH", "DEATHRATTLE", "BATTLECRY", "AVENGE", "MAGNETIC", "BACON_RALLY", "FROZEN"]
KW_SHORT = {"TAUNT": "T", "DIVINE_SHIELD": "DS", "REBORN": "R", "POISONOUS": "P", "VENOMOUS": "V",
            "WINDFURY": "WF", "MEGA_WINDFURY": "MWF", "STEALTH": "S", "DEATHRATTLE": "DR",
            "BATTLECRY": "BC", "AVENGE": "AV", "MAGNETIC": "MAG", "BACON_RALLY": "RALLY", "FROZEN": "FRZ"}


def cname(cid):
    c = CARDS.get(cid)
    return c["name"] if c else (cid or "?")


def local_pid(st):
    return st.players.get(st.local_eid())


def bob_pid(st):
    return st.players.get(st.other_player_eid())


def minion_str(e):
    kws = [KW_SHORT[k] for k in KW if e.get(k)]
    gold = "*" if e.get("PREMIUM") else ""
    s = f"{cname(e.card_id)}{gold} {e.get('ATK', 0)}/{(e.get('HEALTH', 0) or 0) - (e.get('DAMAGE', 0) or 0)}"
    if kws:
        s += " [" + ",".join(kws) + "]"
    return s


def zone_list(st, controller, zone, types=("MINION",)):
    out = [e for e in st.entities.values()
           if e.get("CONTROLLER") == controller and e.get("ZONE") == zone and e.get("CARDTYPE") in types]
    return sorted(out, key=lambda e: e.get("ZONE_POSITION", 0) or 0)


def gold(st):
    p = st.entities[st.local_eid()]
    r, u, t = p.get("RESOURCES", 0) or 0, p.get("RESOURCES_USED", 0) or 0, p.get("TEMP_RESOURCES", 0) or 0
    return {"RESOURCES": r, "RESOURCES_USED": u, "TEMP_RESOURCES": t, "cap_3148": p.get(3148),
            "MAXRESOURCES": p.get("MAXRESOURCES"), "available": r + t - u}


def local_hero(st):
    p = st.entities[st.local_eid()]
    return st.entities.get(p.get("HERO_ENTITY"))


def hp(e):
    return (e.get("HEALTH", 0) or 0) - (e.get("DAMAGE", 0) or 0) + (e.get("ARMOR", 0) or 0)


def lobby(st):
    rows = []
    for e in st.entities.values():
        if e.get("CARDTYPE") == "HERO" and e.get("PLAYER_LEADERBOARD_PLACE") is not None:
            rows.append({"pid": e.get("PLAYER_ID"), "eid": e.id, "hero": cname(e.card_id),
                         "hp": hp(e), "health": e.get("HEALTH"), "damage": e.get("DAMAGE", 0), "armor": e.get("ARMOR", 0),
                         "tier": e.get("PLAYER_TECH_LEVEL"), "place": e.get("PLAYER_LEADERBOARD_PLACE"),
                         "triples": e.get("PLAYER_TRIPLES", 0), "zone": e.get("ZONE"), "controller": e.get("CONTROLLER")})
    return sorted(rows, key=lambda r: r["place"])


def hero_for_pid(st, pid):
    # lobby heroes: the ones that carry PLAYER_LEADERBOARD_PLACE and PLAYER_ID==pid
    for e in st.entities.values():
        if e.get("CARDTYPE") == "HERO" and e.get("PLAYER_ID") == pid and e.get("PLAYER_LEADERBOARD_PLACE") is not None:
            return e
    return None


class Deriver:
    def __init__(self):
        self.turns = {}           # bg turn -> dict
        self.events = []
        self.recruit_shops = {}   # bg turn -> list of shop lists seen (on each change)
        self.bg_turn = 0
        self.phase = "pregame"
        self.last_shop_key = None
        self.anomalies = []
        self.dead = {}
        self.place_changes = []
        self.game_end = None

    def T(self, n):
        return self.turns.setdefault(n, {"bg_turn": n})

    def listener(self, st, kind, **kw):
        if kind != "tag":
            return
        e, tag, old, new, line, ts = kw["ent"], kw["tag"], kw["old"], kw["new"], kw["line"], kw["ts"]
        if e.id == st.game_id and tag == TAG["TURN"] and old != new:
            if new % 2 == 0:
                # entering combat: snapshot end-of-recruit state FIRST (tag already applied, board unchanged)
                n = (new) // 2
                t = self.T(n)
                t["recruit_end"] = self.recruit_snapshot(st, line, ts)
                t["combat_turn_line"] = line
                self.phase = "combat"
            else:
                n = (new + 1) // 2
                if n - 1 in self.turns:
                    self.T(n - 1)["post_combat_lobby"] = lobby(st)
                    lh = local_hero(st)
                    self.T(n - 1)["post_combat_local_hp"] = hp(lh) if lh else None
                self.bg_turn = n
                self.phase = "recruit"
                self.T(n)["recruit_start_line"] = line
                self.T(n)["recruit_start_ts"] = ts
            self.events.append((line, ts, f"TURN {old}->{new}"))
        elif e.id == st.game_id and tag in (TAG["BOARD_VISUAL_STATE"], 2022, 3533) and old != new:
            self.events.append((line, ts, f"{tname(tag)} {old}->{new}"))
            n = self.bg_turn
            if tag == 2022 and new == 0 and old == 1:
                self.T(n)["combat_2022_off"] = self.combat_snapshot(st, line, ts)
            if tag == 2022 and new == 1:
                self.T(n)["combat_2022_on"] = self.combat_snapshot(st, line, ts)
        elif tag == TAG["NEXT_OPPONENT_PLAYER_ID"] and old != new:
            who = "player" if e.id in st.players else "hero"
            self.events.append((line, ts, f"NEXT_OPPONENT_PLAYER_ID({who}) {old}->{new}"))
        elif e.id == st.other_player_eid() and tag == TAG["BACON_CURRENT_COMBAT_PLAYER_ID"] and new:
            self.T(self.bg_turn)["combat_player_id"] = new
        elif e.id == st.other_player_eid() and tag == TAG["HERO_ENTITY"] and old != new:
            self.events.append((line, ts, f"slot10 HERO_ENTITY {old}->{new} ({cname(st.entities[new].card_id) if new in st.entities else '?'})"))

        if e.id == st.game_id and tag == TAG["STATE"] and new == "COMPLETE":
            self.events.append((line, ts, "STATE COMPLETE"))
            self.game_end = {"line": line, "ts": ts, "lobby": lobby(st), "bg_turn": self.bg_turn,
                             "local_place": (local_hero(st) or {}).get("PLAYER_LEADERBOARD_PLACE") if local_hero(st) else None}
        if e.id in st.players and tag == TAG["PLAYSTATE"] and old != new:
            who = "Local" if e.id == st.local_eid() else "Slot"
            self.events.append((line, ts, f"PLAYSTATE {who} {old}->{new}"))
        if e.get("CARDTYPE") == "HERO" and e.get("PLAYER_LEADERBOARD_PLACE") is not None and tag in (TAG["DAMAGE"], TAG["ARMOR"], TAG["HEALTH"]):
            if hp(e) <= 0 and e.id not in self.dead:
                self.dead[e.id] = (self.bg_turn, line, ts, e.get("PLAYER_ID"), cname(e.card_id), e.get("PLAYER_LEADERBOARD_PLACE"))
        if e.get("CARDTYPE") == "HERO" and tag == TAG["PLAYER_LEADERBOARD_PLACE"] and old != new and e.get("PLAYER_ID") is not None:
            self.place_changes.append((self.bg_turn, line, e.get("PLAYER_ID"), old, new))

        # track shop contents during recruit
        if self.phase == "recruit" and tag in (TAG["ZONE"], TAG["ZONE_POSITION"], TAG["CONTROLLER"]):
            shop = zone_list(st, bob_pid(st), "PLAY", ("MINION", "BATTLEGROUND_SPELL"))
            key = tuple(x.id for x in shop)
            if key != self.last_shop_key and shop:
                self.last_shop_key = key
                self.recruit_shops.setdefault(self.bg_turn, []).append((line, ts, [(x.id, minion_str(x)) for x in shop]))

    def recruit_snapshot(self, st, line, ts):
        lp, bp = local_pid(st), bob_pid(st)
        h = local_hero(st)
        return {
            "line": line, "ts": ts,
            "hero": cname(h.card_id) if h else None, "hero_hp": hp(h) if h else None,
            "health": h.get("HEALTH") if h else None, "damage": h.get("DAMAGE", 0) if h else None, "armor": h.get("ARMOR", 0) if h else None,
            "tier": h.get("PLAYER_TECH_LEVEL") if h else None,
            "player_tier_tag": st.entities[st.local_eid()].get("PLAYER_TECH_LEVEL"),
            "gold": gold(st),
            "board": [(x.id, minion_str(x)) for x in zone_list(st, lp, "PLAY")],
            "hand": [(x.id, cname(x.card_id) + ("*" if x.get("PREMIUM") else ""), x.get("CARDTYPE")) for x in
                     sorted([e for e in st.entities.values() if e.get("CONTROLLER") == lp and e.get("ZONE") == "HAND"],
                            key=lambda e: e.get("ZONE_POSITION", 0) or 0)],
            "shop": [(x.id, minion_str(x), x.get("CARDTYPE")) for x in zone_list(st, bp, "PLAY", ("MINION", "BATTLEGROUND_SPELL"))],
            "next_opp_pid": st.entities[st.local_eid()].get("NEXT_OPPONENT_PLAYER_ID"),
            "next_opp_hero_tag": h.get("NEXT_OPPONENT_PLAYER_ID") if h else None,
            "lobby": lobby(st),
        }

    def combat_snapshot(self, st, line, ts):
        lp, bp = local_pid(st), bob_pid(st)
        slot = st.entities[st.other_player_eid()]
        oh = st.entities.get(slot.get("HERO_ENTITY"))
        opp = zone_list(st, bp, "PLAY")
        return {
            "line": line, "ts": ts,
            "slot10_hero": (oh.id, cname(oh.card_id), oh.get("PLAYER_ID")) if oh else None,
            "opp_board": [(x.id, minion_str(x), x.created_line) for x in opp],
            "own_board": [(x.id, minion_str(x), x.created_line) for x in zone_list(st, lp, "PLAY")],
            "opp_minion_created_lines": sorted(x.created_line for x in opp),
        }


def main():
    path = sys.argv[1]
    d = Deriver()
    st = replay(path, "PowerTaskList", [d.listener])
    out = {"meta": st.meta, "choices": st.choices, "turns": d.turns, "events": d.events, "shops": d.recruit_shops,
           "name_bindings": [(l, "LocalPlayer" if "#" in n else n, e) for l, n, e in st.name_bindings],
           "elapsed": st.elapsed, "lines": st.lines, "final_lobby": lobby(st),
           "final": d.recruit_snapshot(st, st.lines, "EOF"),
           "dead": d.dead, "game_end": d.game_end, "place_changes": d.place_changes}
    if "--json" in sys.argv:
        json.dump(out, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1, default=str)
    print(json.dumps(out, indent=1, default=str))


if __name__ == "__main__":
    main()
