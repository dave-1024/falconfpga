#!/bin/bash
# run.sh <prog.s> <built bench workdir> <tb030 generics...>: prints the $3300 result word, IACK count, DONE.
# Board-bisect checks (SPEED_OVERHAUL.md, F142 board failure): irqchk.s (register mix, periodic level 4/6 IRQs,
# loop in ROM and in TT-RAM; run with ST=0), smc_tt.s / smc_st.s (code loaded into cacheable RAM, CACR flush, rerun).
# Compare the result word against a baseline bench build.
S=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); W=$2; shift 2; D=$(mktemp -d)
m68k-linux-gnu-as -m68030 $S -o $D/p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o $D/p.elf $D/p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary $D/p.elf $D/p.bin
python3 -c "d=open('$D/p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('$D/p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
cd $W && ${GHDL:-ghdl} -r --std=08 -fsynopsys -frelaxed --workdir=work tb030 -gROMFILE=$D/p.hex -gSTOPDONE=1 "$@" 2>/dev/null > $D/r.log
r=$(grep "WR   A=00003300 " $D/r.log | tail -1 | grep -o "W=[0-9A-F]*"); n=$(grep -c IACK $D/r.log); d=$(grep -c DONE $D/r.log)
echo "$r iack=$n done=$d"; [ -n "$KEEP" ] && cp $D/r.log $KEEP; rm -rf $D
