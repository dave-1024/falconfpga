# Atarist_030_wip: a 68030 Atari ST, as a test bed for the Falcon

**In one paragraph:** an Atari ST/STE (MiSTeryNano core) whose 68000 is replaced by a 68030 (Wolfgang Foerster's
WF68K30L) behind a TerribleFire-style bus bridge, on a Sipeed Tang Console 138K, with a Gowin AE350 RISC-V helper for
SD card, disks, keyboard/mouse and OSD. It should behave like a real 68030/TF board on an ST bus (no compatibility hacks,
no write buffer beyond the cycle on the bus: a write ends for the control unit at S3 of its last portion, once DSACK
has decided it, as on a 68030). TOS 2.06 boots to the desktop; GEMBENCH 6 runs all tests at 132% of a stock STE.

**Start here:** [docs/BUILD.md](docs/BUILD.md) (building the core and the helper on Windows or Linux, every switch and its
default, timing checks, flash addresses and rules), [docs/FALCON_LESSONS.md](docs/FALCON_LESSONS.md) (lessons and the
"Bugs found" list: symptom, cause, fix, commit), [docs/SD_WRITE_DEBUG.md](docs/SD_WRITE_DEBUG.md) (SD/floppy write path),
[docs/HISTORY.md](docs/HISTORY.md), [docs/TODO.md](docs/TODO.md) (open work, the
phase 2 follow-ups), [docs/ST_HELPER.md](docs/ST_HELPER.md) (helper, detailed lab sections),
[docs/DIAG_OVERLAY.md](docs/DIAG_OVERLAY.md), lab notes in [docs/notes/](docs/notes/) (RAM_PATH, TF536_NOTES, SPI_SDC, DEBUG2).
All HDL is under `hdl/` (since 9 Oct 2026); `helper_fw/` holds the helper firmware.

## Status (16 Oct 2026, main)

Board build: `st_helper_hdn_ph2wp_de35f5f_p3.fs` (main switches + `SD_WRITE_DEBUG` + CPU rework phase 2 with posted
writes, place 3; clk_cpu030 19.65 MHz, clk32 34.2 MHz), helper
`helper_companion_sdwlog_3ec6e20.bin`.

GEMBENCH 6.31, ST Medium, ratio to a stock STE:

| build | RAM | ROM | Display | CPU | Average |
|---|---|---|---|---|---|
| F60 (CHK fix) | 48 | 60 | 31 | 120 | 61 |
| F63 (bridge + SDRAM early start) | 61 | 69 | 37 | 137 | 71 |
| F62d (prefetch queue + JSR fix) | 76 | 85 | 72 | 225 | 112 |
| p3 (early AS + F65 handoff + SD fixes) | 98 | 98 | 80 | 240 | 123 |
| phase 2 (S5->S0 handoff, Fmax, posted writes) | 115 | 115 | 89 | 251 | **132** |

Float Math: OK (12.37 s, 107%). Phase 2: [docs/PHASE2_DESIGN.md](docs/PHASE2_DESIGN.md). The old "float panic" was a corrupt test image, not the CPU
(docs/FALCON_LESSONS.md).

Works: cold boot, 4 MB memory test, desktop in low/medium res, GEMBENCH All Tests, SD floppy images mounted at
power-up (`atarist.ini`) or at runtime, with desktop saves (the swap corruption is fixed by `ST_FLOPPY_MEDIACH`), large
uploads through the helper, SD error recovery (`ST_SD_HARDEN`; a lost sector shows as a disk error in TOS).

Known issues (order of work in [docs/TODO.md](docs/TODO.md)):
- Intermittent "System halted!" after the cartridge self-test on warm resets/bare reloads; cold boot (`c`) clears it
  (pinned in TODO.md). Always `c` after a flash.
- The blitter shows as disabled under EmuTOS.
- A data bus error is taken one operand cycle late and always as a format $B frame (TODO.md phase 2 follow-ups);
  no working caches yet; the control unit still needs 3 clocks between operand requests (option a).
- Placement sensitivity: always check TNS and recovery/removal before flashing.

## Credits and thanks: Stephen J. Leary (TerribleFire)

