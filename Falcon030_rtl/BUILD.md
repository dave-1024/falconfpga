# How to build and flash the Falcon core

This guide is for anyone who wants to build the Falcon core themselves. It tries to use plain words.
You only need to type the commands shown in the grey boxes.

> **Build with Gowin EDA V1.9.12.03 only.** In November 2026, a V1.9.12.04 build of the same source
> met its timing checks but gave a black screen with no HDMI picture, while a V1.9.12.03 build
> booted to the desktop. Settings, constraints and pins were identical. The same problem was also
> reported for the stock MiSTeryNano and NanoMig cores. Thanks to **Łukasz Jokiel** for finding
> this. Treat any other Gowin version as not supported. Use the V1.9.12.03 programmer too.

This is a personal workbench, not a finished product. David does not give support for it. See
"This is not a product" in the main [README](../README.md) before you buy anything.

Project overview: the top [README](../README.md). Technical status:
[README.md](README.md) in this folder.

---

## 1. What you need

### Hardware

1. A **Sipeed Tang Console** with the **138K** module (chip `GW5AST-LV138PG484AC1/I0`,
   **device version C**).
2. **One** Tang SDRAM module, plugged into slot **J9**. Do not flash the board with J9 empty.
3. A **USB cable** from your PC to the board (used for flashing and for the helper's text console).
4. A **microSD card** formatted FAT.
5. An **HDMI** screen, and a USB keyboard and mouse.

### Software

1. **Gowin EDA V1.9.12.03** (build 86714), Windows or Linux. Use exactly this version.
2. **Gowin Programmer** (`programmer_cli`), which comes with Gowin EDA.
3. **git**, to download the code.
4. Your own **TOS 4.04** image (512 KB). Atari TOS is not in this repository.
5. To build the **helper** firmware (only if you want a new helper image; the one already on
   the board works):
   - The **Andes AST v5.1.1** toolchain (`nds32le-elf-newlib-v5`), from GitHub
     `andestech/Andes-Development-Kit`, release `ast-v5_1_1-release-linux`.
     A normal RISC-V compiler will **not** do instead.
   - Gowin's **RiscV_AE350_SOC_V1.3** package (the "BSP", the helper's basic support files).

Where to download Gowin EDA V1.9.12.03 and RiscV_AE350_SOC_V1.3 is not written in this repository.

### Where to put the Andes toolchain and the AE350 SDK

The helper build scripts do not use the Andes IDE. They call the compiler from an unpacked
directory, and they find it with environment variables.

**On Linux**, the defaults are:

| Variable | Default | What should be there |
|---|---|---|
| `FALCON_TC` | `$HOME/andes/5_1_1/nds32le-elf-newlib-v5/bin` | `riscv32-elf-gcc` in that folder |
| `FALCON_SDK` | `$HOME/ae350sdk` | `library/bsp` inside that folder, including the linker script `library/bsp/sag/ae350-ddr.ld` |

Unpack the Andes AST v5.1.1 release so that `~/andes/5_1_1/` exists, and unpack the Gowin
RiscV_AE350_SOC_V1.3 zip so that `~/ae350sdk/library/bsp` exists. If you put them somewhere
else, set `FALCON_TC` and `FALCON_SDK` before you run the script.

**On Windows**, the defaults are:

| Variable | Default |
|---|---|
| `FALCON_TC` | `C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin` |
| `FALCON_SDK` | `C:\Dev\RiscV_AE350_SOC_V1.3` |
| `FALCON_CYGBIN` | `C:\Dev\AndeSight_RDS_v511\cygwin\bin` |

You can also put an `env.bat` next to `build_companion.bat` to set those variables.

---

## 2. Get the code

```
git clone -b falcon https://github.com/dave-1024/falconfpga.git
cd falconfpga
```

All the commands below start from this `falconfpga` folder unless it says otherwise.

---

## 3. Build the FPGA bitstream

This is the file that turns the board into a Falcon. From the repository root:

```
gw_sh Falcon030_rtl/build_falcon.tcl
```

On Linux, if you installed Gowin under `/opt/gowin`:

```
QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh Falcon030_rtl/build_falcon.tcl
```

Use Gowin V1.9.12.03 only. The build takes around 15 to 40 minutes. The output file is
`impl/pnr/falcon.fs` (in the folder you ran the command from). The script also checks that
the design meets its timing, including that the 68030 clock can run at 16 MHz. If that check
fails, do not flash the result.

---

## 4. Build the helper (optional)

The helper is a small program that already lives on the board. It looks after the SD card,
floppy images, USB keyboard and mouse, and the on-screen menu. You only need this step if
you want to build a new helper image yourself. The firmware already on the board is left
as it is until a planned helper cleanup starts.

**On Linux:**

```
bash Falcon030_rtl/helper/companion/build_companion.sh
```

**On Windows:**

```
Falcon030_rtl\helper\companion\build_companion.bat
```

