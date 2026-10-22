# Which TOS works on the 68030 ST core

## What every TOS image needs
- Written to the board's flash at **`0x500000`** (the TOS slot) with `programmer_cli` op 56 `--mcuFile <file> --spiaddr 0x500000`.
- The file name must end in **`.bin`**.
- A single **256 KB** image (STE TOS slot). A smaller image (e.g. 192 KB): TODO, padding to 256 KB is assumed but not documented in the sources.
- Normal byte order. (Some downloads are byte-swapped, e.g. exxos `TOS_19_06_2025/TOS.bin`.)
- TOS is not in git: supply your own.

## Summary

| TOS | Works? | Notes |
|---|---|---|
| EmuTOS 192K UK | TODO: no board result in the sources | EmuTOS's 192K build (TARGET_192) has **no TT-RAM support**. Hatari forces EmuTOS 192 to a 68000 |
| **EmuTOS 256K UK** | **Yes, the current working TOS** | Detects TT-RAM ("Alt-RAM 16 MB") since the [C2] CMPA.W fix plus `TT_RV_MASK` ($5A8 hidden), commit `f73d42d`. With the [C10] I-cache fix (71624aa, build tt20) programs loaded into TT-RAM run with the caches on (FrontBench prgflags 7: lastcount 1362 vs 1169 caches off vs 990 ST-RAM). Blitter shows greyed out (open) |
| TOS 1.04 | **GAP for David:** no board result in the repo | A 68000-era TOS (192 KB). Expected to know nothing about TT-RAM or the 030 caches, so it would only use ST-RAM. Not confirmed; needs a board test (and the 192 KB padding question above) |
| **TOS 2.06** (256K) | **Yes** | Boots to the GEM desktop from cold; used for all GEMBENCH comparisons. Switches the caches on at boot. TT-RAM with stock 2.06 on this core: TODO (not tested in the sources). The ST536 v2 image uses a stock-2.06-style probe (steps 128K from `$01000000` until a bus error) |
| exxos ST536 TOS 2.06 **v1** (`ST536.img`, May 2022 alpha) | No (in Hatari) | Halts (double fault) during the ST-RAM test in Hatari 2.5.0. Not tried on the board **(unsure)**. Copies ROM to TT-RAM above 60 MB, assuming a 64 MB card |
| exxos ST536 TOS 2.06 **v2** (`ST536a2/tos206uk.img`, March 2023, "TTram fix") | Boots in Hatari; board inconclusive | In Hatari it shows the ST536 logo, "Checking ROM CRC.. Done!" and reaches the desktop. On the board the test was inconclusive (HDMI stayed black) **(from the session report; not written in the source files)**. Checks it runs at `$E00000` and checksums the ROM. No PMMU code. May need changes for this board |

## ST536 / TF536 extras
- Neither exxos image contains "TF536"/"Terriblefire" text, so they are exxos's **ST536** builds, not confirmed TF536 TOS.
- A real TF536 uses **stock TOS 2.06** plus AUTO-folder tools from agranlund's `tftools` (GPL2): `fastram.prg` (TOS 2.x), `maprom.prg`, `blitfix.prg`, in that order.
- **BLITFIX:** use it if icons are missing or menus hang **(symptom wording from the session; the readme is `blitfix.txt`)**.
- **GAP (later, extensive testing):** the exact BLITFIX and MAPROM setup on this core.
- **MAPROME / maprom:** leave out for now (copies the ROM into RAM; on a real 030 that needs the PMMU, which this core lacks) **(reason unsure)**.
- Source downloads and checksums: `/workspace/tosimg/tf536/SOURCES.md` (not in git).

## Why some work and some don't (plain words)
- **EmuTOS 256K** is written to cope with many machines. It probes for TT-RAM itself, so once the CPU compared
  addresses correctly ([C2]) and stopped trusting stale memory flags (`TT_RV_MASK`) it found the 16 MB.
- **EmuTOS 192K** is built without TT-RAM support at all.
- **TOS 2.06** knows the 68030 caches and turns them on, so it boots; whether it uses TT-RAM on this core is untested.
- **ST536 TOS 2.06** images were made for exxos's ST536 board (other memory layout, ROM copied to fast RAM), so they
  probably need BLITFIX/MAPROM-style help, or changes, on this board. Untested here; a later target.
- **TOS 3/4** need a PMMU (PMOVE), which this core does not have yet.

## Status
The board stays on EmuTOS 256K for ongoing work (release build tt20). ST536 TOS 2.06 (with BLITFIX/MAPROM) is
untested and left for the extensive-testing phase.
