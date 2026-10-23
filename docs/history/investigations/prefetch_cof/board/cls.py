import sys
from PIL import Image
import numpy as np
def load(p):
    im=Image.open(p).convert('L').resize((120,68),Image.BOX); a=np.asarray(im,dtype=np.float32)
    return (a-a.mean())/(a.std()+1e-6), a.mean()
r,_=load('/workspace/gb/ph2/ref_desk.png'); s,m=load(sys.argv[1])
c=float((s*r).mean())
print('BLACK' if m<5 else ('DESK' if c>0.8 else 'OTHER'), round(c,2), int(m))
