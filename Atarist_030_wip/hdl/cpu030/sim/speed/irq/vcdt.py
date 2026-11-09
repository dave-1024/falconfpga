import sys,re
# [F155] vcdt.py file.vcd c0 c1 sig... : signal values at every rising tb030.clk, c = (t - 20 us) / 125 ns
# (wall clocks since reset; tb030 log numbers lag these). Names as in the VCD, e.g. i_bus_if.q_adr[31:1].
fn=sys.argv[1]; c0=int(sys.argv[2]); c1=int(sys.argv[3]); want=sys.argv[4:]
ids={}; scope=None; names={}
f=open(fn)
for l in f:
    if l.startswith('$scope'): scope=l.split()[2]
    elif l.startswith('$var'):
        p=l.split(); nm=scope+'.'+p[4]
        names.setdefault(p[3],[]).append(nm)
    elif l.startswith('$enddefinitions'): break
sel={}
for idc,nl in names.items():
    for nm in nl:
        for w in want:
            if nm==w: sel[idc]=w
clkid=[i for i,n in names.items() if 'tb030.clk' in n][0]
val={}; t=0; out=[]
print('clk '+' '.join(w.split('.')[-1] for w in want))
def fmt(v):
    if v and all(c in '01' for c in v) and len(v)>1: return '%x'%int(v,2)
    return v
for l in f:
    if l[0]=='#':
        t=int(l[1:]); continue
    if l[0]=='b': v,i=l[1:].split(); 
    else: v,i=l[0],l[1:].strip()
    if i==clkid and v=='1':
        c=(t-20000000000)//125000000
        if c0<=c<=c1: print(c,' '.join(fmt(val.get(k,'?')) for k in [ [i2 for i2,w2 in sel.items() if w2==w][0] if any(w2==w for w2 in sel.values()) else 'NA' for w in want]))
    if i in sel: val[i]=v
