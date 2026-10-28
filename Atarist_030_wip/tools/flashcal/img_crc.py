import sys
d=open(sys.argv[1],'rb').read(); n=int(sys.argv[2])
w=[(d[2*i]<<8)|d[2*i+1] for i in range(n)]
open('img.hex','w').write('\n'.join('%04x'%x for x in w+[0]*(131072-n))+'\n')
c=0xFFFFFFFF
for x in w:
    for b in range(15,-1,-1):
        bit=((c>>31)^(x>>b))&1; c=((c<<1)&0xFFFFFFFF)^(0x04C11DB7 if bit else 0)
print('%08X'%c)
