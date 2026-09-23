def X(f,w,h):
    ratio=(4/3)/(w/h); return w*ratio*f + w*(1-ratio)/2
def show(w,h,label):
    print(f"== {label}: {w}x{h}  s=h/1080={h/1080:.4f}  4:3 left={X(0,w,h):.1f} right={X(1,w,h):.1f}")
    tile=h*0.69/8; top=0.15*h
    print(f" leaderboard solo: top={top:.1f} tile={tile:.2f} slots y0..: "+", ".join(f"{top+i*tile:.0f}" for i in range(8))+f" bottom={top+8*tile:.0f}; x={X(0,w,h):.1f}..{X(0,w,h)+tile:.1f}")
    dt=h*0.69*(1-0.137)/8; ds=h*0.69*0.137/3
    print(f" leaderboard duos: tile={dt:.2f} gap={ds:.2f} y: "+", ".join(f"{top+i*dt+(i//2)*ds:.0f}" for i in range(8)))
    mw=w*0.63/7*(4/3)/(w/h); mm=w*(4/3)/(w/h)*0.0029; pitch=mw+2*mm; bh=0.158*h
    ptop=h/2-0.03*h; otop=h/2-bh-0.045*h
    print(f" minion ellipse w={mw:.1f} pitch={pitch:.1f} boardH={bh:.1f}; player row top={ptop:.1f} cy={ptop+bh/2:.1f}; bob/opp row top={otop:.1f} cy={otop+bh/2:.1f}")
    for n in (3,7):
        print(f"  n={n} centres x: "+", ".join(f"{w/2+(k-(n-1)/2)*pitch:.0f}" for k in range(n)))
    s=h/1080
    print(f" shop (pinning) cells {138*s:.1f}x{190*s:.1f} top={300*s:.1f} cy={395*s:.1f}")
    # hero pick trigger
    hx=[0.5-(4*0.165+3*0.075)/2 + i*(0.165+0.075-0.005) for i in range(4)]
    print(" hero pick (trigger) left x: "+", ".join(f"{X(f,w,h):.0f}" for f in hx)+f" w={0.165*4/3*h:.0f} top={0.21*h:.0f} h={0.40*h:.0f}")
    print(" hero stats centres: "+", ".join(f"{w/2+(7+(i-1.5)*340)*s:.0f}" for i in range(4)))
    print(" trinket pick left: "+", ".join(f"{X(0.122+p*0.192,w,h):.0f}" for p in range(4))+f" top={0.28*h:.0f} w={0.25*h:.0f} h={0.35*h:.0f}")
    print(" quest pick left: "+", ".join(f"{X(0.117+p*0.27,w,h):.0f}" for p in range(3))+f" top={0.22*h:.0f} w={0.30*h:.0f} h={0.55*h:.0f}")
    print(f" anomaly badge x={X(0.90,w,h):.0f} y={0.33*h:.0f} w={0.13*h:.0f} h={0.1*h:.0f}")
    print(f" hand centre=({w/2-0.035*h:.0f},{0.95*h:.0f})")
for w,h,l in [(1710,1073,"MacBook notched fullscreen"),(1920,1080,"1080p"),(1440,900-28,"1440x900 windowed (28pt titlebar)"),(2560,1080,"21:9 2560x1080"),(3440,1440,"21:9 3440x1440"),(1440,1080,"exact 4:3")]:
    show(w,h,l)
