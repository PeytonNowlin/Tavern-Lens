"""Minimal throwaway Power.log parser + entity/tag store.

Usage: from powerlog import replay; store = replay(path, stream="PowerTaskList")
Tags are canonicalised to ints via enums.json GameTag (unknown names kept as str,
numeric tags like tag=2022 become int 2022). Values: int when numeric, else str.
"""
import json, os, re, sys, time
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ENUMS = json.load(open(os.path.join(HERE, "enums.json")))
TAG = ENUMS["GameTag"]                        # name -> int
TAGNAME = {}
for k, v in TAG.items():
    TAGNAME.setdefault(v, k)

LINE_RE = re.compile(r"^([DWE]) (\d\d:\d\d:\d\d\.\d+) ([\w.]+)\(\) - (.*)$")
# bracket entity; entityName may contain spaces, commas and even nested [..]
BRACKET_RE = re.compile(r"^\[entityName=(.*) id=(\d+) zone=(\w+) zonePos=(\d+) cardId=(\S*) player=(\d+)\]$")
TAGVAL_RE = re.compile(r"^tag=(\S+) value=(\S*)$")
TAG_CHANGE_RE = re.compile(r"^TAG_CHANGE Entity=(.+?) tag=(\S+) value=(\S*)\s*(DEF CHANGE)?\s*$")
FULL_CREATING_RE = re.compile(r"^FULL_ENTITY - Creating ID=(\d+) CardID=(\S*)$")
FULL_UPDATING_RE = re.compile(r"^FULL_ENTITY - Updating (.+) CardID=(\S*)$")
SHOW_RE = re.compile(r"^SHOW_ENTITY - Updating Entity=(.+) CardID=(\S*)$")
CHANGE_RE = re.compile(r"^CHANGE_ENTITY - Updating Entity=(.+) CardID=(\S*)$")
HIDE_RE = re.compile(r"^HIDE_ENTITY - Entity=(.+) tag=(\S+) value=(\S*)$")
GAMEENTITY_RE = re.compile(r"^GameEntity EntityID=(\d+)$")
PLAYER_RE = re.compile(r"^Player EntityID=(\d+) PlayerID=(\d+) GameAccountId=\[hi=(\d+) lo=(\d+)\]$")
BLOCK_START_RE = re.compile(r"^BLOCK_START BlockType=(\w+) Entity=(.+?) EffectCardId=(.*?) EffectIndex=(-?\d+) Target=(.+?) SubOption=(-?\d+)(?: TriggerKeyword=(\S+))?\s*$")
GAME_META_RE = re.compile(r"^(BuildNumber|GameType|FormatType|ScenarioID)=(\S+)$")
GAME_PLAYER_RE = re.compile(r"^PlayerID=(\d+), PlayerName=(.*)$")
CHOICES_HDR_RE = re.compile(r"^id=(\d+) Player=(.+?) TaskList=(\d+) ChoiceType=(\w+) CountMin=(\d+) CountMax=(\d+)$")
CHOSEN_HDR_RE = re.compile(r"^id=(\d+) Player=(.+?) EntitiesCount=(\d+)$")
CHOICE_ENT_RE = re.compile(r"^Entities\[(\d+)\]=(.+)$")


def canon_tag(t):
    if t.isdigit():
        return int(t)
    return TAG.get(t, t)


def canon_val(v):
    if v.lstrip("-").isdigit():
        return int(v)
    return v


def tname(t):
    return TAGNAME.get(t, str(t)) if isinstance(t, int) else t


class Entity:
    __slots__ = ("id", "card_id", "tags", "name", "created_line")

    def __init__(self, eid, card_id="", line=0):
        self.id = eid
        self.card_id = card_id
        self.tags = {}
        self.name = None
        self.created_line = line

    def get(self, tag, default=None):
        if isinstance(tag, str):
            tag = TAG.get(tag, tag)
        return self.tags.get(tag, default)


