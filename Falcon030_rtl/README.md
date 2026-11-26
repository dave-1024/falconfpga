# Falcon030_rtl

RTL for the **Atari Falcon030** core on a Sipeed Tang Console 138K. This folder is self-contained: the WF68K30L
CPU, reused ST peripherals, board support, helper HDL, and a copy of the helper firmware source all live here.
The ST core in [`Atarist_030_wip/`](../Atarist_030_wip/) is retired for now and is left untouched; if something
else is needed from it later, the module is copied in.

Live branch: `falcon`. Project overview and credits: the root [`README.md`](../README.md).

**To build and flash it, follow [BUILD.md](BUILD.md)** (what you need, the FPGA build, the helper build,
flashing, and SD card setup). Lessons and every bug found, including Falcon-era items:
[docs/FALCON_LESSONS.md](docs/FALCON_LESSONS.md). Design note: [docs/DESIGN.md](docs/DESIGN.md).

## Status (26 Nov 2026)

Flash 0 holds **C5** (`46d2de6`: full instruction and data cache for ROM and ST-RAM, write-allocate
in ST-RAM only, and the two-word fill buffer dropped on DMA writes and after idle clocks). Written
26 Nov 2026, 11:17:10–11:19:21 UK, verified: start `0x000000`, end `0x04B2100`
(`< 0x500000`), `Program Flash finished`, cost 131.14 s. clk_cpu030 Fmax 17.619 MHz (34
levels, 16 MHz floor), clk32_core 37.867 MHz, hdmi640 28.533 MHz. `timing_pairs` passes, Gowin
V1.9.12.03. Bitstream `falcon_bli11h_C5.fs`, md5 `6aff47de0f551e6c66441d05b9b7d635`. Previous
flash 0 was C3 (`3407acc`, md5 `661e15e73b8b71989b08bd757e62ef52`).

- TOS 4.04 from the SD card (`TOS404.IMG`) boots to the GEM desktop. Default monitor is VGA.
- HDMI output is 640x480@60. The core runs native Falcon VGA 60 Hz or RGB 50 Hz timing (RGB is forced to a
  313-line 50 Hz beam). An occasional torn frame is accepted. Switch from the OSD (Settings > Monitor), or
  with `var V=1` in `falcon.ini`. TOS is mounted only if `falcon.ini` contains `drive4=/sd/TOS404.IMG`
  (see [BUILD.md](BUILD.md)).
- FrontBench (`FRNTBNCH.PRG`, ST-RAM) lastcount **1079** on VGA 60 Hz, **1319** on RGB 50 Hz, measured
  on `7f0611e` (same video timing; not re-run on C5). A FrontBench video of this build is planned.
- GEMBENCH 6.31 (ST medium, against a blitter STE) on C5: Display 120%, CPU 237%, average 169%.
  Every test matched or beat C3 (average 167%); ROM Access 48.355 s (C3 49.090 s). A few GEM/VDI
  text tests are still a little slower than B3 (average 170%), which did not cache ST-RAM data.
- Working: VIDEL boot modes, blitter, MFP, keyboard ACIA and IKBD, floppy A:, NVRAM/RTC, 14 MB ST-RAM,
  the instruction cache (ROM and ST-RAM) and the full data cache (ROM and ST-RAM) with write-allocate
  in ST-RAM.
- Next: faster SDRAM (also needed for the heavier Videl modes), then a FrontBench video of this build.
- Not yet: DSP 56001, YM2149 / DMA sound and codec (JT49 and STE DMA sound are copied in but not wired),
  SCSI-2 and IDE, EmuTOS, helper firmware cleanup.

The timing goal is the MC68030 manual's cycle counts against zero-wait-state memory. If a count cannot match
exactly, slightly faster is better than slower. No Fmax chasing beyond keeping clk_cpu030 at or above 16 MHz.

## Layout

- `hdl/top`, `hdl/bus`, `hdl/video`, `hdl/peri` — Falcon-native RTL
- `hdl/cpu030` — WF68K30L (local copy)
- `hdl/atarist`, `hdl/fdc1772`, `hdl/ikbd`, `hdl/hdmi`, `hdl/misc`, `hdl/tang`,
  `hdl/helper` — local copies of the modules the Falcon build uses
