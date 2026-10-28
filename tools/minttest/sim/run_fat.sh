#!/bin/bash
cd /tmp/sim030rtl
timeout 30000 /workspace/tools/ghdl/bin/ghdl -r --std=08 -fsynopsys -frelaxed --workdir=work tb030 -gROMFILE=tos.hex -gRAMFILE=/workspace/mtr/fat/ramfat.hex -gST=1 \
  -gRSSP=629976 -gRPC=4190208 -gWS=1 -gIPL_MODE=3 -gIRQ_PER=320000 -gIRQ_PER6=80000 -gVEC6=69 -gMAXCLK=60000000 2>/dev/null | grep -v "assertion warning" \
 | awk '/EXC|HALT|TIMEOUT|DONE|BERR/ {print; fflush()} / PROG A=0002D7D2| PROG A=0002D81C| PROG A=0005828E| PROG A=0005866A| PROG A=000466F2/ {print; fflush()} {n++; if (n%500000==0) {print "progress", $0; fflush()}}' > /workspace/mtr/fat/fat.log
echo END >> /workspace/mtr/fat/fat.log
