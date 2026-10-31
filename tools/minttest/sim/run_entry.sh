#!/bin/bash
# long run: MiNT from entry on the RTL core, timer C (level 6, vector $45, 200 Hz) + VBL (level 4, 50 Hz)
cd /tmp/sim030rtl
timeout 20000 /workspace/tools/ghdl/bin/ghdl -r --std=08 -fsynopsys -frelaxed --workdir=work tb030 -gROMFILE=tos.hex -gRAMFILE=rament.hex -gST=1 \
  -gRSSP=15848 -gRPC=4190208 -gWS=1 -gIPL_MODE=3 -gIRQ_PER=320000 -gIRQ_PER6=80000 -gVEC6=69 -gMAXCLK=40000000 2>/dev/null | grep -v "assertion warning" \
 | awk '/EXC|HALT|TIMEOUT|DONE/ {print; fflush()} / PROG A=0002E2E8| PROG A=0002EA0E| PROG A=0002E2EA/ {print; fflush()} {n++; if (n%500000==0) {print "progress", $0; fflush()}}' > /workspace/mtr/entry.log
echo END >> /workspace/mtr/entry.log