The 68030-to-ST bus bridge in this build (`hdl/cpu030/cpu030_st_bridge.v`) is
modelled on **Stephen J. Leary's TerribleFire TF534** accelerator, in
particular the bus timing, arbitration and 6800-cycle logic from its Atari
build (`bus_top.v`, `arb.v`, `m6800.v`, `bus_delay.v`). The TF534 design is
(C) Stephen J. Leary and released under the GPL; the bridge keeps his credit
and the GPL-2 licence (see `LICENSE-NOTES.md`).

This phase of the work would have been much more difficult without him.
Having a proven, published design for fitting a 68030 to a real ST bus meant
we could follow hardware that is known to work, instead of guessing. Thank
you, Stephen, for the TerribleFire boards and for sharing their source.

- Discord: https://discord.gg/Q5zfusgnmH
- Forum: https://www.exxosforum.co.uk/forum/viewforum.php?f=65

## Video output: HDMI or DVI (read this before you compile)

This build does **not** use MiSTeryNano's original video output. The ST picture
goes through an on-chip frame buffer and out as a standard **640x480 at 60 Hz**
signal. There is a switch for the type of signal, and it matters for your
display.

**The switch** is in `hdl/tang/console138k/top.sv`, on the `hdmi_testpattern_640`
instance (`hdmi_tp`):

```
hdmi_testpattern_640 #(
    .DVI_OUTPUT ( 1 ),   // 1 = plain DVI, no audio (default); 0 = HDMI with audio
    .ST_VIDEO   ( 1 )    // 1 = ST picture (default); 0 = colour bars test pattern
) hdmi_tp ( ...
```

- **`DVI_OUTPUT = 1` (default): plain DVI.** Use this for a monitor with a DVI
  input, for example through a DVI-to-HDMI cable. DVI can't carry audio, so
  none is sent. HDMI TVs accept this too.
- **`DVI_OUTPUT = 0`: full HDMI** (with the HDMI info packets and an audio
  channel). Use this for an HDMI TV if you want sound through it. At the moment
  the audio channel carries only a 1 kHz test tone; the ST's own sound is not
  routed to it yet.
- **`ST_VIDEO = 0`** shows colour bars instead of the ST picture, to check a
  display or cable on its own.

**Why the switch exists:** full HDMI adds extra data (audio and info packets)
between the lines of the picture. A DVI monitor doesn't expect that data and
shows no picture at all. Our main test monitor only has a DVI input, so DVI
is the default, and HDMI stays one setting away for TVs.

**Why we did the HDMI work at all:** with the stock MiSTeryNano output on the
Tang Console 138K, our old TV said "invalid format" and the DVI monitor showed
no signal, although the same TV worked with a Tang Nano 20K. The stock output
sends the ST's own, non-standard timing. We replaced it with a standard
640x480 at 60 Hz mode (the basic mode almost every HDMI or DVI display must
accept), fed from a frame buffer so the ST side keeps its original timing.
The colour bars and the DVI mode were confirmed working on both the monitor
and the TV.

**Things to know:**

- Colour modes (low and medium resolution) are line-doubled and centred with
  black borders; mono (high resolution) is shown 1:1. The position can be
  tuned with `ST_H_OFS_COLOR`, `ST_H_OFS_MONO` and `ST_V_BORDER` in
  `hdmi_testpattern_640.sv`.
- The helper's OSD (`ST_HELPER_OSD`) is drawn over this output.
- To go back to the original MiSTeryNano video output (with OSD and ST audio),
  comment out `` `define HDMI_TESTPATTERN `` near the top of `top.sv`.

## Build option: on-screen diagnostic overlay (`DIAG_OVERLAY`, off by default)

The build has an optional **diagnostic overlay** that draws the 68030's state
straight onto the HDMI/DVI picture: three rows of coloured status squares
(video, reset, SDRAM, ROM, 030 bus activity, bus errors) and six rows of 32
"bit bars" (first bus error address, last bus cycle started by the 030 and its
type, the CPU pins, the bus bridge state, and the last program fetch address).
With it, a frozen CPU can be diagnosed from a photo or capture of the screen.

- **How to enable:** in `hdl/tang/console138k/top.sv`, uncomment
  `` `define DIAG_OVERLAY `` (near the top) and rebuild. Comment it out again
  for the normal build.
- **Why it is off by default:** it costs fabric and some timing margin and it
  covers part of the screen. It is a debugging tool, not a feature. With the
  define off, the debug wiring is unused and synthesis removes it, so the
  normal build is the same as without it.
