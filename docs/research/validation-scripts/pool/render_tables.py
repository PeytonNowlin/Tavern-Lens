import json,collections
pool=json.load(open('pool_final.json'))
hl=json.load(open('cards.json')); h={c['id']:c for c in hl}
mp=json.load(open('mp.json')); ovd={o['dbf_id'] for o in mp['tag_overrides']}
OURS={'BG36_369','BG36_362','BG36_700','BG36_364','BG36_848','BG36_366','BG36_367','BG36_849','BG36_370','BGDUO_700','BGDUO_701'}
ORDER=['ABERRATION','BEAST','DEMON','DRAGON','ELEMENTAL','MECHANICAL','MURLOC','PIRATE','QUILBOAR','UNDEAD']
def grp(p):
    if 'ALL' in p['races']: return 'All-type (Menagerie)'
    rr=[r.title().replace('Mechanical','Mech') for r in p['races']]
    return '/'.join(sorted(rr)) if rr else 'Neutral'
def fmt(p):
    m=''
    if p['id'] in OURS: m='†'
    elif p['dbf'] in ovd: m='*'
    return f"{p['name']} `{p['id']}`{m}"
out=[]
groups=sorted({grp(p) for p in pool.values()}, key=lambda g:(g in('Neutral','All-type (Menagerie)'),'/' in g,g))
for duo in (False,True):
    ps=[p for p in pool.values() if p['duos']==duo]
    tiers=sorted({p['tier'] for p in ps})
    out.append(('### Duos-exclusive minions (Duos only)' if duo else '### Solo pool (also in Duos)')+'\n')
    if not duo:
        out.append('| Tribe | '+' | '.join(f'T{t}' for t in tiers)+' | Total |')
        out.append('|---|'+'---|'*(len(tiers)+1))
        for g in groups:
            row=[p for p in ps if grp(p)==g]
            if not row: continue
            cells=[]
            for t in tiers:
                cells.append('<br>'.join(fmt(p) for p in sorted(row,key=lambda p:p['name']) if p['tier']==t) or '-')
            out.append(f'| {g} | '+' | '.join(cells)+f' | {len(row)} |')
        cnt=collections.Counter(p['tier'] for p in ps)
        out.append('| **Total** | '+' | '.join(f'**{cnt[t]}**' for t in tiers)+f' | **{len(ps)}** |')
    else:
        out.append('| Tier | Minions |'); out.append('|---|---|')
        for t in tiers:
            out.append(f'| T{t} | '+'; '.join(f"{fmt(p)} ({grp(p)})" for p in sorted(ps,key=lambda p:p['name']) if p['tier']==t)+' |')
    out.append('')
open('pool_table.md','w').write('\n'.join(out))
# spells
sp=[c for c in hl if c.get('isBattlegroundsPoolSpell') and c['id'] not in ('BG33_899','BG35_149')]+[h['BG32_337']]
lines=['| Tier | Tavern spells |','|---|---|']
for t in sorted({c.get('techLevel') for c in sp}):
    lines.append(f'| T{t} | '+'; '.join(f"{c['name']} `{c['id']}`"+('†' if c['id']=='BG32_337' else '')+(' (Duos)' if c.get('isBattlegroundsDuosExclusive') else '') for c in sorted(sp,key=lambda c:c['name']) if c.get('techLevel')==t)+' |')
open('spell_table.md','w').write('\n'.join(lines)+f'\n\nTotal {len(sp)}\n')
# removed with ids
rem="Ancestral Automaton, Auto Assembler, Breakout Mastermind, Captain Cookie, Clunker Junker, Cousin Errgl, Dancing Barnstormer, Deepwater Chieftain, Deflect-o-Bot, Dual-Wield Corsair, Dustbone Devastator, Fire-forged Evoker, Glowing Cinder, Ignition Specialist, Kangor's Apprentice, Mama Mrrglton, Metallic Hunter, Meteorite Crasher, Moat Custodian, Molten Rock, Motley Phalanx, Nomi, Kitchen Nightmare, Oozeling Gladiator, Papa Mrrglton, Primitive Painter, Private Investigator, River Skipper, Sand Swirler, Scrap Scraper, Sly Raptor, Thousandth Paper Drake, Unleashed Mana Surge, Vigilant Bristlemane, Void Pup Trainer, Warpwing"
names=[]; buf=rem.split(', ')
i=0
while i<len(buf):
    if buf[i]=='Nomi': names.append('Nomi, Kitchen Nightmare'); i+=2
    else: names.append(buf[i]); i+=1
naga="Fleeing Fugitive, Mini-Myrmidon, Lava Lurker, Shell Collector, Thaumaturgist, Deep-Sea Angler, Waverider, Abyssal Bruiser, Cagey Conjurer, Private Chef, Rimescale Priestess, Seafloor Recruiter, Zesty Shaker, Darkcrest Strategist, Glowscale, Showy Cyclist, Storm Splitter, Tranquil Meditative, Fauna Whisperer, Groundbreaker, Torrential Ruiner, Sea Witch Zar'jira".split(', ')
def ids(n):
    xs=[c for c in hl if c.get('name')==n and c.get('isBattlegroundsPoolMinion')]
    return xs
hr={o['dbf_id'] for o in mp['tag_overrides'] if o['value']==0}
L=['| Card | cardId | Tier | Type | HSReplay override? |','|---|---|---|---|---|']
for n in names:
    for c in ids(n): L.append(f"| {n} | `{c['id']}` | {c.get('techLevel')} | {'/'.join(c.get('races') or ['Neutral']).title()} | {'yes' if c['dbfId'] in hr else '**no (ours)**'} |")
L2=['| Card | cardId | Tier | Type |','|---|---|---|---|']
for n in naga:
    for c in ids(n): L2.append(f"| {n} | `{c['id']}` | {c.get('techLevel')} | {'/'.join(c.get('races')).title()} |")
nagaall=[c for c in hl if c.get('isBattlegroundsPoolMinion') and 'NAGA' in (c.get('races') or [])]
open('removed.md','w').write('\n'.join(L)+'\n\n'+'\n'.join(L2)+'\n\nNaga-typed pool cards in 251952: '+', '.join(f"{c['name']} `{c['id']}` {c.get('races')}" for c in nagaall))
print(len(names), len(L)-2, len(L2)-2, len(nagaall))
