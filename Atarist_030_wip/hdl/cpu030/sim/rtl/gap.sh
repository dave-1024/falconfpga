#!/bin/bash
# [PH2] Bus gap statistics: run_rtl.sh builds tb030 in $W; this runs a program with GAPLOG=1
# and prints a histogram of AS-negated clock edges per transition kind (PP, PD, DP, DD).
# Usage: gap.sh <prog name without .s> [WS] [scratch dir]
set -e
H=$(cd "$(dirname "$0")" && pwd); p=$1; ws=${2:-0}; W=${3:-/tmp/sim030rtl}; cd $W
O="--std=08 -fsynopsys -frelaxed --workdir=work"; G=${GHDL:-ghdl}
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/$p.s -o g.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o g.elf g.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary g.elf g.bin
python3 -c "d=open('g.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('g.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
$G -r $O tb030 -gROMFILE=g.hex -gWS=$ws -gGAPLOG=1 -gSTOPDONE=1 -gMAXCLK=${MAXCLK:-200000} 2>/dev/null > g.log || true
grep -h "DONE" g.log | head -1
python3 - <<'P'
import collections
c=collections.Counter()
for l in open('g.log'):
    if l.startswith('GAP '):
        _,n,k=l.split(); c[(k,int(n))]+=1
for k in ('PP','PD','DP','DD'):
    print(k, ' '.join('%d:%d'%(n,c[(kk,n)]) for (kk,n) in sorted(c) if kk==k))
P
