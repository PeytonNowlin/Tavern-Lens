"""Extract tribe-evidence events from a Power.log: shop draws (dedup frozen carry-overs),
opponent start-of-combat boards, and GENERAL-choice minion options."""
import sys, json, bisect
import os; sys.path.insert(0,os.path.join(os.path.dirname(os.path.abspath(__file__)),'..'))
from powerlog import replay, TAG
CT=TAG['CARDTYPE']; Z=TAG['ZONE']; CTRL=TAG['CONTROLLER']; TURN=TAG['TURN']; CCP=TAG['BACON_CURRENT_COMBAT_PLAYER_ID']
TL=TAG['PLAYER_TECH_LEVEL']; FR=TAG['FROZEN']; POOL=TAG['IS_BACON_POOL_MINION']
path=sys.argv[1]; out=sys.argv[2]
S=dict(seen=set(), shop=[], last_shop=[], prev_frozen=[], carry=None, turn=0, opp=[], opp_seen=set(), attack_seen=False, turn_lines=[])
def on_block(st, kind, **kw):
    if kind=='block_start' and kw.get('btype')=='ATTACK': S['attack_seen']=True
def on_line(st, method, payload, lineno, ts):
    if method!='PowerProcessor.EndCurrentTaskList': return
    g=st.entities.get(st.game_id)
    if not g: return
    turn=g.tags.get(TURN,0)
    if turn!=S['turn']:
        if turn%2==0:   # recruit ended: remember frozen shop
            S['prev_frozen']=[c for (c,f) in S['last_shop'] if f]
        else:
            S['carry']=list(S['prev_frozen']); S['attack_seen']=False
        if turn%2==0: S['attack_seen']=False
        S['turn']=turn; S['turn_lines'].append((lineno,turn))
    slot=st.other_player_eid(); loc=st.local_eid()
    if slot is None: return
    s=st.entities[slot]; spid=st.players[slot]
    tier=st.entities[loc].tags.get(TL)
    ents=[e for e in st.entities.values() if e.tags.get(CTRL)==spid and e.tags.get(Z)=='PLAY' and e.tags.get(CT)=='MINION']
    if turn%2==1 and s.tags.get(CCP,0)==0:
        S['last_shop']=[(e.card_id,e.tags.get(FR,0)) for e in ents]
        for e in sorted(ents,key=lambda e:e.id):
            if e.id in S['seen']: continue
            S['seen'].add(e.id)
            carry=False
            if S['carry'] and e.card_id in S['carry']:
                S['carry'].remove(e.card_id); carry=True
            S['shop'].append(dict(kind='shop',card=e.card_id,bgturn=(turn+1)//2,tier=tier,pool=e.tags.get(POOL),carry=carry,line=lineno))
    elif turn%2==0 and s.tags.get(CCP,0)!=0 and not S['attack_seen']:
        for e in ents:
            if e.id in S['opp_seen']: continue
            S['opp_seen'].add(e.id)
            S['opp'].append(dict(kind='opp',card=e.card_id,bgturn=turn//2,opp=s.tags.get(CCP),pool=e.tags.get(POOL),line=lineno))
st=replay(path,listeners=[on_block],on_line=on_line)
tl=S['turn_lines']; lines=[l for l,_ in tl]
def turn_at(line):
    i=bisect.bisect_right(lines,line)-1
    return tl[i][1] if i>=0 else 1
ch=[]
for c in st.choices.values():
    if c.get('type')!='GENERAL': continue
    for (eid,cid) in c['options']:
        e=st.entities.get(eid)
        if e is None or e.tags.get(CT)!='MINION': continue
        t=turn_at(e.created_line)
        ch.append(dict(kind='choice',card=e.card_id or cid,bgturn=(t+1)//2,pool=e.tags.get(POOL),line=e.created_line))
heroes=[]
PLP=TAG['PLAYER_LEADERBOARD_PLACE']; PID=TAG['PLAYER_ID']
for e in st.entities.values():
    if e.tags.get(CT)=='HERO' and PLP in e.tags: heroes.append((e.tags.get(PID),e.card_id))
json.dump(dict(meta=st.meta,shop=S['shop'],opp=S['opp'],choices=ch,lobby_heroes=sorted(set(heroes)),
   mulligan=[c for c in st.choices.values() if c.get('type')=='MULLIGAN']),open(out,'w'),indent=0)
print(len(S['shop']),sum(x['carry'] for x in S['shop']),len(S['opp']),len(ch))
