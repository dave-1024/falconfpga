#!/bin/bash
# dump.sh name: read (freeze, read, clear) the DIAG_BUSTRACE counters into name.txt, retrying until all 64 entries arrive
cd /workspace/gb/bt
for t in 1 2 3 4; do
  timeout 60 ../hc.sh "sdwlog 64" "sleep 3" > $1.txt 2>&1
  n=$(grep -c "BASE drv" $1.txt); [ "$n" -ge 64 ] && { date +%T > $1.time; echo "$1 ok $n"; exit 0; }
  sleep 5
done; echo "$1 FAIL $n"; exit 1
