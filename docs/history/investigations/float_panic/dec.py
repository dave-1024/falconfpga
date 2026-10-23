import sys
from PIL import Image
Y=[135,173,212,250,289,327]
def centers(im,y,W):
    line=[im.getpixel((x,y)) for x in range(W)]
    segs=[];i=int(70*W/1024)
    while i<int(905*W/1024):
        if line[i]>40:
            j=i
            while line[j]>40: j+=1
            if j-i>8: segs.append((i+j)//2)
            i=j
        else: i+=1
    return segs
def dec(fn,ref):
    im=Image.open(fn).convert('L'); W,H=im.size
    rim=Image.open(ref).convert('L')
    cx=centers(rim,int(Y[0]*H/576),W); assert len(cx)==32,len(cx)
    out={}
    for name,yd in zip('abcdef',Y):
        y=int(yd*H/576)
        out[name]=''.join('1' if sum(im.getpixel((x+d,y)) for d in(-3,0,3))/3>170 else '0' for x in cx)
    return out
ref=sys.argv[1]
for fn in sys.argv[2:]:
    r=dec(fn,ref); print(fn)
    for k,v in r.items(): print(' ',k,' '.join(v[i:i+4] for i in range(0,32,4)), '%08x'%int(v,2))
