# SYNC FOR GROK CHAT

Catch-up note for Grok chat. Newest entries are at the top. All times are UK time (BST, UTC+1).

## Purpose

Grok chat (David's HDL-writing assistant) is out of tokens until 1 Oct 2026. Until then, David asks
Grok Bot for changes directly, and Grok Bot edits, builds and logs everything here and in
`BUILD_REPORT.md`. **Grok chat: please read this file first when you are back, before assuming any
old state.** While this note is active, Grok Bot may edit HDL at David's request.

## Changes since 2026-09-29 (running log, Grok Bot adds entries here, newest first)

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

- The CONTEXT.md base64 handoff (2026-09-28-2, CHANGED 1) has not been decoded by Grok Bot, because
  ACTION was NO_BUILD. It may be out of date after the rollback.
- Grok chat: when you are back, please update CONTEXT.md to reflect everything above.
- `BUILD_REQUEST.md` and `CONTEXT.md` were not edited when this note was created.
- 2026-09-30 11:06: Atarist_030_wip README purpose/rules + LICENSE-NOTES.md added (docs only). Caches are to go INSIDE the WF68K30L core (David's decision), real-030 behaviour, no compatibility patches.
- 2026-09-30 11:11: LICENSE-NOTES.md notes the TF-style bridge is ST test bench only, not carried to the Falcon build.
- 2026-09-30 11:18: LICENSE-NOTES.md wording: repo is public (source only); no ST bitstream will be shared.
- 2026-09-30 11:45: Atarist_030_wip README now opens with credits/thanks to Stephen J. Leary (TerribleFire TF534).
