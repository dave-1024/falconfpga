#!/bin/bash
# [IC] Same program, two built benches (old and new core): the WHOLE bench log must be identical,
# i.e. every bus cycle with its clock number, kind, address, FC, size and data, every exception and
# the DONE clock (GHDL's time-0 metavalue warnings are dropped). Stricter than cmp_wr.sh (writes only). Prints SAME/DIFF, cycles and DONE clocks.
# Usage: [ASFLAGS="--defsym ..."] cmp_full.sh <old scratch> <new scratch> <prog> <WS> [extra ghdl -g args]
H=$(cd "$(dirname "$0")" && pwd); A=$1; B=$2; p=$3; ws=$4; shift 4
O="--std=08 -fsynopsys -frelaxed --workdir=work"; G=${GHDL:-ghdl}
T=$(mktemp -d); cd $T
m68k-linux-gnu-as -m68030 --register-prefix-optional $ASFLAGS $H/$p.s -o p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('$T/p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
for d in $A $B; do (cd $d && $G -r $O tb030 -gROMFILE=$T/p.hex -gWS=$ws -gSTOPDONE=1 -gMAXCLK=${MAXCLK:-100000} "$@" 2>/dev/null | grep -v '(assertion warning)' | sed -E 's#^[^ ]*\.vhd:[0-9]+:[0-9]+:#vhd:#' > $T/$(basename $d).log); done
la=$(basename $A); lb=$(basename $B)
if cmp -s $la.log $lb.log; then r=SAME; else r=DIFF; fi
echo "$p WS=$ws $* $r cycles=$(grep -c ' A=' $la.log)/$(grep -c ' A=' $lb.log) old:$(grep -o 'DONE.*clk [0-9]*' $la.log|awk '{print $NF}'|head -1) new:$(grep -o 'DONE.*clk [0-9]*' $lb.log|awk '{print $NF}'|head -1) $(grep -h TIMEOUT $la.log $lb.log|head -1)"
[ -n "$KEEP" ] && { cp $la.log /tmp/cmpf_old.log; cp $lb.log /tmp/cmpf_new.log; }; rm -rf $T