- `hdl/jt49`, `hdl/gstmcu` — YM2149 and STE DMA sound (copied, not wired yet)
- `osd/falcon.xml`, `osd/falcon_xml.hex` — Falcon OSD menu used by the build
- `helper/` — copy of the AE350 helper firmware source, plus `helper/osd/`.
  Build scripts: `helper/companion/build_companion.sh` (Linux) and `build_companion.bat` (Windows).
  See [BUILD.md](BUILD.md). Do not flash a new helper until the helper cleanup is started, unless
  you mean to replace the one on the board.
- `sim/` — GHDL/iverilog benches (bus, video/timing, blitter, TOS loader, alias).
  The blitter suite is `sim/blit/run.sh`.
- `docs/DESIGN.md` — v1 design note. Some blocks have moved on since it was written:
  the blitter and the keyboard ACIA/IKBD are real, not stubs.
- `docs/FALCON_LESSONS.md` — lessons and bugs found (ST-era list plus Falcon-era findings).
- `BUILD.md` — step-by-step build, flash and SD card guide.

No ROM images in git: TOS 4.04 comes from the SD card.

## Planned

In rough order, and not a schedule. Next is faster memory (below), which is also what the
heavier Videl modes need, and a FrontBench video of the current build.

**CPU cycle counts** (from the ST-era 98-instruction survey of this 68030 core, F172 vC1, 24 Nov 2026:
1243 clocks on the board/DSACK model against the manual's 1059). The biggest remaining gaps, in the
order they were listed:

1. Remaining memory-operand MOVE gap (`d16,d16` 12 against 8; `Dn,d16` 7 against 4).
2. Large `MOVEM` lists (board/DSACK, 8 registers: 69 against 58). A 2-clock synchronous MOVEM push
   write buffer is a later item and needs Fmax work first. `LINK`/`UNLK` is 14 against 9.
3. Calls and returns (`JSR`/`BSR`/`RTS`): still about 2 to 4 clocks over the manual (the odd-address
   case was fixed earlier).
4. `RTE`.
5. Small register and branch gaps: `MOVE.L Dn,Dn` 3 against 2, `ADDA.L` 4 against 2, shifts by a
   number 6 against 4, `BRA.S` 7 against 6, a taken word-size branch 9 against 6.

Other leftover CPU timing: a `DBF` loop of 8 passes is 59.5 against 54; some memory-indirect and CAS2
forms still have idle clocks inside the sequence.

**Faster memory** (this also matters for the heavier Videl modes; see the root
README, [What doesn't work (yet)](../README.md#what-doesnt-work-yet)):

- CPU-first SDRAM start at 32 MHz. On the Falcon bus, an ST-RAM word read is 7.1 clocks in
  simulation against the manual's 3; the aimed-for first step is about 4 clocks.
- Then a 64 MHz SDRAM controller, so cache misses, burst fills and high-bandwidth screen modes are
  faster. The design note records that a 640-pixel 8-plane (256-colour) line is still 40 µs, which
  is longer than one 31.8 µs HDMI line. Earlier 64 MHz work lives on the `sdram64` branch and needs
  bringing up to date first (there is a PLL VCO lock hazard to watch).

**Falcon hardware still to add:** wire the YM2149 (the JT49 copy already in the tree), then the
Falcon's own DMA sound and codec, then SCSI-2 and IDE, then the DSP 56001.

**Helper cleanup**, when that work is started. The firmware on the board is left as it is until then.

## Known issues

See the root README sections [What doesn't work (yet)](../README.md#what-doesnt-work-yet) and
[Planned](../README.md#planned), and [docs/FALCON_LESSONS.md](docs/FALCON_LESSONS.md).

Open CPU/helper items still relevant here: SD card writes can corrupt images; helper serial uploads
can stick until a half-finished transfer is closed; some user-mode prefetch bus-fault frames on the
board lack the FC/FB bits (not reproduced in simulation); turning on instruction tracing (T1) from
supervisor mode just before a `BSR` can loop forever; a stale bus-fault flag on a chained late BERR
is an open corner; the serial port can stall after one kind of blitter operation.

Video caveats still open: a single-buffer artefact on VGA around HDMI row 375; the RGB frame buffer
stores 4 bits per colour (the Falcon palette is 6); RGB modes taller than 240 lines still use the
HDMI-row fetch path and can roll; a debug HUD is still on the picture. Heavier Videl modes (a
640-pixel 256-colour line, and other high-colour, true-colour and larger-resolution modes) wait on
faster SDRAM.

In this tree, `sim/tb_bus_sdram` failed after the folder was made self-contained; the bus logic was
not changed in that commit, and the failure is still to be checked.
