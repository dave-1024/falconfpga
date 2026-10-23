import re
def gh():
    o=[]
    for l in open('gh.log'):
        mm=re.search(r'(\d+) WR\s+A=([0-9A-F]+) FC=(\d) SIZ=(\d) W=([0-9A-F]+)',l)
        if not mm: continue
        c,a,fc,s,wv=int(mm[1]),int(mm[2],16)&0xFFFFFF,mm[3],int(mm[4]),int(mm[5],16)
        if s==1: o.append((a,(wv>>24)&255 if a%2==0 else (wv>>16)&255,c))
        else:
            a&=~1; o.append((a,(wv>>24)&255,c)); o.append((a+1,(wv>>16)&255,c))
    return o
def mu():
    o=[]
    for i,l in enumerate(open('mu_w.txt')):
        a,wd,v=l.split(); a=int(a,16); wd=int(wd); v=int(v,16); n=[1,2,4][wd]
        for k in range(n): o.append((a+k,(v>>(8*(n-1-k)))&255,i))
    return o
g=[x for x in gh() if not 0x7e00<=x[0]<0x8000]; u=[x for x in mu() if not 0x7e00<=x[0]<0x8000]; print(len(g),len(u))
for i,(x,y) in enumerate(zip(g,u)):
    if x[:2]!=y[:2]:
        print('first diff at byte',i,'gh',hex(x[0]),hex(x[1]),'clk',x[2],' mu',hex(y[0]),hex(y[1]),'mu write#',y[2]); break
else: print('no diff in common prefix')
def norm(s):
    out=[];grp=[]
    for x in s:
        if grp and not (abs(x[0]-grp[0][0])<=3 and len(grp)<4 and x[0] not in [y[0] for y in grp]):
            out+=sorted(grp,key=lambda y:y[0]); grp=[]
        grp.append(x)
    return out+sorted(grp,key=lambda y:y[0])
G2=norm(g);U2=norm(u)
for i,(x,y) in enumerate(zip(G2,U2)):
    if x[:2]!=y[:2]:
        print('NORM first diff at byte',i,'gh',hex(x[0]),hex(x[1]),'clk',x[2],' mu',hex(y[0]),hex(y[1]),'mu write#',y[2]); break
else: print('NORM no diff in common prefix', min(len(G2),len(U2)))
