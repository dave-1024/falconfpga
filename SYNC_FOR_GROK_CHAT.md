# SYNC FOR GROK CHAT

Catch-up note for Grok chat. Newest entries are at the top. All times are UK time (BST, UTC+1).

## Purpose

Grok chat (David's HDL-writing assistant) is out of tokens until 1 Oct 2026. Until then, David asks
Grok Bot for changes directly, and Grok Bot edits, builds and logs everything here and in
`BUILD_REPORT.md`. **Grok chat: please read this file first when you are back, before assuming any
old state.** While this note is active, Grok Bot may edit HDL at David's request.

## diag030 results 2026-10-03 (David's monitor)

Build: diag030 local debug build (key under the 2026-10-03 07:15 entry below; BUILD_REPORT 2026-10-03 08:03).

- **After power-up:** snow over the whole picture. LED U12 blinks, so the 030 is running bus cycles.
- **Squares:**
  - Row 0: S17, S18 and S19 green. S20 yellow (a bus error was seen earlier, not now).
  - Row 1: all green. S1/S2 (vsync/hsync) blink, and S8 (frame-buffer writes) is green.
  - Row 2: S11 and S12 green, S13 yellow, S14-S16 green (030 not halted).
  - The TOS word bars read 0110 0000 0010 1110 = 0x602E, the correct EmuTOS first word.
- **After pressing S0 (AA13):** S17-S19 go yellow→green and S20 goes red→yellow, so a bus error happens on EVERY boot,
  early. S5/S6/S7/S10 go yellow→green, and S11 goes through a reset cycle. The word bars don't change. The picture is
  still snow afterwards, so this is NOT a cold-start problem.
- **Conclusion:** the CPU, ROM fetch, bus handover and DSACK all work. Memory contents or writes are wrong.
- **Requests for Grok chat:**
  1. Check how the bridge splits 32-bit and byte/word writes into 16-bit ST cycles: the order of the halves, the
     second-cycle address (A1), the UDS/LDS byte strobes, and the data lane placement for byte writes at odd and even
     addresses.
  2. Find out which access raises the early BERR. Consider adding a latch of the first BERR address to the diag bars
     in a future patch.
  3. Check that the 030's misaligned and long accesses are handled the way a real 030 with 16-bit dynamic bus sizing
     (DSACK1 only) would handle them.

## Changes since 2026-09-29 (running log, Grok Bot adds entries here, newest first)

- 2026-10-03 07:15: **diag030 local DEBUG build (HDL not committed)**: the misterynano_tc138k status-square overlay was ported to
  Atarist_030_wip, built on the laptop (PASS: clk32_core 34.258, clk_cpu030 15.993 MHz, TNS 0) and flashed to 417. The patch
  is at `/workspace/diag030.patch` on Grok Bot's box (not in the repo). See BUILD_REPORT 2026-10-03 07:15.
  - **diag030 square KEY** (squares 48 px with a black frame, columns at x = 8 + 64*i, read left to right; drawn
    straight on the 640x480 output after the frame buffer, lower-left of the picture).
    - Colour rules. Events: green = happening now (last ~0.13-0.26 s), yellow = happened earlier but not now, red = never
      since power-up. Levels: green = true now, yellow = was true earlier but not now, red = never true. **S20 is inverted:**
      green = never seen, yellow = seen earlier, red = happening now.
    - Row 0 (y 296-343), 030 bridge: **S17** x 8: 030 bus cycle started (bridge saw 030 AS); red = 030 never issues a cycle.
      **S18** x 72: rom_fetch latch (same flag as LED0), set by the first bridge cycle to E0xxxx or FC-FExxxx, cleared by
      reset; yellow = set, then cleared by a reset (e.g. S0) and not set again. **S19** x 136: DSACK returned to the 030
      (ST cycles completing). **S20** x 200: BERR returned to the 030 (inverted colours; includes non-IACK CPU-space cycles,
      which the bridge answers with BERR).
    - Row 1 (y 360-407): **S1** x 8: ST vsync (blinks green/dark green while alive). **S2** x 72: ST hsync (blinks ~1 s).
      **S3** x 136: ST DE seen. **S4** x 200: non-black ST pixels. **S5** x 264: ST-side bus cycles (AS falling edges on the
      68000-style bus the bridge drives); S17 green + S5 red = bridge never gets the ST bus. **S6** x 328: TOS ROM selected
      (ROM2_N). **S7** x 392: ROM read returned data other than 0000/FFFF. **S8** x 456: ST frame-buffer writes.
      **S9** x 520: main PLL locked (level). **S10** x 584: 68030 out of reset, bridge released its reset input (level;
      replaces the original JTAGSEL square, JTAGSEL no longer affects reset).
    - Row 2 (y 424-471): **S11** x 8: atarist reset input released (level). **S12** x 72: SDRAM init done (level).
      **S13** x 136: BL616 has talked to the core over SPI (event). **S14** x 200: BL616 not holding the ST in reset
      (level). **S15** x 264: SD wait done, image found or 2 s timeout (level). **S16** x 328: 68030 not halted (level;
      red/yellow = double bus fault halt).
    - TOS word bars (row 2, x 392-635): 16 bars = first TOS word read from ROM offset 0, MSB left, four groups of four;
      white = 1, dark grey = 0. A TOS image normally starts with BRA, so expect 0110 0000 in the left two groups. All grey =
      never read or read as 0000.
    - LEDs. **LED0** (leds_n[0], G11): unchanged, driven by `~rom_fetch`. **Polarity uncertain:** stock MiSTeryNano drives
      these pins high for "on", which would make G11 lit until the first ROM fetch and dark after; the 20261002-7 report
      assumed pin low = lit. Settle it by comparing LED0 with square S18 once there is a picture. **LED1** (leds_n[1],
      U12): blinks ~2 Hz while the 030 runs bus cycles, steady (on or off) when not; readable with either polarity.
    - **Grok chat: while diag030 is in use, please do not send patches that touch the video overlay area of
      `Atarist_030_wip/tang/console138k/top.sv`** (the leds_n assignment, the misterynano diag ports, the area after
      `assign clk32 = clk_pixel;`, and the hdmi_tp instance). diag030.patch is applied locally on the laptop on top of main
      and would conflict.
- 2026-09-30 10:45: **`Atarist_030_wip/` first 030 test** (commit `3b9afa6`): WF68K30L 68030 replaces fx68k via
  `cpu030/cpu030_st_bridge.v` (`CPU_030` define in atarist.v), CPU 8 MHz from PLL CLKOUT5. Build PASS, pins identical,
  CPU Fmax 16.175 MHz (16 MHz experiment 16.552 MHz), clk32 33.09 MHz. See BUILD_REPORT manual-20260930-a030-first.
- 2026-09-30 09:10: new WIP folder **`Atarist_030_wip/`** (commit `b78df28`, next to
  `misterynano_tc138k/`): a copy of the tracked `misterynano_tc138k` files at `c2d695d` (stage 2, ST
  video via BSRAM frame buffer to 640x480@60 DVI), the starting point for new work. 108 files, no
  path changes needed (only a README note). Test build `manual-20260930-atarist-030-wip` from that
  folder PASS, pins and timing identical to stage 2. `misterynano_tc138k/` stays as the reference.
  David has NOT bench-tested stage 2 yet. Not flashed.
- 2026-09-30 07:55: stage 2 ST video (commit `274f8b0`, build `manual-20260930-stage2-stfb` PASS).
  First, reported by David: stage 1b DVI colour bars (c6b1246) confirmed WORKING on both the DVI
  monitor and the old HDMI TV (2026-09-30). Now the raw ST video (clk32, before scandoubler/OSD, so
  **no OSD**) goes into a 120-block BSRAM frame buffer (`st_framebuffer.v`) and out through the
  640x480@60 DVI path: colour 640x240 (20 border lines top/bottom) line-doubled to 480, mono 640x400
  centred; window follows DE (PAL/NTSC/mono auto), mono detected from the hsync period. Default
  `.ST_VIDEO ( 1 )`, set 0 for colour bars; DVI_OUTPUT still 1. Tuning: ST_H_OFS_COLOR (96),
  ST_V_BORDER (20), MONO_TOP (40). Sim: 3 modes, 0 pixel errors. BSRAM 141/340, pixel Fmax 81.3 MHz,
  clk32 34.07 MHz (+0.35 ns worst), 8/8 primary, pins identical, jtagseln T20. Limits: tearing and
  judder, PAL low-res horizontal offset unverified. Not flashed. No "SRAM Erase" (CT2090).
- 2026-09-29 21:25: stage 1b DVI mode (commit `c6b1246`, build `manual-20260929-stage1b-dvi`
  PASS). Stage 1 HDMI (88a4b08): colour bars and tone WORK on David's TV, but the monitor (DVI input,
  DVI-to-HDMI cable) shows no sync, most likely because it rejects HDMI data islands/guard bands. So
  `hdmi_640.sv` now has `DVI_OUTPUT` (plain DVI 1.0: video + control periods only, CTL bits 0, no
  audio) and **DVI mode is now the default** (`top.sv` `.DVI_OUTPUT ( 1 )`; set 0 for HDMI + tone on
  the TV). Also fixed a 1-pixel offset (column 0 was dropped) in both modes. Pixel clock Fmax
  133.6 MHz, clk32 35.277 MHz (+2.9 ns), pins identical, jtagseln T20, 8/8 primary. Symbol-level sim:
  no island/guard symbols, CTL=00, syncs on ch0. Not flashed. No "SRAM Erase" (CT2090).