- **What the bars and squares mean:** see [docs/DIAG_OVERLAY.md](docs/DIAG_OVERLAY.md).

## Build option: AE350 helper alongside the desktop (`ST_HELPER`, separate build)

`gw_sh build_st_helper.tcl` builds the ST desktop **with** the AE350 RISC-V
helper running next to it (`impl/pnr/st_helper.fs`). `build_tc138k.tcl` (the
desktop) does not set the define and is unchanged. Full description, register
map, expected output, risks and port plan: [docs/ST_HELPER.md](docs/ST_HELPER.md).

- **Goal:** the AE350 replaces the BL616 as the core's helper MCU, so the
  FPGA-Companion firmware (keyboard, mouse, OSD, floppy, hard disk) can run on
  it and the BL616 never has to be reflashed.
- **Flash: boot-then-release.** The 030 is held in reset while the AE350 boots
  from the SPI flash and copies its image (0x600000) into DDR3. Its firmware
  then sets GPIO[7:0] = 0xA5 ("done with flash"); once its CS# is idle (or,
  as on the real SoC, which leaves CS# asserted, once 0xA5 has been held for
  1 ms: BOOT $05) the flash pins switch **once, for good** to the ST and the
  030 is released, so TOS loads as usual. A timeout fallback (letters `X`/`T`/`C`/`K` on U15,
  or S1 held at power-up) boots the desktop without the helper. Unlike the
  988c846 runtime mux, the switch happens before the ST's flash controller
  leaves reset, and the ST's dual-I/O pads keep their own output enables.
