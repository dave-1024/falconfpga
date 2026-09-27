# Binaries — flash and use

This folder is for someone who wants to **flash the hybrid and stop**. You do not need to compile anything. You do not need AndeSight.

Unzip `Binaries.zip`. It holds two files, built from the hybrid source in this repo, unmodified:

| File | What it is | Where it goes |
|---|---|---|
| `Falcon030.fs` | FPGA bitstream. About 37 MB (38,476,459 bytes). | External flash, address **0x0** |
| `falcon_m28.bin` | AE350 firmware. About 1 MB (1,021,320 bytes). | External flash, address **0x600000** |

Packed 27 September 2026. If the source in git moves later, this zip is this snapshot. It is not rebuilt for you.

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
4. Start address: **0x600000**. Type it. Do not leave 0x0.
5. Program.
6. Read the log. It must say programming **starts from 0x600000** and ends somewhere near **0x700000** (the file is about 1 MB). The TOS-style line on this bench looked like `Programming Flash starts from 0x0600000`.
7. If the log says it starts at **0x0**, or that it is erasing the whole flash, **stop**. That write is landing on the bitstream. Reflash `Falcon030.fs` at 0x0, then do this step again with the start address set.

`falcon_m28.bin` is not TOS and not the bitstream. Address **0x600000** only.

## 3. After both flashes

1. Unplug USB. Wait a few seconds. Plug it back in. HDMI can stay connected.
2. A picture with **no card** can still appear. That is an old EmuTOS 1.4 burned into the firmware, a fallback only. It is not the TOS to use. Some Falcon video modes misbehave on that copy.
3. For a real card, follow [../HOWTO.md](../HOWTO.md). Short version: FAT32 microSD, files in the root, `FALCON.CFG` with `LOG=0`. **`LOG=1` is the default.** The guest feels slow even if you have no serial cable plugged in. Put `LOG=0` in the cfg.
4. Solid green LED means the firmware is idle and the card is safe to eject. Dark or flickering means a card write is in flight. Do not pull power then.

Sound is not on HDMI. Speaker jumpers on the Console. F11 switches the YM and a 440 Hz tone so you can hear whether that header is alive.

## If it does not

- No device in Programmer: try the other USB Debugger entry, another cable, another USB port. The device line must read **GW5AST-138C**.
- Verify failed: flash that file again. Do not continue to the other file on a failed verify.
- Black screen after a good verify of both files: power-cycle. Then try the card in [../HOWTO.md](../HOWTO.md). A missing card should still fall back to the embedded EmuTOS. No picture at all is not something this folder will diagnose.
- This page will not be updated to chase your board. No support.
