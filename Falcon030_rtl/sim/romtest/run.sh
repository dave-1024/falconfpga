#!/bin/bash
# BLI-11f: tiny ROM programs for tb_falcon (bus-cycle accounting of D-cache effects).
# Usage: run.sh <prog.S> <scratch dir> [extra -g generics, e.g. -gCIMODE=6 -gWAHI=1 -gMEMWAIT=6 -gBUF2W=1]
# The program writes 1 to $400 at the start and 2 to $404 at the end; the clocks between the two W lines = cost.
# gb_rom_movem.S = GEMBENCH 6.08 ROM test (BIN/ALLTEST.o $35E: 40 x 8 x movem.l (a6)+,d3-d7/a1-a3 from *$4F2).
set -e
H=$(cd "$(dirname "$0")/.." && pwd); S=$H/../hdl/cpu030; P=$(readlink -f "$1"); W=$2; shift 2
G=${GHDL:-ghdl}; O="--std=08 -fsynopsys -frelaxed --workdir=work"; AS=${M68K_AS:-m68k-linux-gnu-as}; OC=${M68K_OBJCOPY:-m68k-linux-gnu-objcopy}
mkdir -p $W/work; cd $W
$AS -m68030 -o p.o $P && $OC -O binary p.o p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do $G -a $O $S/wf68k30L_$f.vhd; done
$G -a $O $H/tb_falcon.vhd
$G -r $O tb_falcon -gROMFILE=p.hex -gIRQON=0 -gMAXCLK=200000 -gTRFROM=1 -gTRTO=200000 -gHEART=1000000 "$@" 2>&1 | grep -v "assertion\|NUMERIC_STD\|metavalue" > run.log || true
grep "W A=00000400 \|W A=00000404 " run.log
