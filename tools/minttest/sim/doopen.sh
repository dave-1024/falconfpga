#!/bin/bash
# Replays MiNT 1.19 mint030 do_open("u:/dev/console") (MP off, mint_nomp.st) on the RTL core from a Hatari snapshot.
# 1. Hatari: --machine st --cpulevel 3 --cpuclock 16 --mmu true --fpu none --compatible true --memsize 4 (TOS 2.06),
#    --parse with  b pc = $2e2e8 :once :quiet :file bp.ini ; bp.ini = "r" + "savebin ram_do.bin 0 $400000".
#    (kernel TEXT base $CEBA; $2E2E8 = jsr (a1) to do_open at $35EA4, the call in init() before FATAL "unable to open CONSOLE")
# 2. Put mint_doopen_stub.s (at $3FF000: Hatari regs, CACR $1111, jsr do_open, d0 -> $3404/$3400 DONE) into the image.
# 3. tb030 -gST=1 -gROMFILE=tos.hex -gRAMFILE=ramdo.hex -gRSSP=627982 -gRPC=4190208 -gSTOPDONE=1 ; expect W=00000000 at $3404.
set -e; W=${1:-/workspace/mtr}; B=m68k-linux-gnu
$B-as -m68030 mint_doopen_stub.s -o $W/stub.o && $B-ld -Ttext=0x3ff000 -o $W/stub.elf $W/stub.o && $B-objcopy -O binary $W/stub.elf $W/stub.bin
python3 -c "
r=bytearray(open('$W/ram_do.bin','rb').read()); s=open('$W/stub.bin','rb').read(); r[0x3ff000:0x3ff000+len(s)]=s
open('$W/ramdo.hex','w').write(''.join('%02x%02x\n'%(r[i],r[i+1]) for i in range(0,len(r),2)))"
