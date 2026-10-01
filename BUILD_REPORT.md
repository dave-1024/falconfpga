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

```
REQUEST_ID: manual-20260929-pll32
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD (misterynano_tc138k, gw_sh build_tc138k.tcl), then commit HDL
REPO COMMIT BUILT: 6fe62b8 (tree built from working copy, then committed as 6fe62b8)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines, no TA2003. Licence OK on attempt 1. ~4.7 min.

WHAT CHANGED (6fe62b8):
  gowin_pll/pll_160m_mod.v: MDIV 19 -> 16 (VCO 950 -> 800 MHz), ODIV 6/30/30/10/10 -> 5/25/25/8/8.
    Now 160 MHz TMDS, 32.000 MHz pixel/clk32, 32 MHz SDRAM clock at 338.4 deg
    (PE_COARSE 23, PE_FINE 4; 337.5 deg is not representable with ODIV 25, nearest step),
    100 MHz flash_clk, 100 MHz mspi_clk at 22.5 deg (PE_FINE 4).
  gowin_pll/pll_160m.v: pll_init MULTI_FAC 19 -> 16.
  top.sv: video2hdmi PIXEL_CLOCK 31_666_666 -> 32_000_000 (comments updated).
  atarist.sdc: clk_32 period 31 -> 31.25 ns.
  atarist.cst: IO_LOC "jtagseln" T20; IO_PORT LVCMOS33 PULL_MODE=NONE DRIVE=4 BANK_VCCIO=3.3.
    T20 is bank 4, all LVCMOS33 / 3.3 V, so no IO standard conflict. NET_LOC V_JTAGSELN is kept.

WHY: the console pixel clock was 31.667 MHz, about 1.2% slow against the ST's 32 MHz. A picky old
  HDMI TV may reject the off-spec timing (the Nano 20K, which runs at 32 MHz, works on David's TV).
  jtagseln had no pin constraint; in the first PLL build PnR auto-placed it on H17 (USB-C J17 D+).
  The baseline had it on T20 (unused SDRAM1 header CS), so it is now pinned there.

FMAX: CLKOUT1 (pixel/clk32) target 32.000, actual 33.923 MHz (26 levels), so same-clock setup slack
  about +1.77 ns (31.25 - 29.48). CLKOUT3 100 -> 235.031 MHz; clk_osc 50 -> 212.335 MHz.
  TNS summary 0 for every clock (setup and hold).
WORST SETUP: -20.904 ns ds2_p1/rx_buffer[4]_6_s0/Q -> ikbd .../EXEC/rP_15_s0/D (ds2_p1/clk_spi ->
  CLKOUT1, relation 1.250 ns). All 25 top setup paths start at the auto-derived clock ds2_p1/clk_spi
  (TA1132). Same cross-domain artefact as the rollback build (-19.679), not pixel-clock logic.
WORST HOLD: -2.158 ns misterynano/mcu/spi_data_in_ready_s2/Q -> spi_data_in_readyD_0_s0/D
  (misterynano/mcu/n4_24 -> CLKOUT1). Auto-derived clocks, CDC, as before.
WARNINGS: TA1123 (clk_32 frequency mismatch with PLL) is gone. PR2059 (jtagseln unconstrained) is gone.
  Still: CT2090 V_JTAGSELN, TA1132 x4, PR1014 clk_d on generic routing.
PINS: jtagseln on T20/4 (IOB102[B], constraint Y, LVCMOS33, drive 4). H17 unused (default input, pull-up).
RESOURCES: Logic 19152/138240 (14%) = LUT 17251 + ALU 1703, SSRAM 33; Reg 7527 (FF 7492, IOFF 35);
  CLS 12240 (18%); I/O 118/297; OSER10 3; BSRAM 21/340; DSP 1.5/298.
BITSTREAM: impl/pnr/atarist_tc138k.fs 37047546 bytes (not committed). Copy on the box:
  /workspace/outputs/atarist_tc138k_pll32_t20.fs (sha256 72f2f3be...0ced78a).
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260929-pll32.log

FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
  TOS goes at flash byte address 0x500000 on this Console build (STE 0x540000).
NOTES: Nothing flashed. No bitstream, logs, or impl/ committed. BUILD_REQUEST.md and CONTEXT.md not edited.
```

