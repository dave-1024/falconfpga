import re,sys,subprocess
elf,trace=sys.argv[1],sys.argv[2]
ins={}
for l in subprocess.run(['m68k-linux-gnu-objdump','-d',elf],capture_output=True,text=True).stdout.splitlines():
    m=re.match(r'\s*([0-9a-f]+):\s+((?:[0-9a-f]{4} )+)\s*(\S+)',l)
    if m: a=int(m.group(1),16); n=len(m.group(2).split()); ins[a]=(n,m.group(3))
cof=re.compile(r'^(b|db|jmp|jsr|rts|rte|rtr|rtd)')
cofs={a:(n,o) for a,(n,o) in ins.items() if cof.match(o) and not o.startswith(('btst','bset','bclr','bchg','bf'))}
prog=[]; tot=0; nst=0
for l in open(trace):
    p=l.split()
    if len(p)<5: continue
    nst+=1
    if p[2]=='fc6': prog.append(int(p[4],16))
waste=0; brk=0
for x,y in zip(prog,prog[1:]):
    if y!=x+2:
        brk+=1
        # last COF instruction starting at or before x whose end <= x+2
        c=[a for a in cofs if a<=x and a+2*cofs[a][0]<=x+2 and x-a<20]
        if c:
            a=max(c); end=a+2*cofs[a][0]; waste+=(x+2-end)//2
print(f"ST cycles {nst}, program fetch words {len(prog)}, flow breaks {brk}, words fetched past the COF {waste} ({100*waste/nst:.1f}% of ST cycles)")
