# Hybrid030 — SD card

This is David’s hybrid scaffold (Musashi on the AE350 + REV11b HDL). It is **not** MiSTeryNano and **not** a product. No support. See the root README.

The card contract is `cfg_load()` in `hybrid_musashi/falcon_m28.c`. Keys are matched **exactly** as written below (uppercase, no spaces around `=`).

## What you flash (three different things)

1. **FPGA bitstream** — Gowin `.fs` built from `hybrid_falcon030/` (not in git).
2. **AE350 firmware** — `falcon_m28.bin` at **0x600000**. Build with `hybrid_musashi/build_falcon_m28.bat` (see `hybrid_musashi/FIRST_TIME.md`).
3. **Nothing Atari TOS in flash.** TOS, floppies and hardfiles come from the **microSD** in the Console TF slot.

Embedded **EmuTOS 1.4** inside the firmware is only the fallback if the card has no usable `ROM=` file.

## Card format

- microSD, **FAT32** (MBR partition or superfloppy).
- Files in the **root** directory. Not a subfolder.
- 8.3 names in `FALCON.CFG` (`NAME.EXT`).
- The firmware **never writes the FAT**. It will write *inside* an existing image file if that file’s clusters are contiguous. A fragmented file still *loads*; write-back is then disabled (changes stay in RAM).
- `FALCON.CFG` itself is read as at most 2048 bytes. `#` lines and blanks are ignored by skipping to the next newline; keys must start at column 0 of a line.

Do not use exFAT.

## If it feels slow: turn the log off

**`LOG=1` is the default even if `FALCON.CFG` has no `LOG=` line.** The firmware prints a running trace on the UART while the 68k guest runs. That costs real time. You do not need a serial cable plugged in for it to hurt — the guest just feels sluggish and you will not see why.

Put this in `FALCON.CFG` for normal use:

```
LOG=0
```

F12 still toggles the log at runtime if you later want the UART back.

## `FALCON.CFG` — files

```
ROM=TOS404.IMG
DISKA=DISKA.ST
DISKB=WORK.ST
HDD0=HD0.IMG
HDD1=HD1.IMG
HD0NAME=IDE MASTER
HD1NAME=IDE SLAVE
LOG=0
```

| Line | Meaning |
|---|---|
| `ROM=` | TOS image loaded to the guest ROM window at `0x00E00000`. You supply the file. This bench used 512K TOS 4.04. Missing or failed load → embedded EmuTOS. |
| `DISKA=` | Floppy A: `.ST` image. Default if omitted: look for `DISKA.ST`. Failed load → blank 720K A:. Writes go to the card if the file is contiguous. |
| `DISKB=` | Floppy B: same idea. Omit → blank 720K B:. |
| `HDD0=` | IDE unit 0 **hardfile**. Raw sector image on the card (not a `.ST`). Presented as the Falcon IDE master. AHDI / HDX / GEM partitions work on this file — that is how this bench partitioned C:. Omit → no IDE 0. |
| `HDD1=` | IDE unit 1 (slave), same rules. |
| `HD0NAME=` | IDENTIFY model string for unit 0, up to 40 characters. Else the 8.3 stem (`HD0.IMG` → `HD0`), else the firmware default. |
| `HD1NAME=` | Same for unit 1. |

You supply Atari TOS and any hardfile. This repo does not.

Hardfiles are mapped, not copied into RAM. Size is the file size on the card (sector count = bytes / 512). Same write-back rule as floppies: contiguous clusters can write through; fragmented files stay RAM-side for writes.

A missing card, missing FAT, or missing line does not brick the firmware. Hardfile attach happens **after** the floppies so a bad `HDD0=` cannot take down A:.

## `FALCON.CFG` — behaviour knobs

These are optional. Defaults are what m28 already uses if the line is absent.

| Line | Default | Meaning |
|---|---|---|
| `LOG=0` / `LOG=1` | **on (`1`)** | UART trace while the guest runs. **Makes the machine feel slow.** You will not see this unless a serial adaptor is connected. Put `LOG=0` in the cfg for desktop use. F12 toggles at runtime. |
| `CACHEOPT=0` / `CACHEOPT=1` | on (`1`) | `0` forces the old whole-cache `WBINVAL_ALL` path (also slow). Leave `1`. |
| `FLUSHDIV=N` | `1` | Divider on the cache-flush cadence. `0` is treated as `1`. |
| `BUS=32` | off (24-bit Falcon mask) | First character `3` enables 32-bit addresses (`BUS=32`). Anything else stays masked. |
| `VBL=50` / `VBL=60` | firmware default | Pins VBL to 50 Hz or 60 Hz. |
| `PALSPLIT=0` / `PALSPLIT=1` | on (`1`) | `0` disables the pal-split path. |
| `SLICE=n` | automatic (`0`) | Cap on the 68k slice. `SLICE=10000` is the documented “restore old cap” value. |

## Suggested first card (floppy only)

1. Format FAT32.
2. Copy a 512K TOS or EmuTOS image, e.g. `TOS404.IMG`.
3. Copy a small `.ST` as `DISKA.ST` if you want a writable A:.
4. Root `FALCON.CFG`:

```
ROM=TOS404.IMG
DISKA=DISKA.ST
LOG=0
```

5. Eject cleanly. Insert in the Console **TF** slot. Power with bitstream + `falcon_m28.bin` already in flash.

## Suggested card with a hardfile

Same as above, plus a raw IDE image in the root:

```
ROM=TOS404.IMG
DISKA=DISKA.ST
HDD0=HD0.IMG
HD0NAME=FALCON HD
LOG=0
```

Partition and format that image with Atari tools (HDX / AHDI / GEM) on the hybrid, or copy an image you already prepared. Do not put a `.ST` floppy file on `HDD0=`.

## Green LED (power-off contract)

- **Solid green** — idle, card writes finished, safe to power off or eject.
- **Dark or flickering** — a card write is in flight. Do not power off.
- **Off / frozen** — firmware is not running.

## What this how-to is not

- Not MiSTeryNano companion / OSD / SPI TOS at `0x500000`.
- Not a promise TOS 4.04, HDX, or any game will boot on *your* board.
- Not pin-level SPI documentation. The driver is bit-bang on the REV10 TF-slot GPIOs in `hybrid_musashi/falcon_m28.c`.
