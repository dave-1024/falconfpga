#!/bin/bash
# Unit bench: cpu030_st_bridge + WF68K30L netlist against a behavioural ST bus.
# Needs: wf030.vg (see wf030_syn.tcl), Icarus 12, m68k binutils. Scratch dir: $1 (default /tmp/sim030)
set -e
H=$(cd "$(dirname "$0")" && pwd); W=${1:-/tmp/sim030}; mkdir -p $W; cd $W
PRIM=/workspace/tools/gowin/IDE/simlib/gw5a/prim_sim.v
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog.s -o prog.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o prog.elf prog.o 2>/dev/null
m68k-linux-gnu-objcopy -O binary prog.elf prog.bin
python3 -c "d=open('prog.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('prog.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
iverilog -g2012 -o tb_unit.vvp -s tb $H/tb_bridge.v $H/../cpu030_st_bridge.v wf030.vg $PRIM
for ph in 0 7000 15625 23000 40000 101000; do
  vvp -n tb_unit.vvp +phase=$ph +trace=trace_unit_p$ph.txt | grep -E "ERRORS|FAIL" ; done
