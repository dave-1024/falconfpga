# GEMDOS trace decoder: python3 pages_gd.py 'frames*.png' (dec.py + h1.png); entry starts 4 bits late (as pages_wr.py)
import sys,glob
A=sys.argv[:]; sys.argv=['x']; exec(open('dec.py').read().split('ref=sys.argv[1]')[0])
N={0x48:'Malloc',0x49:'Mfree',0x4a:'Mshrink',0x4b:'Pexec',0x4c:'Pterm',0x3d:'Fopen',0x3f:'Fread',0x3e:'Fclose',0x44:'Mxalloc',0x20:'Super',0x30:'Sversion',0x19:'Dgetdrv',0x47:'Dgetpath',0x3b:'Dsetpath',0x4e:'Fsfirst',0x1a:'Fsetdta',0x2f:'Fgetdta',0x0:'Pterm0',0x31:'Ptermres'}
P={}
for fn in sorted(glob.glob(A[1])):
    r=dec(fn,'h1.png'); b=r['c']+r['d']+r['e']+r['f']
    if b[0]!='1' or b[5]!='1': continue
    pg=int(b[1:5],2); e=b[16:128]+'0000'; h=lambda i,n:int(e[i:i+n],2)
    w=[h(24+16*i,16) for i in range(5)]
    P[pg]='%2d PC=$%06X fn=$%02X %-8s args %04X %04X %04X %04X (calls %d)'%(pg,h(0,24),w[0],N.get(w[0],'?'),w[1],w[2],w[3],w[4],int(b[6:12],2))
for k in sorted(P): print(P[k])
