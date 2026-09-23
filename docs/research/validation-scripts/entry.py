import sys,time,os,mmap
p=sys.argv[1]
t=time.perf_counter()
with open(p,'rb') as f:
    mm=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
    a=mm.rfind(b'GameState.DebugPrintPower() - CREATE_GAME')
    b=mm.rfind(b'tag=STATE value=COMPLETE')
    c=mm.rfind(b'End Spectator')
    s=mm.find(b'tag=GAME_SEED value=',a)
t1=time.perf_counter()
print('size',os.path.getsize(p),'lastCreate@',a,'lastComplete@',b,'endSpect@',c,'seed@',s,'rfind ms %.1f'%((t1-t)*1000))
