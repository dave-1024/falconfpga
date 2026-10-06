# AE350 helper firmware

`fpga-companion/` is the FPGA-Companion source, copied so a handoff patch can edit it. It is the BL616 reference. The BL616 binary does not run on the AE350, and it is not in this tree.

No partner binaries, no built images, and no FatFs document pack. The menu, config file, and SPI messages are the part that ports. `src/bl616/mcu_hw.c` is the hardware side that gets replaced.

Flash slot, once an image exists: external flash `0x0600000`, C Bin write, after the bitstream erase. Do not type `0x6000000`. TOS for the helper image moves to `0x0700000`. Neither address is used by the image that boots today.

The HDL bring-up lives in `../helper/` and does not load this firmware.

The ready stub in `ready/` is the first AE350 image. It drives GPIO 0xA5 so the fabric releases the 030. Flash `output/ready.bin` at 0x0600000 after the bitstream, Program Without Erasure. TOS stays at 0x500000.

`mailbox/` is the firmware for the `ST_HELPER` core (`build_st_helper.tcl`,
see `../docs/ST_HELPER.md`). It signals "done with flash" (GPIO 0xA5), runs
from DDR3, tests the companion SPI link to the core (the port the BL616 uses,
now driven by the AE350's flash SPI controller after the handoff) and answers
the ST mailbox at $FFFB00 over UART2. Build with `mailbox\build_mailbox.bat`,
flash `output\helper_mailbox.bin` at 0x0600000 in place of `ready.bin`.
Its `mcu_spi_begin/tx_u08/end` are the first piece of an AE350
`mcu_hw.c` for FPGA-Companion.

`st_test/` holds `MBXTERM.PRG` (68000 source and `build.sh` for GNU m68k
binutils): a terminal on the ST for that mailbox. The `.PRG` is not in git.