class Store:
    def __init__(self):
        self.reset()
        self.stats = Counter()
        self.unknown_tag_names = Counter()
        self.unresolved_refs = Counter()
        self.name_bindings = []          # (line, name, entity id)
        self.listeners = []              # f(store, kind, **kw)
        self.games = 0

    def reset(self):
        self.entities = {}
        self.game_id = None
        self.players = {}                # entity id -> player id
        self.player_eid = {}             # player id -> entity id
        self.account = {}                # entity id -> (hi, lo)
        self.names = {}                  # name -> entity id
        self.meta = {}
        self.player_names = {}           # PlayerID -> name (DebugPrintGame)
        self.current = None              # entity receiving indented tag= lines
        self.choices = {}
        self._pending_choice = None

    # ---- helpers
    def emit(self, kind, **kw):
        for f in self.listeners:
            f(self, kind, **kw)

    def local_eid(self):
        for eid, (hi, lo) in self.account.items():
            if hi != 0 or lo != 0:
                return eid
        return None

    def other_player_eid(self):
        loc = self.local_eid()
        for eid in self.players:
            if eid != loc:
                return eid
        return None

    def resolve(self, ref, lineno):
        ref = ref.strip()
        if ref == "GameEntity":
            return self.game_id
        if ref.isdigit():
            return int(ref)
        if ref.startswith("["):
            m = BRACKET_RE.match(ref)
            if m:
                return int(m.group(2))
            self.unresolved_refs["bad-bracket"] += 1
            return None
        # a player name
        eid = self.names.get(ref)
        if eid is not None:
            return eid
        # bind unknown names: local BattleTag (from DebugPrintGame) else the other slot
        loc = self.local_eid()
        local_name = self.player_names.get(self.players.get(loc)) if loc else None
        if ref == local_name:
            eid = loc
        else:
            eid = self.other_player_eid()
            self.unresolved_refs["bound-to-other-player"] += 1
        self.names[ref] = eid
        self.name_bindings.append((lineno, ref, eid))
        return eid

    def ent(self, eid, lineno):
        e = self.entities.get(eid)
        if e is None:
            e = Entity(eid, "", lineno)
            self.entities[eid] = e
            self.stats["implicit-entity"] += 1
        return e

    def set_tag(self, e, tag, val, lineno, ts, kind="tag"):
        old = e.tags.get(tag)
        e.tags[tag] = val
        if kind == "change":
            self.emit("tag", ent=e, tag=tag, old=old, new=val, line=lineno, ts=ts)

    # ---- line handlers
    def feed_power(self, payload, lineno, ts):
        stripped = payload.lstrip(" ")
        if stripped.startswith("tag="):
            m = TAGVAL_RE.match(stripped.rstrip())
            if m and self.current is not None:
                t = canon_tag(m.group(1))
                if isinstance(t, str):
                    self.unknown_tag_names[t] += 1
                self.set_tag(self.current, t, canon_val(m.group(2)), lineno, ts)
                self.stats["tag"] += 1
            else:
                self.stats["orphan-tag"] += 1
            return
        self.current = None
        s = stripped.rstrip()
        if s.startswith("TAG_CHANGE"):
            m = TAG_CHANGE_RE.match(s)
            if not m:
                self.stats["bad-tag-change"] += 1
                return
            eid = self.resolve(m.group(1), lineno)
            if eid is None:
                return
            t = canon_tag(m.group(2))
            if isinstance(t, str):
                self.unknown_tag_names[t] += 1
            if m.group(4):
                self.stats["def-change"] += 1
            self.set_tag(self.ent(eid, lineno), t, canon_val(m.group(3)), lineno, ts, "change")
            self.stats["TAG_CHANGE"] += 1
            return
        if s.startswith("FULL_ENTITY"):
            m = FULL_UPDATING_RE.match(s) or FULL_CREATING_RE.match(s)
            if not m:
                self.stats["bad-full"] += 1
                return
            eid = self.resolve(m.group(1), lineno)
            existed = eid in self.entities
            e = Entity(eid, m.group(2), lineno)
            if existed:
                self.stats["full-entity-reused-id"] += 1
                e.tags = self.entities[eid].tags  # keep, then overwrite
            self.entities[eid] = e
            bm = BRACKET_RE.match(m.group(1).strip())
            if bm:
                e.name = bm.group(1)
            self.current = e
            self.stats["FULL_ENTITY"] += 1
            self.emit("full", ent=e, line=lineno, ts=ts)
            return
        if s.startswith("SHOW_ENTITY"):
            m = SHOW_RE.match(s)
            eid = self.resolve(m.group(1), lineno)
            e = self.ent(eid, lineno)
            e.card_id = m.group(2)
            self.current = e
            self.stats["SHOW_ENTITY"] += 1
            self.emit("show", ent=e, line=lineno, ts=ts)
            return
        if s.startswith("CHANGE_ENTITY"):
            m = CHANGE_RE.match(s)
            eid = self.resolve(m.group(1), lineno)
            e = self.ent(eid, lineno)
            e.card_id = m.group(2)
            self.current = e
            self.stats["CHANGE_ENTITY"] += 1
            return
        if s.startswith("HIDE_ENTITY"):
            m = HIDE_RE.match(s)
            eid = self.resolve(m.group(1), lineno)
            e = self.ent(eid, lineno)
            self.set_tag(e, canon_tag(m.group(2)), canon_val(m.group(3)), lineno, ts, "change")
            self.stats["HIDE_ENTITY"] += 1
            return
        if s == "CREATE_GAME":
            self.games += 1
            listeners, stats, unk, unres, nb, games = (self.listeners, self.stats, self.unknown_tag_names,
                                                        self.unresolved_refs, self.name_bindings, self.games)
            meta, pnames = self.meta, self.player_names
            self.reset()
            # DebugPrintGame (GameState) arrives *before* the PowerTaskList CREATE_GAME; keep it
            self.meta, self.player_names = meta, pnames
            self.stats["CREATE_GAME"] += 1
            self.emit("create_game", line=lineno, ts=ts)
            return
        m = GAMEENTITY_RE.match(s)
        if m:
            eid = int(m.group(1))
            self.game_id = eid
            e = Entity(eid, "", lineno); e.name = "GameEntity"
            self.entities[eid] = e
            self.current = e
            return
        m = PLAYER_RE.match(s)
        if m:
            eid, pid = int(m.group(1)), int(m.group(2))
            e = Entity(eid, "", lineno)
            self.entities[eid] = e
            self.players[eid] = pid
            self.player_eid[pid] = eid
            self.account[eid] = (int(m.group(3)), int(m.group(4)))
            self.current = e
            return
        if s.startswith("BLOCK_START"):
            m = BLOCK_START_RE.match(s)
            if not m:
                self.stats["bad-block-start"] += 1
                return
            self.stats["BLOCK_START"] += 1
            self.emit("block_start", btype=m.group(1), ent=m.group(2), line=lineno, ts=ts)
            return
        head = s.split(" ", 1)[0]
        self.stats[head] += 1

    def feed_game(self, payload):
        m = GAME_META_RE.match(payload)
        if m:
            self.meta[m.group(1)] = m.group(2)
            return
        m = GAME_PLAYER_RE.match(payload)
        if m:
            self.player_names[int(m.group(1))] = m.group(2)

    def feed_choices(self, method, payload, lineno, ts):
        p = payload.strip()
        if method == "GameState.DebugPrintEntityChoices":
            m = CHOICES_HDR_RE.match(p)
            if m:
                self._pending_choice = {"id": int(m.group(1)), "type": m.group(4), "options": [], "chosen": [], "line": lineno, "ts": ts}
                self.choices[int(m.group(1))] = self._pending_choice
                return
            m = CHOICE_ENT_RE.match(p)
            if m and self._pending_choice:
                bm = BRACKET_RE.match(m.group(2))
                self._pending_choice["options"].append((int(bm.group(2)), bm.group(5)) if bm else m.group(2))
        elif method == "GameState.DebugPrintEntitiesChosen":
            m = CHOSEN_HDR_RE.match(p)
            if m:
                self._pending_choice = self.choices.setdefault(int(m.group(1)), {"id": int(m.group(1)), "options": [], "chosen": []})
                self._pending_choice["chosen_line"] = lineno
                return
            m = CHOICE_ENT_RE.match(p)
            if m and self._pending_choice:
                bm = BRACKET_RE.match(m.group(2))
                self._pending_choice["chosen"].append((int(bm.group(2)), bm.group(5)) if bm else m.group(2))


