import json, itertools, math, sys, collections
pool=json.load(open('pool_final.json'))
hid={c['id']:c for c in json.load(open('cards.json'))}
OTHER=['BEAST','DEMON','DRAGON','ELEMENTAL','MECHANICAL','MURLOC','PIRATE','QUILBOAR','UNDEAD']
FORCED={'ABERRATION'}
K=4   # 5 tribes per lobby, Aberration forced -> 4 of the other 9
W={1:16,2:15,3:13,4:11,5:9,6:7,7:0}   # assumed copies per tier (only relative weights matter)
if len(sys.argv)>2 and sys.argv[2]=='uniform': W={t:1 for t in W}
EPS_SHOP=1e-3; EPS_CONF=0.02
def base(cid):
    c=hid.get(cid,{})
    if cid.endswith('_G') and c.get('battlegroundsNormalDbfId'):
        for x in hid.values():
            if x.get('dbfId')==c['battlegroundsNormalDbfId']: return x['id']
    return cid
solo={k:v for k,v in pool.items() if not v['duos']}
def tribes(p): return [r for r in p['races'] if r!='ALL'] if 'ALL' not in p['races'] else []
hyps=[frozenset(FORCED|set(h)) for h in itertools.combinations(OTHER,K)]
def in_pool(p,H):
    t=tribes(p); return (not t) or any(r in H for r in t)
denom={}
for i,H in enumerate(hyps):
    acc=[0]*8
    for p in solo.values():
        if in_pool(p,H) and p['tier']<=6: acc[p['tier']]+=W[p['tier']]
    denom[i]=[sum(acc[1:t+1]) for t in range(8)]
logp=[0.0]*len(hyps)
def post():
    m=max(logp); ps=[math.exp(l-m) for l in logp]; s=sum(ps); return [p/s for p in ps]
def marg():
    ps=post(); return {r:sum(p for p,H in zip(ps,hyps) if r in H) for r in OTHER}
ev=json.load(open(sys.argv[1]))
mode=sys.argv[3] if len(sys.argv)>3 else 'all'
events=[e for e in ev['shop'] if not e['carry']]
if mode=='all': events+=ev['opp']+ev['choices']
events.sort(key=lambda e:e['line'])
confirmed=set(); first_conf={}
rows=[]; unknown=[]
n_shop=0; resolved_at=None
for e in events:
    cid=base(e['card']); p=solo.get(cid)
    if p is None:
        if e['kind']=='shop': unknown.append((e['bgturn'],cid,hid.get(cid,{}).get('name')))
        continue
    t=tribes(p)
    if e['kind']=='shop':
        n_shop+=1
        tier=min(e['tier'] or 1,6)
        for i,H in enumerate(hyps):
            logp[i]+= math.log(W[p['tier']]/denom[i][tier]) if in_pool(p,H) else math.log(EPS_SHOP)
    else:
        if e.get('pool')!=1: continue
        for i,H in enumerate(hyps):
            logp[i]+= 0.0 if in_pool(p,H) else math.log(EPS_CONF)
    if len(t)==1 and t[0] in OTHER and t[0] not in confirmed:
        confirmed.add(t[0]); first_conf[t[0]]=(e['bgturn'],e['kind'],p['name'],n_shop)
    m=marg()
    if resolved_at is None and all(v>0.99 or v<0.01 for v in m.values()):
        resolved_at=(e['bgturn'],e['kind'],n_shop)
    rows.append((e['bgturn'],e['kind'],p['name'],m))
# per-turn summary: state at end of each BG turn
last={}
for r in rows: last[r[0]]=r
print('unknown shop cards (not in pool table):',unknown)
print('first confirmation per tribe:',first_conf)
print('resolved (all tribes P>0.99 or <0.01) at:',resolved_at)
for t in sorted(last):
    m=last[t][3]
    print('T%-2d'%t,' '.join('%s=%.2f'%(r[:4],m[r]) for r in OTHER))
ps=post(); best=max(range(len(hyps)),key=lambda i:ps[i]); print('MAP',sorted(hyps[best]),'%.4f'%ps[best])
