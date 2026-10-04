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

## 2026-10-01 21:50 – Atarist_030_wip: double reset on cold start (rigsdram AUTO_WARM scheme)

- Requested by David: give the 030 ST core the same automatic second reset that rigsdram's AUTO_WARM broker does (`rigsdram/src/rigsdram_top.vhd` AW_FREE_RUN 256 core clocks, then AW_PULSE 128 core clocks, once per power-up).
- Change, `Atarist_030_wip/atarist/atarist.v` only: after porb, wait for the first ST reset (`reset_cnt`) to end, count DR_GAP = 1536 clk_32 (~48 us: 16 us bridge RESET_HOLD + ~256 clk_cpu of free run at 8 MHz), then reload `reset_cnt <= 7'h7f` once (127 clk_32 ~4 us of `reset`, same as an ST reset button press; the bridge then holds the 030 another 128 clk_cpu = 16 us). Re-armed only by porb. Applies to both the CPU_030 and fx68k paths. SDRAM controller is outside atarist.v and is not reset.
- Note: README "Methods" says AUTO_WARM is a board workaround, not a core fix; this is that workaround applied to the ST core at David's request.
- Build/flash: results in the next entry.

## 2026-10-01 22:00 – Atarist_030_wip double cold-start reset (c967a5e): build PASS, flashed, still black

- Laptop build (`gw_sh build_tc138k.tcl`, impl/ deleted first, CPU_030 on): PASS, TNS 0 setup/hold all clocks. Fmax: clk32_core 32.069 MHz (32 target), clk_cpu030 17.622 MHz (8 target), clk_hdmi640_pix 95.9 MHz, clk_osc 200.8 MHz. Logic 30821/138240 (23%).
- Flashed to location 417 (programmer_cli op 53, SPI 0x000000): "Program Flash finished", 97 s.
- Capture ~15 s after flash: black frame (9.9 KB PNG), same as before the change. The double reset did not bring up the 030 desktop.

## 2026-10-02 12:52 BST – AE350 helper roadmap handoff (docs only)

- REQUEST_ID: 20261002-4
- ACTION: APPLY_ONLY
- RESULT: APPLIED. README.md roadmap step 7 added; docs only, no build.

## 2026-10-02 20:45 BST – bridge read-word sync + S0 reset handoff (rejected)

- REQUEST_ID: 20261002-5
- ACTION: BUILD (build only, do not flash)
- RESULT: NOT_RUN. `git apply --check handoff/20261002-2030-bridge-word-s0.patch` fails: `error: corrupt patch at line 71`. The hunk headers have wrong line counts: `@@ -211,18 +211,45 @@` in `Atarist_030_wip/cpu030/cpu030_st_bridge.v` carries 47 new lines (declared 45), and `@@ -121,6 +121,22 @@` in `Atarist_030_wip/tang/console138k/top.sv` carries 23 new lines (declared 22). Nothing applied, no build, no flash; TOS slot unchanged (EmuTOS).
- Note for Grok chat: the body is otherwise good; `git apply --check --recount` passes against current main (top.sv hunk 2 at offset +3). Regenerate with `git diff` (or fix the two counts to +211,47 and +121,23) and resubmit under a new REQUEST_ID.

## 2026-10-02 20:47 BST – 20261002-5 applied with --recount (David's exception): build PASS, not flashed

- REQUEST_ID: 20261002-5
- RESULT: APPLIED + BUILT (supersedes the NOT_RUN entry above). David approved applying `handoff/done/20261002-2030-bridge-word-s0.patch` with `git apply --recount` (the hunk counts were wrong, the content was fine). Commit 982beec.
- Change: `cpu030_st_bridge.v` passes the returning tag, DSACK, AVEC, BERR and read word through two clk_cpu flops before the 030 sees them. `top.sv` drives `misterynano.reset` from S0 (`reset_n`), synchronised and armed only after 65535 clk cycles past pll_lock.
- Laptop build (`gw_sh build_tc138k.tcl` in Atarist_030_wip, impl/ deleted first, ~6 min, log `build_local_20261002-5.log`): PASS, TNS 0 setup/hold on all clocks. Fmax: clk32_core 34.608 MHz (32 target), clk_cpu030 14.308 MHz (8 target), clk_hdmi640_pix 80.202 MHz (25.2 target), clk_osc 171.591 MHz.
- Note: the setup path table shows negative slack (worst -13.742 ns) from `misterynano/flash/dout_0_s0` to `atarist/dma/acsi/cmd_parameter` registers, launched from `pll_hdmi CLKOUT3.default_gen_clk` (no create_clock, default 100 MHz) into clk32_core. These are not counted in the TNS summary. The flash/ACSI path was not changed by this patch.
- Bitstream: laptop `Atarist_030_wip\impl\pnr\atarist_tc138k.fs` (not committed).
- Flash: NOT flashed, on David's instruction. TOS slot untouched (EmuTOS at 0x500000).
- Screen result: pending David's monitor check (EmuTOS logo then GEM desktop = pass; snow or blank = fail; snow that clears to the desktop after S0 = cold-start reset fault).

