# Notices

This repository is a collection. It does **not** have one license that covers every file. Headers inside each file win. This page is a map.

## Already in the tree

| Path | Upstream | License (as shipped) |
|---|---|---|
| `misterynano_tc138k/` | [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) / MiSTery | Keep each component’s file. **fx68k** is GPL-3 — text is in `misterynano_tc138k/fx68k/LICENSE` |
| `rigsdram/` wf68k30L `*.vhd` | Wolfgang Foerster, Inventronik GmbH | **CERN OHL v1.2** (stated in the VHDL headers). This tree is a **modified** core; the header stays |
| `patches/` | this project | same as the file they patch |

## When hybrid source lands

| Path | Upstream | License |
|---|---|---|
| `hybrid_musashi/` Musashi | Karl Stenerud | MIT-style — keep the block in `m68k.h` |
| `hybrid_musashi/` EmuTOS C array | [EmuTOS](https://github.com/emutos/emutos) `VERSION_1_4` | **GPL-2** — keep `emutos/LICENSE.TXT` and the pointer in `emutos_rom.c` |
| `hybrid_falcon030/` original fabric | David | to be stated when the zip is imported |
| TF534 files, if copied later | Stephen J. Leary | **GPL-2** — keep that `LICENSE` |

## Not in this repository

- Atari TOS (any version). User supplies it on SD.
- Andes gcc, Cygwin DLLs, Gowin AE350 SDK.
- Game disks, IDE images, bitstreams.

## What we do not do

- Do not replace upstream headers with a single root `LICENSE` that claims the cores are ours.
- Do not drop `fx68k/LICENSE` or the CERN OHL comment in wf68k30L.
- David’s original glue can take its own license later. Until then, assume you may read and follow along, not relicense the cores.
