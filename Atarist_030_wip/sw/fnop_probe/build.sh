#!/bin/sh
# builds FNOP4.PRG (TOS executable, no relocations needed: position independent)
set -e
cd "$(dirname "$0")"
m68k-linux-gnu-as -m68030 -o fnop4.o fnop4.s
m68k-linux-gnu-objcopy -O binary -j .text fnop4.o fnop4.text
python3 - <<'PY'
import struct
t = open('fnop4.text','rb').read()
if len(t) & 1: t += b'\0'
hdr = struct.pack('>HIIIIIIH', 0x601a, len(t), 0, 0, 0, 0, 0, 0)
open('FNOP4.PRG','wb').write(hdr + t + struct.pack('>I', 0))
print('FNOP4.PRG', len(hdr + t) + 4, 'bytes')
PY
