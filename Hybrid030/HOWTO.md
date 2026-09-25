# Hybrid030 — SD card

This is David’s hybrid scaffold (Musashi on the AE350 + REV11b HDL). It is **not** MiSTeryNano and **not** a product. No support. See the root README.

The card contract is `cfg_load()` in `hybrid_musashi/falcon_m28.c`. Keys are matched **exactly** as written below (uppercase, no spaces around `=`).

## What you flash (three different things)

1. **FPGA bitstream** — Gowin `.fs` built from `hybrid_falcon030/` (not in git).
2. **AE350 firmware** — `falcon_m28.bin` at **0x600000**. Build with `hybrid_musashi/build_falcon_m28.bat` (see `hybrid_musashi/FIRST_TIME.md`).
3. **Nothing Atari TOS in flash.** TOS, floppies and hardfiles come from the **microSD** in the Console TF slot.

Firmware contains an **older EmuTOS 1.4** only so a dead or missing card still puts something on the screen. Do not use that copy on purpose. See [EmuTOS](#emutos-vs-tos-404) below.

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

## Sound

There is **no HDMI audio** on this hybrid. Picture is HDMI; sound is not.

Wire a speaker (or a small amp) to the **speaker jumpers on the Tang Console**. Silent HDMI is normal. F11 still switches PSG ↔ 440 Hz so you can hear whether that header is alive.

## Host keys (USB, not on a real Atari keyboard)

Checked in `falcon_m28.c` (`hid_consume`). These keys do not exist on a Falcon keyboard, so firmware swallows them. TOS never sees the scancode.

### F10 — 50 Hz / 60 Hz

Toggles the guest VBL between **50 Hz (PAL)** and **60 Hz (VGA)**. Boot default is 60 Hz unless `VBL=50` is in the cfg.

A real Falcon on VGA runs 60 Hz. PAL titles and a lot of chip music were written for 50 Hz VBL, so on 60 Hz they run about 20% fast. If a game or a tune is rushed, press F10 before assuming the CPU is wrong.

### F11 — audio source

Toggles the audio path between the **YM/PSG** and a **440 Hz test tone**. Use it on the Console speaker header when a title is silent. It does not change frame rate and it does not put sound on HDMI.

### F12 — UART log

Toggles the same flag as `LOG=` in the cfg. On = firmware prints while the 68k runs (slow). Off = desktop speed.

### Print Screen — keyboard joystick

Toggles **IKBD joystick 1** (the ST joystick port, not the mouse port). Games that expect a stick on port 1 can be played from the USB keyboard.

| Control | Keys |
|---|---|
| Up / down / left / right | arrows **or** numpad 8 / 2 / 4 / 6 |
| Fire | Space **or** numpad 0 |

While the mode is on, those keys are **consumed** — they are not also typed into TOS, so a game that reads both keyboard and stick cannot see double input. Turning the mode off sends an all-released packet so a direction cannot stick.

There is no on-screen flag. If a title starts acting like a stick is held, press Print Screen again.

## EmuTOS vs TOS 4.04

EmuTOS generally **runs faster** on this scaffold. It polls hardware and fails cleanly when a chip is missing or odd. Atari TOS 4.04 **assumes** Falcon hardware is present and waits on it. That is TOS, not a broken bitstream.

If you want EmuTOS, put a **current 512K EmuTOS** on the card and point `ROM=` at it. Do **not** rely on the copy burned into firmware.

- The embedded image is an **older 1.4**. Some Falcon video resolutions misbehave on that build.
- Current EmuTOS is **still labelled 1.4**, but those video bugs are fixed. Get a 512K image from the EmuTOS project and put it in the card root.
- The burned copy exists only as a last resort: SD init failed, FAT missing, or `ROM=` load failed, and you still get a desktop instead of a black screen.

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
| `ROM=` | TOS image loaded to the guest ROM window at `0x00E00000`. You supply the file. This bench used 512K TOS 4.04 **or** a current 512K EmuTOS. Missing or failed load → **older embedded EmuTOS 1.4** (fallback only). |
| `DISKA=` | Floppy A: `.ST` image. Default if omitted: look for `DISKA.ST`. Failed load → blank 720K A:. Writes go to the card if the file is contiguous. |
| `DISKB=` | Floppy B: same firmware idea. **Seen working under EmuTOS. Not useful under TOS 4.04** — a real Falcon has no second floppy port, and TOS 4.04 does not drive B:. Omit this line on a TOS 4.04 card. |
| `HDD0=` | IDE unit 0 **hardfile**. Raw sector image on the card (not a `.ST`). Presented as the Falcon IDE master. Omit → no IDE 0. |
| `HDD1=` | IDE unit 1 (slave), same rules. |
| `HD0NAME=` | **IDE IDENTIFY model string** for unit 0 (≤40 chars). This is what tools see on the IDE chain. It is **not** the filename. If omitted, firmware uses the 8.3 stem (`HD0.IMG` → `HD0`). |
| `HD1NAME=` | Same for unit 1. |

You supply Atari TOS, EmuTOS, and any hardfile. This repo does not ship Atari TOS.

Hardfiles are mapped, not copied into RAM. Size is the file size on the card (sector count = bytes / 512). Same write-back rule as floppies: contiguous clusters can write through; fragmented files stay RAM-side for writes.

A missing card, missing FAT, or missing line does not brick the firmware. Hardfile attach happens **after** the floppies so a bad `HDD0=` cannot take down A:.

## Floppy B

The firmware will still attach `DISKB=` if the file is there. EmuTOS will show drive B. TOS 4.04 will not: Falcon TOS only knows one floppy. That is TOS, not a dead image. Use `HDD0=` for a second volume under TOS 4.04.

## Hardfile name (`HD0NAME=` / `HD1NAME=`)

Some Atari HD tools only accept **legacy drive model names** — strings that shipped with a real Falcon or with a period IDE box. They look at the IDENTIFY model, not at `HD0.IMG`.

If a partitioner refuses the image, the file is often fine and the **name does not match** what that tool was written for. Set `HD0NAME=` to a model that tool already knows, then try again.

This bench has used the IDE hardfile with:

- **HDDRIVER**
- Atari’s own Falcon setup disks (**AHDI / HDX**)
- other partitioning software that talks **IDE** (GEM partitions included)

That is a workbench result, not a promise every HD tool will like every name.

## `FALCON.CFG` — behaviour knobs

Leave these alone unless you know why you are changing them. Defaults are what m28 uses if the line is absent.

**`LOG=0` / `LOG=1`** — default **on**. UART trace while the guest runs. See above. F12 toggles live.

**`VBL=50` / `VBL=60`** — boot frame rate only. Default 60 Hz. F10 toggles live after boot. Use `VBL=50` if every PAL title on this card should start at PAL speed.

**`BUS=32`** — default is **24-bit**, like a stock Falcon (addresses masked to 16 MB). That is the mode that matched Hatari and this bench for TOS and games. `BUS=32` turns the mask off. Only for experiments that need a full 32-bit address. Do not set it to “make it faster”.

**`CACHEOPT=1`** (default) — range flushes of the framebuffer and mailbox. **`CACHEOPT=0`** forces the old whole-cache `WBINVAL_ALL` every VBL. That is much slower. Leave `1`.

**`FLUSHDIV=N`** — default `1` (flush every VBL). Higher N skips flushes (`FLUSHDIV=8` = every 8th VBL). That was a diagnostic: it can make the guest feel quicker and will tear or stale the picture. `0` is treated as `1`. Do not leave this above `1` for a desktop card.

**`PALSPLIT=1`** (default) — raster palette-split list published to the video fabric, so mid-frame palette changes can display. **`PALSPLIT=0`** turns that path off (fabric falls back). Only if a title misbehaves on splits and you want to prove it.

**`SLICE=n`** — how many 68k cycles the AE350 runs per host slice. Default `0` = automatic (coarse 10000, finer only when a short timer IRQ or a palette split needs it). **`SLICE=10000`** pins the old pre-M28 cap for bisection. Smaller numbers make the host check hardware more often and cost AE350 time. Leave unset unless you are chasing a timer or split bug.

## Suggested first card (TOS 4.04)

1. Format FAT32.
2. Copy a 512K TOS 4.04 image as `TOS404.IMG`.
3. Copy a small `.ST` as `DISKA.ST` if you want a writable A:.
4. Root `FALCON.CFG`:

```
ROM=TOS404.IMG
DISKA=DISKA.ST
LOG=0
```

5. Eject cleanly. Insert in the Console **TF** slot. Power with bitstream + `falcon_m28.bin` already in flash.

## Suggested card (current EmuTOS)

Same FAT32 card. Put a **current** 512K EmuTOS in the root (still called 1.4; not the firmware copy):

```
ROM=EMUTOS.IMG
DISKA=DISKA.ST
DISKB=WORK.ST
LOG=0
```

`DISKB=` is only worth it on EmuTOS.

## Suggested card with a hardfile

```
ROM=TOS404.IMG
DISKA=DISKA.ST
HDD0=HD0.IMG
HD0NAME=FALCON HD
LOG=0
```

`HD0NAME=` is the string on the IDE chain. Change it to a legacy Falcon-era model if HDDRIVER / HDX / AHDI will not touch the disk. Do not put a `.ST` floppy file on `HDD0=`.

## Green LED (power-off contract)

- **Solid green** — idle, card writes finished, safe to power off or eject.
- **Dark or flickering** — a card write is in flight. Do not power off.
- **Off / frozen** — firmware is not running.

## What this how-to is not

- Not MiSTeryNano companion / OSD / SPI TOS at `0x500000`.
- Not a promise TOS 4.04, HDX, or any game will boot on *your* board.
- Not pin-level SPI documentation. The driver is bit-bang on the REV10 TF-slot GPIOs in `hybrid_musashi/falcon_m28.c`.
