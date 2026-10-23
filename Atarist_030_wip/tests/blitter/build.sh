#!/bin/bash
# Builds ${P:-BLTTEST}.PRG (GNU m68k binutils, no relocation: the code is position independent).
set -e; cd "$(dirname "$0")"; B=${B:-/workspace/tools/bin}
$B/m68k-linux-gnu-as -m68030 --register-prefix-optional ${N:-blttest}.s -o ${N:-blttest}.o
$B/m68k-linux-gnu-ld -Ttext=0 -o ${N:-blttest}.elf ${N:-blttest}.o
$B/m68k-linux-gnu-objcopy -O binary ${N:-blttest}.elf ${N:-blttest}.bin
N=${N:-blttest} P=${P:-BLTTEST} python3 - <<'P'
import struct,os
N=os.environ['N'];Pn=os.environ['P']
t=open(N+'.bin','rb').read(); t+=b'\0'*(len(t)&1)
open(Pn+'.PRG','wb').write(struct.pack('>HIIIIIIH',0x601a,len(t),0,0,0,0,0,0)+t+b'\0\0\0\0')
P
echo "${P:-BLTTEST}.PRG $(stat -c%s ${P:-BLTTEST}.PRG) bytes"
