#!/bin/bash
# [IC] Gate-level I cache check through cpu030_st_bridge (ICACHE_DESIGN.md §2a): prog_icache_net.s on tb_bridge
# with the Gowin netlist. The bridge's per-cycle CIIN decode leaves $01xxxxxx cachable (it aliases the ST space on
# this bench) and asserts CIIN for everything else. Expected loop-line fetches: cold 8, warm 0, same code via the
# ST address 48 (no hit, no fill), cachable address again 0 (still hits), EI off 48.
# Usage: run_icache_net.sh <wf030.vg> [scratch dir]. Needs Icarus 12, m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); NET=$(readlink -f $1); W=${2:-/tmp/sim030icnet}; mkdir -p $W; cd $W
PRIM=${PRIM:-/workspace/tools/gowin/IDE/simlib/gw5a/prim_sim.v}
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_icache_net.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('prog.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
iverilog -g2012 -DWF030_NETLIST -o tb_icn.vvp -s tb $H/tb_bridge.v $H/../cpu030_st_bridge.v $NET $PRIM
vvp -n tb_icn.vvp +phase=0 +trace=trace_icn.txt > /dev/null   # (tb_bridge's own checks are for prog.s; ignored)
r=$(python3 $H/check_icache_net.py trace_icn.txt); E="c1:8 c2:0 c3:48 c4:0 c5:48 c6:0"
echo "$r"; [ "$r" = "$E" ] && echo "PASS: gate-level I cache through the bridge" || { echo "FAIL: expected $E"; exit 1; }
