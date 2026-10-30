
## Untimed SDRAM/flash pads: a different failure on every build (branch pmmu, F102-F104, 30 Oct 2026)
**Symptom:** the same MiNT image failed in a new way after each rebuild, while every build passed timing: an XaAES MEMORY VIOLATION,
a hang after reading xaaes.cnf, a kernel Bus Error, or a black screen with TOS word 0 read as $80B8 instead of $602E (one flash SCK late).
Builds with identical logic counts (f99a and f101u) still failed differently, so the cause was placement, not logic.
**What was wrong:** the SDC had no input/output delays at all, so the tools never checked the SDRAM or flash pads.
**What we found:** the flash input register (`dspi_in_r`) was already in the pin cell (IOB93); the earlier "fabric register" guess from its name was wrong.
The flash SCK pin is L12 = CCLK, a configuration pin with no IOLOGIC, so an ODDR there fails to place (PR1125).
The SCK leaves through a fabric LUT mux, and STA treats a port clock as ideal, so that delay was never analysed.
SDRAM address/bank registers stay in the fabric even with `syn_useioff`, probably because they have clock enables; `sd_cmd` (written every clock) does pack.
**Fix:** F102 adds generated clocks for the SDRAM clock (PLL out 2, 338.4 deg) and SCK (PLL out 4, 22.5 deg) on their pins, SDRAM in/out delays,
flash input delays and the multicycles, plus reports for the new pairs. F103 pins the SCK mux LUT (`mspi_clk_d_s`) at R101C175 next to the CCLK pad
with INS_LOC, so its route is the same in every build. Result (f103b): 5/5 reloads to the TOS desktop with the helper up, no panics (f102b: 1 of 5 panicked),
and mint030c.hd now gets through the kernel to XaAES (it stops at "Fcntl(KM_RUN) failed, error 64") instead of the early Bus Error. F104 (`syn_useioff` on sd_addr/sd_ba) had no effect and was dropped.
**Still open:** the SDRAM data/byte-mask outputs are combinational (not constrained), and the SDRAM data inputs go through about 7 ns of fabric routing.
**Lesson:** "timing passes" means nothing for pins without I/O constraints. When a failure moves around with each build, check the pads first.
For a pin that cannot hold a register (a configuration pin), fix the location of the logic that drives it.

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
