#!/bin/bash
# Build STKTEST.PRG (position independent: TOS header, no relocation).
set -e; cd "$(dirname "$0")"
m68k-linux-gnu-as -m68000 stktest.s -o stk.o
m68k-linux-gnu-objcopy -O binary stk.o stk.bin
python3 -c "
import struct;b=open('stk.bin','rb').read();b+=b'\0'*(len(b)&1)
open('STKTEST.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,0,0,0,0,0)+b+struct.pack('>I',0))"
rm -f stk.o stk.bin; ls -l STKTEST.PRG
