#!/bin/bash
# Run seeds vs F156. Records $OUT/summary.txt
# Usage: run_batch.sh [START] [END]
# Extra: NCHUNKS, MAXCLK, DUT_W, REF_W, OUT, IRQ=0|2|3
set -u
DT=$(cd "$(dirname "$0")" && pwd)
START=${1:-1}
END=${2:-50}
NCH=${NCHUNKS:-20}
export MAXCLK=${MAXCLK:-80000}
export DUT_W=${DUT_W:-/tmp/w_f157ot}
export REF_W=${REF_W:-/tmp/w_f156}
OUT=${OUT:-/tmp/difftest_batch}
IRQ=${IRQ:-0}
mkdir -p "$OUT"
sum=$OUT/summary.txt
: > "$sum.tmp"
fail=0
skip=0
ok=0
for s in $(seq $START $END); do
  src=$OUT/s$s.s
  python3 $DT/gen_difftest.py --kind random --seed $s --nchunks $NCH --irq $IRQ -o "$src"
  extra=""
  export IRQ_ARCH=0
  export GHDL_EXTRA=""
  if [ "$IRQ" = "3" ]; then
    export IRQ_ARCH=1
    export GHDL_EXTRA="-gIPL_MODE=3 -gIRQ_PER=$((400 + s * 13)) -gIRQ_DLY=$s"
  elif [ "$IRQ" = "2" ]; then
    export IRQ_ARCH=1
    export GHDL_EXTRA="-gIPL_MODE=2 -gIRQ_DLY=$((s % 32))"
  fi
  if ! $DT/run_one.sh "$src" s$s "$OUT" > "$OUT/s$s.out" 2>&1; then
    if grep -q "Assembler messages" "$OUT/s$s.out"; then
      echo "SKIP seed=$s ASMERR" | tee -a "$sum.tmp"
      skip=$((skip+1))
    else
      echo "DIFF seed=$s irq=$IRQ" | tee -a "$sum.tmp"
      tail -25 "$OUT/s$s.out" >> "$sum.tmp"
      fail=$((fail+1))
    fi
  else
    echo "MATCH seed=$s irq=$IRQ" | tee -a "$sum.tmp"
    ok=$((ok+1))
  fi
done
{
  echo "ok=$ok fail=$fail skip=$skip range=$START-$END nchunks=$NCH irq=$IRQ dut=$DUT_W"
  cat "$sum.tmp"
} > "$sum"
cat "$sum"
[ $fail -eq 0 ]
