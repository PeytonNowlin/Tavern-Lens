import sys
from powerlog import replay, TAG
def t2s(t):
    h,m,s=t.split(':'); return int(h)*3600+int(m)*60+float(s)
def collect(stream):
    out={}
    def lis(st,kind,**kw):
        if kind=='tag' and kw['ent'].id==st.game_id:
            if kw['tag']==TAG['TURN']: out[('TURN',kw['new'])]=kw['ts']
            if kw['tag']==2022 and kw['new']==0: out.setdefault(('2022off',st.entities[st.game_id].get('TURN')),kw['ts'])
            if kw['tag']==TAG['STATE'] and kw['new']=='COMPLETE': out[('COMPLETE',0)]=kw['ts']
    replay(sys.argv[1],stream,[lis]); return out
g,p=collect('GameState'),collect('PowerTaskList')
for k in sorted(p, key=lambda k:t2s(p[k])):
    if k in g and (k[0]!='TURN' or k[1]%2==1 or k[0]=='COMPLETE'):
        print(k, 'GS',g[k],'PTL',p[k],'lead %.1fs'%(t2s(p[k])-t2s(g[k])))
