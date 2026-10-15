#!/bin/bash
# Linux mirror of build_companion.bat (AE350 FPGA-Companion helper image).
# Toolchain: Andes AST v5.1.1 Linux nds32le-elf-newlib-v5 (gcc 10.3.0, commit
# 80566eec933, same as the laptop's AndeSight RDS v5.1.1), from
# github.com/andestech/Andes-Development-Kit release ast-v5_1_1-release-linux.
# BSP: Gowin RiscV_AE350_SOC_V1.3 library/bsp (copied from the laptop).
# Output: output/helper_companion.bin -> flash at 0x0600000 with programmer_cli
# op 56 --mcuFile --spiaddr 0x600000. Never write 0x500000 (TOS slot).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
FALCON_TC=${FALCON_TC:-$HOME/andes/5_1_1/nds32le-elf-newlib-v5/bin}
FALCON_SDK=${FALCON_SDK:-$HOME/ae350sdk}
GCC=$FALCON_TC/riscv32-elf-gcc; OBJCOPY=$FALCON_TC/riscv32-elf-objcopy
OBJDUMP=$FALCON_TC/riscv32-elf-objdump; SIZE=$FALCON_TC/riscv32-elf-size
BSP=$FALCON_SDK/library/bsp
S=$HERE/../fpga-companion/src
OUT=${OUT:-$HERE/output}
mkdir -p "$OUT/obj/u8g2"; rm -f "$OUT"/obj/*.o "$OUT"/obj/u8g2/*.o
BSPINC="-I$BSP/ae350 -I$BSP/config -I$BSP/driver/ae350 -I$BSP/driver/include -I$BSP/lib"
APPINC="-I$S/ae350/rtos_shim -I$S/ae350 -I$S -I$S/fatfs/source -I$S/u8g2/csrc"
COMMON="-DREF_TEST_CLK -O2 -mcmodel=medium -g3 -Wall -Wno-unused-function -mcpu=a25 -ffunction-sections -fdata-sections -fno-builtin -fomit-frame-pointer"
LDFLAGS="-mcpu=a25 -O2 -nostartfiles -static -T$BSP/sag/ae350-ddr.ld -Wl,--gc-sections -Wl,-Map=$OUT/helper_companion.map"
cd "$OUT/obj"
$GCC $COMMON $BSPINC -c $BSP/ae350/{start.S,ae350.c,cache.c,initfini.c,interrupt.c,loader.c,reset.c,trap.c}
$GCC $COMMON $APPINC -c $S/ae350/{main.c,mcu_hw.c,console.c,stubs.c,tinyprintf.c,usb.c,rtos_shim/coop.c} \
  $S/{sdc.c,sysctrl.c,inifile.c,config.c,xml.c,puff.c,hid.c,ps2helper.c,menu.c,osd_u8g2.c} $S/fatfs/source/{ff.c,ffunicode.c}
cd u8g2
for f in $S/u8g2/csrc/*.c $S/u8g2/sys/bitmap/common/u8x8_d_bitmap.c; do $GCC $COMMON $APPINC -c "$f"; done
cd ..
# NTFS lists the .o case-insensitively sorted; keep that link order
U8OBJ=$(ls u8g2/*.o | LC_ALL=C sort -f)
$GCC $LDFLAGS start.o ae350.o cache.o initfini.o interrupt.o loader.o reset.o trap.o main.o mcu_hw.o console.o stubs.o tinyprintf.o usb.o hid.o ps2helper.o coop.o menu.o osd_u8g2.o $U8OBJ sdc.o sysctrl.o inifile.o config.o xml.o puff.o ff.o ffunicode.o -o $OUT/helper_companion.adx -lc -lgcc
$OBJCOPY -S -O binary $OUT/helper_companion.adx $OUT/helper_companion.bin
$OBJDUMP -h $OUT/helper_companion.adx | grep -qi '\.bootloader' || echo "WARNING: no .bootloader section. Do not flash."
$OBJDUMP -h $OUT/helper_companion.adx | grep -Ei '\.(text|data|bss|bootloader|loader)'
$SIZE $OUT/helper_companion.adx
sha256sum $OUT/helper_companion.bin; stat -c '%s bytes' $OUT/helper_companion.bin
echo "Flash output/helper_companion.bin at 0x0600000. Leading 0. Not 0x6000000."
