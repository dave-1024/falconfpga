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
${P}as -mcpu=68030 -o probe.o probe.s && ${P}ld -Ttext=0 -o probe.elf probe.o && ${P}objcopy -O binary probe.elf probe.bin
python3 -c "
import struct;b=open('probe.bin','rb').read();b+=b'\\0'*(len(b)&1)
open('PROBE.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,1)+b)"
${P}as -mcpu=68030 -o probe2.o probe2.s && ${P}ld -Ttext=0 -o probe2.elf probe2.o && ${P}objcopy -O binary probe2.elf probe2.bin
python3 -c "
import struct;b=open('probe2.bin','rb').read();b+=b'\\0'*(len(b)&1)
open('PROBE2.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,1)+b)"
${P}as -mcpu=68030 -o mtree.o mtree.s && ${P}ld -Ttext=0 -o mtree.elf mtree.o && ${P}objcopy -O binary mtree.elf mtree.bin
python3 -c "
import struct;b=open('mtree.bin','rb').read();b+=b'\\0'*(len(b)&1)
open('MTREE.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,1)+b)"
ls -l MPTEST.PRG STAGE0.PRG PROBE.PRG PROBE2.PRG MTREE.PRG
