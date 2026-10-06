#!/bin/sh
# Compile-and-link check of the AE350 FPGA-Companion port on the box
# (Debian gcc-riscv64-unknown-elf + picolibc, rv32imac). The real image is
# built on the laptop with build_companion.bat (AndeSight + Gowin BSP).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
S=$HERE/../fpga-companion/src
OUT=${OUT:-/tmp/companion_check}
mkdir -p "$OUT"
CC=riscv64-unknown-elf-gcc
CFLAGS="-march=rv32imac_zicsr -mabi=ilp32 -mcmodel=medany -O2 -Wall -Wno-unused-function -ffunction-sections -fdata-sections --specs=picolibc.specs \
 -I$S/ae350/rtos_shim -I$S/ae350 -I$S -I$S/fatfs/source"
SRCS="$S/ae350/main.c $S/ae350/mcu_hw.c $S/ae350/console.c $S/ae350/stubs.c $S/ae350/tinyprintf.c $S/ae350/usb.c $S/hid.c $S/ps2helper.c \
 $S/sdc.c $S/sysctrl.c $S/inifile.c $S/config.c $S/xml.c $S/puff.c \
 $S/fatfs/source/ff.c $S/fatfs/source/ffunicode.c"
$CC $CFLAGS $SRCS -nostartfiles -Wl,--gc-sections -Wl,-e,main -Wl,--defsym=__flash=0x0 -Wl,--defsym=__flash_size=0x400000 -Wl,--defsym=__ram=0x400000 -Wl,--defsym=__ram_size=0x400000 -o "$OUT/companion_check.elf" "$@"
riscv64-unknown-elf-size "$OUT/companion_check.elf"
