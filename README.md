# FalconFPGA

Hello — thanks for opening this.

This is a private workshop for bringing an **Atari Falcon** up on a small modern FPGA board. It is not a finished core you download and play. It is the notes, HDL, and build plumbing for one machine on the bench: a Sipeed Tang Console with a 138K SOM, a real 68030 as the teacher, and a lot of patience.

The owner of the board is David. If you are reading this as a future-me, or as someone helping compile, the useful sentence is: we already had a software 68030 that could boot TOS and render for a day without drifting a byte. Now we are teaching the same machine to exist in gates, carefully, on hardware we can hold.

## This is not a product

**Read this before you buy a Tang Console, an SDRAM module, or anything else because of this repository.**

This is a **personal workbench**, published so other people can follow along if they want to. It is not a product. It is not a promise of a product. It is not a promise that a Falcon, an ST desktop, or any particular game will ever work on your board.

- Do **not** buy hardware expecting a finished core you can plug in and use.
- David will **not** provide technical support to get “X” working on your machine.
- Issues, mail, and “it doesn’t boot” tickets are not a support channel.
- Dates, checklists, and “where it is headed” are a map of *this* bench. They are not a delivery schedule.

If you clone this anyway, you are on your own — same as any other public FPGA notebook.

## AI assistance

This bench is **one person**. An AI assistant is used for engineering help: HDL drafts and review, documentation, and git plumbing. That is how a single workbench produces this much writing.

It does not replace the board, the real 68030, or the decision of what is known-good. Silicon results and the instruction audit are David’s. Commit volume is not a team. The cores listed under Credits were written by the people named there, not by the assistant.

---

FPGA work toward an Atari Falcon on a **Sipeed Tang Console** with the **GW5AST-138K** SOM (device `GW5AST-LV138PG484AC1/I0`, **Version C**). Toolchain is **Gowin IDE / gw_sh V1.9.12** on Windows, plus a Linux headless Gowin box used only to compile.

This repository is **source only**. Bitstreams, `impl/`, and disk images stay on the machine that built or flashed them. **Atari TOS is not in git.** The hybrid was designed so **any TOS the user owns can be loaded from an SD card**.

## What this is

The long goal is a Falcon-class machine in FPGA: Motorola **68030** guest, ST-compatible chipset first, Falcon hardware later.

The guest CPU started from the public **wf68k30L** core. That stock core was **heavily re-engineered** here — initialisers, exception frames, MOVEM/abort, NBCD, RTD, SFC/DFC reset, and a pile of smaller bus and privilege fixes. It was also **heavily audited for CPU instruction errors** against a real 68030: opcode by opcode, including cases where the tests passed and the silicon still disagreed. What lives in `rigsdram/` is that tree, not an unmodified download. It is not a Musashi rewrite and it is not fx68k.

PMMU is a later fabric + RISC-V walk, not inside the CPU core. First silicon for this core does not turn cache or PMMU on.

## Where it started

The project began as a **hybrid scaffold**: HDL fabric plus C modules on the SOM’s **Andes AE350** RISC-V. The guest CPU in that scaffold was **Musashi**. That hybrid was accurate enough to:

- boot **Atari TOS 4.04** from an SD image the user supplies (that became the default guest TOS; EmuTOS was not the only target)
- run ST games on the Falcon model (Robocop, Treasure Island Dizzy, Frontier) through a GAMEX wrapper
- accept Atari legacy HD tools and GEM partitions on IDE images
- survive a 36-hour POV-Ray soak whose output file matched the same POV-Ray version on a real Atari STE

C was assembled with Windows batch files and `riscv32-elf-gcc`, not Andesight. Debug was Hatari state saves plus disassembly.

The hybrid exists to **move modules from C to RTL one at a time**, not as the finished machine. Locked AE350/DDR3/AHB errata from that era still apply to any RISC-V fabric path: do not use the dead write lane or 64-bit read upper half; keep AHB 32-bit.

Archive slots: `hybrid_falcon030/` (HDL) and `hybrid_musashi/` (C + bats). Source lands when David sends the final tree. Compile notes are already in `hybrid_musashi/FIRST_TIME.md`. Do not install AndeSight.

## Where we are

Two **active** vehicles in this repo, on purpose. They do not share a top. The hybrid folders above are frozen history, not a third live Gowin target.

### `rigsdram/` — 030 + external SDRAM oracle

The re-engineered wf68k30L plus a guest image that walks T0–T11 (BSRAM through vectors, including a 32 MB march). Last cold-and-warm silicon that is treated as known-good printed:

```
12345
RIGSDRAM GUEST
IMG=74D8E373
T0–T11 PASS
DONE P
```

`12345` is the healthy UART signature. `112345` only means the AUTO_WARM broker pulse fired late. PnR uses **Replicate Resources = TRUE**. CPU target is **16 MHz**; current Fmax on that tree is above that.

