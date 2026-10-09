#!/bin/bash
# RTL bench (GHDL) for the WF68K30L alone: 16-bit port, DSACK1, AVEC on IACK.
# Checks that a level-4 interrupt is never taken with mask 7 (F55, MOVE to SR).
# Usage: run_rtl.sh [scratch dir, default /tmp/sim030rtl]. Needs GHDL >= 4 and m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); S=${WF_SRC:-$H/../..}; W=${1:-/tmp/sim030rtl}; mkdir -p $W/work; cd $W
G=${GHDL:-ghdl}; O="--std=08 -fsynopsys -frelaxed --workdir=work"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache top; do
  $G -a $O $S/wf68k30L_$f.vhd 2>/dev/null; done
echo ffff > prog.hex; $G -a $O $H/tb030.vhd 2>/dev/null && $G -e $O tb030
fail=0
for p in a b; do
  m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_srmask_$p.s -o p.o
  m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
  python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('prog.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
  for d in $(seq 0 3 ${MAXD:-150}); do
    $G -r $O tb030 -gIPL_MODE=2 -gIRQ_DLY=$d -gMAXCLK=1500 2>/dev/null > r.log || true
    sr=$(awk '/IACK/{f=1} f&&/WR/{n++; if(n==3){print substr($0,index($0,"W=")+2,4); exit}}' r.log)
    grep -q DONE r.log || { echo "FAIL prog $p dly $d: no DONE"; fail=1; }
    [ "$sr" = "2700" ] && { echo "FAIL prog $p dly $d: level 4 taken with SR mask 7"; fail=1; }
  done
done
# JSR fix: A7 written back by the previous instruction while JSR/BSR/PEA/-(SP) decrements it
# (prog_spwb.s); $600DC0DE at $3300 = every case saw the right SP.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_spwb.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_spwb.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for ws in 0 1 3 7; do
  $G -r $O tb030 -gROMFILE=prog_spwb.hex -gWS=$ws -gMAXCLK=60000 2>/dev/null > r.log || true
  grep -q "A=00003300 FC=5 SIZ=0 W=600DC0DE" r.log || { echo "FAIL prog_spwb WS=$ws: $(grep -o 'A=00003300 FC=5 SIZ=0 W=[0-9A-F]*' r.log | head -1)"; fail=1; }
done
[ $fail = 0 ] && echo "PASS: no interrupt taken above the SR mask, all runs finished, SP writeback/push ok"
