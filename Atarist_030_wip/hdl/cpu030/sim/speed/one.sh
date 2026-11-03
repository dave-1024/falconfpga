#!/bin/bash
# Speed harness (SPEED_OVERHAUL.md): one test, K unrolled copies, I-cache warm, clocks between the two $3400 markers of pass 2.
# one.sh name body K  -> prints name total_clocks (second pass, marker to marker)
S=$(cd "$(dirname "$0")" && pwd)
n=$1; b=$2; K=$3; D=${OUT:-/tmp/speedh}/$n; mkdir -p $D; cd $D
W=${WORKDIR:-/tmp/speedh_w}; G=${GHDL:-ghdl}
python3 $S/gen.py "$b" $K p.s
m68k-linux-gnu-as -m68030 --register-prefix-optional p.s -o p.o 2>as.err && m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary p.elf p.bin || { echo "$n ASMERR"; exit; }
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
(cd $W && $G -r --std=08 -fsynopsys -frelaxed --workdir=work tb030 -gROMFILE=$D/p.hex -gWS=${WS:-0} -gCIMODE=1 -gSTOPDONE=1 -gMAXCLK=20000 2>/dev/null | grep -v assertion > $D/r.log)
c=$(grep "WR   A=00003400 " r.log | awk '{print $1}' | tail -2 | awk 'NR==1{p=$1} NR==2{print $1-p}')
echo "$n ${c:-NA}"
