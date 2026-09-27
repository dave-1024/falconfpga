# Hybrid030 — SD card

This is David’s hybrid scaffold (Musashi on the AE350 + REV11b HDL). It is **not** MiSTeryNano and **not** a product. No support. See the root README.

The card contract is `cfg_load()` in `hybrid_musashi/falcon_m28.c`. Keys are matched **exactly** as written below (uppercase, no spaces around `=`).

## Board

**No Tang SDRAM module.** This hybrid uses the DDR3 on the 138K SOM. Leave the J9 socket empty.

The plug-in SDRAM module is for the HDL trees only: `misterynano_tc138k/`, `rigsdram/`, and every HDL build after this one. Do not flash those with J9 empty.

## What you flash (three different things)

1. **FPGA bitstream** — Gowin `.fs` built from `hybrid_falcon030/` (not in git). If you build in the GUI, tick **Use MSPI as regular IO** and **Use CPU as regular IO** first, or Place & Route fails. Steps: [hybrid_falcon030/GUI.md](hybrid_falcon030/GUI.md). CLI: `build_hybrid.tcl` sets them.
2. **AE350 firmware** — `falcon_m28.bin` at **0x600000**. Build with `hybrid_musashi/build_falcon_m28.bat` (see `hybrid_musashi/FIRST_TIME.md`).
3. **Nothing Atari TOS in flash.** TOS, floppies and hardfiles come from the **microSD** in the Console TF slot.

Firmware contains an **older EmuTOS 1.4** only so a dead or missing card still puts something on the screen. Do not use that copy on purpose. See [EmuTOS](#emutos-vs-tos-404) below.
