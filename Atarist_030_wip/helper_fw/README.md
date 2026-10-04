# AE350 helper firmware

`fpga-companion/` is the FPGA-Companion source, copied so a handoff patch can edit it. It is the BL616 reference. The BL616 binary does not run on the AE350, and it is not in this tree.

No partner binaries, no built images, and no FatFs document pack. The menu, config file, and SPI messages are the part that ports. `src/bl616/mcu_hw.c` is the hardware side that gets replaced.

Flash slot, once an image exists: external flash `0x0600000`, C Bin write, after the bitstream erase. Do not type `0x6000000`. TOS for the helper image moves to `0x0700000`. Neither address is used by the image that boots today.

The HDL bring-up lives in `../helper/` and does not load this firmware.
