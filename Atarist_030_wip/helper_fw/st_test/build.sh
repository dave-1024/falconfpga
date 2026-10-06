#!/bin/sh
# Builds MBXTERM.PRG with GNU m68k binutils (box: /workspace/tools/bin).
# MBXTERM.PRG is a build product: not in git.
set -e
cd "$(dirname "$0")"
B=${M68K_BIN:-/workspace/tools/bin}
$B/m68k-linux-gnu-as -m68000 --register-prefix-optional -o mbxterm.o mbxterm.s
$B/m68k-linux-gnu-ld -Ttext=0 -e 0 -o mbxterm.elf mbxterm.o
$B/m68k-linux-gnu-objcopy -O binary mbxterm.elf MBXTERM.PRG
rm -f mbxterm.o mbxterm.elf
ls -l MBXTERM.PRG
