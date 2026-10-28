
## Flash left in continuous-read mode across a JTAG reconfigure: helper silent after every reload (branch pmmu, F70)
**Symptom:** after any FPGA reload without a power cycle (op 53 + op 1, op 1 alone, or an SRAM load), the AE350 helper printed nothing and
never answered on U15. TOS still booted. A replug always fixed it, and so did a programmer flash op (verify, op 66) before the load.
**Cause:** flash_dspi.v (the ST's TOS reader) runs the SPI NOR in dual-I/O 0xBB **continuous read** (mode bits M5:4 = 10). The flash then
takes every CS# cycle as address + mode bits with no command. A JTAG reconfigure resets the FPGA but not the flash, so the AE350 boot loader's
read of 0x600000 was misread, the helper image was garbage, and the helper never came up. The ST reader re-inits the flash for itself, so TOS was fine.
PLLs were ruled out on the board: a no-PLL "alive" bitstream and a one-PLL variant both talked, and the PLL locked.
**Fix (F70):** `flash_unstick.v`. After por, while the AE350 is in reset, the fabric sends a mode-bit exit (CS# low, 16 SCK with IO0 = IO1 = 1),
then 0x66 and 0x99 (reset), and waits 40 µs. st_helper_ctrl releases the AE350 only after that (`fu_done`). Sim: `sim/tb_flash_unstick.v`.
**Lesson:** a design that leaves an external chip in a sticky mode must put it back at its own start-up, not rely on power-up. JTAG reloads
do not reset the board.
