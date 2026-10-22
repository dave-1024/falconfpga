# Hatari blitter.c (src/blitter.c, main) word loop, HOP=2 OP=3, positive increments; memory = dict of words
import sys
def mem_init():
    m={}; d=0x12345678
    for i in range(512):
        d^=(d<<13)&0xffffffff; d^=d>>17; d^=(d<<5)&0xffffffff
        v=(~d)&0xffffffff
        for base,w in ((0x10000,d),(0x21000,v),(0x24000,v)):
            m[base+4*i]=w>>16; m[base+4*i+2]=w&0xffff
    return m
def blit(m,buf,src,sxi,syi,dst,dxi,dyi,xc,yc,em,skw):
    fxsr=bool(skw&0x80); nfsr=bool(skw&0x40); sk=skw&15
    for y in range(yc):
        st_nfsr=False; have_fxsr=False; x=xc
        while True:
            first=(x==xc)
            mask=em[0] if (first or xc==1) else (em[2] if x==1 else em[1])
            fetched=False
            if fxsr and not have_fxsr:
                buf=((buf<<16)&0xffffffff)|m.get(src,0); src+=sxi; have_fxsr=True
            if not st_nfsr:
                buf=((buf<<16)&0xffffffff)|m.get(src,0); fetched=True
            lop=(buf>>sk)&0xffff
            m[dst]=(lop&mask)|(m.get(dst,0)&~mask&0xffff) if mask!=0xffff else lop
            if x==2 and nfsr: st_nfsr=True
            if fetched: src+= syi if (x==1 or st_nfsr) else sxi
            if x==1: dst+=dyi; break
            x-=1; dst+=dxi
    return buf
m=mem_init(); m[0x18000]=0xa5c3; m[0x18002]=0x3c5a
b=blit(m,0,0x18000,2,2,0x18010,2,2,2,1,(0xffff,)*3,0)  # primer (src not in m -> but set it)
b=blit(m,b,0x10100,2,4,0x21000,2,80,9,5,(0x3fff,0xffff,0xfffc),0x4b)
m[0x18000]=0xa5c3; m[0x18002]=0x3c5a
b=blit(m,b,0x18000,2,2,0x18010,2,2,2,1,(0xffff,)*3,0)
b=blit(m,b,0x10400,2,2,0x24000,2,60,20,3,(0x00ff,0x0ff0,0xff00),0xc3)
ram=[int(l,16) for l in open(sys.argv[1]) if l.strip() and not l.startswith('//')]
for name,lo,hi in (('T6',0x21000,0x21800),('T7',0x24000,0x24800)):
    bad=[(a,m.get(a,0),ram[a>>1]) for a in range(lo,hi,2) if m.get(a,0)!=ram[a>>1]]
    print(name,'mismatches',len(bad),' '.join('%05x:hat=%04x rtl=%04x'%(t[0],t[1],t[2]) for t in bad[:12]))
