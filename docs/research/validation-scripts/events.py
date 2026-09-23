import sys
from powerlog import *
stream = sys.argv[1] if len(sys.argv)>1 else 'PowerTaskList'
W = {TAG['TURN'],TAG['BOARD_VISUAL_STATE'],2022,3533,TAG['NEXT_OPPONENT_PLAYER_ID'],TAG['HERO_ENTITY'],TAG['BACON_CURRENT_COMBAT_PLAYER_ID'],TAG['STEP'],TAG['NEXT_STEP'], TAG['CURRENT_PLAYER'],3148,TAG['STATE'],3479, TAG['PLAYSTATE']}
def lis(st, kind, **kw):
    if kind=='tag' and kw['tag'] in W:
        e=kw['ent']
        who = 'Game' if e.id==st.game_id else ('Local' if e.id==st.local_eid() else ('Slot10' if e.id in st.players else f'e{e.id}:{e.card_id}'))
        if kw['old']!=kw['new']:
            print(kw['line'], kw['ts'], who, tname(kw['tag']), kw['old'],'->',kw['new'])
        else:
            print(kw['line'], kw['ts'], who, tname(kw['tag']), '(same)', kw['new'])
replay('/Applications/Hearthstone/Logs/Hearthstone_2026_09_22_20_33_28/Power.log', stream, [lis])
