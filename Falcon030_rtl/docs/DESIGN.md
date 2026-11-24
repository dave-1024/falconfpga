# Falcon030_rtl: design note, v1 (FAL_01, 24 Nov 2026)

Copyright (C) 2026 FalconFPGA project (dave-1024). SPDX-License-Identifier: GPL-3.0-or-later.

**Goal v1:** Atari TOS 4.04 boots to the desktop with HDMI video, from SRAM, on the Tang Console 138K
(GW5AST-LV138PG484AC1/I0, version C), with a real floppy drive A:.

**Behaviour reference:** Hybrid030 (`reference/Hybrid030/`). Its C model (`hybrid_musashi/falcon_m28.c` and
friends) booted TOS 4.04 under Musashi on the AE350, and was built against a real 68030 (minus cache and MMU),
so its bus and IO behaviour is hardware-verified; it was correct, just too slow. Where Hybrid030 and Hatari
disagree, this design follows Hybrid030 for what TOS 4.04 needs on this board, and says so in
[Differences](#differences-from-hybrid030-and-hatari). Every decision below names the Hybrid030 document it comes
from ([Sources](#sources-per-decision)). Read for this note: `README.md`, `HOWTO.md`, `AE350_ERRATA.md`,
`Binaries/README.md`, `hybrid_falcon030/README.md`, `hybrid_falcon030/GUI.md`, `hybrid_musashi/README.md`,
`HOWTO.md`, `COMPILE.md`, `FIRST_TIME.md`, the revision header of `falcon_m28.c` (M1..M28) and of
`hybrid_falcon030/src/falcon_video.v` (v6.2).

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
| Keyboard ACIA + IKBD | stub (Hybrid030 M5) | `hdl/peri/falcon_ikbd_acia.v`: TDRE always, $80 $01 replies $F1; MIDI still ST `acia.v` |
| NVRAM/RTC MC146818 | real (new) | `hdl/peri/falcon_nvram.v`, $FF8961/$FF8963 |
| Floppy A: | **real** | ST `fdc1772.v` + `dma.v` at the Falcon addresses, the helper's floppy mounting; drive A: only |
| HD density select | real (latch) | $FF860E (Falcon: bit 0/1 = HD) to the FDC clock select |
| YM2149 | stub | `hdl/peri/falcon_ym_stub.v`: register store and readback; port A drives drive/side select |
| Blitter | stub | $FF8A00-$FF8A3D latch (TOS 4.04 probes it; no blits) |
| IDE | stub | ONE interface at $F00000-$F0003F answers, no device (status 0); other IDE addresses BERR |
| SCSI/ACSI | stub | NCR5380 latch at $FF8780 (bus free, selection times out), ACSI: no target |
| DSP 56001 host | stub | $FFA200-$FFA207, ISR reads TXDE/TRDY |
| Sound DMA / codec / crossbar | stub | $FF8900-$FF897F latch, no playback |
| SCC, joypads | stub | latch / reads $FF |
| AE350 | helper only | OSD, SD, TOS load, as in the ST build |

## Memory map (68030, 24-bit bus: A31:24 not decoded, every address aliases into 16 MB)

| Address | What | Port |
|---|---|---|
| $000000-$000007 | ROM vector mirror (reads; writes go to RAM) | SDRAM $E00000.. |
| $000008-$DFFFFF | 14 MB ST-RAM | SDRAM, 16-bit, DSACK1 |
| $E00000-$E7FFFF | TOS 4.04 (writes ignored, DSACK) | SDRAM, 16-bit |
| $F00000-$F0003F | IDE (one interface, v1: no device, status 0) | stub |
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
| $FFFC00-$FFFC07 | keyboard + MIDI ACIA | kbd: Hybrid030 M5 stub (TDRE, $F1 reset reply); MIDI: ST acia.v TDRE only |
| rest of $FF8000-$FFFFFF and all other space | **BUS ERROR** | - |

The IO whitelist is `falcon_io_valid()` from falcon_m28.c, unchanged. Interrupts: VBL level 4 and HBL level 2
autovector, MFP level 6 vectored (vector from the MFP), as on the Falcon.

### $FF8006 (monitor and RAM size)

TOS 4.04 at $E0013A reads the word at $FF8006: `code = ((hi>>1)&1) | ((hi>>3)&6)`, RAM = 512K << code, and
code 5 means 14 MB. Bits 7:6 are the monitor (00 mono, 01 RGB, 10 VGA, 11 TV). v1 returns hi = $92
(VGA, 14 MB). The sim bench uses code 1 (1 MB) so the RAM clear loop takes 1.6 M clocks, not 22 M.

## Clocks

| Clock | Use |
|---|---|
| clk_cpu 16 MHz (+ 180 degree copy) | WF68K30L, falcon_bus, VIDEL regs, NVRAM, stubs. Floor 16 MHz (timing_pairs). |
| clk_32 | MFP/ACIA/IKBD/FDC/DMA enables as in the ST core (synchronised to the bus with the ST core's handshake idea, no bridge) |
| SDRAM clock | ST core `sdram.v` (shared ports: CPU, DMA, scanout) |
| pixel 25.2 MHz / TMDS x5 | `gowin_pll_hdmi`, 640x480@60 |

## Peripheral sub-bus (clk_32 blocks)

The reused ST blocks (MFP, ACIAs, IKBD, dma.v, fdc1772) run on clk_32 with the ST enables (8 MHz, E clock for the
ACIAs) and expect a 68000-style cycle: select held for the whole cycle, read side effects (MFP UDR, ACIA RDR)
once per cycle. clk_cpu is phase-locked to clk_32 (16 = 32/2, same PLL, as in the ST build), so falcon_bus.v
hands an IO cycle over synchronously: it holds select, address, R/W and data for the whole IO cycle and raises
DSACK when the clk_32 side says done. The clk_32 side (`hdl/bus/falcon_pbus.v`, NEXT) makes one write strobe and
one read-side-effect strobe per cycle, waits for the E clock for $FFFC0x (like the ST's VPA/VMA cycle), and
returns MFP vectors on level 6 IACK. This is not `cpu030_st_bridge.v`: no ST bus timing, no GSTMCU, only the
peripheral handshake.

## SDRAM ports

The ST core's `sdram.v` is reused. In the ST build the GSTMCU sequenced CPU, DMA and shifter slots. The Falcon
build has no GSTMCU, so a small arbiter (`hdl/bus/falcon_sdram_arb.v`, NEXT) gives the scanout priority
(line bursts in blanking), then the floppy DMA (`dma.v` rdy_i/rdy_o word transfers), then the CPU word port of
falcon_bus.v. The TOS loader uses the same port before the CPU leaves reset.

David (24 Nov) picked (a): the arbiter (`hdl/bus/falcon_sdram_arb.v`) generates the GSTMCU-style 8-clock
(250 ns at 32 MHz) slot cadence on the ST port of `sdram.v`. Priority in each slot: a periodic AUTO_REFRESH
(every 16 slots = 4 us), then scanout, then floppy DMA, then the TOS loader / CPU (the loader uses the port
while the CPU is held in reset). `ecs` is 0 in v1.

The CPU word port of `falcon_bus.v` (address, write data, we, byte enables) is latched on the same
clk_cpu edge as `mem_req`. The combo path from the 030 MMU physical address through the arbiter into
`sd_din` is then a registered CDC into clk32 (31.25 ns). On 56d6a85 the combinational version missed
that relation by 6.2 ns (`timing_pairs` clk_cpu030 -> clk32_core setup). Functional latency is
unchanged: the latch is the same edge that already raised `mem_req`.
The return path is the other way: the arbiter writes `cpu_q` at slot phase 5 and
raises `cpu_ack` at phase 6 (data at least one clk32 old), and `falcon_bus`
samples both on clk_cpu. A leftover ack still high from the previous word is
not accepted (wait for it to fall, then raise `mem_req`), the same 4-phase
rule as the TOS loader.

CPU and `falcon_bus` reset is generated in clk_cpu, like `cpu030_st_bridge.v`:
the clk32 `por` / `cpu_reset` / `user_reset` sources are 2-flop synchronised
and RESET_INn / HALT_INn stay low for 128 clk_cpu cycles after they fall.
Releasing those pins on a clk32 tick that is `clk_cpu_n` (the in-between
edge) would let the two halves of WF68K30L leave reset a half-cycle apart.

The IO port of `falcon_bus.v` (address, UDS/LDS, R/W, write data) is latched the
same way on the S_IDLE -> S_IO edge (write data is sampled again in S_IO, in case
the 030 presents it after AS). 9bd249a still failed the same clock pair (-8.0 ns,
FILL_ACC through `mem_a_c` and the videl/io/pbus decode into `sd_din`) because
those signals were left combinational and fan into `falcon_fdc` / `dma.v`
(`dma_dout` is the arbiter's `dma_d`).

The ST port in `sdram.v` was bank 0 only (8 MB). A backward-compatible `st_ba` input was added (the ST build
ties it to `2'b00`; ST benches updated to match). Falcon maps 16 MB across banks 0 and 1: bank = `{1'b0, byte A23}`,
word address = A22:A1, which covers 14 MB ST-RAM plus the TOS copy at $E00000.
The vector-mirror address must be the same 23-bit `{A23:A1}` as `tos_loader`
(`{5'b11100, A2:A1}` for $E00000). A 22-bit `{20'hE0000, A2:A1}` zero-extends
and drops A23, so reset-vector reads landed at $700000 (zeros) and the 030
halted with PC=0 (c518b4c HUD).

The always-on HDMI HUD (falcon_dbg_hud.v) is ten 8-pixel rows and does not
depend on VIDEL. Rows 0-2 are PC, last IO, BERR, VBAS/HHT/VFT, TOS CRC and
flags. Rows 3-9 snoop (on clk_cpu, at DSACK / io_wr / AS falling) the PMMU
table at $700..$7FF (XOR and the $700/$740/$7C0/$7F8 descriptors; TOS 4.04
image XOR is $0F000080, U-bit writebacks only touch the low nibble),
_phystop ($42E), _frclock ($466), $FF82C0, the last 8 IO writes, the last 8
program-fetch addresses, and the first program fetch outside $00E0xxxx plus
the previous $E0 fetch. That is how a single grab shows whether the board
diverged from the GHDL PMMU walk (identity map, $7F8 = $00E00001) or jumped
out of TOS ROM.


Bandwidth: a Falcon-only page-mode burst-2 read (`st_rd2`, default 0) issues a second CAS of addr+1 in the
same 8-clock slot, MODE stays burst-length 1. The ST build ties `st_rd2` to 0; a compare of the new
controller against the pre-burst `sdram.v` (256 slots: read/write/refresh/ecs/zmask) was bit-identical
on every SDRAM pin and `dout` (2361 clocks, 0 mismatches, `Falcon030_rtl/sim` notes). Burst-2 gives
16-bit x 2 / 250 ns = 16 MB/s: a 640x480 4-plane line is 80 slots = 20 us, inside the 31.8 us HDMI line
(headroom for refresh, floppy DMA and the CPU). An 8-plane 640 line is still 40 us (later). Do not use
`st_rd2` on a TTRAM build (the second CAS would sit on a TT command clock). Bring this `sdram.v` change
to `speed`/`main` later; it lives on `falcon` only for now.

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

The helper reads the gzip'd OSD XML from the core (`sysctrl.v` CMD 8) unless `/sd/config.xml` is
present. The menu lives in `Falcon030_rtl/osd/falcon.xml` (hex `falcon_xml.hex`). `sysctrl.v` is
shared with the ST core and picks that file under `` `ifdef FALCON `` (from `build_sel.vh`).
`$readmemh("falcon_xml.hex")` searches the gw_sh working directory, not the `add_file` path:
build 85ca498 took the FALCON branch but Gowin warned EX3988 (file not found), left the XML ROM
empty, and the helper printed `config[0] = 00` / "no core config loaded". Image 4 (TOS ROM) was
never mounted, so the loader held the CPU in reset. `build_falcon.tcl` now copies the hex into
the cwd. The console `mount` command only accepts `a|b|h0|h1` (drives 0-3); image 4 is mounted
from `falcon.ini` `drive4=` (the XML `default=` uses the helper `imageN` ROM-upload path, which
does not pulse `image_mounted`). `sd_card.v` pulses `image_mounted` for one clk32 cycle.
`falcon_soc.por` is `por32|helper_hold`, so a mount during the helper hold would reset
`tos_loader` and drop the pulse. `tos_mount_latch.v` (clk32 / sd_card domain, reset by `por32`
only) keeps a sticky 512K mount and issues a one-cycle go once `helper_hold` is clear, SDRAM
is ready, and 1 ms has passed for the helper's CMD 6 direct-map (sent after INSERT; starting
earlier takes the MCU IRQ path). The loader itself is reset by `por32` only, not `helper_hold`.
The CPU stays in reset until all 1024 sectors are in `$E00000` and the header base is
`$00E00000` (Hybrid030 `flop_init` / `ROM=`: copy the ROM, then release the CPU).
While `cpu_reset` is high, `falcon_soc.v` substitutes
colour bars and a bottom progress strip (`sect * 640 / 1024`) so a later HDMI grab can tell a
waiting/loading core from no TMDS; a bad image is a red screen. Helper `sdlog on` logs each
loader SD read (bytes = sectors * 512) without a firmware change.

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
| NVRAM at power-up | zeroed user cells, invalid checksum (M11h: removed its own pre-planted mode because a stock Falcon has none) | file or defaults | **Hybrid030 stock** (`PRESET=0`, the v1 default). David (24 Nov): TOS writes its defaults from a bad checksum, as a stock Falcon does. `PRESET=1` remains a parameter ($001A VGA, 80 col, 4 planes, valid checksum) for a faster sim; run at least one check with `PRESET=0` before the board test. |
| Address bus | 24-bit by default (`BUS=24`, "matched Hatari and this bench for TOS") | 24-bit on Falcon | 24-bit, A31:24 ignored |
| IDE | one interface answers at $FFF00000-3F (M11q); TOS 4.04 BERRed on alt status +$39 before that | IDE emulated | one interface answers, no device |
| $FF8006 | io_shadow $A2 (VGA, code 5) | monitor + RAM config | $A2xx (VGA, 14 MB), so TOS sizes 14 MB without probing |
| GPIP7 | mono-detect XOR sound DMA | mono detect | Hybrid030 (no sound DMA: reads 1) |
| IO whitelist | coarse ranges | per register | Hybrid030 ranges |
| YM shadows $8804-$88FF | mirror $8800-$8803 | same | same |
| Floppy | C model of the FDC, A: and B: (B: works only under EmuTOS; HOWTO "Floppy B") | A:, B: | real fdc1772, **A: only** |

## Layout

```
Falcon030_rtl/
  build_falcon.tcl      Gowin V1.9.12.03 build (template: Atarist_030_wip/build_st_helper.tcl)
  docs/DESIGN.md        this file
  hdl/top/              falcon_top.sv (from console138k/top.sv), falcon_core.v, tos_loader.v
  hdl/bus/              falcon_bus.v, falcon_sdram_arb.v
  hdl/video/            videl_regs.v, falcon_sdp_ram.v, falcon_scanout.v (port of falcon_video.v; RGB line buffer and Falcon palette are SDP BSRAM with syn_ramstyle = "block_ram")
  hdl/peri/             falcon_nvram.v, falcon_ym_stub.v, falcon_io.v (stubs + IO mux)
  sim/                  tb_falcon.vhd + run_tos.sh (TOS 4.04 on the shared core, behavioural bus)
```

## Sources per decision

| Decision | Hybrid030 source |
|---|---|
| Falcon memory map (vector mirror, 14 MB ST-RAM, ROM at $E00000, cart $FA0000) | `falcon_m28.c` M1 header "Memory map (68k side)" |
| Unmapped IO and open space bus-error; IO whitelist ranges | `falcon_m28.c` M1 header + `falcon_io_valid()` |
| 24-bit address bus | `HOWTO.md` "`BUS=32`" (24-bit default, masks to 16 MB); `falcon_m28.c` M22 |
| One IDE interface at $FFF00000-3F, the other three must BERR | `falcon_m28.c` M11q |
| IDE INTRQ shares MFP GPIP5 with the FDC (for later, real IDE) | `falcon_m28.c` M11y |
| Stock NVRAM, live BCD clock, regs C/D read-only, UIP pulse | `falcon_m28.c` M11h + `nvram_read/nvram_write` |
| MFP timer counters must run while TOS 4.04 polls TCDR with IRQs masked ($E0256E delay calibration) | `falcon_m28.c` M11e |
| Floppy A: only; TOS 4.04 never selects B: | `HOWTO.md` "`DISKB=`" and "Floppy B"; `falcon_m28.c` M11i |
| FDC command with no drive selected pends, does not fail | `falcon_m28.c` M11i |
| YM shadows ($8804-$88FF mirror $8800-$8803), port A read-modify-write for drive/side | `falcon_m28.c` M25, `psg_*` |
| NCR5380 stub: ICR AIP follows mode ARBITRATE, mode reads back | `falcon_m28.c` M11w |
| No FPU (F-line traps) | `falcon_m28.c` M24 |
| TOS from the SD card, not flash; 512K at $E00000 | `HOWTO.md` "`ROM=`"; `falcon_m28.c` M9G/M10 ROM-from-card |
| Blitter (v1 stub). When real: reads ROM (system font) and latches $FF8A3C as one word | `falcon_m28.c` M11g, M11f |
| Scanout: decode-on-fetch, geometry guard against insane transient VIDEL values; RGB line buffer and 256x18 Falcon palette are `falcon_sdp_ram` (syn_ramstyle = "block_ram", same style as `st_fb_ram`). A 640-deep combinational-port rawbuf was inferred as 62k LUT and is gone. | `falcon_video.v` v6 header; `falcon_m28.c` M11d; Hybrid sync-read BSRAM comment; `st_fb_ram` |
| Use the J9 SDRAM, not the SOM DDR3 (dead lanes, burst rules) | `AE350_ERRATA.md`, `README.md` "SOM DDR3" |
| TOS 4.04 waits on missing hardware (EmuTOS fails cleanly) | `HOWTO.md` "EmuTOS vs TOS 4.04" |
| VBL at 60 Hz on VGA (50 Hz option later) | `HOWTO.md` "F10" / `VBL=` |

## Third reference: AURA "Atari Falcon Hardware Registers" v0.4 (Aeon & Chris, 1993)

Source: https://www.neperos.com/article/qs4f1491a6baa850 (plain text copy outside git:
`/workspace/falcon_refs/neperos_qs4f.txt`). An early 1993 document, so it ranks below Hybrid030
(hardware-checked against a real 68030) and next to Hatari. Checked against the v1 map:

| Register | AURA v0.4 | Hybrid030 / Hatari | v1 | Note |
|---|---|---|---|---|
| IDE $FFF00000-$FFF0003F | one window, "new Falcon registers", contents unknown | one interface (M11q) | one interface, no device | agrees |
| $FF8006 | b7:6 monitor (00 SM124, 01 SC1435, 10 VGA, 11 TV); sample value $56 | same monitor bits; TOS 4.04 RAM-size bits | $A2 (VGA, 14 MB) | Hybrid030 `io_shadow[0x0006]=0xA2` (VGA, code 5) is the value that booted TOS 4.04. Bits: b7:6=monitor, b5:4=MEMCODE[2:1], b1=MEMCODE[0]. AURA's $56 is a different packing (not used). |
| $FF8266 SPSHIFT | b10 2-colour, b8 true colour, b4 256 colour, b5/b6 ext sync | same (Hatari) | same | agrees |
| $FF82C2 VCO/VMODE | b1 interlace, b2 640 px; **bit 0 not described** | Hatari: b0 line doubling | b0 = line doubling | AURA silent on b0; v1 follows Hatari/Hybrid030 (falcon_video.v vdbl) |
| $FF8210 VWRAP | 10-bit words per line, sample $0050 | same | same | agrees |
| $FF860E/$FF860F | "new Falcon registers", no meaning given (sample $00/$80) | density select (Hybrid030 `flop_density` latch, both bytes) | density latch, bits 1:0 | AURA gives no bit meaning; v1 follows Hybrid030 |
| $FF8800/$8802 | read data at $8800, write data at $8802 | same | same | agrees |
| $FF8C80-$FF8C87 | SCC: odd bytes are the registers, even bytes unused | whitelist latch (Hybrid030) | latch | v1 latches even bytes too (harmless; Hybrid030 does the same) |
| $FF9200 | fire buttons, sample $BF (bit 6 low) | Hybrid030 reads $FF | $FFFF | **settled (David, 24 Nov)**: stays $FF, as Hybrid030 has it. AURA's sample has bit 6 low; TOS 4.04 does read $FF9200 at $E0042E, but Hybrid030 booted with $FF. |
| $FFA202 DSP ISR | sample $06 (TRDY, TXDE) | Hybrid030 falcon_m28 (shadow) / Hatari | $06 | agrees |
| $FF8961/$FF8963 | NVRAM select / data | same | same | agrees |

## Wiring reference: ReFalcon (Steve Suavek)

ReFalcon-030 (https://github.com/eskwadrat/ReFalcon, commit 56105f4) is a validated replica of the Falcon030
motherboard rev 1 with all Field Service Guide ECOs: a 27-page schematic of rev 1.1 and the BOM. Credit: Steve
Suavek. Its licence is educational/non-commercial, so nothing from it (artwork, schematic pages) is copied into
this repo; it is referenced by page. Priority for this project: Hybrid030 for behaviour, ReFalcon for wiring
and signals, then Hatari, then the AURA doc.

Confirmed on rendered pages (`pdftoppm` of `ReFalcon_R1.1(RC).pdf`, 24 Nov; PDF page numbers below).
Nothing from the schematic is copied into this repo.


| Item | ReFalcon page | First reading | v1 |
|---|---|---|---|
| 68030 STERM | p12 (U55 pin 122) | **confirmed**: pin 122 to R199 4k7 pull-up only, not driven. No synchronous cycles. | STERMn tied high, async DSACK only (agrees) |
| 68030 CIIN | p12 (U55 pin 73) | **confirmed on-page**: pin 73 only to the R200 pull-up in the same pack as STERM/EM1/EM0 (R199/R200/R204/R206). No on-page driver; a PAL/COMBEL driver may be off-page. | v1 drives CIIN from the address decode (ST-RAM and IO inhibited) |
| DSACK0/DSACK1, BERR | p12, p13 (XDSACK0/1, XBERR, EBERR) | **confirmed**: U55 pin 132 = DSACK1/XDSACK1, pin 3 = DSACK0/XDSACK0, pin 130 = BERR/EBERR; p13 has the XDSACK/XBERR buffers. Both DSACK lines routed, generated off-CPU. | v1 answers 16-bit (DSACK1) for every port, as Hybrid030; whether any Falcon port answers 32-bit is still open |
| YM2149 port A (IOA0-7) | p3 (U170) | **confirmed**: U170 YM2149, IOA0 net SEL, DOSEL/SOSEL to the floppy, XDSPRESET, XSPKON (speaker); YM RESET from XRESET. | v1: IOA0 side, IOA1 drive A select (B ignored); DSP reset bit ignored (stub) |
| Floppy density DENS | p6 | DENS net to the drive connector | v1 latches $FF860E; to wire to the FDC clock select later |
| IDE chip selects IDECS0/IDECS1 | p4, p5 | two chip selects (task file / control block) | v1: one interface window, no device |
| VIDEL digital RGB, syncs, pixel clock | J703 (ReFalcon addition) | VIDEL digital outputs exposed for a scaler | v1 scanout regenerates 640x480 from SDRAM, not from VIDEL timing; J703 is the reference if we later drive pixels from the VIDEL timing registers |

The PAL equations (U62/U63/U67/U68) do not appear to be in the repo, so address-decode details inside the PALs
still come from Hybrid030/Hatari.
