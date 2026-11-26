#!/bin/sh
# Builds, with GNU m68k binutils (box: /workspace/tools/bin):
#  - MBXTERM.PRG  ST terminal for the mailbox (build product, not in git)
#  - ../../hdl/tang/console138k/st_helper_cart.hex  the self-test cartridge
#  - MBXTERM.ST  720 KB floppy image with MBXTERM.PRG (mkst.py), for the SD card
#    ROM for build option ST_HELPER_CART (generated, committed: the laptop
#    has no m68k toolchain). Rebuild the core after changing mbxcart.s.
set -e
cd "$(dirname "$0")"
B=${M68K_BIN:-/workspace/tools/bin}
AS="$B/m68k-linux-gnu-as -m68000 --register-prefix-optional"
$AS -o mbxterm.o mbxterm.s
$B/m68k-linux-gnu-ld -Ttext=0 -e 0 -o mbxterm.elf mbxterm.o
$B/m68k-linux-gnu-objcopy -O binary mbxterm.elf MBXTERM.PRG
$AS -o mbxcart.o mbxcart.s
$B/m68k-linux-gnu-ld -Ttext=0xfa0000 -e 0xfa0000 -o mbxcart.elf mbxcart.o
$B/m68k-linux-gnu-objcopy -O binary mbxcart.elf MBXCART.BIN
python3 mkcart.py MBXCART.BIN ../../hdl/tang/console138k/st_helper_cart.hex
python3 mkst.py MBXTERM.ST MBXTERM.PRG    # 720 KB floppy image for the SD card (later)
rm -f mbxterm.o mbxterm.elf mbxcart.o mbxcart.elf
ls -l MBXTERM.PRG MBXCART.BIN MBXTERM.ST
