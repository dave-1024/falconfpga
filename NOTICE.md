# Notices

This repository is a collection. It does **not** have one license that covers every file. Headers inside each file win. This page is a map.

David’s original files are **GPL-3.0-or-later**. See `LICENSE-ORIGINAL.md`.

| Path | Upstream | License (as shipped) |
|---|---|---|
| Original fabric, docs, handshake, own patches | David Dunne | **GPL-3.0-or-later** — `LICENSE-ORIGINAL.md` |
| `reference/misterynano_tc138k/` | [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) / MiSTery | Keep each component’s file. **fx68k** is GPL-3 — text is in `misterynano_tc138k/fx68k/LICENSE` |
| `reference/rigsdram/` wf68k30L `*.vhd` | Wolfgang Foerster, Inventronik GmbH | **CERN OHL v1.2** (stated in the VHDL headers). This tree is a **modified** core; the header stays |
| `reference/Hybrid030/hybrid_musashi/` Musashi | Karl Stenerud | MIT-style — keep the block in `m68k.h` |
| `reference/Hybrid030/hybrid_musashi/emutos_rom.c` | [EmuTOS](https://github.com/emutos/emutos) `VERSION_1_4` | **GPL-2** — `reference/Hybrid030/hybrid_musashi/LICENSE.TXT` |
| `reference/Hybrid030/` original glue | David Dunne | **GPL-3.0-or-later** |
| `docs/history/patches/` that only edit upstream | this project | same as the file they patch |
| `Atarist_030_wip/` | MiSTeryNano + wf68k30L + TF534-style bridge | Mixed; see `Atarist_030_wip/LICENSE-NOTES.md` |
| TF534 files, if copied later | Stephen J. Leary | **GPL-2** — keep that `LICENSE` |

## Not in this repository

- Atari TOS (any version). User supplies it on SD.
- Andes gcc, Cygwin DLLs, Gowin AE350 SDK.
- Game disks, IDE images, bitstreams.

## What we do not do

- Do not replace upstream headers with a single root `LICENSE` that claims the cores are ours. (The root `LICENSE`, added 23 Oct 2026, covers David's original work only and points here.)
- Do not drop `fx68k/LICENSE` or the CERN OHL comment in wf68k30L.