- 2026-09-29 20:36: stage 1 video-out sanity check (commit `88a4b08`, build
  `manual-20260929-stage1-colourbars` PASS). TV test of the pll32 build first (reported by David):
  flashed, the Console gives "invalid format" on the old TV while the 20K is OK there; the main monitor
  shows no sync on both. So `top.sv` now has `` `define HDMI_TESTPATTERN ``: the core stays running but
  its video is off HDMI, and a standalone 640x480@60 (VIC 1, 4:3) picture is sent instead: 8 colour
  bars with a 1 px white border plus a quiet 1 kHz beeping tone. It uses its own PLL
  (`gowin_pll_hdmi`, from Hybrid030, 126 MHz) with CLKDIV/5 = 25.2 MHz and MiSTeryNano's `hdmi/` core
  (`hdmi_640.sv`). Pixel clock Fmax 104.4 MHz (+30.1 ns); clk32 margin now only ~0.11 ns
  (32.117 MHz). TMDS pins identical, jtagseln on T20, primary clocks 8/8 (ds2 SPI clock moved to LW).
  To switch back: comment out the define AND edit `atarist.sdc` (re-enable clk_hdmi, comment out the
  stage 1 block). Not flashed. No "SRAM Erase" (CT2090). Details in `BUILD_REPORT.md`.
- 2026-09-29 13:35: exact 32 MHz PLL for the Console (commit `6fe62b8`, build `manual-20260929-pll32`
  PASS). `pll_160m_mod.v` now MDIV 16, VCO 800 MHz, ODIV 5/25/25/8/8: 160 MHz TMDS, 32.000 MHz pixel
  (was 31.667 MHz, ~1.2% slow), 32 MHz SDRAM clock at 338.4 deg (was 337.5), 100 MHz flash/mspi (was 95).
  `pll_160m.v` MULTI_FAC 16, `top.sv` PIXEL_CLOCK 32_000_000, `atarist.sdc` clk_32 31.25 ns.
  `atarist.cst` now pins `jtagseln` to T20 (it had been auto-placed on H17, USB-C D+). Pixel clock Fmax
  33.923 MHz, `.fs` 37047546 bytes. Not flashed yet. Do not use Gowin Programmer "SRAM Erase" (CT2090).
  TOS still at 0x500000. Details in `BUILD_REPORT.md`.
- 2026-09-29 12:47: this note created. No HDL changed.

## Current goal

Get the Console 138K version (`misterynano_tc138k`) showing a picture on David's very old HDMI TV,
starting from the rolled-back known-good tree (`66f57bb`).

## Nano 20K bench result (reported by David)

Stock MiSTeryNano on David's Tang Nano 20K gave a picture on his very old HDMI TV. This proves the TV
works with MiSTeryNano's stock HDMI output.

## TOS flash address (verified from the HDL)

- On this Console build, TOS goes at byte offset **0x500000**. The `08dc9cc` claim of 0x100000 was wrong.
- `misterynano.sv` lines ~149-159 pass the word address `{3'b001, slot, ste, rom_addr[17:1]}`.
- `tang/console60k/flash_dspi.v` (the flash module this project uses) forces byte bit A22=1 via
  `(state==6'd8)?{2'b01}`, which adds 0x400000, and shifts the word address to a byte address.
- So: ST TOS at 0x500000, STE at 0x540000, secondary slots at 0x580000 and 0x5C0000.
- 0x100000 is the Tang Nano 20K layout. On the Console it would land inside the bitstream.
- This matches the upstream MiSTeryNano Console 60K table.

## 2026-09-28 21:49 - build `manual-20260928-rollback` of `66f57bb`: PASS

- The `.fs` is 36538618 bytes, identical to mn3/mn4.
- Pixel clock CLKOUT1 reaches 33.313 MHz against a 31.667 MHz target.
- `-co-place_io_registers 0` was accepted by Gowin 1.9.12.03, so the `d10de5b` claim that it is
  unknown was wrong.
- No HDMI pin errors. The only negative slack is on cross-clock paths from auto-detected clocks
  (`ds2_p1/clk_spi` into IKBD setup at -19.7 ns, and `video2hdmi/clk_audio` hold at -2.1 ns),
  unchanged from before.
- Report commit: `bca98e9`.

## 2026-09-28 21:43 - rollback

`misterynano_tc138k/` was rolled back to `687446a` (the last good mn3/mn4 build tree) in commit
`66f57bb`, at David's request. It undoes 14 commits, `ea085ff`..`f492d96`:

- the HDMI pin sim files `sim/tb_hdmi_pins.sv` and `sim/run_hdmi_sim.sh` (deleted)
- the `d10de5b` tcl co-place change
- the stray empty file `git`
- the `00ebf80` `atarist.cst` separate HDMI P/N constraint (G16 tmds_clk_n)
- the `08dc9cc` README TOS address change
- all LED blink and Timer C probe work in `top.sv` and `atarist/mfp.v`
  (`9fb57be`, `3d2b7e7`, `1191ff6`, `4c85fb0`, `5c809f7`, `bafd9d3`, `6e72415`, `f492d96`)

The history is kept, so any of it can be restored.

## Open notes

- The old CONTEXT.md base64 handoff (2026-09-28-2, CHANGED 1) was not decoded because ACTION was
  NO_BUILD. It is retained as historical context only; the retired BUILD_REQUEST/CONTEXT watcher is
  superseded by the Patch handoff.
- `BUILD_REQUEST.md` and `CONTEXT.md` were not edited when this note was created.
- 2026-09-30 11:06: Atarist_030_wip README purpose/rules + LICENSE-NOTES.md added (docs only). Caches are to go INSIDE the WF68K30L core (David's decision), real-030 behaviour, no compatibility patches.
- 2026-09-30 11:11: LICENSE-NOTES.md notes the TF-style bridge is ST test bench only, not carried to the Falcon build.
- 2026-09-30 11:18: LICENSE-NOTES.md wording: repo is public (source only); no ST bitstream will be shared.
- 2026-09-30 11:45: Atarist_030_wip README now opens with credits/thanks to Stephen J. Leary (TerribleFire TF534).
- 2026-09-30 11:47: main README now urges readers to read Credits; credits expanded (Leary, Tejada, Puri).
- 2026-09-30 12:50: both MiSTeryNano READMEs now explain the HDMI/DVI switch and why the HDMI work was done (docs only).
- 2026-09-30 14:05: cpu030_st_bridge.v comments now credit Stephen J. Leary first and at each TF534-derived block (no logic change).
- 2026-10-01 11:22: misterynano_tc138k top.sv reset fix: `wire por = !pll_lock;` (dropped `|| bl616_jtagsel`; stock BL616 firmware never drives it low, so the V14 pull-up held the ST in reset = DVI sync, black screen). Build PASS (clk32 35.0 MHz, pix 86.4 MHz), not flashed, awaiting David's hardware test.
- 2026-10-01 19:36: Atarist_030_wip top.sv gets the same reset fix as 8adecde (`wire por = !pll_lock;`). Build PASS (cpu030 17.18 MHz, clk32 32.002 MHz met with near-zero margin), not flashed. David confirmed 19:25 BST that 8adecde boots misterynano_tc138k to the TOS desktop on the Console with stock BL616 firmware.
- 2026-10-01 21:50: Atarist_030_wip atarist.v: double reset on cold start (rigsdram AUTO_WARM scheme): ~48 us after the first ST reset ends, one extra reset_cnt reload (ST reset-button-equivalent); re-armed only by porb; both CPU paths.

## Catch-up 2026-10-01/02 (from Grok Bot)

- **Console black screen / “invalid signal” root cause:** Tang Console `top.sv` had `por = !pll_lock || bl616_jtagsel`. The BL616 is running stock Sipeed firmware (FPGA-Companion has never been installed), so it never drives that pin low and the ST stayed in reset. The Nano 20K uses `!pll_lock` only. Fixed in `8adecde` (`misterynano_tc138k`) and `a89f293` (`Atarist_030_wip`). The standard core now boots TOS 1.04 to the desktop on the Console.
- Upstream `top.sv` ties off the S0 (AA13) and S1 (AB13) buttons. Re-enabling S0 as a CPU reset is parked as a future debug aid.
- `c967a5e` added a double cold-start reset to `Atarist_030_wip/atarist/atarist.v`, porting rigsdram’s `AUTO_WARM` scheme. It is outside the `CPU_030` ifdef, so it also applies to the 68000 build. The rigsdram README says `AUTO_WARM` is a board workaround, not a product feature; this may be reverted.
- **Important correction:** David’s “C1-2 USB3 Video” HDMI capture device was faulty and has been returned. Screen captures are suspended until a new capture device arrives. Earlier capture results (030 “black screen”; 68000 build of the 030 tree “two bombs / bus error”) are therefore **unreliable**. On 2026-10-02, checking a real monitor showed the 68000 build of `Atarist_030_wip` ( `CPU_030` commented out, with the `misterynano_tc138k` SDC, hence no `clk_cpu030` `create_generated_clock` or clock-group entry) boots EmuTOS 1.4 to the desktop. Those were local laptop edits and are not committed.
- A read-only diff found `Atarist_030_wip` effectively identical to `misterynano_tc138k` outside the 030 files, apart from clock plumbing: PLL `CLKOUT5` at 8 MHz, `clk_cpu030` in the SDC, and the `clk_cpu` port.
- **Current board state:** the 030 build from main `9b0718d` (including the double reset) is flashed. Timing passed: `clk32_core` 32.069 MHz against 32 (almost no margin), `clk_cpu030` 17.6 MHz, TNS 0. EmuTOS 1.4 UK is in the TOS slot at `0x500000`. David will check the monitor when he is back; the result is pending.
- **TOS swapping (only when requested):** images are in `C:\tosimg` on David’s laptop: `tos104.bin` and `emutos-192uk-1.4.img`, both 192K padded with `FF` to 256K. Flash with `programmer_cli` op 56 using `--mcuFile` at `--spiaddr 0x500000` on cable location **417** (never 418), then reflash the core `.fs` with op 53.
- **Timing note:** detailed reports show negative-slack paths from `ds2_p1/clk_spi` (a Gowin-derived clock) into `clk32_core` (ikbd), while TNS remains 0. This looks like an unconstrained clock-domain crossing and is worth checking against the standard core.
- **Next steps:** get the monitor result for the 030 build. If it is black, try EmuTOS for a crash dump and consider adding margin to `clk32_core`.
- **Patch handoff (from 2026-10-02):** to hand code changes to Grok Bot, commit one `handoff/<YYYYMMDD-HHMM>-<short-name>.patch` (unified diff that `git apply`s on main) plus a matching `.md` (REQUEST_ID, ACTION, WORKDIR, BUILD_CMD, TOS, description). David tells Grok Bot when one is waiting. Full rules in `AGENT_PROTOCOL.md`, template in `handoff/README.md`.
