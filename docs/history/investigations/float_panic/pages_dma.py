# dma-watch decoder (DIAG_DMAWATCH): python3 pages_dma.py 'frames*.png' (dec.py + h1.png in cwd)
# page 0 = newest RAM write into $55C96-$55D21 before the vector-6 freeze; src = DMA/BLIT/BGACK flags
import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
P={}
for fn in sorted(glob.glob(A[1])):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); e=b[16:128]+"0000"; h=lambda i,n:int(e[i:i+n],2)
    src=[n for n,i in (('DMA',0),('BLIT',1),('BGACK',2)) if e[i]=='1'] or ['CPU']
    P[pg]='%2d %-9s A=$%06X D=%04X U%d L%d t=%d (writes %d)'%(pg,'+'.join(src),h(4,24),h(28,16),h(44,1),h(45,1),h(46,32),int(b[6:12],2))
for k in sorted(P): print(P[k])