## 2026-10-02 21:58 BST – ROM-fetch LED handoff (rejected)

- REQUEST_ID: 20261002-6
- ACTION: BUILD_AND_FLASH (TOS: keep)
- RESULT: NOT_RUN. `git apply --check handoff/20261002-2148-rom-fetch-led.patch` fails: `error: corrupt patch at line 18` (hunk line counts wrong: the first bridge hunk `@@ -309,6 +309,11 @@` carries 7 old / 13 new lines). David approved `--recount` for count-only failures, so I tried it. The three `cpu030_st_bridge.v` hunks then apply (offsets +29/+37/+30). The `Atarist_030_wip/tang/console138k/top.sv` hunk still fails (`patch failed: top.sv:175`). Its context lines `// use leds for debugging, leds are active low` and `// ------------ clock and reset -----------` are not in that file. The real code is `wire [5:0] leds_int_n;` / `assign leds_n = ~leds_int_n[1:0];` at lines 194-195. Not a count-only failure, so the patch was rejected. Nothing applied, no build, no flash; TOS slot unchanged (EmuTOS).
- Note for Grok chat: regenerate the patch with `git diff` against current main (d245a96 or later) and resubmit under a new REQUEST_ID. `top.sv` reads the bridge flag through the hierarchical name `misterynano.atarist.cpu030.rom_fetch`. The bridge instance in atarist.v is `cpu030` (line 499). GowinSynthesis may not accept a hierarchical reference in synthesis, and a port out of the bridge, atarist and misterynano is the safer route.

## 2026-10-02 22:31 BST – ROM-fetch LED through ports: build PASS, flashed

- REQUEST_ID: 20261002-7
- ACTION: BUILD_AND_FLASH (TOS: keep)
- RESULT: APPLIED + BUILT + FLASHED. `git apply --check` clean (no --recount needed). Commit 77ca552.
- Change: `cpu030_st_bridge.v` latches `rom_fetch` on the first accepted ST cycle with A23:20 == E or A23:16 == FC/FD/FE, cleared in the bridge reset branch. The flag goes out as a port through atarist.v (tied 0 in the fx68k build) and misterynano.sv to top.sv, which drives `leds_n[0]` = ~rom_fetch (pin low = LED on). `leds_n[1]` unchanged. No hierarchical reference.
- Laptop build (`gw_sh build_tc138k.tcl` in Atarist_030_wip, impl/ deleted first, ~5.7 min, log `build_local_20261002-7.log`): PASS, TNS 0 setup/hold on all clocks. Fmax: clk32_core 32.368 MHz (32 target, thin margin), clk_cpu030 17.361 MHz (8 target), clk_hdmi640_pix 92.669 MHz (25.2 target), clk_osc 193.205 MHz. Logic 30583/138240 (23%). leds_n[0] placed on G11, leds_n[1] on U12.
- Note: the first gw_sh start exited 1 at once with an empty log (transient). The successful run was from a clean impl/. The setup path table shows negative slack (worst -14.281 ns) on `ds2_p1/clk_spi` -> ikbd paths. These are not counted in the TNS summary and were not touched by this patch.
- Flash: programmer_cli op 53, location 417, SPI 0x000000, `...\Atarist_030_wip\impl\pnr\atarist_tc138k.fs`: "Program Flash finished", 0x000000-0x04A9A00, 97 s. The first flash run finished in ~102 s but its console capture was truncated by progress output. The same image was flashed again to confirm the result (log `flash_20261002-7.log` on the laptop).
- TOS: untouched, EmuTOS at 0x500000.
- LED/screen result: pending David. leds_n[0] (G11) on and staying on = a ROM fetch left the bridge; off after power-up = the 030 never started one; S0 clears it, then it comes back on if the next boot fetches. Screen may still be snow.

## 2026-10-03 07:15 BST – diag030 local debug build, not committed HDL, flashed

