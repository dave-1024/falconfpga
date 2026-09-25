# Hybrid workbench — SD card (follow along)

This is David’s hybrid scaffold (Musashi on the AE350 + HDL fabric). It is **not** MiSTeryNano and **not** a product. No support. See the root README.

The card contract below is taken from `falcon_m28.c` (“the card is the machine”). Source for the bats and firmware lands with the final zip. Pin names are REV10-era TF-slot SPI as commented in that file.

## What you flash (three different things)

1. **FPGA bitstream** — Gowin `.fs` for `hybrid_falcon030/` (not in git).
2. **AE350 firmware** — `falcon_m28.bin` at **0x600000** (build with `build_falcon_m28.bat`; see FIRST_TIME.md).
3. **Nothing Atari TOS in flash.** TOS and disks come from the **microSD** in the Console TF slot.

Embedded **EmuTOS 1.4** inside the firmware is only the fallback if the card has no ROM file.

## Card format

- microSD, **FAT32** (MBR partition or superfloppy).
- Files in the **root** directory.
- 8.3 names as written in `FALCON.CFG`.
- The firmware **never writes the FAT**. It will write *inside* an existing image file if that file’s clusters are contiguous. A fragmented file still *loads*; write-back is then disabled (changes stay in RAM).

Do not use exFAT. Do not put the images in a subfolder.

## `FALCON.CFG` (root of the card)

Plain text, one setting per line:

```
ROM=EMUTOS.IMG
DISKA=DISKA.ST
DISKB=WORK.ST
```

| Line | Meaning |
|---|---|
| `ROM=` | 512K TOS image loaded to the guest ROM window at `0x00E00000`. Your file. Typical name for Atari TOS 4.04 is whatever you called the 512K dump. |
| `DISKA=` | Floppy A: `.ST` image. Writes go through to the card if the file is contiguous. |
| `DISKB=` | Floppy B: same idea. |

Any missing line or missing file falls back: embedded EmuTOS, blank A:, blank B:. That is deliberate. A missing card does not brick the firmware.

You supply Atari TOS. This repo does not.

## Suggested first card

1. Format FAT32.
2. Copy a 512K TOS or EmuTOS image as e.g. `TOS404.IMG` or `EMUTOS.IMG`.
3. Copy a small `.ST` as `DISKA.ST` if you want a writable A:.
4. Create `FALCON.CFG`:

```
ROM=TOS404.IMG
DISKA=DISKA.ST
```

5. Eject cleanly from the PC. Insert in the Console **TF** slot. Power the board with bitstream + `falcon_m28.bin` already in flash.

## Green LED (power-off contract)

From the same firmware comments:

- **Solid green** — idle, card writes finished, safe to power off or eject.
- **Dark or flickering** — a card write is in flight. Do not power off.
- **Off / frozen** — firmware is not running.

## What this how-to is not

- Not MiSTeryNano companion / OSD / SPI TOS at `0x500000`.
- Not a promise TOS 4.04 or any game will boot on *your* board.
- Not pin-level SPI documentation. The driver is bit-bang on the REV10 TF-slot GPIOs described in `falcon_m28.c` once that file is in this folder.
