import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
P={}
for fn in sorted(glob.glob(A[1] if len(A)>1 else 'q*.png')):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); t=b[6:34]; e=b[34:110]
    h=lambda i,n:int(e[i:i+n],2)
    P[pg]='%2d FC%d %s $%06X D=%04X latch@T=%02X adrP=%02X pcL=%02X adrL=%02X'%(pg,h(0,3),'R' if e[3]=='1' else 'W',h(4,24),h(28,16),h(44,8),h(52,8),h(60,8),h(68,8))
    V='vector %d ($%03X) %d cycles before'%(int(b[110:118],2),int(b[110:118],2)*4,int(b[118:122],2))
    T='trig FC%d $%06X'%(int(t[:3],2),int(t[4:],2))
print(T,V) if P else print('none')
for k in sorted(P): print(P[k])