- **Companion link:** after the handoff the AE350 bit-bangs the core's
  `mcu_spi` port (the BL616's port) on GPIO[0..2] (SS#, SCK, MOSI); MISO,
  the core's IRQ# and a "link up" flag reach the AE350 as UART2 CTS#, DCD#
  and DSR# (the SoC's flash SPI registers are not reachable from its CPU).
  Tested on the board 6 Oct 2026: `core status: 5C 42 ... link OK`.
  The BL616 is kept off the link (its inputs ignored, MISO tristated, IRQ held
  high).
- **Mailbox for the ST:** $FFFB00-$FFFB1F (unused on ST/STE/TT/Falcon),
  bridged to the helper's UART2 inside the FPGA. `helper_fw/st_test/`
  (`MBXTERM.PRG`) is a small terminal for it.
- **Serial:** U15 (BL616 USB serial, 115200 8N1) carries the AE350's UART2;
  typing in the same terminal reaches the helper through V14. `spi_irqn`
  moves to C22 in `atarist_st_helper.cst`.
- **ST-side test without disk or keyboard:** `ST_HELPER_CART` (on in this
  build) adds a small self-test cartridge ROM at $FA0000 that TOS runs once
  at boot: it sends a line to the helper and shows the answer, then the
  desktop starts.
- **Firmware:** `helper_fw/companion/` (`build_companion.sh` on Linux, `.bat` on
  Windows), flashed at 0x0600000. See helper_fw/README.md.
- **USB keyboard/mouse:** `ST_HELPER_USB` (on in this build) is a USB host
  on both Console USB-A ports. The AE350 companion firmware
  (`helper_fw/companion/`) reads it. See docs/ST_HELPER.md 7b.
- **STE:** `ST_STE` (on in `build_st_helper.tcl`) forces the STE chipset
  (STE video/DMA sound/joypads, blitter) but keeps TOS in the ST ROM slot
  (flash 0x500000) instead of the MiSTeryNano STE offset. Extra 8 MB RAM stays
  on its own OSD setting. The SD switches (`ST_SD_WRITE_FIX`, `ST_FLOPPY_MEDIACH`,
  `ST_SD_HARDEN`, all on) are described in docs/BUILD.md.
- **030 caches:** `ST_030_CACHES` (off; commented out in
  `build_st_helper.tcl`) builds in the experimental WF68K30L instruction and
  data caches (`wf68k30L_icache.vhd`, `wf68k30L_dcache.vhd`, CACHES generic on
  `WF68K30L_TOP`). They are incomplete (no CIIN, burst fill, write-allocate or
  DMA/blitter snoop), and a TF534/TF536 does not cache ST-RAM, so by default
  the core has no caches: every access goes to the bus. CACR/CAAR stay MOVEC
  readable/writable either way. See docs/ST_HELPER.md 7g.
- **Colour monitor:** `ST_COLOUR_MONITOR` (on in this build) holds the ST's
  mono-detect line high, so TOS boots in colour (low res; medium via
  Options > Change resolution). Delete its line in `build_st_helper.tcl` to
  get ST High (mono). The desktop build (`build_tc138k.tcl`) has no such
  define and stays mono.
- **OSD menu:** `ST_HELPER_OSD` (on in this build) puts the MiSTeryNano
  OSD (`st_helper_osd.v`) over the ST video in front of the HDMI frame
  buffer. The AE350 companion draws it with the original FPGA-Companion
  menu.c/osd_u8g2.c and u8g2. Press F12 to open it (Shift+F12 opens the
  system menu), or use `osd toggle` on the COM console. See
  docs/ST_HELPER.md 7d.
- **Why a separate build:** it changes the boot sequence and the flash pad
  path; the desktop build must keep booting TOS exactly as before.

## What this build is for

This folder is an Atari ST in which a 68030 replaces the 68000, built the way a
TerribleFire (TF) accelerator board is fitted to a real ST. It exists to give
the 030 CPU core a real desktop and real software to run **before** we move it
to the Falcon hardware. It is not meant to be the fastest or most compatible ST.

## The rules for this build

- **Correct, not patched.** The aim is to behave like a real 68030 on a real
  TF board. If a program fails on a real 68030 or TF-accelerated ST, it may
  fail here too. We don't add workarounds to make such software run.
- **The chipset stays stock.** The ST side (GST MCU, shifter, MFP, DMA,
  blitter, sound, floppy) keeps its normal 8 MHz timing. Only the CPU and the
  bus bridge change.
- **The CPU core must stay portable.** Anything that belongs to the 68030
  itself (instruction and data caches, CACR) goes **inside** the WF68K30L core
  in `hdl/cpu030/`, so the same core can move to the Falcon unchanged. Anything
  specific to the ST bus belongs in the bridge (`hdl/cpu030/cpu030_st_bridge.v`).
- **The 68000 stays available.** `ST_CPU_68000` (`build_st_68000.tcl`) builds the original fx68k
  68000 instead of the 030, for comparisons.

## Where it came from

A copy of `misterynano_tc138k/` at commit `c2d695d` (stage 2: ST video through
an on-chip frame buffer to 640x480@60 DVI), made on 2026-09-30. New HDL work
happens here; `misterynano_tc138k/` is kept as it was. File, module and output
names (`atarist_tc138k`) were left unchanged. `HOW_TO_FILL.md` still describes
the original `misterynano_tc138k` upload.

## Core limits

No MMU, no FPU, no working caches, and no address error on odd word accesses, so it is not yet a complete 68030.
TOS 3/4 won't boot (they need PMOVE). Use TOS 2.06, TOS 1.04 or EmuTOS. See `hdl/cpu030/README.md` for the bridge.

## Board

- Device: `GW5AST-LV138PG484AC1/I0` **Version C**
- Top: `hdl/tang/console138k/top.sv` (`module top`)
- Output name: `atarist_tc138k`
- **Tang SDRAM module required**, in J9 / SDRAM0 (`hdl/tang/mega138kpro/sdram.v`, CS0 tied low). This is the plug-in module, not the DDR3 on the SOM. Do not flash this bitstream with J9 empty.
- `Hybrid030/` is the only tree that does **not** need that module. Every HDL build from here does, including this one, `rigsdram/`, and the 030 splice.
- SPI flash: bitstream from 0, **TOS at 0x500000** (with `ST_STE` too), **helper firmware at 0x600000**. Only the bitstream changes between builds (op 53). Never bulk erase, and don't use Gowin Programmer's "SRAM Erase".

## Build

See [docs/BUILD.md](docs/BUILD.md): `gw_sh build_st_helper.tcl` (Windows or Linux), timing checks, op 53 flashing,
and the helper build. `build_tc138k.tcl` / `atarist_tc138k.gprj` are the old desktop build without the helper.

## Not in this tree

- Bitstreams, helper binaries and disk images (kept on the build box, `~/fpga_bitstreams`)
- TOS ROM images
- Nano 20K, Primer 25K, Mega 138K, Console 60K board tops

## Licence

This folder mixes code under several licences. See `LICENSE-NOTES.md` in
this folder for the full list, and for an open question about combining the
GPL-2-only bridge with GPL-3 code.
