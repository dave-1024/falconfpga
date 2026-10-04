# AE350 helper firmware

This is the firmware for the hard AE350, not the BL616. The BL616 stays the JTAG programmer and is not reflashed.

The companion source to port is the reference copy of FPGA-Companion. The BL616 binary does not run on the Andes core. The USB driver is the hybrid front-USB-A path, not the BL616 USB stack.

Flash slot, once an image exists: external flash `0x0600000`, C Bin write, after the bitstream erase. Do not type `0x6000000`. TOS for the helper image moves to `0x0700000`. Neither address is used by the image that boots today.

Not in this directory yet: a build, a linker script, or an image. The first file here is the port. The HDL bring-up lives in `../helper/` and does not load this firmware.
