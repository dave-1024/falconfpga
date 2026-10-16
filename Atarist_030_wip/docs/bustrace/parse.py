#!/usr/bin/env python3
# parse.py sdwlog.txt [baseline.txt]: DIAG_BUSTRACE counters from "sdwlog 64" output (docs/BUSTRACE.md)
import re,sys,json
def load(p):
    c=[None]*128
    for m in re.finditer(r'#(\d+) BASE drv \d+ old (\d+) -> new (\d+)',open(p).read()):
        i=int(m.group(1)); c[2*i]=int(m.group(2)); c[2*i+1]=int(m.group(3))
    miss=[i for i,v in enumerate(c) if v is None]
    if miss: print('MISSING entries', sorted(set(i//2 for i in miss)), file=sys.stderr)
    return [v or 0 for v in c]
c=load(sys.argv[1])
if len(sys.argv)>2:
    b=load(sys.argv[2]); c=[x-y for x,y in zip(c,b)]
T=c[0] or 1
ns=lambda k: c[k]*31.25/1e6
R=['RAM','ROM','IO','other']; S={0:'long',1:'byte',2:'word',3:'3byte'}
print(f"total {c[0]} clk32 = {c[0]/32e6:.3f} s")
for k,n in [(1,'030 AS low'),(2,'no request, bridge idle'),(3,'request pending'),(4,' pending: bus held by other master'),
            (5,' pending: bridge busy S0-S4'),(6,' pending: waiting for en1'),(9,'bus not ours (arb)'),(12,'RMC lock')]:
    print(f"{n:38s} {c[k]:>11} clk  {100*c[k]/T:6.2f}%  {ns(k):9.3f} ms")
st=c[7] or 1
print(f"ST cycles started {c[7]}  (from S6 {c[14]}, from IDLE {c[15]})  per s {c[7]/(T/32e6):.0f}")
print(f"S4 wait states {c[8]}  ({c[8]/st:.3f}/cycle)  per region RAM {c[16]} ROM {c[17]} IO {c[18]} other {c[19]}")
print(f"grants {c[10]}  other-master DTACKs {c[11]}  RMC cycles {c[13]}  VPA {c[20]}  BERR {c[21]}")
print(f"program fetches {c[22]}  avg wait {c[23]/max(1,c[22]):.2f} clk32")
print(f"avg start wait all {sum(c[56:88])/st:.2f} clk32 (pending clocks/cycle {c[3]/st:.2f})")
print("class                 cycles      %    avg wait clk32")
for i in range(32):
    n=c[24+i]
    if n: print(f"{R[i>>3]:5s} {'W' if i&4 else 'R'} {S[i&3]:5s}   {n:>10}  {100*n/st:5.1f}  {c[56+i]/n:6.2f}")
print("start-wait histogram (clk32):", ' '.join(f"{k}:{c[88+k]}" for k in range(32) if c[88+k]))
print("RAM wait-state histogram:", ' '.join(f"{k}:{c[120+k]}" for k in range(8) if c[120+k]))
json.dump(c,open(sys.argv[1]+'.json','w'))
