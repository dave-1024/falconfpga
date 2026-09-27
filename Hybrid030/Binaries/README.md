# Binaries — flash and use

This folder is for someone who wants to **flash the hybrid and stop**. You do not need to compile anything. You do not need AndeSight.

Unzip `Binaries.zip`. It holds two files, built from the hybrid source in this repo, unmodified:

| File | What it is | Where it goes |
|---|---|---|
| `Falcon030.fs` | FPGA bitstream. About 37 MB (38,476,459 bytes). | External flash, address **0x0** |
| `falcon_m28.bin` | AE350 firmware. About 1 MB (1,021,320 bytes). | External flash, address **0x0600000** |

Packed 27 September 2026. If the source in git moves later, this zip is this snapshot. It is not rebuilt for you.

## The firmware address

Type **0x0600000**. Copy that. The Programmer box insists on the leading 0.

`0x600000` is the same number on paper. In that box it is much too easy to type **0x6000000**, and that is a **different address**. The firmware will not land, and the board will not boot.

- Yes: `0x0600000`
- No: `0x600000`
- No: `0x6000000`

The log must say programming starts from `0x0600000`. The file is about 1 MB, so the end is near `0x0700000`. Not `0x700000`.

## What this is not

**Not a product. No support.** David will not help you get a desktop, a game, or a monitor working. Issues and mail are not a support channel. If it does not do what you hoped, you are on your own.

It is also not:

- a promise of a TOS desktop, sound, or a picture on your monitor
- MiSTeryNano, and not the 030 HDL path in `rigsdram/`
- a Tang SDRAM image. **Leave J9 empty.** This hybrid uses the DDR3 on the 138K SOM. The plug-in module is for the other trees.
- Atari TOS. TOS is not in the zip. You supply it on a microSD card. See [../HOWTO.md](../HOWTO.md).
- HDMI audio. Picture is HDMI. Sound is a speaker on the Console speaker jumpers.

Flashing the wrong file at the wrong address will not boot. The two files are not interchangeable.

## What you need

- Tang Console with the **138K SOM** (device `GW5AST-138C`)
- A USB cable to the Console programming port
- **Gowin Programmer** (the Programmer tool, not the project window). This bench uses Gowin V1.9.12.03. Do not install AndeSight.
- HDMI cable and a monitor, if you want a picture
- A FAT32 microSD, if you want your own TOS. Optional for the first flash. See [../HOWTO.md](../HOWTO.md).

No SDRAM module.

## 1. Flash the bitstream first

Do this **before** the firmware. This step erases external flash, then writes the bitstream. If you write firmware first, this step wipes it.

1. Unzip `Binaries.zip`. Confirm `Falcon030.fs` is about 37 MB. A tiny file is a bad unzip.
2. Power the Console from USB. Leave J9 empty.
3. Open **Gowin Programmer**.
4. Scan the cable. You may see more than one **USB Debugger**. Pick the one whose device is **GW5AST-138C**. If the device line is not that, try the other cable. Do not program a cable that does not see the FPGA.
5. Double-click the Operation line (or Edit → Configure Device).
6. Access Mode: **External Flash Mode**.
7. Operation: the one that programs a bitstream (`.fs`) and verifies it, at address **0x0**. On a Tang Console Programmer this is often named **exFlash Erase, Program thru GAO-Bridge Arora V**. A plain **exFlash Erase, Program, Verify** that takes the `.fs` is the same job if that is the name in your list.
8. Programming file: `Falcon030.fs`. Start address **0x0**.
9. Do **not** pick SRAM Program. That lasts until power-off. Do **not** pick a **C Bin** operation for this file. C Bin is the firmware step.
10. Program. Wait until it says program and verify succeeded.

## 2. Flash the firmware

Same cable. Same device, **GW5AST-138C**. Do not power-cycle between the two steps if you can help it. A power-cycle is fine if you have to. Do not run the bitstream erase again.

1. Device configuration, Access Mode: **External Flash Mode**.
2. Operation: **exFlash C Bin Program** if it is in the list. That writes the bin and does not erase the bitstream you just wrote. If the list only has **exFlash C Bin Erase, Program, Verify**, use that, but read the log in the next step before you walk away.
3. Programming file: `falcon_m28.bin`.
4. Start address: **0x0600000**. Copy it, including the leading 0. Do not leave 0x0. Do not type `0x6000000`.
5. Program.
6. Read the log. It must say programming **starts from 0x0600000** and ends near **0x0700000** (the file is about 1 MB). Not `0x700000`.
7. If the log says it starts at **0x0**, or at **0x6000000**, or that it is erasing the whole flash, **stop**. That write is not the firmware slot. Reflash `Falcon030.fs` at 0x0, then do this step again with **0x0600000**.

`falcon_m28.bin` is not TOS and not the bitstream. Address **0x0600000** only.

## Be patient on a cold start. A dark screen is normal then.

This wait is only a **cold switch-on**, or a reset that reloads the FPGA. The bitstream is large. The flash has to program the fabric before HDMI can do anything. That takes a few seconds, and the monitor can take longer to notice.

- **No instant picture is not a fault.** From power-on to monitor sync can take about **20 seconds**. Amber, or "no signal", in that window is normal. Do not pull power and try again yet.
- The first picture is **colour bars**. That means the fabric is up. It is looking at the card and loading TOS, floppies, and hardfiles. It is not a crash and it is not the desktop.
- TOS starts after that. Allow about **30 seconds** from power-on to a boot. A card with large hardfiles takes longer, because those files are opened during the wait.
- Wait. Then decide it failed.

A TOS reset does **not** do this. **Ctrl-Alt-Del** is a soft computer reset. **Ctrl-Alt-Shift-Del** is a hard computer reset. Neither reloads the FPGA. The monitor stays synced, and TOS reboots at a normal Atari speed. No colour bars. No unsync.

## 3. After both flashes

1. Unplug USB. Wait a few seconds. Plug it back in. HDMI can stay connected. Then wait. See above. Do not expect a picture in the first second. That wait is a cold start only.
2. A picture with **no card** can still appear, after that wait. That is an old EmuTOS 1.4 burned into the firmware, a fallback only. It is not the TOS to use. Some Falcon video modes misbehave on that copy.
3. For a real card, follow [../HOWTO.md](../HOWTO.md). Short version: FAT32 microSD, files in the root, `FALCON.CFG` with `LOG=0`. **`LOG=1` is the default.** The guest feels slow even if you have no serial cable plugged in. Put `LOG=0` in the cfg.
4. Solid green LED means the firmware is idle and the card is safe to eject. Dark or flickering means a card write is in flight. Do not pull power then.

Sound is not on HDMI. Speaker jumpers on the Console. F11 switches the YM and a 440 Hz tone so you can hear whether that header is alive.

## If it does not

- No device in Programmer: try the other USB Debugger entry, another cable, another USB port. The device line must read **GW5AST-138C**.
- Verify failed: flash that file again. Do not continue to the other file on a failed verify.
- Log starts at `0x6000000`: that is the wrong address. The box ate a missing leading 0. Reflash the bitstream at `0x0`, then the firmware at `0x0600000`.
- Still no sync after **30 seconds** from a cold switch-on, and no colour bars: power-cycle once and wait another 30 seconds. Then it is not something this folder will diagnose. No support.
- A TOS reset that unsyncs the monitor is not what Ctrl-Alt-Del or Ctrl-Alt-Shift-Del do. Those stay synced.
- This page will not be updated to chase your board. No support.
