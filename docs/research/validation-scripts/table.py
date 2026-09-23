"""Render timeline JSON (from timeline.py --json) as Markdown tables. python3 table.py out.json"""
import json, sys
o = json.load(open(sys.argv[1]))
def pidhero(lobby, pid):
    for x in lobby:
        if x['pid'] == pid: return x['hero']
    return '?'
print("| BG turn | Recruit start (PTL) | Hero HP (start → after combat) | Gold | Tier | Own board at end of recruit | Hand | Shop at end of recruit | Opponent (PlayerID → hero) | Opponent board at combat (tag 2022 1→0) | Place after combat |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
prev_hp = None
for n, t in sorted(o['turns'].items(), key=lambda kv: int(kv[0])):
    r = t.get('recruit_end'); c = t.get('combat_2022_off') or {}
    if not r:
        r = o['final']; note = " (log ends mid-recruit)"
    else: note = ""
    lob = r['lobby']
    opp = t.get('combat_player_id') or r['next_opp_pid']
    after = t.get('post_combat_local_hp')
    place = next((x['place'] for x in t.get('post_combat_lobby', []) if x['pid'] == next(y['pid'] for y in lob if y['hero'] == r['hero'])), '—')
    g = r['gold']
    gold = f"{g['RESOURCES']} (used {g['RESOURCES_USED']}{', temp '+str(g['TEMP_RESOURCES']) if g['TEMP_RESOURCES'] else ''})"
    board = "; ".join(x[1] for x in r['board']) or "—"
    hand = "; ".join(x[1] for x in r['hand']) or "—"
    shop = "; ".join(x[1] for x in r['shop']) or "—"
    oppb = "; ".join(x[1] for x in c.get('opp_board', [])) or "—"
    hp0 = prev_hp if prev_hp is not None else r['hero_hp']
    print(f"| {n}{note} | {t.get('recruit_start_ts','')[:8]} | {hp0} → {after if after is not None else '—'} | {gold} | {r['tier']} | {board} | {hand} | {shop} | P{opp} → {pidhero(lob, opp)} | {oppb} | {place} |")
    prev_hp = after
print()
last = None
for n, t in sorted(o['turns'].items(), key=lambda kv: int(kv[0])):
    if 'post_combat_lobby' in t: last = (n, t['post_combat_lobby'])
if o.get('game_end'):
    rows = o['game_end']['lobby']; label = f"at STATE=COMPLETE (BG turn {o['game_end']['bg_turn']})"
else:
    rows = o['final_lobby']; label = "at end of log"
print(f"Lobby {label}:\n")
print("| Place | PlayerID | Hero | HP+armor | Tier | Triples | Hero entity / zone |")
print("|---|---|---|---|---|---|---|")
for x in rows:
    print(f"| {x['place']} | {x['pid']} | {x['hero']} | {x['hp']} | {x['tier']} | {x['triples']} | {x['eid']} / {x['zone']} |")
