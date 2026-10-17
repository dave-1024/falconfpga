#!/bin/bash
# [DC] Data cache unit test (DCACHE_DESIGN.md §5): prog_dcache.s on tb030 with CIMODE=1 (RAM $8000-$FFFF and
# the BERR range $20000-$2FFFF cachable: hits, fills incl. fill cycles, write-through, WA, FD, CD, CED/CAAR,
# ED, CDIS, FC in the tag, CIIN asserted mid-run, TAS/CAS forced read miss, bus errors on operand and
# fill-only cycles, CPU space, MOVES) and CIMODE=0 (CIIN asserted as on the ST bridge: no read fills, WA
# write allocation still creates entries), WS 0/1/3/7, FAST_HANDOFF 0/1. Results must equal
# expect_dcache_ci{1,0}.txt ("cN:<data reads>/<data writes>" in the test range per case | result writes).
# Usage: run_dcache.sh <built tb030 scratch dir>. Needs GHDL and m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); W=$(cd "${1:-/tmp/sim030rtl}" && pwd)
O="--std=08 -fsynopsys -frelaxed --workdir=work"; G=${GHDL:-ghdl}
T=$(mktemp -d); cd $T
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_dcache.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
fail=0
for ci in 1 0; do for fh in 1 0; do for ws in 0 1 3 7; do
  (cd $W && $G -r $O tb030 -gROMFILE=$T/p.hex -gWS=$ws -gCIMODE=$ci -gFASTH=$fh -gSTOPDONE=1 -gMAXCLK=80000 2>/dev/null) | grep -v '(assertion warning)' > r.log || true
  r=$(python3 $H/check_dcache.py r.log)
  d=$(grep -o 'DONE.*clk [0-9]*' r.log | awk '{print $NF}' | head -1)
  if [ "$r" = "$(cat $H/expect_dcache_ci$ci.txt)" ] && grep -q "W=600DC0DE" r.log; then echo "ok   CIMODE=$ci FASTH=$fh WS=$ws DONE $d"
  else echo "FAIL CIMODE=$ci FASTH=$fh WS=$ws: $r"; fail=1; fi
done; done; done
rm -rf $T
[ $fail = 0 ] && echo "PASS: data cache unit test"
