"""python3 bench.py <Power.log> ... : median of 5 warm runs per stage."""
import time, statistics, sys, os
from powerlog import replay
import timeline
def run(f, n=5):
    ts=[]
    for _ in range(n):
        t=time.perf_counter(); f(); ts.append(time.perf_counter()-t)
    return statistics.median(ts)
print('python', sys.version.split()[0])
for P in sys.argv[1:]:
    size=os.path.getsize(P); nl=sum(1 for _ in open(P,'rb'))
    print(f'{os.path.basename(os.path.dirname(P))}: {size/1e6:.1f} MB, {nl:,} lines')
    def raw():
        with open(P,'rb') as fh:
            for l in fh: l.decode('utf-8','replace')
    for name,f in [('read+decode only',raw),('entity store (PTL)',lambda: replay(P)),
                   ('store + BG derivation',lambda: replay(P,'PowerTaskList',[timeline.Deriver().listener]))]:
        med=run(f)
        print(f"  {name:24s} {med*1000:8.1f} ms  {nl/med:12,.0f} lines/s  {size/med/1e6:7.1f} MB/s")
