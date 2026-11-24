# Falcon030_rtl: design note, v1 (FAL_01, 24 Nov 2026)

Copyright (C) 2026 FalconFPGA project (dave-1024). SPDX-License-Identifier: GPL-3.0-or-later.

**Goal v1:** Atari TOS 4.04 boots to the desktop with HDMI video, from SRAM, on the Tang Console 138K
(GW5AST-LV138PG484AC1/I0, version C), with a real floppy drive A:.

**Behaviour reference:** `reference/Hybrid030/hybrid_musashi/falcon_m28.c` (Hybrid030 booted TOS 4.04 under
Musashi on the AE350; its behaviour was correct, just too slow). Where Hybrid030 and Hatari disagree, this
design follows Hybrid030 for what TOS 4.04 needs on this board, and the difference is listed in
[Differences](#differences-from-hybrid030-and-hatari).

## Blocks

| Block | v1 | Source |
|---|---|---|
| CPU | real | WF68K30L, **shared by path** from `Atarist_030_wip/hdl/cpu030/wf68k30L_*.vhd` (no copy, no fork, so every timing fix lands in both builds). Not `cpu030_st_bridge.v`. |
| Bus | real | `hdl/bus/falcon_bus.v`: 24-bit decode, async DSACK, 16 MHz, BERR on anything unmapped |
| ST-RAM | real | 14 MB in the J9 SDRAM (W9825G6KH), ST core's `sdram.v` controller. **No TT/fast RAM.** |
| TOS ROM | real | 512K TOS 4.04, SDRAM copy at $E00000, loaded from the SD card (see [TOS load](#tos-load-path)) |
| VIDEL | real (boot modes) | `hdl/video/videl_regs.v` register file + port of Hybrid030 `falcon_video.v` onto the SDRAM |
| HDMI | real | the ST core's working path (`hdl/hdmi/*`, 640x480, `gowin_pll_hdmi`), one stack only |
| MFP 68901 | real | ST `hdl/atarist/mfp*.v` |
| Keyboard ACIA + IKBD | real | ST `acia.v`, `ikbd/` (HD63701) |
| NVRAM/RTC MC146818 | real (new) | `hdl/peri/falcon_nvram.v`, $FF8961/$FF8963 |
| Floppy A: | **real** | ST `fdc1772.v` + `dma.v` at the Falcon addresses, the helper's floppy mounting; drive A: only |
| HD density select | real (latch) | $FF860E (Falcon: bit 0/1 = HD) to the FDC clock select |
| YM2149 | stub | `hdl/peri/falcon_ym_stub.v`: register store and readback; port A drives drive/side select |
| Blitter | stub | $FF8A00-$FF8A3D latch (TOS 4.04 probes it; no blits) |
| IDE | stub | $FFF00000-: BERR (no drive) as Hybrid030 with no HDD |
| SCSI/ACSI | stub | NCR5380 latch at $FF8780 (bus free, selection times out), ACSI: no target |
| DSP 56001 host | stub | $FFA200-$FFA207, ISR reads TXDE/TRDY |
| Sound DMA / codec / crossbar | stub | $FF8900-$FF897F latch, no playback |
| SCC, joypads | stub | latch / reads $FF |
| AE350 | helper only | OSD, SD, TOS load, as in the ST build |

## Memory map (68030, 24-bit decode: A31:24 = $00 or $FF, else BERR)

| Address | What | Port |
|---|---|---|
| $000000-$000007 | ROM vector mirror (reads; writes go to RAM) | SDRAM $E00000.. |
| $000008-$DFFFFF | 14 MB ST-RAM | SDRAM, 16-bit, DSACK1 |
| $E00000-$E7FFFF | TOS 4.04 (writes ignored, DSACK) | SDRAM, 16-bit |
| $FA0000-$FBFFFF | cartridge, reads $FFFF | - |
| $FF8000-$FF800F | memory/bus config; $FF8006 monitor type + RAM size | IO |
| $FF8200-$FF8211 | video base, counter, line offset, VWRAP | VIDEL |
| $FF8240-$FF826F | ST palette, shifter mode, SPSHIFT | VIDEL |
| $FF8280-$FF82C7 | VIDEL timing (HHT..VDE, VCO, VMODE) | VIDEL |
| $FF8604-$FF860F | FDC/DMA (real), $FF860E density | dma.v / fdc1772.v |
| $FF8780-$FF878F | SCSI NCR5380 | stub |
| $FF8800-$FF88FF | YM2149 (+shadows) | stub |
| $FF8900-$FF897F | sound DMA, crossbar, codec; NVRAM at $FF8961/63 | stub / NVRAM |
| $FF8A00-$FF8A3D | blitter | stub |
| $FF8C80-$FF8C87 | SCC | stub |
| $FF9200-$FF921F | joypads, DIP | stub |
| $FF9800-$FF9BFF | 256 x Falcon palette | VIDEL |
| $FFA200-$FFA207 | DSP host port | stub |
| $FFFA00-$FFFA3F | MFP | real |
| $FFFC00-$FFFC07 | keyboard + MIDI ACIA | real (MIDI: TDRE only) |
| rest of $FF8000-$FFFFFF and all other space | **BUS ERROR** | - |

The IO whitelist is `falcon_io_valid()` from falcon_m28.c, unchanged. Interrupts: VBL level 4 and HBL level 2
autovector, MFP level 6 vectored (vector from the MFP), as on the Falcon.

### $FF8006 (monitor and RAM size)

TOS 4.04 at $E0013A reads the word at $FF8006: `code = ((hi>>1)&1) | ((hi>>2)&6)`, RAM = 512K << code, and
code 5 means 14 MB. Bits 7:6 are the monitor (00 mono, 01 RGB, 10 VGA, 11 TV). v1 returns hi = $92
(VGA, 14 MB). The sim bench uses code 1 (1 MB) so the RAM clear loop takes 1.6 M clocks, not 22 M.

## Clocks

| Clock | Use |
|---|---|
| clk_cpu 16 MHz (+ 180 degree copy) | WF68K30L, falcon_bus, VIDEL regs, NVRAM, stubs. Floor 16 MHz (timing_pairs). |
| clk_32 | MFP/ACIA/IKBD/FDC/DMA enables as in the ST core (synchronised to the bus with the ST core's handshake idea, no bridge) |
| SDRAM clock | ST core `sdram.v` (shared ports: CPU, DMA, scanout) |
| pixel 25.2 MHz / TMDS x5 | `gowin_pll_hdmi`, 640x480@60 |

## SDRAM ports

The ST core's `sdram.v` is reused. In the ST build the GSTMCU sequenced CPU, DMA and shifter slots. The Falcon
build has no GSTMCU, so a small arbiter (`hdl/bus/falcon_sdram_arb.v`, NEXT) gives the scanout priority
(line bursts in blanking), then the floppy DMA (`dma.v` rdy_i/rdy_o word transfers), then the CPU word port of
falcon_bus.v. The TOS loader uses the same port before the CPU leaves reset.

## Video

`videl_regs.v` decodes the VIDEL/shifter registers and outputs exactly the fields the Hybrid030 mailbox
used to carry (fb_base, planes 0/1/2/4/8, hdbl, vdbl, native height, linebytes, 16 ST palette entries,
256 Falcon palette entries). The port of `falcon_video.v` keeps its decode-on-fetch line buffer and pixel
side, drops the mailbox parse and the DDR3 lane-5 bursts, and fetches each native line from SDRAM through
the arbiter. Output goes into the ST core's HDMI path at 640x480. v1 needs the TOS boot modes only
(640x480 4-plane VGA from NVRAM, ST modes doubled).

## TOS load path

TOS 4.04 (512K, md5 e5ea0f216fb446f1c4a4f476bc5f03d4) is a file on the SD card, not in flash. The helper
(FPGA-Companion on the AE350) mounts it from the core's OSD XML entry "TOS ROM" (default `TOS404.IMG`) as an
extra SD image slot, exactly like a floppy image. A fabric loader (`hdl/top/tos_loader.v`, NEXT) holds the CPU
in reset, reads image sectors 0..1023 through the existing `sd_card.v` core port and writes them to SDRAM
$E00000-$E7FFFF, checks the header (BRA at $E00000, $00E00000 base), then releases reset. No flash slot is
used, so the ST core's flash layout (TOS 2.06 at 0x500000) is untouched. Existing SD images are never
written; the loader only reads.

## Floppy (drive A: only)

The Falcon has one floppy drive and no second floppy port. `fdc1772.v` and `dma.v` are instantiated as in
`atarist.v`, with: drive select from YM port A bit 1 only (bit 2, drive B, is ignored; select is
`{1'b1, ~porta[1]}` so B: never answers); side from port A bit 0; image slot 0 only from the helper
(`sd_img_mounted[0]`); HD/DD density from the $FF860E latch (bits 1:0 = 11 HD), fed to the FDC as its
clock select and reported back on read. DMA is the sector-count/address DMA at $FF8604-$FF860D, its RAM side on
the SDRAM arbiter. ACSI in `dma.v` gets no images (stub).

## Differences from Hybrid030 and Hatari

| Item | Hybrid030 (falcon_m28.c) | Hatari | v1 |
|---|---|---|---|
| NVRAM at power-up | zeroed, invalid checksum; TOS writes its defaults | file or defaults | **valid checksum and mode $001A (VGA, 80 col, 4 planes)** per David's brief; TOS behaves the same as after its own default write |
| $FF8006 | io_shadow $FF (TV, code 7) | monitor + RAM config | $92xx (VGA, 14 MB), so TOS sizes 14 MB without probing |
| GPIP7 | mono-detect XOR sound DMA | mono detect | Hybrid030 (no sound DMA: reads 1) |
| IO whitelist | coarse ranges | per register | Hybrid030 ranges |
| YM shadows $8804-$88FF | mirror $8800-$8803 | same | same |
| Floppy | C model of the FDC, A: and B: | A:, B: | real fdc1772, **A: only** |

## Layout

```
Falcon030_rtl/
  build_falcon.tcl      Gowin V1.9.12.03 build (template: Atarist_030_wip/build_st_helper.tcl)
  docs/DESIGN.md        this file
  hdl/top/              falcon_top.sv (from console138k/top.sv), falcon_core.v, tos_loader.v
  hdl/bus/              falcon_bus.v, falcon_sdram_arb.v
  hdl/video/            videl_regs.v, falcon_scanout.v (port of falcon_video.v)
  hdl/peri/             falcon_nvram.v, falcon_ym_stub.v, falcon_io.v (stubs + IO mux)
  sim/                  tb_falcon.vhd + run_tos.sh (TOS 4.04 on the shared core, behavioural bus)
```
