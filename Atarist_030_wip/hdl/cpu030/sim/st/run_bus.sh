#!/bin/bash
# Whole ST core bench (F61): atarist.v + cpu030_st_bridge + WF68K30L netlist,
# board-like RAM (sdram.v cycle model) and TOS flash (flash_dspi.v at 100 MHz)
# latencies. Checks when read data is valid in each bridge cycle and logs the
# ST AS->AS spacing.
# Usage: run_bus.sh <wf030.vg> [scratch dir] [ROM: bus (default) | <tos.img>] [extra vvp args]
#   wf030.vg: Gowin netlist of the core (wf030_syn.tcl). Needs Icarus 12, m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); R=$(cd $H/../../.. && pwd); NET=$(readlink -f $1); W=${2:-/tmp/simbus}; ROM=${3:-bus}; shift 3 || true
mkdir -p $W; cd $W
# iverilog-friendly copies (no functional change)
sed 's/^always begin/always @* begin/' $R/fdc1772/fdc1772.v | tr -d '\r' > fdc1772_sim.v
python3 - $R <<'P'
import sys; R=sys.argv[1]
s=open(R+'/atarist/acsi.v').read().replace('\r','')
s=s.replace('assign inquiry_str = "MiSTery Harddisk Image  4711";','wire [8*28-1:0] inquiry_s = "MiSTery Harddisk Image  4711";\ngenvar gi; generate for (gi=0; gi<28; gi=gi+1) begin : g_inq assign inquiry_str[gi] = inquiry_s[8*(27-gi)+:8]; end endgenerate')
open('acsi_sim.v','w').write(s)
s=open(R+'/atarist/stBlitter.sv').read().replace('\r','').replace('typedef struct {','typedef struct packed {',1)
s=s.replace("enum int unsigned { S0 = 0, S2, S4, S6} busState;","localparam [1:0] S0=0, S2=1, S4=2, S6=3; logic [1:0] busState;")
s=s.replace("	enum bit[1:0] { DMAST_IDLE = 0, DMAST_REQ, DMAST_ACTIVE1, DMAST_ACTIVE2} dmaState, next;","	localparam [1:0] DMAST_IDLE=0, DMAST_REQ=1, DMAST_ACTIVE1=2, DMAST_ACTIVE2=3; logic [1:0] dmaState, next;")
s=s.replace("enum int unsigned { ST_IDLE = 0, ST_FXSR1, ST_RDSRC, ST_RDEST, ST_WDEST} bltState, next, first;","localparam [2:0] ST_IDLE=0, ST_FXSR1=1, ST_RDSRC=2, ST_RDEST=3, ST_WDEST=4; logic [2:0] bltState, next, first;")
open('stBlitter_sim.sv','w').write(s)
P
cp $R/ikbd/rom/ikbd.hex . 2>/dev/null || true
if [ "$ROM" = bus ]; then
  m68k-linux-gnu-as -m68030 $H/prog_bus.s -o bus.o && m68k-linux-gnu-ld -Ttext=0xe00000 -o bus.elf bus.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary bus.elf rom.bin
else cp $ROM rom.bin; fi
python3 -c "d=open('rom.bin','rb').read(); d+=b'\xff'*(max(4096,len(d))-len(d)+len(d)%2); open('rom.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
A=$R/atarist; G=$R/gstmcu/hdl; J=$R/jt49; K=$R/ikbd
iverilog -g2012 -DWF030_NETLIST -DST_HELPER -I$K/hd63701 -o bus.vvp -s tb_bus $H/tb_bus.v \
  $A/acia.v acsi_sim.v $A/atarist.v $A/cubase2_dongle.v $A/cubase3_dongle.v $A/dma.v $A/io_fifo.v $A/mfp.v $A/mfp_hbit16.v \
  $A/mfp_srff16.v $A/mfp_timer.v $A/ste_joypad.v fdc1772_sim.v $R/fdc1772/floppy.v $G/clockgen.v $G/gstmcu.v $G/gstshifter.v \
  $G/hdegen.v $G/hsyncgen.v $H/latch_sim.v $G/mcucontrol.v $G/modules.v $H/register_sim.v $G/shifter_video.v $G/sndcnt.v \
  $G/vdegen.v $G/vidcnt.v $G/vsyncgen.v $J/jt49.v $J/jt49_bus.v $J/jt49_cen.v $J/jt49_div.v $J/jt49_eg.v $J/jt49_exp.v \
  $J/jt49_noise.v $J/filter/jt49_dcrm.v $J/filter/jt49_dcrm2.v $J/filter/jt49_dly.v $J/filter/jt49_mave.v $K/ikbd.sv \
  $K/hd63701/HD63701.v $K/hd63701/HD63701_ALU.v $K/hd63701/HD63701_CORE.v $K/hd63701/HD63701_EXEC.v $K/hd63701/HD63701_MCROM.v \
  $K/hd63701/HD63701_SEQ.v $K/rom/MCU_BIROM.v $R/tang/mega138kpro/gowin_dpb/fdc_dpram.v stBlitter_sim.sv \
  $R/cpu030/cpu030_st_bridge.v $R/tang/mega138kpro/sdram.v $NET ${GOWIN_SIMLIB:-/workspace/tools/gowin/IDE/simlib/gw5a}/prim_sim.v 2>&1 | grep -v "warning\|sorry\|: note" || true
for ph in 15625 46875; do vvp -n bus.vvp +rom=rom.hex +cph=$ph +trace=trace_$ph.txt "$@" > run_$ph.log 2>&1 & done; wait
grep -hv WARNING run_*.log
