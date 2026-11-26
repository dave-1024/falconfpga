#!/bin/bash
# BLI-11g: ST-RAM data-cache coherency check. Runs a directed program with RAM data uncached (CIMODE=4)
# and cached (CIMODE=5), board-like bus (WAHI=1 MEMWAIT=6 BUF2W=1), and diffs the RAM write stream to
# $3000-$4FFF (results area; stack and IRQ counters excluded). Usage: dc_check.sh <prog.S> <scratch> [extra -g]
# Programs: dc_ram.S (write-hit update, byte/word/misaligned, RMW ALU, RAM->RAM copy, MOVEM, stack, TAS,
# memory-test pattern), dc_vec.S (TOS $E02CD2 vector swap + bus error), dc_trap.S (exception frames, RTE
# on a cached stack), dc_irq.S (dc_ram x3 with VBL interrupts: add -gIRQON=1 -gVBLPER=1013),
# dc_flush.S (MOVES FC=1 write behind an FC=5 entry, then CACR CD; without the CD the check FAILs, so the harness is sensitive).
P=$(readlink -f "$1"); W=$2; shift 2; D=$(cd "$(dirname "$0")" && pwd)
mkdir -p $W; for c in 4 5; do bash $D/run.sh $P $W/c$c -gCIMODE=$c -gWAHI=1 -gMEMWAIT=6 -gBUF2W=1 "$@" > $W/c$c.out 2>&1 &
done; wait
for c in 4 5; do grep -E " W A=0000([34]|040[89A-F]|041)" $W/c$c/run.log | awk '{print $4,$6,$7}' > $W/c$c.w; done
if diff -q $W/c4.w $W/c5.w >/dev/null && [ -s $W/c4.w ]; then echo "PASS $(wc -l < $W/c4.w) writes identical"; else echo FAIL; diff $W/c4.w $W/c5.w | head; fi
