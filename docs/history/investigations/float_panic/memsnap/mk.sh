#!/bin/bash
# mk.sh name.s OUT.PRG : PC-relative code only, no relocation table
set -e
B=/workspace/tools/bin
$B/m68k-linux-gnu-as -m68000 --register-prefix-optional -o ${1%.s}.o $1
$B/m68k-linux-gnu-ld -Ttext=0 -o ${1%.s}.elf ${1%.s}.o
$B/m68k-linux-gnu-objcopy -O binary ${1%.s}.elf ${1%.s}.bin
python3 - ${1%.s}.bin $2 <<'P'
import sys,struct
b=open(sys.argv[1],'rb').read()
if len(b)&1: b+=b'\0'
open(sys.argv[2],'wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,0)+b+b'\0\0\0\0')
P
