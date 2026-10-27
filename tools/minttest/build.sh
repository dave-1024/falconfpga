#!/bin/bash
# Builds MPTEST.PRG: flat binary + GEMDOS header (no relocations, all code is PC relative).
set -e; cd "$(dirname "$0")"; P=${P:-/workspace/tools/bin/m68k-linux-gnu-}
${P}as -mcpu=68030 -o mptest.o mptest.s
${P}ld -Ttext=0 -o mptest.elf mptest.o
${P}objcopy -O binary -j .text mptest.elf mptest.bin
python3 - <<'P'
import struct
b=open('mptest.bin','rb').read()
if len(b)&1: b+=b'\0'
bss=0
# prgflags 0: ST RAM, memory protection mode private (bits 4-7 = 0); absflag=1: no relocs
h=struct.pack('>HIIIIIIH',0x601a,len(b),0,bss,0,0,0,1)
open('MPTEST.PRG','wb').write(h+b)
P
${P}as -mcpu=68030 -o stage.o stage.s && ${P}ld -Ttext=0 -o stage.elf stage.o && ${P}objcopy -O binary stage.elf stage.bin
python3 -c "
import struct;b=open('stage.bin','rb').read();b+=b'\\0'*(len(b)&1)
open('STAGE0.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,1)+b)"
ls -l MPTEST.PRG STAGE0.PRG
