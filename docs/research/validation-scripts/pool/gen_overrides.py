import json
from collections import OrderedDict

rules = json.load(open('rd_cards_rules.json'))
cards = {c['id']: c for c in json.load(open('cards.json'))}
FS = {'MECH': 'MECHANICAL'}
def norm(ts):
    return sorted({FS.get(t, t) for t in ts if t})

gates = OrderedDict()
heroes = OrderedDict()
for cid in sorted(rules):
    b = rules[cid].get('bgsMinionTypesRules') or {}
    if not b:
        continue
    c = cards.get(cid, {})
    need = norm(b.get('needTypesInLobby') or [])
    banned = norm(b.get('bannedWithTypesInLobby') or [])
    if c.get('type') == 'HERO':
        if cid.startswith('BGDUO') or cid.endswith('_Tutorial') or not (need or banned):
            continue
        r = OrderedDict()
        if need: r['needs_any'] = need
        if banned: r['banned_with_any'] = banned
        heroes[cid] = r
    elif c.get('type') == 'MINION' and c.get('techLevel') and not c.get('races') and need:
        gates[cid] = need

doc = OrderedDict()
doc['patch'] = '36.6.1'
doc['client_build'] = 251952
doc['valid_from'] = '2026-09-22T17:18:14Z'
doc['tribes_in_rotation'] = ['BEAST', 'DEMON', 'DRAGON', 'ELEMENTAL', 'MECHANICAL', 'MURLOC', 'PIRATE', 'QUILBOAR', 'UNDEAD', 'ABERRATION']
doc['tribes_per_lobby'] = 5
doc['forced_tribes'] = [OrderedDict([('tribe', 'ABERRATION'), ('until', '2026-10-06T17:00:00Z'),
                                     ('note', 'Estimate: Blizzard says "first two weeks ... starting September 22". Confirm when announced.')])]
doc['minion_pool'] = OrderedDict([
    ('BG32_172', 0), ('BG35_140', 0), ('BG25_013', 0),
    ('BG36_369', 1), ('BG36_362', 1), ('BG36_700', 1), ('BG36_364', 1), ('BG36_848', 1),
    ('BG36_366', 1), ('BG36_367', 1), ('BG36_849', 1), ('BG36_370', 1),
    ('BGDUO_700', 1), ('BGDUO_701', 1),
])
doc['minion_notes'] = OrderedDict([
    ('BG32_172', 'Auto Assembler: Blizzard removed list; missing from HSReplay overrides'),
    ('BG35_140', 'Mama Mrrglton: Blizzard removed list; missing from HSReplay overrides'),
    ('BG25_013', 'Rot Hide Gnoll: raw IS_BACON_POOL_MINION is 2 (not in the pool); HearthstoneJSON flattens it to true'),
    ('BG36_369', 'Greedy Conniver: Blizzard new minion'),
    ('BG36_362', 'Sacrificial Wrathguard: Blizzard new minion'),
    ('BG36_700', 'Sewer Escapee: Blizzard new minion'),
    ('BG36_364', 'Hopebringer: Blizzard new minion; seen in a log with pool=1'),
    ('BG36_848', 'Lichling Hoarder: Blizzard new minion'),
    ('BG36_366', 'Resourceful Robot: Blizzard new minion'),
    ('BG36_367', 'Auto Reveille: Blizzard new minion'),
    ('BG36_849', 'Heroic Broodmother: Blizzard new minion; seen in a shop'),
    ('BG36_370', 'Victorious Geomant: Blizzard new minion; seen in a log with pool=1'),
    ('BGDUO_700', 'Voidpriest Cloner: Blizzard new Duos minion'),
    ('BGDUO_701', "C'Thrax Wrecker: Blizzard new Duos minion"),
])
doc['spell_pool'] = OrderedDict([('BG33_899', 0), ('BG35_149', 0), ('BG32_337', 1)])
doc['non_shop'] = ['BGFYM_000', 'BGFYM_011', 'BG36_205']
doc['minion_tribe_gates'] = gates
doc['hero_tribe_rules'] = heroes
doc['special'] = {'BG36_360': 'Dark Paradox: one ALL-type variant per game (t3..t9), tier varies; never tribe evidence'}
doc['disputed'] = {'BG26_537': 'Flourishing Frostling: HSJSON+HSReplay pool, hsbg.cards absent, not on Blizzard lists; keep, watch sightings'}
doc['sources'] = [
    'https://hearthstone.blizzard.com/en-us/news/24302091/aberrations-join-battlegrounds-at-blizzcon',
    'https://hsbg.cards/api/v1/patches/36.4.2_36.6.1',
    'https://github.com/Zero-to-Heroes/hs-reference-data/blob/master/src/cards_rules.json (minion_tribe_gates, hero_tribe_rules)',
    'docs/research/minion-pool-and-tribe-inference.md',
]
print(json.dumps(doc, indent=2, ensure_ascii=False))
print(len(gates), len(heroes), file=__import__('sys').stderr)
