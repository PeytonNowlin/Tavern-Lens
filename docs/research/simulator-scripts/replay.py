#!/usr/bin/env python3
"""Minimal PowerTaskList replayer: builds entity/tag state up to a line number and dumps
both BG boards in the shape Firestone's parser uses. Read-only on the log."""
import re, sys, json

LOG = sys.argv[1]
STOP = int(sys.argv[2])
LOCAL_PID = int(sys.argv[3]) if len(sys.argv) > 3 else 2  # 1-based line number, inclusive
PREFIX = "PowerTaskList.DebugPrintPower() - "

ents = {}      # id -> {"cardId": str, "tags": {name: value}}
names = {}     # player name -> entity id
pid_to_ent = {}

re_id = re.compile(r"\bid=(\d+)")
re_tag = re.compile(r"tag=(\S+) value=(\S*)")

def ival(v):
    try:
        return int(v)
    except ValueError:
        return v

def resolve(ref):
    ref = ref.strip()
    if ref == "GameEntity":
        return game_entity
    if ref.startswith("["):
        m = re_id.search(ref)
        return int(m.group(1)) if m else None
    if ref.isdigit():
        return int(ref)
    if ref in names:
        return names[ref]
    # BG: only two Player entities exist; any other name is the opponent slot (its name changes per opponent)
    local = pid_to_ent.get(LOCAL_PID)
    others = [e for p, e in pid_to_ent.items() if p != LOCAL_PID]
    return others[0] if others else None

cur = None
game_entity = None
name_by_pid = {}
unresolved = {}
with open(LOG, encoding="utf-8", errors="replace") as f:
    for n, line in enumerate(f, 1):
        if n > STOP:
            break
        m = re.search(r"DebugPrintGame\(\) - PlayerID=(\d+), PlayerName=(.*)$", line)
        if m:
            name_by_pid[int(m.group(1))] = m.group(2).strip()
with open(LOG, encoding="utf-8", errors="replace") as f:
    for n, line in enumerate(f, 1):
        if n > STOP:
            break
        i = line.find(PREFIX)
        if i < 0:
            continue
        body = line[i + len(PREFIX):].rstrip("\n")
        s = body.strip()
        if s == "CREATE_GAME":
            ents.clear(); pid_to_ent.clear(); cur = None
            continue
        m = re.match(r"GameEntity EntityID=(\d+)", s)
        if m:
            game_entity = int(m.group(1)); cur = game_entity
            ents[cur] = {"cardId": "GameEntity", "tags": {}}
            continue
        m = re.match(r"Player EntityID=(\d+) PlayerID=(\d+)", s)
        if m:
            cur = int(m.group(1)); ents[cur] = {"cardId": "Player", "tags": {"PLAYER_ID": int(m.group(2))}}
            pid_to_ent[int(m.group(2))] = cur
            if int(m.group(2)) in name_by_pid:
                names[name_by_pid[int(m.group(2))]] = cur
            continue
        m = re.match(r"(FULL_ENTITY - (?:Creating|Updating)|SHOW_ENTITY - Updating|CHANGE_ENTITY - Updating) (?:Entity=)?(.*) CardID=(\S*)$", s)
        if m:
            ref = m.group(2)
            eid = int(ref.split("=")[1]) if ref.startswith("ID=") else resolve(ref)
            e = ents.setdefault(eid, {"cardId": "", "tags": {}})
            if m.group(3):
                e["cardId"] = m.group(3)
            cur = eid
            continue
        m = re.match(r"HIDE_ENTITY - Entity=(.*) tag=(\S+) value=(\S+)", s)
        if m:
            eid = resolve(m.group(1))
            if eid in ents:
                ents[eid]["tags"][m.group(2)] = ival(m.group(3))
            cur = None
            continue
        m = re.match(r"TAG_CHANGE Entity=(.*) tag=(\S+) value=(\S*)", s)
        if m:
            ref = m.group(1)
            eid = resolve(ref)
            if eid is None and not ref.startswith("["):
                # unknown player name: bind lazily if the tag is PLAYER-ish (first sighting)
                eid = None
            if eid is None:
                unresolved[ref] = unresolved.get(ref, 0) + 1
            if eid is not None:
                ents.setdefault(eid, {"cardId": "", "tags": {}})["tags"][m.group(2)] = ival(m.group(3))
            cur = None
            continue
        m = re.match(r"tag=(\S+) value=(\S*)$", s)
        if m and cur is not None:
            ents[cur]["tags"][m.group(1)] = ival(m.group(2))
            continue
        if s.startswith(("BLOCK_START", "BLOCK_END", "META_DATA", "SUB_SPELL", "Info[", "Source", "Target")):
            cur = None if s.startswith(("BLOCK", "META", "SUB_SPELL")) else cur

json.dump({"unresolvedCount": sum(unresolved.values()), "unresolvedRefs": len(unresolved), "gameEntity": game_entity, "pidToEnt": pid_to_ent, "ents": ents}, sys.stdout)
