import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
P={}
for fn in sorted(glob.glob(A[1])):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); e=b[12:84]; h=lambda i,n:int(e[i:i+n],2)
    P[pg]='%2d vec %3d SR=%04X PC=$%06X A5=$%06X (count %d)'%(pg,h(0,8),h(8,16),h(24,24),h(48,24),int(b[6:12],2))
for k in sorted(P): print(P[k])