The result is `Falcon030_rtl/helper/companion/output/helper_companion.bin`. The script prints
the size and a checksum. If it warns that the `.bootloader` section is missing, do not flash
the file.

These scripts are the same style as the retired ST core's helper build: they use the unpacked
Andes SDK and Gowin BSP, not the IDE. See section 1 for `FALCON_TC` and `FALCON_SDK`.

---

## 5. Flash the board

### Where things go in flash

| Address | What goes there |
|---|---|
| `0x000000` | the FPGA bitstream (`.fs`) |
| `0x600000` | the helper firmware (already on the board) |

TOS 4.04 does **not** go in flash. It goes on the SD card (next section). The old ST core used
a TOS slot at `0x500000`; the Falcon core does not need it.

### Safety rules

- **Never use "bulk erase".** It wipes everything on the flash chip.
- **Never reflash the BL616** (the board's own USB chip). This guide never needs it.
- Type the helper address carefully: `0x600000`, not `0x6000000`.
- If you flash a new helper, keep a copy of the `.bin` that is already on the board, so you
  can put it back.

### Order matters

Flash from a **fresh power-cycle**. Once the core has run, it can leave the flash chip in a
mode the programmer cannot talk to, and you may see "can't find SPI flash". If that happens,
power-cycle and try again. Never bulk-erase to "fix" it.

On Linux, run these from `/opt/gowin/Programmer/bin` as root (`sudo`), and type `./programmer_cli`.
On Windows use `programmer_cli.exe` from the Gowin Programmer folder.

1. **Power-cycle the board** (switch off and on).
2. **Find the board.** Do this every time, because the number changes:

   ```
   ./programmer_cli --scan-cables
   ```

   Note the "location" number it shows. Below, replace `LOC` with your number.

3. **Flash the helper** only if you built a new one and you mean to replace the one on the
   board. Skip this step if you are only updating the Falcon core.

   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 56 --mcuFile helper_companion.bin --spiaddr 0x600000
   ```

4. **Flash the bitstream** (takes a few minutes):

   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 53 --fsFile impl/pnr/falcon.fs
   ```

   It should end with "Program Flash finished". The end address it prints should stay below
   `0x500000`.

5. **Power-cycle the board** again so it starts cleanly from flash. Later, to reload the FPGA
   without a power-cycle:

   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 1
   ```

6. **Linux only:** the programmer can disconnect the helper's console port. Bring it back with:

   ```
   sudo modprobe ftdi_sio
   ```

---

## 6. Set up the SD card

Format the card as **FAT**. Put these files in the **root** of the card (not in a subfolder):

1. **`TOS404.IMG`** — your 512 KB TOS 4.04 image, with exactly that file name.
2. **`falcon.ini`** — a small text file that tells the helper to mount TOS. It must contain
   this line:

   ```
   drive4=/sd/TOS404.IMG
   ```

   The on-screen menu's default name alone is not enough: TOS is only mounted when this
   `drive4=` line is present.

   To start in RGB 50 Hz instead of VGA 60 Hz, you can also add:

   ```
   var V=1
   ```

   (`var V=0`, or no such line, is VGA.) Only write `falcon.ini` when you mean to. Do not use
   the on-screen "Save settings" item unless you intend to overwrite this file.

3. Optional **floppy images** (`.st` files). You can mount them from the on-screen menu
   (Disk A:) or from the helper console.

Do not put an `atarist.ini` here; that file belongs to the retired ST core. Do not delete or
overwrite other images already on the card.

---

## 7. First boot

1. Put the SD card in the board, connect HDMI, keyboard and mouse, and power on.
2. You should get a picture at 640x480, and after TOS has been copied from the card, the GEM
   desktop. The first boot can take a little while.
3. The on-screen menu can mount a floppy image and switch VGA 60 Hz / RGB 50 Hz (the change
   takes effect at the next reset).
4. The helper also has a text console on the USB serial port (Linux `/dev/ttyUSB1`, 115200
   8N1). Type `help` for the list of commands.

If the picture is missing after a flash, try a power-cycle, or reload with `--run 1`. If you
just flashed, a second reload sometimes brings HDMI up.

---

## If something goes wrong

- **Black screen, no HDMI sync, after a build with a Gowin version other than V1.9.12.03:**
  rebuild with V1.9.12.03.
- **"Can't find SPI flash":** power-cycle and try again. Never bulk-erase.
- **TOS never starts:** check that `TOS404.IMG` is in the root of the SD card and that
  `falcon.ini` contains `drive4=/sd/TOS404.IMG`.
- **Helper console has gone after a flash (Linux):** `sudo modprobe ftdi_sio`. The port
  number may change (for example ttyUSB0 instead of ttyUSB1).

More technical notes: [README.md](README.md), [docs/DESIGN.md](docs/DESIGN.md), and
[docs/FALCON_LESSONS.md](docs/FALCON_LESSONS.md).
