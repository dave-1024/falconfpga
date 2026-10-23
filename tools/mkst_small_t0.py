#!/usr/bin/env python3
# mkst2.py out.st root_files... -- auto_files...   (720K FAT12, AUTO folder)
import struct, sys, os
a=sys.argv[2:]; i=a.index('--'); rootf, autof = a[:i], a[i+1:]
BPS,SPC,RES,NF,NDIR,NSEC,SPF,SPT,NH=512,2,1,2,16,36,1,9,2
img=bytearray(NSEC*BPS); bs=bytearray(BPS)
bs[0:2]=b'\x60\x38'; bs[2:8]=b'FALCON'; bs[8:11]=b'\x12\x34\x56'
struct.pack_into('<HBHBHHBHHHH',bs,11,BPS,SPC,RES,NF,NDIR,NSEC,0xF9,SPF,SPT,NH,0)
if sum(struct.unpack('>256H',bs))&0xffff==0x1234: bs[30]^=1
img[0:BPS]=bs
fat=[0xFF9,0xFFF]; data0=RES+NF*SPF+NDIR*32//BPS; nxt=[2]
def alloc(n):
    c=nxt[0]
    for k in range(n): fat.append(c+k+1 if k<n-1 else 0xFFF)
    nxt[0]+=n; return c
def off(c): return (data0+(c-2)*SPC)*BPS
def ent(name,attr,clus,size):
    b,e=os.path.splitext(name.upper()); nm=(b[:8].ljust(8)+e[1:4].ljust(3)).encode()
    return struct.pack('<11sB10sHHHI',nm,attr,b'',0,(46<<9)|(10<<5)|21,clus,size)
root=bytearray(NDIR*32); ri=0
pre=[(f,alloc(max(1,-(-len(open(f,'rb').read())//(SPC*BPS))))) for f in autof]
adir=alloc(1); root[0:32]=ent('AUTO',0x10,adir,0); ri=1
ad=bytearray(SPC*BPS)
ad[0:32]=struct.pack('<11sB10sHHHI',b'.          ',0x10,b'',0,0,adir,0)
ad[32:64]=struct.pack('<11sB10sHHHI',b'..         ',0x10,b'',0,0,0,0)
for j,f in enumerate(autof):
    d=open(f,'rb').read(); c=dict(pre)[f]
    img[off(c):off(c)+len(d)]=d; ad[64+32*j:96+32*j]=ent(os.path.basename(f),0x20,c,len(d))
img[off(adir):off(adir)+len(ad)]=ad
for f in rootf:
    d=open(f,'rb').read(); n=max(1,-(-len(d)//(SPC*BPS))); c=alloc(n)
    img[off(c):off(c)+len(d)]=d; root[ri*32:ri*32+32]=ent(os.path.basename(f),0x20,c,len(d)); ri+=1
fb=bytearray(SPF*BPS)
for j,v in enumerate(fat):
    o=j*3//2
    if j&1: fb[o]|=(v<<4)&0xF0; fb[o+1]=v>>4
    else: fb[o]=v&0xFF; fb[o+1]|=v>>8
for k in range(NF): img[(RES+k*SPF)*BPS:(RES+(k+1)*SPF)*BPS]=fb
r0=(RES+NF*SPF)*BPS; img[r0:r0+len(root)]=root
open(sys.argv[1],'wb').write(img); print(sys.argv[1],'clusters used',nxt[0])
