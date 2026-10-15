import struct
d=open('/workspace/gb/x/BIN/AUTOFPU.BIN','rb').read()
_,tl,dl,bl,sl=struct.unpack('>HIIII',d[:18])
T=0x5581C; P=T-0x100
img=bytearray(0x400000)
prg=d[28:28+tl+dl]; img[T:T+len(prg)]=prg
r=28+tl+dl+sl; off=struct.unpack('>I',d[r:r+4])[0]; r+=4
def rl(a): v=struct.unpack('>I',img[a:a+4])[0]; img[a:a+4]=struct.pack('>I',v+T)
if off:
  a=T+off; rl(a)
  while True:
    b=d[r]; r+=1
    if b==0: break
    if b==1: a+=254; continue
    a+=b; rl(a)
w=lambda a,v:img.__setitem__(slice(a,a+4),struct.pack('>I',v))
h=lambda a,v:img.__setitem__(slice(a,a+2),struct.pack('>H',v))
# vectors: default stub per vector writes $BAD0vvvv at $3300 then loops
for v in range(2,256):
  s=0x1000+16*v; w(4*v,s)
  img[s:s+12]=bytes.fromhex('23fc')+struct.pack('>I',0xbad00000+v)+bytes.fromhex('00003300')+bytes.fromhex('60fe')
for v in (33,45,46):   # trap #1/#13/#14 -> d0=0, rte
  w(4*v,0x2000); 
img[0x2000:0x2004]=bytes.fromhex('70004e73')
w(0,0x8000); w(4,0x2100)
# boot: lea $3F0000,a0; move.l a0,usp; move.w #0,sr; jmp T
img[0x2100:0x2100+16]=bytes.fromhex('41f9003f0000'+'4e60'+'46fc0000'+'4ef9')+struct.pack('>I',T)
img[0x2200:0x2208]=bytes.fromhex('23fc600dc0de')[:6]; img[0x2200:0x220c]=bytes.fromhex('23fc600dc0de0000330060fe')
w(0x3F0000,0x2200); w(0x3F0004,P)
bp=[P,0x3F0000,T,tl,T+tl,dl,T+tl+dl,bl,P+128,0,0,0x3000]
for i,v in enumerate(bp): w(P+4*i,v)
# patch FPU probe (jsr target $5798c in fm.dis base, = T+0x5798c-0x5581c): clr.l 476(a4); rts
pa=T+0x5798c-0x5581c; img[pa:pa+6]=bytes.fromhex('42ac01dc4e75')
print('bss',hex(T+tl+dl),'end',hex(T+tl+dl+bl), 'probe', img[pa-4:pa].hex())
open('img.bin','wb').write(img)
open('img.hex','w').write('\n'.join('%04x'%(img[i]<<8|img[i+1]) for i in range(0,0x400000,2))+'\n')
