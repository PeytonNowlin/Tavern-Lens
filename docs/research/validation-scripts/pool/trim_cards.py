"""Trim HearthstoneJSON cards.json (build 251952) to what the pool and tribe tests need:
pool-candidate minions (flagged, or named by an HSReplay/our override) and their goldens,
pool spells, BG heroes and their skins, and every BG minion or hero whose ID appears in the
fixture logs (IDs only; no log content)."""
import json, sys
cards = json.load(open('cards.json'))
mp = json.load(open('mp.json'))
ov = json.load(open('overrides.json'))
logids = set(open('logcards.txt').read().split())
ovdbf = {o['dbf_id'] for o in mp['tag_overrides']}
ovid = set(ov['minion_pool']) | set(ov['spell_pool']) | set(ov['minion_tribe_gates']) | set(ov['non_shop'])
KEEP = ['id', 'dbfId', 'name', 'type', 'techLevel', 'races', 'isBattlegroundsPoolMinion', 'isBattlegroundsPoolSpell',
        'isBattlegroundsDuosExclusive', 'battlegroundsNormalDbfId', 'battlegroundsPremiumDbfId', 'battlegroundsHero',
        'battlegroundsSkinParentId']
bydbf = {c['dbfId']: c for c in cards}
keep = {}
for c in cards:
    t = c.get('type')
    tl = (c.get('techLevel') or 0) > 0
    cand = c.get('isBattlegroundsPoolMinion') or c.get('isBattlegroundsPoolSpell') or c['dbfId'] in ovdbf or c['id'] in ovid
    if (t == 'MINION' and tl and (cand or c['id'] in logids)) or (t == 'BATTLEGROUND_SPELL' and cand):
        keep[c['dbfId']] = c
    elif t == 'HERO' and (c.get('battlegroundsHero') or c.get('battlegroundsSkinParentId')):
        keep[c['dbfId']] = c
for c in list(keep.values()):
    g = c.get('battlegroundsPremiumDbfId')
    if g and g in bydbf: keep[g] = bydbf[g]
out = sorted(keep.values(), key=lambda c: c['dbfId'])
out = [{k: c[k] for k in KEEP if k in c} for c in out]
s = '[\n' + ',\n'.join(json.dumps(c, separators=(',', ':'), ensure_ascii=False) for c in out) + '\n]\n'
open(sys.argv[1], 'w').write(s)
print(len(out), len(s))
