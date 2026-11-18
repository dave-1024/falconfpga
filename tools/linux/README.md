# Linux/m68k floppy image

`linux68k30.zip` holds `linux68k30.st` (2,949,120 bytes, md5 `9c98aca4bdb2900b1b255574a8fe4550`), the exact image
used for the Linux board test on F164 (18 Nov 2026). It has `AUTO/TTRAM.PRG`, `BOOTSTRA.PRG`, `VMLINUX.GZ`,
`INITRD.GZ` and `BOOTARGS`.

How to use it (EmuTOS in the TOS slot): unzip it onto the SD card, mount it as drive A:, boot to the desktop and run
`BOOTSTRA.PRG`. Booting is slow. On our board, about 15 minutes after starting BOOTSTRA the kernel is up, and the
BusyBox `#` prompt appears after about 18 minutes. Type `uname` to check that it prints `Linux`.
