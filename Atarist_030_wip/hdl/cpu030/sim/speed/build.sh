#!/bin/bash
# build.sh <cpu030 src dir> <workdir>
S=$1; W=$2; mkdir -p $W/work; cd $W; G=${GHDL:-ghdl}; O="--std=08 -fsynopsys -frelaxed --workdir=work"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do $G -a $O $S/wf68k30L_$f.vhd 2>&1 | grep -i "error" ; done
echo ffff>prog.hex; $G -a $O $S/sim/rtl/tb030.vhd 2>/dev/null; $G -e $O tb030 && echo built
