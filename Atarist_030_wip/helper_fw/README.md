# AE350 helper firmware

The Tang Console 138K SOM has an Andes AE350 RISC-V SoC. In the `ST_HELPER` builds it does the job the BL616 does
on MiSTeryNano: SD card, floppy images, USB keyboard/mouse, the OSD and a serial console. The BL616 stays the USB
JTAG/serial bridge and is never reflashed.

## What is here
- `fpga-companion/`: **FPGA-Companion** by Till Harbaum / MiSTle-Dev (the MiSTeryNano helper MCU firmware), with an
  AE350 port in `src/ae350/` (`main.c`, `mcu_hw.c`, `console.c`, `usb.c`, the RTOS shim). Menu, config, FatFs, the
  SD/floppy protocol (`sdc.c`) and u8g2 are the upstream code. Keep the upstream credits in those files.
- `companion/`: the build for the image that runs on the board, `helper_companion.bin`.
  - `build_companion.sh`: Linux (Andes AST v5.1.1 + Gowin AE350 BSP; setup in [../docs/BUILD.md](../docs/BUILD.md) section 8).
  - `build_companion.bat`: Windows (AndeSight RDS v5.1.1 toolchain, same flags, same output).
- `mailbox/`, `ready/`, `st_test/`, `tools/`: the bring-up firmware (the 0xA5 ready stub, the $FFFB00 mailbox test,
  `MBXTERM.PRG`). History only, superseded by the companion image.

## Build and flash
```
bash companion/build_companion.sh          # -> companion/output/helper_companion.bin (+ size, SHA-256)
programmer_cli -d GW5AST-138C --location <loc> --run 56 --mcuFile helper_companion.bin --spiaddr 0x600000
```
- **0x600000** (leading zero; not 0x6000000). Op 56 only, no bulk erase. **Never 0x500000**: that is TOS.
- Back up the `.bin` that is on the board first and roll back to it if the console doesn't come up.
- The helper starts after the core loads (op 1 reload or power cycle). Boot sequence and the flash handoff:
  [../docs/ST_HELPER.md](../docs/ST_HELPER.md).

## Console
BL616 USB serial (Linux `/dev/ttyUSB1`), 115200 8N1. `help` lists the commands: boot/reset (`c`, `w`), images
(`ls`, `mount a <img>`, `eject`, `save`), files (`crc`, `scrc`, `get`, upload with `put`/`h`/`pend`), input
(`key`, `type`, `mouse`, `click`), SD status (`sd`, `sdlog on`) and, with a `SD_WRITE_DEBUG` core, `sdwlog`,
`sdstate`, `sdrw` ([../docs/SD_WRITE_DEBUG.md](../docs/SD_WRITE_DEBUG.md)).

Note: contiguous images are read/written by the core directly (sd_card.v direct mapping), so `sdlog` shows only
helper-handled requests; use the core-side `sdwlog` for those.
