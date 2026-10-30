# Build-sensitivity brief: Tang Console 138K Atari ST + 68030 (pmmu branch)

Written 30 Oct 2026 (UTC) for a Grok review. **Ask:** find unconstrained paths, clock-domain crossings, false-path / clock-group
mistakes, or I/O timing gaps that would make the board fail in a different way on each place-and-route, while every build passes
the timing report (`tools/timing/timing_pairs.py`, exit 0).

## Symptom
The same SD image (`mint030c.hd`, CRC32 9352a14d; FreeMiNT 1.19 + XaAES 1.7.0, TOS 2.06, 68030 with the PMMU on) fails
differently depending on the build. The RTL simulations (run_rtl, icache, dcache, prog_dw2) pass. Hatari (EmuTOS, 68030+MMU, 16 MB TT-RAM)
with the same image gets past every point where the board stops.

The three build-dependent failure modes:
1. **XaAES MEMORY VIOLATION** in xaloader / the xaaes env loop (AA=3F97DDA PC=1053A1E; `lea (1,a2,d0.l),a2` at $1FB114A).
   This was seen on f97fw-era builds. On f100d (the IDX_DEBUG latches) that `lea` runs 231 times with the correct index (37) and
   EA (a2+1+37), with no pending write-back. **The CPU index logic is computing correctly.**
2. **Stop after "Reading xaaes.cnf ... 34433 bytes done"** (f99a, f100d, f100nc with all caches hard-off). Hatari prints
   "both moose_w.adi and moose.adi found" next, so the board stops between the cnf parse and the moose ADI load.
3. **Fails before MiNT runs:**
   - **f101h:** black screen. The CPU halts at reset because the first TOS ROM word reads **$80B8 instead of $602E**. The SSP/PC
     vectors are garbage ($80B80814/$80B80818), and it is the same after an SRAM reload and a cold reset.
     $80B8 is the low 16 bits of $602E << 2, which is exactly one dual-I/O SCK cycle (2 bits) of shift in the flash read.
     So the flash data sample instant has moved by one clock in this placement.
   - **f101u:** MiNT panics with "Bus Error" early in the kernel (pc=$E0F89E, addr=$E1091C, ssr=0115). f101u has the
     **same LUT/ALU/register counts as f99a** (the DIAG_DUMP logic was pruned), so the logic is practically identical and only the placement differs.

There is also a separate lead: `mint030.hd` now gets a FATFS "bio_data_read out of range [5085]" while loading xaaes.km, with caches on and off.
This may be card damage from board SD writes. It is unverified because the card can't be read off-board without unplugging it.

## Build table (all on linserver `~/wf97`, `Atarist_030_wip/build_st_helper.tcl`, Gowin; timing_pairs exit 0 on all)
| Build | Source | Extra defines | clk_cpu030 Fmax | clk32_core Fmax | LUT + ALU / regs | Board result (mint030c.hd) |
|---|---|---|---|---|---|---|
| f97fw | 8c55cb0 | - | 20.12 | 32.02 | - | EmuTOS desktop, MiNT reached the XaAES MEMORY VIOLATION (mode 1) |
| f99a | dd4763d | - | 21.975 | 34.553 | 45763 + 5319 / 18484 | stop after xaaes.cnf (mode 2) |
| f100d | 8c1dd5a tree | IDX_DEBUG, SD_WRITE_DEBUG | (not recorded) | - | 46428 + 5423 / - | stop after xaaes.cnf; env-loop `lea` correct |
| f100nc | as f99a, `CDISn` tied 0 | - | - | - | - | stop after xaaes.cnf (caches off) |
| f101h | 8c1dd5a | DIAG_HEARTBEAT, DIAG_DUMP | 22.201 | 34.470 | 46773 + 5456 / 18945 | **ROM word0 $80B8**, CPU halted at reset (mode 3) |
| f101u | 8c1dd5a | DIAG_DUMP (pruned) | 22.163 | 34.553 | 45763 + 5319 / 18484 | MiNT Panic Bus Error pc=$E0F89E (mode 3) |

Timing reports: `docs/timing/f99a`, `docs/timing/f101u`, `docs/timing/f101h` on this branch (st_helper_tr_content.html,
st_helper.timing_paths, st_helper.rpt.txt, st_helper.pin.html, timing_pairs_output.txt). Older ones: `docs/timing/f97*`.

