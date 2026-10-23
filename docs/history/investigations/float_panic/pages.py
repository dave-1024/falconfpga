import sys,subprocess
sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
import glob
pages={}
for fn in sorted(glob.glob('pg*.png')):
    r=dec(fn,'h1.png'); bits=r['c']+r['d']+r['e']+r['f']
    if bits[0]!='1': continue
    pg=int(bits[3:6],2); t=bits[6:34]
    e=[bits[34:78],bits[78:122]]
    for k,b in enumerate(e):
        fc=int(b[0:3],2); rw=b[3]; a=int(b[4:28],2); d=int(b[28:44],2)
        pages[2*pg+k]='%2d FC%d %s $%06X %04X'%(2*pg+k,fc,'R' if rw=='1' else 'W',a,d)
    print('trig FC%d %s $%06X'%(int(t[:3],2),t[3],int(t[4:],2)))
for k in sorted(pages): print(pages[k])
