#!/bin/bash
# Run seeds START..END inclusive vs F156. Records /tmp/difftest_batch/summary.txt
set -u
DT=$(cd "$(dirname "$0")" && pwd)
START=${1:-1}
END=${2:-50}
NCH=${NCHUNKS:-20}
export MAXCLK=${MAXCLK:-80000}
export DUT_W=${DUT_W:-/tmp/w_f157ot}
export REF_W=${REF_W:-/tmp/w_f156}
OUT=${OUT:-/tmp/difftest_batch}
mkdir -p "$OUT"
sum=$OUT/summary.txt
: > "$sum.tmp"
fail=0
skip=0
ok=0
for s in $(seq $START $END); do
  src=$OUT/s$s.s
  python3 $DT/gen_difftest.py --kind random --seed $s --nchunks $NCH -o "$src"
  if ! $DT/run_one.sh "$src" s$s "$OUT" > "$OUT/s$s.out" 2>&1; then
    if grep -q "Assembler messages" "$OUT/s$s.out"; then
      echo "SKIP seed=$s ASMERR" | tee -a "$sum.tmp"
      skip=$((skip+1))
    else
      echo "DIFF seed=$s" | tee -a "$sum.tmp"
      tail -20 "$OUT/s$s.out" >> "$sum.tmp"
      fail=$((fail+1))
    fi
  else
    echo "MATCH seed=$s" | tee -a "$sum.tmp"
    ok=$((ok+1))
  fi
done
{
  echo "ok=$ok fail=$fail skip=$skip range=$START-$END nchunks=$NCH"
  cat "$sum.tmp"
} > "$sum"
cat "$sum"
[ $fail -eq 0 ]
