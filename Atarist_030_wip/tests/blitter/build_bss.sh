#!/bin/bash
# build_bss.sh <name> <PRG>: like build.sh, but vars/stack in .bss (small text, fits on track 0 of the 18 KB image)
set -e; cd "$(dirname "$0")"; N=$1; P=$2; M=m68k-linux-gnu
$M-as -m68030 --register-prefix-optional $N.s -o $N.o
$M-ld -Ttext=0 -o $N.elf $N.o 2>/dev/null
T=$($M-objdump -h $N.elf | awk '$2==".text"{print $3}')
$M-ld -Ttext=0 -Tbss=0x$T -o $N.elf $N.o 2>/dev/null
B=$($M-objdump -h $N.elf | awk '$2==".bss"{print $3}')
$M-objcopy -O binary -j .text $N.elf $N.bin
python3 -c "
import struct; t=open('$N.bin','rb').read(); t+=b'\0'*(len(t)&1)
open('$P.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(t),0,0x$B,0,0,0,0)+t+b'\0\0\0\0')"
echo "$P.PRG $(stat -c%s $P.PRG) bytes, bss 0x$B"