The instruction audit was run against a real **68030 in an Amiga A1200 + ACA1230-55N** (FIXREV14 session and the work before it). The audit was treated as complete for the scoped instruction set. The A1200 overturned more than one paper argument about `$A`/`$B` boundaries — F38 looked fine in tests and was still wrong. That machine is the oracle for CPU behaviour. Do not drop a fresh upstream wf68k30L on top of this tree and expect the same results.

Parked on this tree: a false Line-F at `$406` after a cold start; the next instrument is a pipe trace, not another reset workaround.

### `misterynano_tc138k/` — stock ST desktop on this board

Console-138K-only cut of [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) (upstream snapshot `c8e4601`). CPU here is still **fx68k** (68000). Build with `gw_sh build_tc138k.tcl` from that folder (Version C, JTAG-as-GPIO). A one-line board fix dropped a stale `.clk` port map that upstream tc138k still carries (`20260925-mn3`). Replay `mn4` matched. Bitstream is not in git (~36.5 MB `.fs` on the build box).

This tree is **not yet a proven desktop on David’s Console**. Companion firmware, TOS in SPI flash, and SDRAM in J9 are still required. Do not splice the 030 into this folder.

## Where it is headed

1. **Prove stock MiSTeryNano** on the Tang Console: repeated cold boots to a GEM desktop.
2. **Freeze** that tree. Clone it (`misterynano_030/` or similar).
3. **Splice the re-engineered wf68k30L** into the clone using TerribleFire **TF534** bus arbitration, not a drop-in replacement of fx68k. 030 bus (`SIZ` / `DSACKn` / `FC`) is not a 68000 bus.
4. First splice: **8 MHz CPU**, stock ST chipset. Caches off. PMMU off.
5. Then: **16 MHz CPU**, chipset still stock ST speed — a real accelerator, wait-stated onto the 8 MHz bus.
6. Only after that desktop validates the 030: move the same core onto **Falcon** glue (VIDEL, IDE, the hybrid memory map).

Keep `rigsdram/` alive the whole way. If the ST desktop dies, that is the isolated 030+SDRAM check.

## Methods

- **Silicon first.** A passing Gowin log is not a passing board.
- **One golden guest at a time.** Do not judge Line-F work against a shorter test that was never the flashed image.
- **Instruction audit against a real 030** (A1200 + ACA1230-55N). Tests that pass can still be wrong; the Amiga was allowed to overrule them. Hatari + state saves for TOS/game behaviour on the hybrid.
- **Gowin on this SOM:** device Version **C**, Replicate Resources **TRUE** when chasing Fmax. Do not flip that flag to “compare” old reports.
- **Git handshake** for the compile box: `BUILD_REQUEST.md` (chat) / `BUILD_REPORT.md` (bot). See `AGENT_PROTOCOL.md`. The bot compiles and reports; it does not invent HDL. Chat writes the RTL.
- **No double-reset as a product.** AUTO_WARM is a board workaround, not a core fix.

## Hardware notes

- Tang Console + 138K SOM. External SDRAM module in J9 for the ST/rigsdram path.
- FPGA-Companion / BL616 is required for MiSTeryNano OSD, keyboard and TOS load. It is **not** in this repo.
- Hybrid TOS: user-supplied image on **SD**. EmuTOS 1.4 may ship as a GPL C array; Atari TOS does not.
- Nano TOS flash offset is measured from bitstream size after a real build (HDL map 0x500000 vs some docs 0x900000). Do not guess.

## Credits

Courtesy only — these people built the shoulders. Licenses stay in `NOTICE.md` and in their files. Nothing here assigns their work to David.

- **Wolfgang Foerster** (Inventronik) — wf68k30L, the 030 core this project started from
- **Karl Stenerud** — Musashi, the hybrid guest CPU
- **Jorge Cwik** — fx68k, the 68000 in MiSTeryNano
- **Till Harbaum** and **MiSTle-Dev** — MiSTeryNano and FPGA-Companion on the Tang boards
- **György Szombathelyi** (gyurco) and the MiSTery authors — the STE FPGA core Nano ports
- **Stephen J. Leary** — TF534 bus arbitration, the planned 030-on-ST splice
- **The EmuTOS developers** — the optional GPL TOS image
- **The Hatari developers** — the hybrid debug method (state saves and disassembly)
- **Individual Computers** — the ACA1230-55N used as the real-030 instruction oracle

If a name is missing, say so and it goes here.

## Layout

| Path | Role |
|---|---|
| `rigsdram/` | re-engineered and instruction-audited wf68k30L + SDRAM guest tests |
| `misterynano_tc138k/` | stock ST, fx68k, Console 138K only |
| `hybrid_falcon030/` | hybrid HDL scaffold (source pending) |
| `hybrid_musashi/` | hybrid C guest + bats (source pending; compile notes ready) |
| `patches/` | named diffs the bot may apply when a request says so |
| `AGENT_PROTOCOL.md` | chat / bot rules |
| `BUILD_REQUEST.md` / `BUILD_REPORT.md` | current compile handshake |
| `NOTICE.md` / `LICENSE-ORIGINAL.md` | license map; David’s original files are GPL-3.0-or-later |
