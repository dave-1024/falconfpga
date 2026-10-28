import sys
L=[l.strip() for l in open(sys.argv[1]) if len(l.strip())==36]
prev=None; out=[]
for i,l in enumerate(L):
    v=int(l,16); ctl=(v>>104)&0xFFFF; vec=(v>>96)&0xFF; adr=(v>>64)&0xFFFFFFFF; dat=(v>>32)&0xFFFFFFFF; pc=v&0xFFFFFFFF
    b=lambda n:(ctl>>(15-n))&1
    s="%s%s ds%d%d %s%s%s %s fc%d sz%d %s%s%s"%("AS" if not b(0) else "..","DS" if not b(1) else "..",b(2),b(3),"BE" if not b(4) else "..","HL" if not b(5) else "..","RS" if not b(6) else "..","R" if b(7) else "W",(ctl>>5)&7,(ctl>>3)&3,"ST" if not b(13) else "..","IP" if not b(14) else "..","EX%02X"%vec if b(15) else "....")
    key=(s,adr,pc)
    if key!=prev: out.append("%4d %s A=%08X D=%08X PC=%08X"%(i,s,adr,dat,pc))
    prev=key
n=int(sys.argv[2]) if len(sys.argv)>2 else 80
print("\n".join(out[-n:]))
