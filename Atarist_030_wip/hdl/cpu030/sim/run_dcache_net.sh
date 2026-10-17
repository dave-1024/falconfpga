#!/bin/bash
# [DC] Gate-level D cache check through cpu030_st_bridge (DCACHE_DESIGN.md §5): prog_dcache_net.s on tb_bridge with
# the Gowin netlist. Expected: cachable long 2 reads then hits, byte 1 + 1 fill, ST address 4 reads (no hit, no fill),
# hit again, write-through 1 write + hit, WA allocation of an ST-side long write then a hit, ED off 2 reads.
# Usage: run_dcache_net.sh <wf030.vg> [scratch dir]. Needs Icarus 12, m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); NET=$(readlink -f $1); W=${2:-/tmp/sim030dcnet}; mkdir -p $W; cd $W
PRIM=${PRIM:-/workspace/tools/gowin/IDE/simlib/gw5a/prim_sim.v}
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_dcache_net.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('prog.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
iverilog -g2012 -DWF030_NETLIST -o tb_dcn.vvp -s tb $H/tb_bridge.v $H/../cpu030_st_bridge.v $NET $PRIM
vvp -n tb_dcn.vvp +phase=0 +trace=trace_dcn.txt > /dev/null   # (tb_bridge's own checks are for prog.s; ignored)
r=$(python3 $H/check_dcache_net.py trace_dcn.txt)
E="c1:2/0 c2:2/0 c3:4/0 c4:0/0 c5:0/1 c6:0/2 c7:2/0 c8:0/0 | 3700:0000 3702:0010 3704:0000 3706:beef 3708:1234 370a:5678"
echo "$r"; [ "$r" = "$E" ] && echo "PASS: gate-level D cache through the bridge" || { echo "FAIL: expected $E"; exit 1; }