## Constraints
- SDC: `Atarist_030_wip/hdl/tang/console138k/atarist_st_helper.sdc` (pmmu). Pins: `atarist_st_helper.cst`, same folder.
- **No `set_input_delay` / `set_output_delay` anywhere.** The SDRAM pins (O_sdram_*, IO_sdram_dq[15:0]) and the flash
  pins (mspi_*) have no I/O timing at all. STA doesn't check pad-to-flop or flop-to-pad timing, so it changes with each placement.
- `clk_32` is a `create_clock` on the **output** port `O_sdram_clk` (pll_hdmi CLKOUT2, 32 MHz at 338.4 deg). It is not a generated
  clock of the PLL, so the SDRAM clock phase relative to clk32_core (CLKOUT1) is not part of any analysed path.
- Only **15 I/O-register FFs and 66 IOLOGIC** are used (identical in f99a, f101u and f101h). The SDRAM DQ capture (`dout <= sd_data`
  in sdram.v at clk32) and the address/command outputs are fabric flops, not IOB flops (sdram.v has no `syn_useioff`).
- Flash: `flash_dspi.v` (FLASH_CAL is **not** defined in build_st_helper.tcl). F79 added a `syn_useioff` input register
  `dspi_in_r`. In the timing report it appears as `misterynano/flash/dspi_in_r_0_s1` with a `_s1` slice-style name,
  so check whether it is really packed in the IOB on every build. SCK leaves through a LUT (a mux with the AE350), which is untimed.
  `flash_cal.v` (F85, IDDR + self-calibrated sample point + FCAL report) exists but is not built in.
- Clock groups: clk_osc/clk_g/clk_32/clk_spi/clk32_core/clk_cpu030/clk_cpu030_n are one related group. st_flash_clk (100 MHz, CLKOUT3)
  is only made exclusive to ae350_flash_clk and is otherwise related to clk32 (same VCO). Check the flash -> chipset `rom_dout`/`ready` crossing.
- Multicycle: clk_cpu030 -> clk32_core through the MMU nets XLATE_PIN/BLK_PIN/H_PA* (setup 2, F66). Check that it is not hiding a real 1-cycle path.

## Files on pmmu (https://github.com/dave-1024/falconfpga/tree/pmmu/Atarist_030_wip)
- Flash reader: `hdl/tang/console60k/flash_dspi.v` (built), `hdl/tang/console138k/flash_cal.v` (not built), instance in `hdl/misterynano.sv` ~l.199-250,
  pad mux / AE350 hand-over in `hdl/tang/console138k/top.sv` ~l.700-740, `st_helper_ctrl.v`.
- SDRAM controller: `hdl/tang/mega138kpro/sdram.v` (ST RAM + TT-RAM ports, DQ capture l.~244/272).
- Clock generation: `hdl/tang/console138k/gowin_pll/pll_160m.v` (pll_hdmi: CLKOUT1 clk32, CLKOUT2 SDRAM clock 338.4 deg, CLKOUT3 flash 100 MHz,
  CLKOUT5/6 clk_cpu030 / clk_cpu030_n), instance in `top.sv` ~l.928.
- CDC points: `hdl/tang/console138k/reset_sync.v` (por), `st_helper_mailbox.v`, `st_helper_ctrl.v`, `st_helper_mculink.v`, `hdl/misc/mcu_spi.v`
  (spi_io_clk -> clk32 toggle sync), `st_framebuffer.v` (clk32 -> HDMI), the CPU bridge `hdl/cpu030/cpu030_st_bridge.v`
  (clk_cpu030/clk_cpu030_n <-> clk32_core, timed as related; uses both edges).
- Build script: `build_st_helper.tcl` (regenerates hdl/tang/console138k/build_sel.vh).

## Questions for the review
1. Which unconstrained I/O (SDRAM DQ in/out, SDRAM command/address, flash IO0/IO1 in, SCK out) can plausibly move by >= one 32 MHz / 100 MHz
   window between placements, and what set_input_delay/set_output_delay values (and IOB packing) should be added?
2. Is `clk_32` on O_sdram_clk correct, or should it be a generated clock from CLKOUT2, so SDRAM capture is timed against the real phase?
3. Are there CDC paths between clk32_core, st_flash_clk and clk_cpu030(_n) that are timed as related but not phase-aligned, or that use a single flop?
4. Does the F66 multicycle on the MMU nets cover paths that are not actually two-cycle?
5. Is the flash dspi_in_r really in the IOB? If not, how do we force it (or switch to flash_cal.v's IDDR + calibration)?
