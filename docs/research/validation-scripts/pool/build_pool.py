import json,collections
bx=json.load(open('bacon.json'))
hjl=json.load(open('cards.json')); hj={c['dbfId']:c for c in hjl}; hid={c['id']:c for c in hjl}
mp=json.load(open('mp.json'))
RACE={20:'BEAST',24:'DRAGON',15:'DEMON',18:'ELEMENTAL',17:'MECHANICAL',14:'MURLOC',23:'PIRATE',43:'QUILBOAR',11:'UNDEAD',126:'ABERRATION',92:'NAGA'}
live={RACE[r] for r in mp['minion_types']}
ov={(o['dbf_id'],o['tag']):o['value'] for o in mp['tag_overrides']}
# our override file (36.6.1)
OUR={ # cardId: IS_BACON_POOL_MINION value, reason
 'BG32_172':(0,'Blizzard removed list; missing from HSReplay overrides'),
 'BG35_140':(0,'Blizzard removed list; missing from HSReplay overrides'),
 'BG36_369':(1,'Blizzard new minion'),'BG36_362':(1,'Blizzard new minion'),'BG36_700':(1,'Blizzard new minion'),
 'BG36_364':(1,'Blizzard new minion; seen in log with pool=1'),'BG36_848':(1,'Blizzard new minion'),
 'BG36_366':(1,'Blizzard new minion'),'BG36_367':(1,'Blizzard new minion'),'BG36_849':(1,'Blizzard new minion; seen in shop'),
 'BG36_370':(1,'Blizzard new minion; seen in log with pool=1'),
 'BGDUO_700':(1,'Blizzard new Duos minion'),'BGDUO_701':(1,'Blizzard new Duos minion'),
}
DUOS={'BGDUO_700','BGDUO_701'}
def tag(x,name,num):
    v=ov.get((x['dbf'],num))
    if v is not None: return v
    t=x['tags'].get(name); return int(t) if t is not None else 0
pool={}; src={}
for x in bx.values():
    cid=hj.get(x['dbf'],{}).get('id',x['id'])
    pv=tag(x,'IS_BACON_POOL_MINION',1456)
    s='hsjson' if (x['dbf'],1456) not in ov else 'hsreplay'
    if cid in OUR: pv=OUR[cid][0]; s='ours'
    if tag(x,'TECH_LEVEL',1440)<=0 or pv!=1: continue
    c=hj.get(x['dbf'],{})
    races=[r for r in (c.get('races') or [])]
    rr=[r for r in races if r!='ALL']
    if rr and not any(r in live for r in rr): continue
    pool[cid]=dict(id=cid,dbf=x['dbf'],name=c.get('name'),tier=tag(x,'TECH_LEVEL',1440),races=races,
        duos=bool(int(x['tags'].get('IS_BACON_DUOS_EXCLUSIVE') or 0)) or cid in DUOS, src=s)
json.dump(pool,open('pool_final.json','w'),indent=0)
solo=[p for p in pool.values() if not p['duos']]
print('total',len(pool),'solo',len(solo),'duos-excl',len(pool)-len(solo))
print('solo per tier',sorted(collections.Counter(p['tier'] for p in solo).items()))
def grp(p):
    rr=[r for r in p['races'] if r!='ALL']
    if 'ALL' in p['races']: return 'ALL (Menagerie)'
    if not rr: return 'Neutral'
    return '/'.join(sorted(rr))
g=collections.Counter(grp(p) for p in solo); print(g)
tt=collections.defaultdict(collections.Counter)
for p in solo: tt[grp(p)][p['tier']]+=1
for k in sorted(tt): print(k, dict(sorted(tt[k].items())), sum(tt[k].values()))
# compare to hsbg
hs=json.load(open('hsbg_all.json'))
hsb={x['externalId']:x for x in hs if x.get('cardType')=='minion' and 'tavern' in (x.get('categories') or [])}
print('only ours',[(k,pool[k]['name']) for k in set(pool)-set(hsb)])
print('only hsbg',[(k,hsb[k]['name']) for k in set(hsb)-set(pool)])
