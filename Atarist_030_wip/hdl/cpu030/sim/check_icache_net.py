#!/usr/bin/env python3
# [IC] run_icache_net.sh checker: program-space bus cycles in the loop line $FC1000-$FC100F per case ($3600 markers) from a tb_bridge trace.
import re,sys
case=0; cnt={}
for l in open(sys.argv[1]):
    m=re.search(r'fc=(\d) (R|W) a=([0-9a-f]{6}) \S+ d=([0-9a-f]{4})',l)
    if not m: continue
    fc,rw,a,d=int(m.group(1)),m.group(2),int(m.group(3),16),m.group(4)
    if rw=='W' and a==0x3600: case=int(d,16); cnt.setdefault(case,0); continue
    if case and fc in (2,6) and 0xfc1000<=a<0xfc1010: cnt[case]+=1
print(' '.join('c%d:%d'%(k,v) for k,v in sorted(cnt.items())))
