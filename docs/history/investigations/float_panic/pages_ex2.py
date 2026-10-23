# excwatch V2 decoder: python3 pages_ex2.py 'frames*.png' (needs dec.py and h1.png in cwd)
import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
P={}
for fn in sorted(glob.glob(A[1])):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); e=b[12:84]; x=b[84:128]; h=lambda s,i,n:int(s[i:i+n],2)
    t='%2d vec %3d SR=%04X PC=$%06X IRD=%04X (count %d) | '%(pg,h(e,0,8),h(e,8,16),h(e,24,24),h(e,48,16),h(b,6,6))
    if pg<8: t+='ffrz=%s fetch[%d] A=$%06X D=%04X'%(x[0],pg,h(x,4,24),h(x,28,16))
    elif pg>8: t+='jump[%d] $%06X -> $%06X'%(pg-9,h(x,0,22),h(x,22,22))
    else: t+='snoop $55D18: lastWR=%04X lastFETCH=%04X nWR=%d nFETCH=%d ffrz=%s'%(h(x,0,16),h(x,16,16),h(x,32,4),h(x,36,4),x[43])
    P[pg]=t
for k in sorted(P): print(P[k])
