#!/bin/bash
# [IC] Instruction cache unit test (ICACHE_DESIGN.md §4): prog_icache.s on tb030 with
# CIMODE=1 (fake cacheable region: hits, fills, EI/FI/CEI/CI, CAAR, FC2 tag, CDIS, no snoop,
# misaligned streams, no fill on a bus error) and CIMODE=0 (CIIN asserted as on the ST bridge:
# no hits at all), WS 0/1/3/7, FAST_HANDOFF 0/1. Results must equal expect_icache_ci{1,0}.txt.
# [XH1] CIMODE=0 also accepts expect_icache_ci0_xh1.txt: case 17 fetches one more long in the loop line
# (the earlier prefetch request reads the jmp after bne.s once more); only a prefetch count, no cache result.
# Usage: run_icache.sh <built tb030 scratch dir> (e.g. the one run_rtl.sh builds). Needs GHDL and m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); W=$(cd "${1:-/tmp/sim030rtl}" && pwd)
O="--std=08 -fsynopsys -frelaxed --workdir=work"; G=${GHDL:-ghdl}
T=$(mktemp -d); cd $T
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_icache.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
la=$(m68k-linux-gnu-objdump -t p.elf | awk '$NF=="lpa"{print $1}'); lb=$(m68k-linux-gnu-objdump -t p.elf | awk '$NF=="lpb"{print $1}')
fail=0
for ci in 1 0; do for fh in 1 0; do for ws in 0 1 3 7; do
  (cd $W && $G -r $O tb030 -gROMFILE=$T/p.hex -gWS=$ws -gCIMODE=$ci -gFASTH=$fh -gSTOPDONE=1 -gMAXCLK=60000 2>/dev/null) > r.log || true
  r=$(python3 $H/check_icache.py r.log $la $lb)
  d=$(grep -o 'DONE.*clk [0-9]*' r.log | awk '{print $NF}' | head -1)
  if { [ "$r" = "$(cat $H/expect_icache_ci$ci.txt)" ] || { [ $ci = 0 ] && [ "$r" = "$(cat $H/expect_icache_ci0_xh1.txt)" ]; }; } && grep -q "W=600DC0DE" r.log; then echo "ok   CIMODE=$ci FASTH=$fh WS=$ws DONE $d"
  else echo "FAIL CIMODE=$ci FASTH=$fh WS=$ws: $r"; fail=1; fi
done; done; done
rm -rf $T
[ $fail = 0 ] && echo "PASS: instruction cache unit test"
