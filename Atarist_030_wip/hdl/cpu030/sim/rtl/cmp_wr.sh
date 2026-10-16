#!/bin/bash
# [PH2] Same program, two built benches (old and new core): the sequence of writes
# (address, size, data) and exceptions must be identical; prints DONE clocks of both.
# Usage: cmp_wr.sh <old scratch> <new scratch> <prog> <WS> [extra ghdl -g args]
H=$(cd "$(dirname "$0")" && pwd); A=$1; B=$2; p=$3; ws=$4; shift 4
O="--std=08 -fsynopsys -frelaxed --workdir=work"; G=${GHDL:-ghdl}
T=$(mktemp -d); cd $T
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/$p.s -o p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('$T/p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
for d in $A $B; do (cd $d && $G -r $O tb030 -gROMFILE=$T/p.hex -gWS=$ws -gSTOPDONE=1 -gMAXCLK=${MAXCLK:-100000} "$@" 2>/dev/null > $T/$(basename $d).log); done
# FILT=5000: only the result writes at $5000-$50FF (programs whose interrupts are timing-dependent).
if [ -n "$FILT" ]; then f() { awk '/ WR +A=000050/{print $3,$5,$6}' $1; }
else f() { awk '/ WR /{print $3,$5,$6} /^EXC/{print} /IACK/{print "IACK",$3}' $1; }; fi
la=$(basename $A); lb=$(basename $B)
if diff <(f $la.log) <(f $lb.log) >/dev/null; then r=SAME; else r=DIFF; fi
echo "$p WS=$ws $r writes=$(f $la.log|wc -l) old:$(grep -o 'DONE.*clk [0-9]*' $la.log|awk '{print $NF}'|head -1) new:$(grep -o 'DONE.*clk [0-9]*' $lb.log|awk '{print $NF}'|head -1) $(grep -h TIMEOUT $la.log $lb.log|head -1)"
[ -n "$KEEP" ] && { f $la.log > /tmp/cmp_old.txt; f $lb.log > /tmp/cmp_new.txt; }; rm -rf $T
