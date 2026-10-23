exec(open('hmodel.py').read().split("m=mem_init();")[0])
def blitv(m,buf,src,sxi,syi,dst,dxi,dyi,xc,yc,em,skw,mode):
    fxsr=bool(skw&0x80); nfsr=bool(skw&0x40); sk=skw&15; bus=0
    for y in range(yc):
        st=False; hf=False; x=xc
        while True:
            first=(x==xc); mask=em[0] if (first or xc==1) else (em[2] if x==1 else em[1])
            f=False
            if fxsr and not hf: bus=m.get(src,0); buf=((buf<<16)&0xffffffff)|bus; src+=sxi; hf=True
            if not st: bus=m.get(src,0); buf=((buf<<16)&0xffffffff)|bus; f=True
            if mask!=0xffff: bus=m.get(dst,0)
            nf = mode and nfsr and x==1
            if nf: buf=((buf<<16)&0xffffffff)|bus
            lop=(buf>>sk)&0xffff
            out=(lop&mask)|(m.get(dst,0)&~mask&0xffff); m[dst]=out
            if nf and mode>=2: buf=((buf<<16)&0xffffffff)|(lop if mode==2 else out)
            if x==2 and nfsr: st=True
            if f: src+= syi if (x==1 or st) else sxi
            if x==1: dst+=dyi; break
            x-=1; dst+=dxi
    return buf
import sys
ram=[int(l,16) for l in open(sys.argv[1]) if l.strip() and not l.startswith('//')]
for mode in (0,1,2,3):
    m=mem_init(); m[0x18000]=0xa5c3; m[0x18002]=0x3c5a
    b=blitv(m,0,0x18000,2,2,0x18010,2,2,2,1,(0xffff,)*3,0,0)
    b=blitv(m,b,0x10100,2,4,0x21000,2,80,9,5,(0x3fff,0xffff,0xfffc),0x4b,mode)
    m[0x18000]=0xa5c3; m[0x18002]=0x3c5a
    b=blitv(m,b,0x18000,2,2,0x18010,2,2,2,1,(0xffff,)*3,0,0)
    b=blitv(m,b,0x10400,2,2,0x24000,2,60,20,3,(0x00ff,0x0ff0,0xff00),0xc3,mode)
    print('mode',mode,'T6/T7 mismatches vs RTL',[sum(1 for a in range(lo,lo+0x800,2) if m.get(a,0)!=ram[a>>1]) for lo in (0x21000,0x24000)])
