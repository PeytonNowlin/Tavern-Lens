import json, itertools, math, random, collections, statistics
pool=json.load(open('pool_final.json'))
OTHER=['BEAST','DEMON','DRAGON','ELEMENTAL','MECHANICAL','MURLOC','PIRATE','QUILBOAR','UNDEAD']
W={1:16,2:15,3:13,4:11,5:9,6:7}
SHOP={1:3,2:4,3:4,4:5,5:5,6:6}
CURVE=[1,2,2,3,3,4,4,5,5,6,6,6]   # tavern tier by BG turn (typical-ish)
solo=[p for p in pool.values() if not p['duos'] and p['tier']<=6]
def tribes(p): return [] if 'ALL' in p['races'] else [r for r in p['races']]
hyps=[frozenset({'ABERRATION'}|set(h)) for h in itertools.combinations(OTHER,4)]
def inp(p,H): t=tribes(p); return (not t) or any(r in H for r in t)
den=[[sum(W[p['tier']] for p in solo if inp(p,H) and p['tier']<=t) for t in range(7)] for H in hyps]
EPS=1e-3
def run(rolls_per_turn, trials=1500, seed=1):
    rnd=random.Random(seed); res=[]
    for _ in range(trials):
        Ht=rnd.randrange(len(hyps)); H=hyps[Ht]
        avail=[p for p in solo if inp(p,H)]
        logp=[0.0]*len(hyps); done=None; slots=0
        for turn,tier in enumerate(CURVE,1):
            cand=[p for p in avail if p['tier']<=tier]; wts=[W[p['tier']] for p in cand]
            for r in range(1+(rolls_per_turn if turn>=3 else 0)):
                for p in rnd.choices(cand,wts,k=SHOP[tier]):
                    slots+=1
                    for i,Hh in enumerate(hyps):
                        logp[i]+=math.log(W[p['tier']]/den[i][tier]) if inp(p,Hh) else math.log(EPS)
            m=max(logp); ps=[math.exp(l-m) for l in logp]; s=sum(ps)
            marg={r:sum(pp for pp,Hh in zip(ps,hyps) if r in Hh)/s for r in OTHER}
            if all(v>0.99 or v<0.01 for v in marg.values()):
                ok=all((marg[r]>0.5)==(r in H) for r in OTHER)
                done=(turn,slots,ok); break
        res.append(done or (99,slots,None))
    turns=[d[0] for d in res]; wrong=sum(1 for d in res if d[2] is False)
    q=lambda f: sorted(turns)[int(f*len(turns))-1]
    print(f'rolls/turn={rolls_per_turn}: median turn {statistics.median(turns)}, p75 {q(.75)}, p90 {q(.90)}, p95 {q(.95)}, unresolved by T12 {sum(t==99 for t in turns)}, wrong {wrong}/{len(res)}; dist {sorted(collections.Counter(turns).items())}')
for r in (0,1,2): run(r)