- REQUEST_ID: manual-20261003-diag030 (David approved: DEBUG build, local only, do not commit the HDL)
- Patch: `/workspace/diag030.patch` on Grok Bot's box (sha256 dde97963…285a), made with `git diff` against main b321d4a. Ports the misterynano_tc138k diagnostic overlay to Atarist_030_wip: new `tang/console138k/diag_overlay.v`, plus port-only edits to `cpu030_st_bridge.v`, `atarist.v`, `misterynano.sv`, `hdmi_testpattern_640.sv`, `top.sv` and `build_tc138k.tcl`. No hierarchical references. 20 status squares are drawn straight onto the 640x480 output after the frame buffer (rows at y 296/360/424). The 030 additions are: 030 out of reset, 030 AS seen, rom_fetch, DSACK seen, and BERR seen (colours inverted). leds_n[0] is still ~rom_fetch. leds_n[1] blinks while the 030 runs bus cycles. FB self-test is a separate mode and is left OFF (`DIAG_FB_SELFTEST 0`).
- Laptop build (`gw_sh build_tc138k.tcl`, impl/ deleted first, 352 s, log `build_local_diag030.log`): PASS, GW_EXIT 0, TNS 0 setup/hold on all clocks. Fmax: clk32_core 34.258 MHz (32), clk_cpu030 15.993 MHz (8), clk_hdmi640_pix 85.758 MHz (25.2), clk_osc 196.863 MHz. Logic 30782/138240 (23%). leds_n[0] G11, leds_n[1] U12. The old ds2_p1/clk_spi -> ikbd negative-slack paths are unchanged (not in TNS).
- Flash: programmer_cli op 53, location 417, SPI 0x000000, `C:\Users\dave_\OneDrive\Documents\GitHub\falconfpga\Atarist_030_wip\impl\pnr\atarist_tc138k.fs`: "Program Flash finished", 0x000000-0x04B5400, 97.66 s, exit 0 (log `flash_diag030.log`). TOS was not touched (EmuTOS at 0x500000).
- Laptop: afterwards `git checkout -- .` restored the tracked files. impl/ and the .fs were kept, as were the untracked `diag030.patch` and `tang/console138k/diag_overlay.v`. Main has no diag HDL; to rebuild, apply the patch again.
- Square/LED key: in the square table in `diag_overlay.v` (in the patch). Result pending David.

### 2026-10-03 08:03 BST – diag030 monitor result (David)

- Power-up: snow over the whole picture. LED U12 blinks, so the 030 is running bus cycles.
- Squares: S17-S19 green. S20 yellow, so a bus error was seen earlier but not now. Row 1 all green, with S1/S2 blinking and S8 (frame-buffer writes) green. S11/S12 green, S13 yellow, S14-S16 green (030 not halted). TOS word bars read 0x602E, the correct EmuTOS first word.
- After S0 (AA13): S17-S19 go yellow→green, S20 red→yellow (a bus error early on every boot), S5/S6/S7/S10 yellow→green, and S11 goes through a reset cycle. The word bars don't change. The picture is still snow afterwards, so this is not a cold-start problem.
- Conclusion: the CPU, ROM fetch, bus handover and DSACK work. Memory contents or writes are wrong. Requests for Grok chat are in SYNC_FOR_GROK_CHAT.md ("diag030 results 2026-10-03"): (1) bridge write splitting and byte lanes, (2) the source of the early BERR, (3) misaligned and long accesses under 16-bit dynamic bus sizing.

## 2026-10-03 09:05 BST – "write at S4" handoff: reviewed, rejected as ineffective

