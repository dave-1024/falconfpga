# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260928-2
ACTION: BUILD
RESULT: PASS
GOWIN_VERSION: V1.9.12.03 (gw_sh via /usr/local/bin/gowin-sh / /workspace/tools/bin/gowin-sh, Linux)
PROJECT: rigsdram
WORKDIR: rigsdram
BUILD_CMD: gw_sh build_rigsdram.tcl; echo GW_EXIT:$?
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE (set_option -replicate_resources 1; PnR cmd.do has -replicate)
REPO COMMIT BUILT: 50a188d

STAGE REACHED: Gowin full flow PASS (synthesis, place, route, timing, bitstream). GW_EXIT:0. ~4.5 min.
LICENCE: OK (attempt 1, no retries)

WHAT WAS RUN:
  1. git pull (5c809f7..50a188d; includes aaac988 SDC RESET false-path removal, new build_rigsdram.tcl)
  2. cd rigsdram && gw_sh build_rigsdram.tcl
  No patch. No HDL edits. No sim. No flash. misterynano_tc138k not built.

GW:
  GW_RESULT: PASS
  GW_EXIT: 0
  ERRORS: none (no ERROR lines)
  TA2003: none (lock_meta_s0/RESET not named anywhere)
  current device: GW5AST-138C GW5AST-LV138PG484AC1/I0; PnR report Device Version: C
  NOTE (EX0101): Current top module is "RIGSDRAM_TOP"
  WARNINGS OF NOTE (non-fatal):
    NL0002: BUS_TRACE U_TRC swept (rigsdram_top.vhd:401) - expected per CHECK 4
    AG0100: 17 lines (wf68k30L loops) - expected per CHECK 4
    PR1014: CLK_d routed on generic routing (skew/delay risk)
    EX4160: latch inferred P_BITFIELD_OP.BF_NZ (wf68k30L_alu.vhd:494); 0 latches after PnR

RESOURCES (impl/pnr/rigsdram.rpt.txt):
  Logic:    19187/138240 (14%) - LUT 17665 + ALU 1498 (+4 SSRAM)
  Register: 3555/139095 (3%)  - all logic FF
  BSRAM:    32/340 (10%) SDPB
  DSP:      9/298 (4%)

FMAX (Max Frequency Summary):
  clk_ref   constraint 50.000  actual 310.691 MHz
  clk50     constraint 50.000  actual 124.059 MHz
  core_clk  constraint 12.500  actual 18.228 MHz (42 logic levels)

SETUP / HOLD:
  Setup violated endpoints: 0. Worst setup +11.939 ns
    U_SDR/act_age[0]_0_s1/Q -> U_SDR/act_age[2]_10_s1/D (clk50 -> clk50)
  Hold violated endpoints: 1. Worst hold -0.680 ns
    from u_pll/u_pll_init/state_2_s0/Q (clk_ref) to u_lock_meta/D (clk50), skew -1.296
    NOTE: the false path covers state_1_s0/Q only; this path starts at state_2_s0/Q so it is still timed.
    TNS summary shows 0 (cross-clock not counted, as the SDC warns). Next worst hold +0.247 (clk50 same-clock).
  Timing Constraints Report: all 6 SDC commands Actived (clk_ref, clk50, core_clk, both multicycles, lock false path).

BITSTREAM:
  impl/pnr/rigsdram.fs 36345089 bytes (not committed)

CHECK:
  1. git pull, build rigsdram only with build_rigsdram.tcl     DONE
  2. No sim, flash, HDL edit, patch, impl/bitstream push        DONE
  3. PASS only if GW_EXIT 0 and no TA2003                        PASS - GW_EXIT 0, no TA2003
  4. NL0002 BUS_TRACE / AG0100 not failures                      seen, ignored
  5. top RIGSDRAM_TOP, device version C, replicate 1             CONFIRMED
  6. core_clk Fmax 18.228 MHz; worst hold state_2_s0/Q -> u_lock_meta/D -0.680 ns;
     LUT 17665 / FF 3555 / BSRAM 32 / DSP 9; .fs 36345089 bytes

NOTES:
  CONTEXT.md CHANGED is 0: not decoded, not edited. No HANDOFF_SEEN.
  Nothing flashed. No bitstream, logs, or impl/ committed.
```

```
REQUEST_ID: manual-20260928-rollback
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD (misterynano_tc138k, gw_sh build_tc138k.tcl)
REPO COMMIT BUILT: 66f57bb (rollback of misterynano_tc138k to 687446a)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines, no TA2003. Licence OK on attempt 1. ~4.7 min.
CO-PLACE: -co-place_io_registers 0 accepted by Gowin 1.9.12, no error or warning. tcl unmodified.
BITSTREAM: misterynano_tc138k/impl/pnr/atarist_tc138k.fs 36538618 bytes (same as mn3/mn4; not committed)
RESOURCES: Logic 19268/138240 (14%) = LUT 17366 + ALU 1704, SSRAM 33; Reg 7518 (FF 7483, IOFF 35);
  CLS 12333 (18%); I/O 118/297; IOLOGIC 6 (OSER10 3); BSRAM 21/340; DSP 1.5/298; PLL 1; PRIMARY clk 8/8
FMAX: CLKOUT1 (pixel) target 31.667, actual 33.313 MHz (27 levels); CLKOUT3 95.000 -> 245.685;
  clk_osc 50 -> 234.087. TNS summary 0 for every clock.
WORST SETUP: -19.679 ns ds2_p1/rx_buffer[4]_7_s0/Q -> ikbd/HD63701V0_M6/core/EXEC/rP_13_s0/D
  (ds2_p1/clk_spi -> CLKOUT1, relation 0.526 ns). All 25 top setup paths start at the auto-derived
  clock ds2_p1/clk_spi (TA1132, not in SDC). This is a cross-domain artefact, not pixel-clock logic.
WORST HOLD: -2.065 ns video2hdmi packet_picker audio_sample_word_transfer_control_s0/Q -> sync chain
  (video2hdmi/clk_audio -> CLKOUT1). Also misterynano/mcu/n4_24 -> CLKOUT1. Auto-derived clocks, CDC.
HDMI/CONSTRAINT WARNINGS: no HDMI pin or CST errors. TA1123 clk_32/clk_spi frequency does not match
  PLL CLKOUT2/CLKOUT4; TA1132 x4 (i2s_bclk_d, ds2_p1/clk_spi, mcu/n4_24, video2hdmi/clk_audio);
  PR1014 clk_d on generic routing; PR2059 jtagseln placed on T20 without constraint; CT2090 V_JTAGSELN.
  HDMI audio infoframe modules swept (NL0002), as before.
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260928-rollback.log
NOTES: Nothing flashed. Only BUILD_REPORT.md committed.
```
