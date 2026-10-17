#!/usr/bin/env python3
# [DC] run_dcache_net.sh checker: data reads/writes of $8000-$80FF per case ($3600 markers) and result words at $3700.
import re,sys
case=0; cnt={}; res=[]
for l in open(sys.argv[1]):
    m=re.search(r'fc=(\d) (R|W) a=([0-9a-f]{6}) \S+ d=([0-9a-f]{4})',l)
    if not m: continue
    fc,rw,a,d=int(m.group(1)),m.group(2),int(m.group(3),16),m.group(4)
    if rw=='W' and a==0x3600: case=int(d,16); cnt.setdefault(case,[0,0]); continue
    if rw=='W' and 0x3700<=a<0x3710: res.append('%04x:%s'%(a,d)); continue
    if case and fc in (1,5) and 0x8000<=a<0x8100: cnt[case][0 if rw=='R' else 1]+=1
print(' '.join('c%d:%d/%d'%(k,v[0],v[1]) for k,v in sorted(cnt.items()))+' | '+' '.join(res))
