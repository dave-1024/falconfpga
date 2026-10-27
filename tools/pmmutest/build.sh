#!/bin/bash
# Builds PMMUTEST.PRG: flat binary + GEMDOS header (no relocations, all code is PC relative).
set -e; cd "$(dirname "$0")"; P=/workspace/tools/bin/m68k-linux-gnu-
${P}as -mcpu=68030 -o pmmutest.o pmmutest.s
${P}ld -Ttext=0 -o pmmutest.elf pmmutest.o
${P}objcopy -O binary pmmutest.elf pmmutest.bin
python3 - <<'P'
import struct
b=open('pmmutest.bin','rb').read()
if len(b)&1: b+=b'\0'
h=struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,1)   # absflag=1: no relocation table
open('PMMUTEST.PRG','wb').write(h+b)
P
ls -l PMMUTEST.PRG
