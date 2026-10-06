REQUEST_ID: 20261005-4
ACTION: APPLY_ONLY
WORKDIR: Atarist_030_wip
BUILD_CMD: none (firmware only: helper_fw\ready\build_ready.bat on the laptop, then flash ready.bin)
TOS: keep

WHAT: Fixes the AE350 serial-proof stub (helper_fw/ready). Two firmware faults, either one
alone gives exactly PIN then DR and nothing else:
1. ready.c used bare-16550 offsets (THR at +0x00, LSR at +0x14). UART2 is an Andes
   ATCUART100 (MUG1029 Table 7-1): THR/DLL +0x20, IER/DLM +0x24, FCR +0x28, LCR +0x2C,
   LSR +0x34. +0x14 is OSCR, reset 0x10, so bit 5 is never set and uart_putc spun
   forever before the first character. Stub now uses the right offsets, 115200 from
   UCLK = APB_CLK = 50 MHz (divisor 27).
2. build_ready.bat linked ae350-ddr.ld without loader.c (and cache.c, -DREF_TEST_CLK).
   loader.c is the BUILD_BURN boot_loader that sits at the reset vector 0x80000000
   (.bootloader) and copies the DDR-linked image out of flash. The image that boots
   (Hybrid030 build_falcon_m28.bat) links loader.c and cache.c with -DREF_TEST_CLK.
   Source set now matches it. The bat prints the section list and warns if there is
   no .bootloader.

WHY: The bitstream side matches the known-good 168ktest/Hybrid030 boot chain closely
enough (same AE350 IP body, same PLLs, same reset chain, same flash pins, same
0x0600000 slot) that the stub is the first thing to fix. No bitstream rebuild needed.

LOOK FOR: Keep ae350_serial_flash_v2.fs at 0x0. Rebuild ready.bin, flash it at 0x0600000
(C Bin, Program Without Erasure). U15 at 115200: PIN, DR, then "AE350 alive".
Garbled text after R = runs, baud/UCLK wrong (try 38400 terminal or check UCLK).
Still nothing after DR = apply 20261005-2050-ae350-serial-netlist next.
