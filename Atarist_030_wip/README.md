# Atarist_030_wip: a 68030 Atari ST, as a test bed for the Falcon

## Credits and thanks: Stephen J. Leary (TerribleFire)

The 68030-to-ST bus bridge in this build (`cpu030/cpu030_st_bridge.v`) is
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

**The switch** is in `tang/console138k/top.sv`, on the `hdmi_testpattern_640`
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
- The on-screen menu (OSD) is **not** shown on this output yet.
- The ST picture through the frame buffer has not yet been tested on real
  hardware (the colour bars have).
- To go back to the original MiSTeryNano video output (with OSD and ST audio),
  comment out `` `define HDMI_TESTPATTERN `` near the top of `top.sv`.

## Build option: on-screen diagnostic overlay (`DIAG_OVERLAY`, off by default)

The build has an optional **diagnostic overlay** that draws the 68030's state
straight onto the HDMI/DVI picture: three rows of coloured status squares
(video, reset, SDRAM, ROM, 030 bus activity, bus errors) and six rows of 32
"bit bars" (first bus error address, last bus cycle started by the 030 and its
type, the CPU pins, the bus bridge state, and the last program fetch address).
With it, a frozen CPU can be diagnosed from a photo or capture of the screen.

- **How to enable:** in `tang/console138k/top.sv`, uncomment
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
- **Firmware:** `helper_fw/mailbox/` (`build_mailbox.bat`, AndeSight), flashed
  at 0x0600000.
- **USB keyboard/mouse:** `ST_HELPER_USB` (on in this build) is a USB host
  on both Console USB-A ports. The AE350 companion firmware
  (`helper_fw/companion/`) reads it. See docs/ST_HELPER.md 7b.
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
  in `cpu030/`, so the same core can move to the Falcon unchanged. Anything
  specific to the ST bus belongs in the bridge (`cpu030/cpu030_st_bridge.v`).
- **The 68000 stays available.** Comment out `` `define CPU_030 `` at the top
  of `atarist/atarist.v` to build the original fx68k 68000 instead.

## Where it came from

A copy of `misterynano_tc138k/` at commit `c2d695d` (stage 2: ST video through
an on-chip frame buffer to 640x480@60 DVI), made on 2026-09-30. New HDL work
happens here; `misterynano_tc138k/` is kept as it was. File, module and output
names (`atarist_tc138k`) were left unchanged. `HOW_TO_FILL.md` still describes
the original `misterynano_tc138k` upload.

## Status

| Step | State |
|---|---|
| 68030 (WF68K30L) replaces fx68k through a TF534-style bridge, CPU at 8 MHz locked to the ST bus | Built and simulated (`3b9afa6`), **not yet tested on hardware** |
| Tighter bridge: 16 MHz CPU clock locked to `clk_32`, faster bus handshake | Planned |
| Instruction cache inside the core (256 bytes, 16-byte lines, CACR control) | Planned |
| Data cache inside the core (256 bytes, write-through, never caching I/O at `$FF8000` and up) | Planned |
| Fast RAM | Later |

Known limits of the core today: no MMU, no FPU, no caches yet, and no
address error on odd word accesses, so it is not yet a complete 68030. TOS 3
and 4 won't boot, because they need PMOVE (MMU). Use EmuTOS or TOS 1.04.

See `cpu030/README.md` for how the bridge works, and `BUILD_REPORT.md` at the
top of the repository for each build's results.

## Board

- Device: `GW5AST-LV138PG484AC1/I0` **Version C**
- Top: `tang/console138k/top.sv` (`module top`)
- Output name: `atarist_tc138k`
- **Tang SDRAM module required**, in J9 / SDRAM0 (`tang/mega138kpro/sdram.v`, CS0 tied low). This is the plug-in module, not the DDR3 on the SOM. Do not flash this bitstream with J9 empty.
- `Hybrid030/` is the only tree that does **not** need that module. Every HDL build from here does, including this one, `rigsdram/`, and the 030 splice.
- TOS in SPI flash: **0x500000** (STE TOS at 0x540000), as in `misterynano_tc138k`. Only the bitstream changes between builds. Don't use Gowin Programmer's "SRAM Erase".

## Build (Windows Gowin V1.9.12)

Open this folder, not `rigsdram`.

**Preferred (options actually applied):**

```
cd Atarist_030_wip
gw_sh build_tc138k.tcl
```

TCL sets Version C, `use_jtag_as_gpio 1`, MSPI/SSPI/DONE/CPU/READY as GPIO, `replicate_resources 1`.

**IDE:** File → Open → `atarist_tc138k.gprj`. The `.gprj` is a file list. Confirm Process Configuration matches the TCL before you hit Run: SystemVerilog 2017, top module `top`, device version C, and dual-purpose pins JTAG / DONE / READY / MSPI / SSPI / CPU as GPIO. Leave MODE and I2C off.

Bitstream: `impl/pnr/atarist_tc138k.fs` (gitignored).

## Not in this tree

- FPGA-Companion / BL616 firmware (needed for OSD / TOS load / keyboard)
- TOS ROM images
- Nano 20K, Primer 25K, Mega 138K, Console 60K board tops

Cold-boot on this SOM is a known open item in both this core and rigsdram. Stock `top.sv` already ties `.reset` / `.user` to `0` “to fix tc138k booting”.

## Licence

This folder mixes code under several licences. See `LICENSE-NOTES.md` in
this folder for the full list, and for an open question about combining the
GPL-2-only bridge with GPL-3 code.
