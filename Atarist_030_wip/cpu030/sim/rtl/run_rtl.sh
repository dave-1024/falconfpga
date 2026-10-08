#!/bin/bash
# RTL bench (GHDL) for the WF68K30L alone: 16-bit port, DSACK1, AVEC on IACK.
# Checks that a level-4 interrupt is never taken with mask 7 (F55, MOVE to SR),
# and that prog_chk.s / prog_branch.s (F62: branches to 4n/4n+2, jumps, traps,
# prefetch bus errors, code written ahead of the PC, user mode) write the
# results in expect_*.txt with 0, 1, 3 and 7 wait states.
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
for p in chk branch; do
  m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_$p.s -o p.o
  m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
  python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_$p.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
  for ws in 0 1 3 7; do
    $G -r $O tb030 -gROMFILE=prog_$p.hex -gWS=$ws -gMAXCLK=20000 2>/dev/null > r.log || true
    r=$(python3 -c "
import re
s=[]
for l in open('r.log'):
    m=re.match(r'\\s*\\d+\\s+WR\\s+A=([0-9A-F]{8}) FC=\\d SIZ=(\\d) W=([0-9A-F]{8})',l)
    if m and 0x5000<=int(m.group(1),16)<0x5100:
        a=int(m.group(1),16); w=m.group(3)
        s.append('%04x:%s'%(a,(w[0:2] if a%2==0 else w[2:4]) if m.group(2)=='1' else w[0:4]))
print(' '.join(s))")
    [ "$r" = "$(cat $H/expect_$p.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_$p WS=$ws"; fail=1; }
  done
done
[ $fail = 0 ] && echo "PASS: no interrupt taken above the SR mask, all runs finished, chk/branch results match"
