cd /tmp/sim030rtl
for d in 0 40 80 120 160 200 240 280 320 360 400 440; do timeout 900 /workspace/tools/ghdl/bin/ghdl -r --std=08 -fsynopsys -frelaxed --workdir=work tb030 -gROMFILE=tos.hex -gRAMFILE=ramstub.hex -gST=1 -gRSSP=627838 -gRPC=4190208 -gWS=1 -gIPL_MODE=3 -gIRQ_PER=4000 -gIRQ_DLY=$d -gMAXCLK=30000 2>/dev/null > /tmp/ri_$d.log & done; wait
for d in 0 40 80 120 160 200 240 280 320 360 400 440; do f=/tmp/ri_$d.log; echo "$d walks=$(grep -c MMUWALK $f) exc=$(grep EXC $f | awk '{print $2}' | sort | uniq -c | tr '\n' ' ') $(grep -i -m1 -E 'halt|TIMEOUT' $f)"; done