```
REQUEST_ID: manual-20260929-stage1-colourbars
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD (misterynano_tc138k, gw_sh build_tc138k.tcl), then commit HDL
REPO COMMIT BUILT: 88a4b08 (tree built from working copy on b9d76df, then committed unchanged as 88a4b08)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines, no TA2003. Licence OK on attempt 1. ~4.2 min.
  (A first attempt failed on the SDC with TA2003/TA2004: constraint on the missing net
  video2hdmi/clk_pixel_x5 and on hdmi_tp/clk_pixel, which synthesis renames. Fixed in the SDC.)

WHY: David's main monitor and his old HDMI TV both reject the core's native Atari timing on clk32
  (~32 MHz, non-standard). Stage 1 is a video-output sanity check: disconnect the core from HDMI and
  send a standard 640x480@60 colour-bar picture. Long-term goal: 640x480@60 from a frame buffer.

WHAT CHANGED (88a4b08), all in misterynano_tc138k/:
  tang/console138k/top.sv: `define HDMI_TESTPATTERN; `ifdef instantiates hdmi_testpattern_640
    (hdmi_tp) instead of video2hdmi. The Atari core, pll_160m, clk32, SDRAM, OSD, scandoubler and
    lcd_* outputs are unchanged; only the core's video no longer goes to HDMI.
  tang/console138k/hdmi_testpattern_640.sv (new): gowin_pll_hdmi 50 -> 126 MHz, CLKDIV "5" ->
    25.2 MHz pixel clock, pixel reset from PLL_INIT lock (2-FF sync + 255 clocks), timing/pattern,
    48 kHz audio clock (25.2 MHz / 525 exactly), 1 kHz test tone (+/-2048, ~-24 dBFS, 0.5 s on /
    0.5 s off; AUDIO_TONE=0 for silence), hdmi_640, ELVDS_OBUF x4 (same as video2hdmi.v).
  tang/console138k/video_testpattern_640.v (new): 800x525, H 640/16/96/48, V 480/10/2/33, negative
    syncs; vsync edges on the hsync leading edge (CEA-861 style, as hdmi.sv does). 8 vertical 80 px
    bars at 75% (white, yellow, cyan, green, magenta, red, blue, black) + 1 px 100% white border.
  tang/console138k/hdmi_640.sv (new): fixed VIC 1 copy of hdmi/hdmi.sv; cx/cy/syncs from the
    timing generator; AVI 4:3; reuses packet_picker/packet_assembler/tmds_channel/serializer (OSER10).
  tang/console138k/gowin_pll_hdmi/ (new): .v/_mod.v/.ipc/.mod copied from Hybrid030 (VCO 787.5 MHz,
    126 MHz out, MULTI_FAC 15). Only change: lock exported as a port. No module name clash.
  hdmi/packet_picker.sv: new PICTURE_ASPECT_RATIO parameter to the AVI InfoFrame, default 00, so the
    original Atari path is unchanged.
  tang/console138k/atarist.sdc: clk_hdmi (video2hdmi/clk_pixel_x5) commented out; new clk_hdmi640_x5
    7.937 ns (net hdmi_tp/clk_pixel_x5), clk_hdmi640_pix 39.683 ns (pin
    hdmi_tp/clkdiv_hdmi640/CLKOUT), clk_hdmi640_audio 20833.333 ns (net hdmi_tp/clk_audio);
    set_clock_groups -asynchronous {x5 pix} / {audio} / {clk_osc clk_32 clk_spi}.
  build_tc138k.tcl, atarist_tc138k.gprj: 5 new source files added.

ENCODER: MiSTeryNano hdmi/ core (full HDMI: data islands, AVI VIC 1 4:3, SPD, audio InfoFrame,
  48 kHz audio). Not the DVI-only fallback.

FMAX / SLACK (new clocks; per-clock report_timing from a re-run with report commands in a temporary
  SDC copy, bitstream identical apart from the timestamp line):
  clk_hdmi640_pix   25.200 MHz -> 104.427 MHz (7 levels). Worst setup +30.107 ns, worst hold +0.247 ns.
  clk_hdmi640_x5    126 MHz: no fabric paths (only CLKDIV HCLKIN + OSER10 FCLK), like the old clk_hdmi.
  clk_hdmi640_audio 48 kHz -> 422.791 MHz, setup +20830.969 ns.
  TNS 0 (setup and hold) for every clock.
CORE CLOCKS: CLKOUT1 (clk32) 32.000 -> 32.117 MHz (12 levels), margin only ~0.11 ns
  (was 33.923 MHz / +1.77 ns in manual-20260929-pll32; placement change, keep an eye on it).
  CLKOUT3 100 -> 217.305 MHz; clk_osc 50 -> 278.343 MHz.
  Worst setup -15.181 ns ds2_p1/rx_buffer[3]_5_s0/Q -> ikbd EXEC (ds2_p1/clk_spi -> CLKOUT1): same
  auto-derived-clock CDC artefact as before (was -20.904). Worst hold -2.195 ns misterynano/mcu
  (n4_24 -> CLKOUT1), as before. Worst recovery -7.748 ns pll_init state -> core async clears
  (clk_osc -> CLKOUT1), auto-derived CDC; baseline had -8.176 (vreset -> old serializer).
  No path between the HDMI test-pattern domain and the core is timed (async groups).

PRIMARY CLOCKS: 8/8 still, placement OK, no manual fix needed. Freed: old 160 MHz clk_pixel_x5 and
  video2hdmi/clk_audio. Added: hdmi_tp/clk_pixel_x5 (126 MHz, primary + BANK3 HCLK),
  hdmi_tp/tmds_clock (= CLKDIV 25.2 MHz), hdmi_tp/clk_audio. PnR moved ds2_p1/clk_spi from PRIMARY to
  LW (slow dualshock SPI clock, Fmax 190.656 MHz vs 100 MHz default). clk_d, lcd_clk_d (clk32),
  O_sdram_clk_d, flash_clk, mspi_clk_d stay on PRIMARY. LW 5/8, PLL 2/12, CLKDIV 1/24.

PINS: identical to manual-20260929-pll32 (pin report compared port by port, 0 differences):
  tmds_clk G15/G16, tmds_d[0] J14/H14, tmds_d[1] J15/H15, tmds_d[2] K17/J17, LVCMOS33D drive 8.
  jtagseln T20/4 (IOB102[B], LVCMOS33, drive 4). H17 unused (default input, pull-up).
RESOURCES: Logic 19152/138240 (14%) = LUT 17349 + ALU 1605, SSRAM 33; Reg 7525 (FF 7490, IOFF 35);
  CLS 12182 (18%); I/O 118/297; OSER10 3; BSRAM 21/340; DSP 1.5/298.
WARNINGS: TA1132 x3 (i2s_bclk_d, ds2_p1/clk_spi, mcu/n4_24; video2hdmi/clk_audio gone),
  PR1014 clk_d on generic routing, CT2090 V_JTAGSELN.
SIM (Icarus 12, timing generator + pattern only): totals 800x525; hsync period 800, 96 clocks low
  from x=656; vsync 1600 clocks (2 lines) in a 420000-clock frame (60.000 Hz at 25.2 MHz), falls at
  x=656 y=489, rises at x=656 y=491; 307200 DE pixels per frame; 0 DE/RGB errors; bar colours and
  border correct. Testbench not committed (box: /workspace/outputs/tb_video_testpattern_640.v).
BITSTREAM: impl/pnr/atarist_tc138k.fs 37047546 bytes (not committed). Copy on the box:
  /workspace/outputs/atarist_tc138k_stage1_colourbars.fs (sha256 9b1dd9c0...b45a3f).
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260929-stage1-colourbars.log

HOW TO SWITCH BACK to the core video path (video2hdmi):
  1. top.sv: comment out `define HDMI_TESTPATTERN.
  2. atarist.sdc: re-enable the clk_hdmi create_clock line (video2hdmi/clk_pixel_x5) and comment
     out the "stage 1" block at the end (3 create_clock + set_clock_groups). Gowin errors (TA2003)
     on a constraint for a net that does not exist, so the SDC must match the define.

FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
  TOS goes at flash byte address 0x500000 on this Console build (STE 0x540000).
NOTES: Nothing flashed. No bitstream, logs, impl/ or testbench committed. BUILD_REQUEST.md and
  CONTEXT.md not edited.
```

```
REQUEST_ID: manual-20260929-stage1b-dvi
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD (misterynano_tc138k, gw_sh build_tc138k.tcl), then commit HDL
REPO COMMIT BUILT: c6b1246 (tree built from working copy on dd79d81, then committed unchanged as c6b1246)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines, no TA2003. Licence OK on attempt 1. ~4.2 min.

WHY: stage 1 (88a4b08, HDMI mode) colour bars and tone WORK on David's HDMI TV, but his monitor shows
  no sync. The monitor has a DVI input and is connected with a DVI-to-HDMI cable, so it most likely
  rejects the HDMI data islands, preambles and guard bands. DVI mode is now the default.

WHAT CHANGED (c6b1246):
  tang/console138k/hdmi_640.sv: new parameter DVI_OUTPUT (MiSTeryNano's hdmi core has no such option;
    Sameer's original had one, re-implemented the same way). DVI_OUTPUT=1: plain DVI 1.0 TMDS, only
    video periods and control periods; no data islands, no data island preambles/guard bands, no video
    preamble/guard bands; CTL0..3 = 0; {vsync, hsync} on channel 0 (syncs delayed with the pixel data,
    so they keep the timing generator's position relative to DE).
    Also, in both modes, rgb is registered once so the pixel data lines up with the video period.
    Before, the first video symbol carried pixel x=1: column 0 (left border) was dropped and the last
    column was black. Found in the new symbol-level sim; the HDMI-mode picture on the TV had this
    1-pixel shift.
  tang/console138k/hdmi_testpattern_640.sv: DVI_OUTPUT parameter passed to hdmi_640. No audio in DVI
    mode (packet logic and the 48 kHz audio clock are optimised away).
  tang/console138k/top.sv: hdmi_tp #(.DVI_OUTPUT(1)), with comments. One-line switch: 0 = HDMI + tone.
  tang/console138k/atarist.sdc: clk_hdmi640_audio create_clock and its clock group removed, because the
    net does not exist in DVI mode (TA2003 ERROR). In HDMI mode it becomes an auto-derived clock
    (TA1132 warning), like video2hdmi/clk_audio used to. HDMI x5/pixel clocks still async to the core.
  The Atari path (video2hdmi, hdmi/ core files) is not touched.

FMAX / SLACK:
  clk_hdmi640_pix 25.200 MHz -> 133.607 MHz (10 levels); setup slack about +32.2 ns (39.683 - 7.485,
    derived from Fmax, no per-clock report re-run). TNS 0 setup and hold.
  clk_hdmi640_x5 126 MHz: no fabric paths (CLKDIV + OSER10 FCLK only).
  CLKOUT1 (clk32) 32.000 -> 35.277 MHz (30 levels), margin about +2.9 ns (was ~0.11 ns in stage 1).
  CLKOUT3 100 -> 267.858 MHz; clk_osc 50 -> 275.880 MHz. TNS 0 for every clock.
  Worst setup -17.780 ns ds2_p1/clk_spi -> ikbd (CLKOUT1), worst hold -2.203 ns mcu n4_24 -> CLKOUT1,
  worst recovery -7.145 ns pll_init state -> core async clears: the same auto-derived-clock CDC
  artefacts as in earlier builds, none involve the HDMI domain.
PRIMARY CLOCKS: 8/8: clk_d, lcd_clk_d (clk32), O_sdram_clk_d, flash_clk, mspi_clk_d, ds2_p1/clk_spi
  (back on PRIMARY), hdmi_tp/tmds_clock (25.2 MHz CLKDIV), hdmi_tp/clk_pixel_x5 (126 MHz, + BANK3 HCLK).
  LW 4/8 (por, i2s_bclk_d, mcu/n4_24, peripheral_reset). PLL 2/12, CLKDIV 1/24.
PINS: identical to stage 1 and to manual-20260929-pll32 (pin report compared port by port, 0 diffs):
  tmds_clk G15/G16, tmds_d[0] J14/H14, tmds_d[1] J15/H15, tmds_d[2] K17/J17, LVCMOS33D drive 8;
  jtagseln T20/4 (LVCMOS33, drive 4); H17 unused (default input, pull-up).
RESOURCES: Logic 17995/138240 (14%) = LUT 16246 + ALU 1551; Reg 6963 (FF 6928, IOFF 35);
  CLS 11205 (17%); OSER10 3; BSRAM 21/340; DSP 1.5/298.
WARNINGS: TA1132 x3 (i2s_bclk_d, ds2_p1/clk_spi, mcu/n4_24), PR1014 clk_d on generic routing,
  CT2090 V_JTAGSELN.
SIM (Icarus 12, video_testpattern_640 + hdmi_640 + real tmds_channel; serializer and HDMI packet
  modules stubbed; every 10-bit symbol checked, 3 frames):
  DVI_OUTPUT=1: 0 video guard / 0 data island / 0 island guard symbols; every blanking symbol on all
    3 channels is a control symbol; ch1/ch2 always CTL=00 (0 exceptions); 640 video px per line,
    307200 per frame; hsync on ch0 falls 16 symbols after the last video pixel, 96 low, period 800;
    vsync on ch0 2 lines (1600), period 525 lines, edges together with hsync.
  Decoded pixels: line 100 x0=ffffff (border) x1=c0c0c0 x80=c0c000 x638=000000 x639=ffffff (border);
    lines 1 and 480 all white. HDMI mode (DVI_OUTPUT=0) gives the same aligned pixels.
  Testbench not committed (box: /workspace/outputs/tb_stage1b/).
BITSTREAM: impl/pnr/atarist_tc138k.fs 36643751 bytes (not committed; smaller than stage 1 as the HDMI
  packet logic is gone). Copy on the box: /workspace/outputs/atarist_tc138k_stage1b_dvi.fs
  (sha256 77b1444b...f270d3).
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260929-stage1b-dvi.log

HOW TO SWITCH:
  HDMI mode (TV, with tone): top.sv .DVI_OUTPUT ( 0 ). No SDC change needed.
  Back to the core video path: comment out `define HDMI_TESTPATTERN in top.sv, re-enable the clk_hdmi
  line in atarist.sdc and comment out the stage 1 block at its end.

FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
  TOS goes at flash byte address 0x500000 on this Console build (STE 0x540000).
NOTES: Nothing flashed. No bitstream, logs, impl/ or testbench committed. BUILD_REQUEST.md and
  CONTEXT.md not edited.
```

```
REQUEST_ID: manual-20260930-stage2-stfb
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD (misterynano_tc138k, gw_sh build_tc138k.tcl), then commit HDL
REPO COMMIT BUILT: 274f8b0 (tree built from working copy on 718f8cf, then committed unchanged as 274f8b0)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines. Licence OK on attempt 1. ~4.5 min.

WHY: stage 1b (c6b1246) DVI colour bars confirmed working on BOTH David's DVI monitor and his old
  HDMI TV (2026-09-30). Stage 2 connects the Atari ST video to that 640x480@60 output.

WHAT CHANGED (274f8b0):
  misterynano.sv: new outputs st_video_hs_n/vs_n/de/r/g/b = the raw ST video (st_hs_n, st_vs_n,
    st_de, st_r/g/b[3:0] from the atarist instance, clk32 domain, BEFORE the scandoubler and OSD).
  tang/console138k/st_framebuffer.v (new): st_fb_capture (clk32), st_fb_ram (153600 x 12 bit,
    write clk32 / read 25.2 MHz, inferred -> 120 SDPB BSRAM), st_fb_scanout640 (25.2 MHz, 2-clock
    latency; cx/cy/syncs delayed to match).
  hdmi_testpattern_640.sv: ST_VIDEO parameter (1 = ST frame buffer, default; 0 = colour bars),
    ST video input ports, tuning parameters passed through.
  top.sv: st_video_* wires from misterynano to hdmi_tp, .ST_VIDEO ( 1 ). DVI_OUTPUT stays 1.
  atarist.sdc: create_generated_clock clk32_core on pll_hdmi/u_pll/PLL_inst/CLKOUT1 (50 x 16/25; the
    old clk_32 constraint is only the O_sdram_clk port), added to the core async clock group.
  build_tc138k.tcl, atarist_tc138k.gprj: st_framebuffer.v added.

DESIGN:
  ST timing at the misterynano level (Icarus sim of gstmcu + gstshifter, clk32 from hsync fall):
    PAL line 2048, 313 lines, DE rise 432, first DE line 66; NTSC 2032, 263, 416, 37;
    mono 896, 501, 160, 37. First pixel after DE rise: low +96, medium +91, mono +64.
  Capture: each frame measures the DE position in the line and the first DE line and uses them for
    the next frame (so PAL/NTSC/mono are followed automatically; values kept if a frame has no DE).
    Colour: 240 lines from 20 lines above the first DE line (20 border lines top and bottom);
      640 samples per line, one every second clk32, starting at DE + ST_H_OFS_COLOR (exactly the
      640-pixel active area, no side borders); low res = each pixel sampled twice.
      Scan-out doubles every line: 240 -> 480, full screen.
    Mono: 400 lines from the first DE line, 1 bpp packed 8 px/word, from DE + ST_H_OFS_MONO;
      scan-out 1:1, centred (40 black lines top and bottom).
  Mode detection: mono = hsync period < 1400 clk32, latched per frame, 2-FF synchronised into the
    pixel domain. Only the BSRAM and this flag cross clock domains. Single buffer (tearing possible).
  Colour: 4 bits per gun stored as {r,g,b}, expanded {x,x} to 8 bits.

SIM (Icarus 12, synthetic ST video -> capture -> RAM -> scan-out + 640x480 timing, every pixel of one
  output frame checked): PAL low res, NTSC medium res, mono: 307200/307200 pixels OK each, 0 errors.
  Deliberate offsets (colour +2 clk, V border 21, mono +1 clk) all FAIL (128k-256k errors), so the
  bench catches off-by-one and line-doubling mistakes. Testbench not committed
  (box: /workspace/outputs/tb_stage2/).
TIMING: clk_hdmi640_pix (25.2 MHz) Fmax 81.349 MHz (stage 1b 133.6; ~27 ns slack).
  clk32_core (32 MHz) Fmax 34.070 MHz (stage 1b 35.277); worst same-clock slack +0.347 ns, critical
  path in core logic (19 levels), not the frame buffer. clk_osc 284.6 MHz.
  No timed paths between clk32_core and the 640x480 clocks (async groups). The legacy
  ds2_p1/clk_spi -> clk32 cross-clock paths are still negative (-15.686, was -17.780), unchanged issue.
PRIMARY CLOCKS: 8/8 (unchanged), LW 4/8, PLL 2/12, CLKDIV 1/24.
PINS: identical to manual-20260929-stage1b-dvi (440 pin report entries compared, 0 differences):
  tmds_clk G15/G16, tmds_d[0] J14/H14, tmds_d[1] J15/H15, tmds_d[2] K17/J17, LVCMOS33D drive 8.
  jtagseln T20/4. H17 unused.
RESOURCES: BSRAM 141/340 (was 21; +120 SDPB for the frame buffer; SDPB 125, DPB 2, SP 1, pROM 4,
  pROMX9 9). Logic 18567/138240 (14%) = LUT 16718 + ALU 1651, SSRAM 33; Reg 7317; CLS 11857 (18%);
  I/O 118/297; DSP 1.5/298.
WARNINGS: TA1132 x3, PR1014 clk_d on generic routing, CT2090 V_JTAGSELN; EX2478 x9 (initial values
  on output-port regs in st_framebuffer.v ignored; harmless, only the first clocks after power-up).
BITSTREAM: impl/pnr/atarist_tc138k.fs 38508033 bytes (not committed). Copy on the box:
  /workspace/outputs/atarist_tc138k_stage2_stfb.fs (sha256 2dc4d47d...d9bf1f).
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260930-stage2-stfb.log

TUNING (parameters of hdmi_testpattern_640 / st_fb_scanout640, rebuild needed):
  ST_H_OFS_COLOR (96): clk32 from DE rise to the first colour sample; 4 clk32 = 1 low-res pixel.
    Picture too far right / border on the left: lower it. First columns missing: raise it.
    96 is exact for low res; medium res then loses its leftmost 2 pixels (92 = exact medium res).
  ST_H_OFS_MONO (64): same for mono (1 clk32 = 1 pixel).
  ST_V_BORDER (20): colour border lines captured above the picture (window stays 240 lines).
  MONO_TOP (40, in st_fb_scanout640): first output line of the 400-line mono image.
KNOWN LIMITS:
  No OSD on this output (the OSD is mixed in after the scandoubler; the tap is before it). No audio
    in DVI mode.
  Tearing and judder: single buffer, output fixed at 60 Hz while the ST runs at 50/60/71 Hz.
  PAL low-res horizontal offset unverified: the gstmcu/gstshifter sim was clean for NTSC low res
    (+96) and PAL/NTSC medium res (+91), but PAL low res looked irregular (probably a testbench
    artifact). If PAL low res is shifted or cut off, tune ST_H_OFS_COLOR.
  No side borders in colour modes (only the 640-pixel active area is captured).
  Plain-ST colours are 3 bits per gun (level 7 shows as 0xEE, not 0xFF).

HOW TO SWITCH:
  Colour bars: top.sv .ST_VIDEO ( 0 ). HDMI mode (TV, with tone): .DVI_OUTPUT ( 0 ) (not built in
  this configuration). No SDC change needed for either.
  Back to the core video path: comment out `define HDMI_TESTPATTERN in top.sv, re-enable the clk_hdmi
  line in atarist.sdc and comment out the stage 1/2 block at its end.

FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
  TOS goes at flash byte address 0x500000 on this Console build (STE 0x540000).
NOTES: Nothing flashed. No bitstream, logs, impl/ or testbench committed. BUILD_REQUEST.md and
  CONTEXT.md not edited.
```

```
REQUEST_ID: manual-20260930-atarist-030-wip
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: COPY misterynano_tc138k -> Atarist_030_wip (new work starting point), then test BUILD there
  (Atarist_030_wip, gw_sh build_tc138k.tcl), then commit the copy
REPO COMMIT BUILT: b78df28 (Atarist_030_wip = tracked files of misterynano_tc138k at c2d695d, stage 2)
RESULT: PASS. GW_EXIT 0, 0 ERROR lines. Licence OK on attempt 1. ~4.5 min.

COPY: git archive c2d695d misterynano_tc138k, moved to Atarist_030_wip/: 108 files, ~1.0 MB. No impl/,
  .fs, logs or untracked strays. Only change vs the original: README.md note at the top (copied from
  c2d695d) and "cd Atarist_030_wip" in the build instructions. No path fixes needed: build_tc138k.tcl
  and atarist_tc138k.gprj use folder-relative paths only; all $readmemh / `include files are inside the
  folder. The build log shows every source resolved under Atarist_030_wip (no misterynano_tc138k
  reference). Module, file and output names (atarist_tc138k) unchanged. impl/ is ignored by the root
  .gitignore; *.fs/*.bin by the copied .gitignore.
TIMING: identical to stage 2 (manual-20260930-stage2-stfb): clk_hdmi640_pix Fmax 81.349 MHz (25.2),
  clk32_core 34.070 MHz (32), clk_osc 284.581 MHz. PRIMARY 8/8.
PINS: identical to stage 2 (440 pin report entries compared, 0 differences): tmds_clk G15/G16,
  tmds_d[0] J14/H14, tmds_d[1] J15/H15, tmds_d[2] K17/J17; jtagseln T20/4; H17 unused.
RESOURCES: BSRAM 141/340, Logic 18567/138240, Reg 7317 (same as stage 2).
BITSTREAM: Atarist_030_wip/impl/pnr/atarist_tc138k.fs 38508033 bytes (not committed; same size as
  stage 2, different hash, probably the build timestamp). Copy on the box:
  /workspace/outputs/atarist_030_wip_testbuild.fs (sha256 fe5d7e09...bbcaa0).
LOG: /workspace/repos/falconfpga_build_logs/build_manual-20260930-atarist-030-wip.log

FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
NOTES: Nothing flashed. No bitstream, logs or impl/ committed. BUILD_REQUEST.md and CONTEXT.md not
  edited. Stage 2 has not been bench-tested by David yet.
```

```
REQUEST_ID: manual-20260930-a030-first
REQUESTED: by David in chat (no BUILD_REQUEST; .falconfpga_last_handled not changed)
ACTION: BUILD Atarist_030_wip (gw_sh build_tc138k.tcl) with CPU_030: WF68K30L (68030) replaces fx68k
  via cpu030_st_bridge (TF534-based, toggle handshake, clk_cpu = PLL CLKOUT5 8 MHz)
REPO COMMIT BUILT: 3b9afa6 (built from the working tree before commit, identical sources)
RESULT: PASS. GW_EXIT 0, licence OK on attempt 1. Built 10:16-10:24 BST.

RESOURCES: Logic 30,931/138,240 (23%), registers 8,569 (7%), CLS 19,005 (28%), BSRAM 135/340, I/O 118/297.
TIMING: TNS 0 on all clocks. clk32_core Fmax 33.09 MHz (32 MHz constraint; test build 34.07, margin thinner).
  clk_cpu030 Fmax 16.175 MHz (8 MHz build, 38 logic levels). 16 MHz experiment (copy in /tmp, not committed):
  constraint met, clk_cpu030 Fmax 16.552 MHz (36 levels), clk32 33.68 MHz. Worst in-domain path
  I_OPCODE_DECODER/OP_21 -> I_ADDRESSREGISTERS/PC_I_31 (~39.8 ns, 64% routing). 16 MHz possible but ~3% margin.
  Worst global setup paths ds2_p1/clk_spi -> clk32_core: pre-existing auto-derived clock artefact (as test build).
PINS: 447 pin rows identical to stage 2.
SIM: bridge unit tb 24/24 checks at 6 clock phases; whole-ST EmuTOS 1.3 sim runs 3000 bus cycles (reset vectors,
  ROM execution, Line-F exception frame, RESET, memory sizing). fx68k trace comparison not done.
BUS CYCLE: an 030 ST bus access takes ~1.33 us vs 0.5 us on the 68000 (CPU states + sync + phase alignment),
  so this build is slower than a stock ST.
TOS: use EmuTOS or TOS 1.04 (no PMOVE/MMU, so no TOS 3/4).
LICENCE: cpu030_st_bridge.v is GPL-2-only (TF534-derived); fx68k/MiSTeryNano are GPL-3. Mix to be resolved
  before any release.
FLASHING NOTES:
  CT2090 (upstream warning): because of NET_LOC V_JTAGSELN, do NOT use Gowin Programmer "SRAM Erase"
  (or any SRAM erase), otherwise the FPGA may not be found afterwards.
  If the screen stays blank after power-up, try a warm reset.
LOG: /workspace/repos/falconfpga_build_logs/a030_first_build.log (+ a030_first_impl/, a030_16mhz_impl/)
NOTES: Nothing flashed. No bitstream (.fs kept at /workspace/outputs/atarist_030_first.fs), logs, impl/, sim
  outputs or ROMs committed. BUILD_REQUEST.md and CONTEXT.md not edited.
```

## 2026-09-30 11:06 – Atarist_030_wip: README purpose section + LICENSE-NOTES.md (docs only, no build)

- `Atarist_030_wip/README.md`: rewritten top: what the build is for (68030 ST as a TF-style test bed for the Falcon), agreed rules (correct not patched; stock chipset; I/D caches and CACR go inside the WF68K30L core for portability; fx68k still selectable), origin, status table, known core limits. Old board/build notes kept; TOS line corrected to 0x500000.
- New `Atarist_030_wip/LICENSE-NOTES.md`: per-part licence table and the open GPL-2-only (bridge) vs GPL-3 question to settle before any public release.
- `NOTICE.md`: one row pointing to it.

## 2026-09-30 11:11 – LICENSE-NOTES.md: bridge scope (docs only)

- Added "Scope of the bridge": the TF534-style bridge is ST-test-bench only and won't go into the Falcon build (different bus logic), so the GPL-2/GPL-3 question affects only a public release of the ST test bench.

## 2026-09-30 11:18 – LICENSE-NOTES.md wording (docs only)

- Replaced "while the work stays private" with: repo is public but source only, no bitstreams; David will not share a built ST bitstream.

## 2026-09-30 11:45 – Atarist_030_wip README: credits to Stephen J. Leary (docs only)

- Added a "Credits and thanks" section under the title crediting TF534 as the model for the bridge, with an acknowledgement, plus his public Discord and Exxos forum links. Purpose text now under "What this build is for".

## 2026-09-30 11:47 – main README: credits callout (docs only)

- Added a callout near the top urging readers to read the Credits; Credits section reworded, Stephen J. Leary entry updated (bridge in Atarist_030_wip), JT49 (José Tejada) and hdl-util/hdmi (Sameer Puri) added; Layout row for Atarist_030_wip.

## 2026-09-30 12:50 – READMEs: HDMI/DVI video output section (docs only)

- `misterynano_tc138k/README.md` and `Atarist_030_wip/README.md`: new "Video output: HDMI or DVI" section near the top: the DVI_OUTPUT / ST_VIDEO switches in top.sv, why DVI is default, why the 640x480@60 frame-buffer output replaced the stock output, OSD not shown, ST audio not on HDMI yet, how to restore the original path. misterynano intro no longer says "stock".

## 2026-09-30 14:05 – cpu030_st_bridge.v: fuller credit to Stephen J. Leary (comments only)

- Header now opens with a CREDIT block for Stephen J. Leary / TerribleFire TF534 (files used and what each contributed, thanks), then the adaptation copyright. Inline "TF534 (Stephen J. Leary)" notes added at the IACK decode, DTACK sampling, arbitration, UDS/LDS and E/VMA logic. Code verified identical with comments stripped; no rebuild needed.

## 2026-10-01 11:22 – misterynano_tc138k: reset fix, drop bl616_jtagsel from por (build PASS, not flashed)

- Symptom: DVI sync but black screen. Cause: the Console's BL616 runs stock Sipeed firmware, which never drives `bl616_jtagsel` low; the V14 pull-up (PULL_MODE=UP) kept `por` high, so the ST stayed in reset. Upstream Nano 20K uses `wire por = !pll_lock;`.
- Change (`misterynano_tc138k/tang/console138k/top.sv`, one line; `jtagseln` output at the JTAGSELN line left unchanged, it gates no reset):

```
-wire por = !pll_lock || bl616_jtagsel; 
+wire por = !pll_lock;  // FalconFPGA: no BL616 jtagsel gating (stock BL616 firmware never drives it low; matches Nano 20K)
```

- Build: `gw_sh build_tc138k.tcl` PASS (licence OK attempt 1, ~4.5 min), TNS 0 setup/hold on all clocks. Fmax: clk32_core 35.0 MHz (32 target), clk_hdmi640_pix 86.4 MHz (25.2 target), clk_osc 163.6 MHz. Logic 18342/138240 (14%), BSRAM 141/340 (42%), PLL 2/12.
- Built from clean HEAD + this line only (no diagnostic code). Bitstream kept at `/workspace/diag_bitstreams/mn_resetfix.fs` (not committed). Not flashed; awaiting David's hardware test.

## 2026-10-01 19:36 – Atarist_030_wip: reset fix, drop bl616_jtagsel from por (same as 8adecde; build PASS, not flashed)

- Hardware confirmation: on 2026-10-01 at 19:25 BST David confirmed that 8adecde boots the standard misterynano_tc138k core to a TOS desktop on the Console with stock BL616 firmware.
- Same fix applied to `Atarist_030_wip/tang/console138k/top.sv` (one line; `jtagseln` output left unchanged, it gates no reset; no other bl616_jtagsel reset paths):

```
-wire por = !pll_lock || bl616_jtagsel; 
+wire por = !pll_lock;  // FalconFPGA: no BL616 jtagsel gating (stock BL616 firmware never drives it low; matches Nano 20K)
```

- Build: `gw_sh build_tc138k.tcl` PASS (licence OK attempt 1, ~10 min), TNS 0 setup/hold on all clocks. Fmax: clk_cpu030 17.18 MHz (8 target); clk32_core 32.002 MHz (32 target: met, near-zero margin, placement variance; earlier 030 builds 33-34 MHz); clk_hdmi640_pix 81.9 MHz (25.2 target); clk_osc 204.6 MHz. Logic 30481/138240 (23%), BSRAM 135/340 (40%), DSP 10.5, PLL 2/12.
- Bitstream kept at `/workspace/diag_bitstreams/030_resetfix.fs` (not committed). Not flashed.
