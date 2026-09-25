# FalconFPGA

FPGA work toward an Atari Falcon on a **Sipeed Tang Console** with the **GW5AST-138K** SOM (device `GW5AST-LV138PG484AC1/I0`, **Version C**). Toolchain is **Gowin IDE / gw_sh V1.9.12** on Windows, plus a Linux headless Gowin box used only to compile.

This repository is **source only**. Bitstreams, `impl/`, TOS ROMs and disk images stay on the machine that built or flashed them.

## What this is

The long goal is a Falcon-class machine in FPGA: Motorola **68030** guest, ST-compatible chipset first, Falcon hardware later.

The 030 core is **wf68k30L** (the tree already verified against a real 030), not a rewrite of Musashi and not fx68k. PMMU is a later fabric + RISC-V walk, not inside the CPU core. First silicon for that core does not turn cache or PMMU on.

## Where it started

The project began as a **hybrid scaffold**: HDL fabric plus C modules on the SOM’s **Andes AE350** RISC-V. The guest CPU in that scaffold was **Musashi**. That hybrid was accurate enough to:

- boot **Atari TOS 4.04** (that became the default guest TOS; EmuTOS was not the only target)
- run ST games on the Falcon model (Robocop, Treasure Island Dizzy, Frontier) through a GAMEX wrapper
- accept Atari legacy HD tools and GEM partitions on IDE images
- survive a 36-hour POV-Ray soak whose output file matched the same POV-Ray version on a real Atari STE

C was assembled with Windows batch files and `riscv32-elf-gcc`, not Andesight. Debug was Hatari state saves plus disassembly.

The hybrid exists to **move modules from C to RTL one at a time**, not as the finished machine. Locked AE350/DDR3/AHB errata from that era still apply to any RISC-V fabric path: do not use the dead write lane or 64-bit read upper half; keep AHB 32-bit.

## Where we are

Two vehicles in this repo, on purpose. They do not share a top.

### `rigsdram/` — 030 + external SDRAM oracle

wf68k30L plus a guest image that walks T0–T11 (BSRAM through vectors, including a 32 MB march). Last cold-and-warm silicon that is treated as known-good printed:

```
12345
RIGSDRAM GUEST
IMG=74D8E373
T0–T11 PASS
DONE P
```

`12345` is the healthy UART signature. `112345` only means the AUTO_WARM broker pulse fired late. PnR uses **Replicate Resources = TRUE**. CPU target is **16 MHz**; current Fmax on that tree is above that.

The 030 in this tree is not stock wf68k30L. It carries the instruction audit done against a real **68030 in an Amiga A1200 + ACA1230-55N** (FIXREV14 and earlier). That audit is the oracle for CPU behaviour. Parked on this tree: a false Line-F at `$406` after a cold start; the next instrument is a pipe trace, not another reset workaround.

### `misterynano_tc138k/` — stock ST desktop on this board

Console-138K-only cut of [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) (upstream snapshot `c8e4601`). CPU here is still **fx68k** (68000). Build with `gw_sh build_tc138k.tcl` from that folder (Version C, JTAG-as-GPIO). A one-line board fix dropped a stale `.clk` port map that upstream tc138k still carries (`20260925-mn3`). Replay `mn4` matched. Bitstream is not in git (~36.5 MB `.fs` on the build box).

This tree is **not yet a proven desktop on David’s Console**. Companion firmware, TOS in SPI flash, and SDRAM in J9 are still required. Do not splice the 030 into this folder.

## Where it is headed

1. **Prove stock MiSTeryNano** on the Tang Console: repeated cold boots to a GEM desktop.
2. **Freeze** that tree. Clone it (`misterynano_030/` or similar).
3. **Splice wf68k30L** into the clone using TerribleFire **TF534** bus arbitration, not a drop-in replacement of fx68k. 030 bus (`SIZ` / `DSACKn` / `FC`) is not a 68000 bus.
4. First splice: **8 MHz CPU**, stock ST chipset. Caches off. PMMU off.
5. Then: **16 MHz CPU**, chipset still stock ST speed — a real accelerator, wait-stated onto the 8 MHz bus.
6. Only after that desktop validates the 030: move the same core onto **Falcon** glue (VIDEL, IDE, the hybrid memory map).

Keep `rigsdram/` alive the whole way. If the ST desktop dies, that is the isolated 030+SDRAM check.

## Methods

- **Silicon first.** A passing Gowin log is not a passing board.
- **One golden guest at a time.** Do not judge Line-F work against a shorter test that was never the flashed image.
- **Real 030 as CPU oracle** (A1200 + ACA1230-55N). Hatari + state saves for TOS/game behaviour on the hybrid.
- **Gowin on this SOM:** device Version **C**, Replicate Resources **TRUE** when chasing Fmax. Do not flip that flag to “compare” old reports.
- **Git handshake** for the compile box: `BUILD_REQUEST.md` (chat) / `BUILD_REPORT.md` (bot). See `AGENT_PROTOCOL.md`. The bot compiles and reports; it does not invent HDL. Chat writes the RTL.
- **No double-reset as a product.** AUTO_WARM is a board workaround, not a core fix.

## Hardware notes

- Tang Console + 138K SOM. External SDRAM module in J9 for the ST/rigsdram path.
- FPGA-Companion / BL616 is required for MiSTeryNano OSD, keyboard and TOS load. It is **not** in this repo.
- TOS flash offset on this board is measured from bitstream size after a real build (HDL map 0x500000 vs some docs 0x900000). Do not guess.

## Layout

| Path | Role |
|---|---|
| `rigsdram/` | wf68k30L + SDRAM guest tests |
| `misterynano_tc138k/` | stock ST, fx68k, Console 138K only |
| `patches/` | named diffs the bot may apply when a request says so |
| `AGENT_PROTOCOL.md` | chat / bot rules |
| `BUILD_REQUEST.md` / `BUILD_REPORT.md` | current compile handshake |

Hybrid C/HDL (Musashi + AE350) and reference manuals live outside this repo in the working tree.
