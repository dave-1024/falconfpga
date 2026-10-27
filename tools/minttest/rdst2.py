import subprocess,sys,re
img=sys.argv[1]; path=sys.argv[2].upper().split('/')
def get(off,n):
    o=subprocess.run(['python3','/home/dave/hc.py',f'get {img} {off} {n}'],capture_output=True,text=True).stdout
    return bytes.fromhex(''.join(m.group(1) for m in re.finditer(r'^g [0-9a-f]{6} ([0-9a-f]{2,64})\s*$',o,re.M)))
def c2o(c): return (14+(c-2)*2)*512
def n83(s):
    a,_,b=s.partition('.'); return (a.ljust(8)+b.ljust(3)).encode()
d=b''.join(get(0xE00+512*j,512) for j in range(7)); 
for k,p in enumerate(path):
    for i in range(0,len(d),32):
        e=d[i:i+32]
        if e[:11]==n83(p): break
    else: print('not found',p,[d[i:i+11] for i in range(0,len(d),32) if d[i] not in (0,0xe5)]); sys.exit(1)
    cl=int.from_bytes(e[26:28],'little'); sz=int.from_bytes(e[28:32],'little')
    if k<len(path)-1: d=get(c2o(cl),512)+get(c2o(cl)+512,512)
data=b''
while len(data)<sz: data+=get(c2o(cl)+len(data),min(512,sz-len(data)))
print('size',sz); sys.stdout.write(data.decode('latin1'))