- REQUEST_ID: 20261003-1
- ACTION: BUILD (review first, no flash)
- RESULT: NOT_RUN (review). `git apply --check` was clean, but the patch does not change the hardware's behaviour, so it was not applied or built. Laptop, diag030 overlay, flash and TOS untouched.
- What it does: in `cpu030_st_bridge.v`, a write request is opened only when the 030's DSn is low (`!c_open && (cpu_rwn || !cpu_dsn)`), so `cpu_dout[31:16]` would be captured later. Reads are unchanged.
- Why it is ineffective (from `wf68k30L_bus_interface.vhd`):
  - `DATA_PORT_OUT` (the bridge's `cpu_dout`) is purely combinational from `WP_BUFFER`, `SIZE_I` and `ADR_OUT_I`. `WP_BUFFER` is loaded on the IDLE->START_CYCLE edge, before ASn falls, and frozen for the whole access (WRITEBACK_INFO). STERMn does not gate it, and DATA_EN/DBENn only control a tri-state the bridge does not use. The write word is valid at S1/S2, so the premise "data not valid until S4, so the bridge stored the previous word" does not hold for this core.
  - DSn for a write is not S3-only. The second term of the DSn equation (`'0' when S0..S4`, commented "Read") is not qualified by RW, so a write has DSn low in S0..S5, the same time as ASn. The new condition is already true at the edge where the bridge opens now, and the patch changes nothing.
- Evidence: the unit bench `Atarist_030_wip/cpu030/sim/tb_bridge.v` (WF68K30L Gowin netlist + bridge against a behavioural ST bus, `prog.s` with long, word, even/odd byte and misaligned-long writes and reads) was run on current main and on main + this patch (MAX_US 700; the default 400 us now ends just before the done marker because the bus is slower since the 20261002-5 sync). Both give ERRORS=0, and the ST bus traces (240 cycles, 91 writes) are byte-identical, timestamps included. All write checks pass on main: $2000 long 12345678, $2004 word ABCD, $2006/$2007 bytes 11/22 (UDS/LDS lanes correct), misaligned long at $2009 split correctly (00A5A55A / 5A00). Half order, A1 of the second cycle, UDS/LDS and the lane placement are correct per MC68030 16-bit dynamic bus sizing (DSACK1 only). No compatibility hack in the patch, and it does not touch the diag030 area of top.sv.
- Note for Grok chat: at the bridge level the 030 write path is correct, so the snow is probably elsewhere. Candidates: (1) the early BERR. The bridge answers every non-IACK CPU-space cycle (FC=7, e.g. coprocessor/FPU or MMU probes) with BERR. Check what EmuTOS probes and that WF68K30L takes the exception a real 030 would (a BERR on a coprocessor-space cycle should end as an F-line exception on a real 030 with no FPU). A latch of the first BERR address/FC in diag030 would settle it. (2) Run the whole-system bench `sim/tb_st.v` (atarist.v + EmuTOS, it logs every CPU ST cycle) far enough to see the screen-memory writes and compare with what the shifter fetches.

## 2026-10-03 09:17 BST – diag030b local debug build (BUILD ONLY, not flashed, HDL not committed)

- REQUEST_ID: manual-20261003-diag030b (David approved: build only, no flash, local HDL)
- Patch: `/workspace/diag030b.patch` on Grok Bot's box (sha256 4ee1fbb6…0769d), made against main e502d8f. It includes all of diag030 and adds:
  - the bridge's first-BERR latch: A31:0 (A31:24 from a new front-end flop), FC2:0, RW, SIZE, and whether the BERR came from the bridge itself (CPU space) or from the ST bus;
  - the last 030 program fetch (FC x10), live and frozen at the first BERR;
  - an ST-bus capture in atarist.v of the bytes written to $FF8201/$FF8203, with a written flag for each.
  All latches clear on the ST reset. The signals go out through ports (bridge `dbg_trace[87:0]`, atarist `dbg_vbase[17:0]`). The overlay draws four new bit-bar rows a-d at y 160-287, above the squares. S1-S20 and the TOS word bars are unchanged. Key: SYNC_FOR_GROK_CHAT.md 2026-10-03 09:17.
- Laptop build (`gw_sh build_tc138k.tcl`, impl/ deleted first, 346 s, log `build_local_diag030b.log`): PASS, GW_EXIT 0, TNS 0 setup/hold on all clocks. Fmax: clk32_core 36.304 MHz (32), clk_cpu030 15.705 MHz (8), clk_hdmi640_pix 72.103 MHz (25.2), clk_osc 209.569 MHz. Logic 31205/138240 (23%), registers 9311 (7%). All 111 new latch flops are present in the netlist. The old ds2_p1/clk_spi -> ikbd negative-slack paths are unchanged (not in TNS). Nothing had to be simplified, so row d (live fetch) is in.
- NOT FLASHED. The board still runs diag030. .fs: `C:\Users\dave_\fpga_caps\diag030b.fs`, a copy of `...\Atarist_030_wip\impl\pnr\atarist_tc138k.fs` (sha256 F8173D0C…6F69029). The flashed diag030 image was saved first as `C:\Users\dave_\fpga_caps\diag030.fs`.
- Laptop: `git checkout -- .` afterwards. impl/ and the .fs are kept. The untracked `diag030b.patch`, `diag030.patch` and `tang/console138k/diag_overlay.v` (now the diag030b version) are also still there.

## 2026-10-03 19:45 BST – F55 WF68K30L interrupt-mask fix (RTL bench verified, board built + flashed with diag030c)

- REQUEST_ID: manual-20261003-fix030 (David approved: bench, fix, build, flash 417, capture, commit core fix)
- RTL bench (GHDL 6, WF68K30L alone, 16-bit port, DSACK1, AVEC on IACK): `Atarist_030_wip/cpu030/sim/rtl/` (`run_rtl.sh`, `tb030.vhd`, `prog_srmask_a/b.s`).
  - Bug reproduced: an interrupt latched while the main controller sleeps in MOVE to SR (INT_TRIG is active in SLEEP, the SR is still the old one) was taken after `move #$2700,sr` finished: stacked SR $2700, stacked PC = next instruction (level 4 taken with mask 7). Prog A: 14 of 61 IRQ delays; prog B (EmuTOS $FD3C9E sequence) 2 of 81 delays per wait-state setting (WS 0/3/8).
  - Root cause: `wf68k30L_exception_handler.vhd`, EX_P_INT is set when `INT_TRIG = '1' and STATUS_REG_IN(10 downto 8) < IRQ` (line ~337) and is never re-checked against the mask before the exception starts.
  - Fix (F55): new `INT_REQ = EX_P_INT and (IRQ_PEND_I = "111" or SR mask < IRQ_PEND_I)` is used for EXH_REQ, IPENDn, the exception selection and the IDLE->INIT decision; a pending request that the new mask covers is dropped (re-latched by INT_TRIG when the mask goes down). Level 7 stays nonmaskable.
  - After the fix: 0 interrupts above the mask in all sweeps, all runs finish, the deferred interrupt is taken after the mask is lowered (stacked SR $2300). STOP #$2300 wake-up unchanged. `run_rtl.sh` prints PASS (FAIL on the old core).
  - Not reproduced in RTL: (1) the board stall after `move #$2700,sr` at $FD3CA4 (no stall in any run, incl. EmuTOS 192K booted for 1.5M clocks), (2) PC A20..A18 dropped (RTL fetches $FC772E correctly after `jsr $00FC772E`, EmuTOS boot fetches stay in $FC-$FE). Both point at synthesis/board: the Gowin log lists combinational loops in the core (AG0100, e.g. `NEXT_FETCH_STATE[2]` control.vhd:2478, control.vhd:776-801/1891-1910, data_registers.vhd:110-111) and a latch (alu.vhd:494 BF_NZ).
- Laptop build (fix + local diag030c overlay, not committed): PASS, TNS 0 all clocks, clk32_core 37.122 MHz, clk_cpu030 17.669 MHz. Flashed location 417: "Program Flash finished" (99.7 s).
- Board result: unchanged. Snow; diag030c bars identical to before the fix (last cycle started $00E13CA6 program word fetch, DSACK, no cycle in progress, not hung, IPL level 2 pending, IACKs taken, bridge idle, cycle counter still moving). The F55 fix is a real 68030-conformance fix but not the cause of the stall.

## 2026-10-03 20:30 BST – F56 WF68K30L: combinational loops (AG0100) and BF_NZ latch removed (RTL + gate-level verified, board built + flashed with diag030c)

- REQUEST_ID: manual-20261003-loops030 (David approved: remove loops/latch, rebuild, flash 417, capture, commit core)
- Gowin synthesis of the core alone (`cpu030/sim/wf030_syn.tcl`): before 17 AG0100 + 1 EX4160 latch, after 0 + 0. Full build: 0 AG0100/EX4160 in the core.
  - Loop 1: NEXT_FETCH_STATE -> INIT_ENTRY -> DR_SEL_RD_2 (BFINS `INIT_ENTRY` arm, F22/F24) -> DR_IN_USE (data hazard) -> FETCH_DEC -> NEXT_FETCH_STATE (warnings control 466/511/776-818/1891-1910/2478, data_registers 110-111). Broken: read port 2 still selects the BFINS pattern register at INIT_ENTRY, but the hazard check compares new outputs DR_SEL_ADH_2 (port-2 select without the INIT_ENTRY arm) and DR_SEL_ADH_3 (BIW_1(14:12) whenever OP = BFINS). It covers the same registers, and can only add a wait.
  - Loop 2 (shown once loop 1 was gone): NEXT_FETCH_STATE -> INIT_ENTRY -> OP_SIZE (PACK/UNPK arms) -> DATA_IMMEDIATE -> BRANCH_ATN -> NEXT_FETCH_STATE (ANDI/EORI/ORI/MOVE to SR). Broken: BRANCH_ATN takes the S/M bits from BIW_1 (xxI to SR) and IBUFFER(13:12) (MOVE #imm,SR) directly. These are bit-identical to DATA_IMMEDIATE(13:12) for those opcodes.
  - Latch: alu.vhd P_BITFIELD_OP, BF_NZ/BFFFO_CNT get defaults at process start (only read on the BFFFO path, which assigns them).
- RTL (GHDL): progA/B/C/D (D = new BFINS/BFFFO/BFEXTU register+memory test with hazards) cycle-identical to 61147c9 under 3 IRQ/WS settings. IRQ sweeps B WS 0/3/8 81/81 done, stacked SR $2300. `cpu030/sim/rtl/run_rtl.sh` PASS. EmuTOS 1.5M clocks: log identical to before (fetches stay in $FC-$FE).
- Gate level: `cpu030/sim/run_unit.sh` on the new netlist (MAX_US 700): ERRORS=0 for all 6 phases, ST bus traces byte-identical to the 61147c9 netlist.
- Laptop build (F56 + local diag030c overlay, deterministic, rebuilt for timing reports): PASS, TNS 0 all clocks. clk32_core 32.066 MHz (37.122 before; core-unrelated placement change, still >= 32), clk_cpu030 18.627 MHz (17.669 before), 41 logic levels.
  - clk_cpu030 worst path after: OP reg -> ALU_OP2_IN -> DR_SEL_RD_1 -> NEXT_FETCH_STATE -> AR_SEL_RD_1 -> NEXT_FETCH_STATE -> OP_SIZE -> ALU_OP1_IN -> exception handler EX_P_TRACE (slack 71.3 ns of 125).
  - Before: the fmax figure did not match any reported path, because STA cut the loop arcs. The worst analysed path was OP reg -> PHASE2/ADR_MODE -> DR_SEL_RD_1 -> NEXT_FETCH_STATE -> DR/AR mux -> ADR_EFF (slack 82.2 ns).
- Flashed location 417 (`C:\Users\dave_\fpga_caps\loops030.fs`): "Program Flash finished" (101 s). Board unchanged: still snow, and the diag030c bars match fix030 (last cycle $00E13CA6, bridge idle, counter moving).

## 2026-10-04 07:45 BST – F57 WF68K30L: explicit power-up values for set-type flops (RTL + gate-level verified, no build)

- REQUEST_ID: manual-20261004-f57 (David approved: commit F57)
- Cause: Gowin synthesis drops implicit VHDL initial values. A register mapped to a set-type flop (DFFSE) without an INIT then powers up at 1, while RTL starts it at 0/false. 18 such flops in the core netlist (core-only and the full board build alike).
- Visible effect: BKPT_REQ = 1 at configuration. The first instruction-word request takes the "restore from breakpoint" path (IPIPE.D <= IPIPE_D_VAR, pipe not advanced) and corrupts the first instruction. Gate-level `run_unit` program (first instruction `move #$2700,sr`): the CPU drops to user mode (FC 2/1 from then on). TOS 1.04 also starts with `move #$2700,sr` at $FC0030, so a cold start could drop to user mode and take a privilege violation at the following `reset`. EmuTOS starts with BRA $FC004E, which absorbs it (benign, not the EmuTOS board stall).
- Fix (F57): explicit initial values in `wf68k30L_opcode_decoder.vhd` (BKPT_REQ, LOOP_BSY_I, OPCODE_FLUSH, FLUSHED; LOOP_BSY driven by one concurrent assignment) and `wf68k30L_alu.vhd` (ADR_MODE, BF_UPPER_BND, CAS2_COND, CHK2CMP2_DR, SHIFT_WIDTH; new ALU_BSY_I := '0' drives ALU_BSY). Values equal what RTL already assumed.
- Verification: RTL progA/B/C/D cycle-identical to c3493db (3 IRQ/WS settings); `cpu030/sim/rtl/run_rtl.sh` PASS. Re-synthesis: only MSBIT_0, DATA_VALID, IRQ_PEND_I remain without INIT (all set by the CPU reset). New netlist cycle-identical to RTL (progA-D, run_unit program, TOS 1.04 start); `run_unit.sh` ERRORS=0 (3 phases).