def replay(path, stream="PowerTaskList", listeners=(), on_line=None):
    """stream: 'PowerTaskList' or 'GameState' decides which DebugPrintPower feeds the store."""
    st = Store()
    st.listeners.extend(listeners)
    power_method = stream + ".DebugPrintPower"
    t0 = time.perf_counter()
    n = 0
    with open(path, "rb") as f:
        for lineno, raw in enumerate(f, 1):
            n += 1
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            m = LINE_RE.match(line)
            if not m:
                st.stats["unparsable-line"] += 1
                continue
            _lvl, ts, method, payload = m.groups()
            if method == power_method:
                st.feed_power(payload, lineno, ts)
            elif method == "GameState.DebugPrintGame":
                st.feed_game(payload)
            elif method in ("GameState.DebugPrintEntityChoices", "GameState.DebugPrintEntitiesChosen"):
                st.feed_choices(method, payload, lineno, ts)
            if on_line:
                on_line(st, method, payload, lineno, ts)
    st.elapsed = time.perf_counter() - t0
    st.lines = n
    return st


if __name__ == "__main__":
    p = sys.argv[1]
    for stream in ("PowerTaskList", "GameState"):
        st = replay(p, stream)
        print(stream, f"{st.lines} lines in {st.elapsed:.3f}s = {st.lines/st.elapsed:,.0f} lines/s; entities={len(st.entities)}")
        print("  stats", dict(st.stats))
        print("  unknown tag names", dict(st.unknown_tag_names))
        print("  unresolved", dict(st.unresolved_refs))
