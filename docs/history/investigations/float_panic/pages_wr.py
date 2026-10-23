# write-watch decoder: python3 pages_wr.py 'frames*.png' (dec.py + h1.png in cwd)
import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
P={}
for fn in sorted(glob.glob(A[1])):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); e=b[16:128]+"0000"; h=lambda i,n:int(e[i:i+n],2)
    P[pg]='%2d %s PC=$%06X A=$%06X D=%04X SIZ=%d FC=%d SR=%04X A5=$%06X (writes %d)'%(pg,'first' if pg<8 else 'last ',
        h(0,24),h(24,24),h(48,16),h(64,2),h(66,3),h(69,16),h(85,24),int(b[6:12],2))
for k in sorted(P): print(P[k])
