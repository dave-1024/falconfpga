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
