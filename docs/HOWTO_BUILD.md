# How to build falconfpga, step by step

This guide is for anyone who wants to build this project themselves. It tries to use plain words.
You only need to type the commands shown in the grey boxes.

> **Please read first.** This is a personal workbench, not a finished product. David does not give support for
> it. See the "This is not a product" part of the main [README](../README.md) before you buy anything.

The detailed engineer's version of this guide is [Atarist_030_wip/docs/BUILD.md](../Atarist_030_wip/docs/BUILD.md).
If this guide and that one ever disagree, trust that one.

---

## A few words explained (once)

- **FPGA**: a chip that can be "rewired" by loading a file into it. Here it becomes an Atari.
- **Bitstream** (`.fs` file): the file that tells the FPGA how to wire itself. You build it from the source code.
- **Helper**: a small computer (called AE350) inside the same chip. It runs its own program ("firmware") and looks
  after the SD card, floppy images, USB keyboard/mouse and the on-screen menu.
- **TOS**: the Atari's operating system. It is **not** included; you supply your own copy.
- **Flash**: the memory on the board that keeps everything when the power is off. "Flashing" means writing to it.

---

## Part 1: What you need

### Hardware
1. A **Sipeed Tang Console** with the **138K** module (chip `GW5AST-LV138PG484AC1/I0`, **device version C**).
2. **One** Tang SDRAM module, plugged into slot **J9**. The design uses this one module only (ST-RAM and TT-RAM
   both live on it); you do not need a second module, and other slots stay empty. Do not flash the board with J9 empty.
3. A **USB cable** from your PC to the board (used for flashing and for the helper's text console).
4. A **microSD card** formatted FAT, with Atari floppy images (`.st` files) on it.
5. An **HDMI** screen, and a USB keyboard and mouse.

### Software
1. **Gowin EDA version V1.9.12.03**. Use exactly this version: other versions lay the design out differently and
   it may then fail. Works on Windows or Linux.
2. **Gowin Programmer** (`programmer_cli`), which comes with Gowin EDA.
3. For the helper firmware:
   - **Andes AST v5.1.1** toolchain (`nds32le-elf-newlib-v5`), from GitHub
     `andestech/Andes-Development-Kit`, release `ast-v5_1_1-release-linux`.
     A normal RISC-V compiler will **not** do instead.
   - Gowin's **RiscV_AE350_SOC_V1.3** package (it contains the "BSP", the helper's basic support files).
4. **git**, to download the code.
5. Your own **TOS image** (EmuTOS 256K or TOS 2.06, 256 KB), saved as a file ending in `.bin`.

**GAP for David:** where to download Gowin EDA V1.9.12.03 and RiscV_AE350_SOC_V1.3, and which licence is needed
(not written in the repo). Tip: if the build stops on a licence check, simply run it again; it usually works the
second time.

---

## Part 2: Get the code

1. Open a terminal (Linux) or Command Prompt (Windows).
2. Type:
   ```
   git clone https://github.com/dave-1024/falconfpga.git
   cd falconfpga
   ```
3. All the commands below start from this `falconfpga` folder unless it says otherwise.

The TT-RAM work (16 MB of fast RAM for the 68030, with the caches working) is on branch `tt-ram` until it is merged.
To use it before then: `git checkout tt-ram`. TT-RAM is built in by default: there is no build switch and nothing to
turn on (the build script sets `TTRAM`). The 68030 I and D caches are also built in by default. An on/off option
for TT-RAM will be added to the helper later.

Note: the release build tt20 was made with `debug_builds/build_st_helper_hdn.tcl`, which is the same as `build_st_helper.tcl`
except `place_option 3` (instead of 1) and the extra `SD_WRITE_DEBUG` line. **GAP for David:** which of the two
scripts this guide should tell builders to use.

---

## Part 3: Build the FPGA bitstream

1. Go into the main project folder:
   ```
   cd Atarist_030_wip
   ```
2. Start the build.
   - **Windows:**
     ```
     C:\Dev\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe build_st_helper.tcl
     ```
     (Change the path if you installed Gowin somewhere else.)
   - **Linux:**
     ```
     QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper.tcl
     ```
3. Wait. It takes about **25 to 40 minutes**.
4. When it finishes, your bitstream is here:
   `Atarist_030_wip/impl/pnr/st_helper.fs`
5. **Check that it passed the speed test** ("timing"). Open this file in a web browser:
   `Atarist_030_wip/impl/pnr/st_helper_tr_content.html`
   - In the **TNS** table, every number must be **0** (both "setup" and "hold").
     **GAP for David:** the current TT-RAM release build (tt20) does *not* meet this (worst slack -4.89 ns) yet works
     on the board at clk_cpu030 22.42 MHz (rule: at least 17 MHz). Which pass rule a builder should use is for David to
     decide.
   - In the **Recovery/Removal** tables, every number must be **positive**.
   - Ignore the "violated endpoints" count at the top.
6. If the check fails, do **not** flash it. Open `build_st_helper.tcl` in a text editor, change
   `place_option 1` to `place_option 3` (or back), save, and build again.
7. Copy the `.fs` file somewhere safe and give it a name you will recognise, for example with the date.
   Always keep the last one that worked.

---

## Part 4: Build the helper firmware

### On Linux
1. Unpack the Andes toolchain so that this folder exists: `~/andes/5_1_1/nds32le-elf-newlib-v5/bin`
   (or tell the script where it is: `export FALCON_TC=/your/path/bin`).
2. Unpack RiscV_AE350_SOC_V1.3 so that this folder exists: `~/ae350sdk/library/bsp`
   (or `export FALCON_SDK=/your/path`).
3. From the `falconfpga` folder, run:
   ```
   bash Atarist_030_wip/helper_fw/companion/build_companion.sh
   ```
4. The result is `Atarist_030_wip/helper_fw/companion/output/helper_companion.bin`.
5. If the script prints **"WARNING: no .bootloader section. Do not flash."**, stop: do not flash that file.

### On Windows
1. Run `Atarist_030_wip\helper_fw\companion\build_companion.bat`. It makes the same file.

**GAP for David:** the Windows toolchain/BSP paths the `.bat` expects are not described in the guide docs.

---

## Part 5: Prepare TOS

1. Get a 256 KB TOS image you are allowed to use. **EmuTOS 256K** is the one used for current work;
   TOS 2.06 also boots.
2. Make sure the file name ends in **`.bin`** (the programmer will not accept it otherwise). Rename it if needed,
   for example `emutos256k.bin`.

**GAP for David:** which exact EmuTOS 256K release/file to download (not recorded in the repo).

---

## Part 6: Flash the board

### The three places in the flash memory (important)
| Where | What goes there |
|---|---|
| `0x000000` | the bitstream (`.fs`) |
| `0x500000` | TOS |
| `0x600000` | helper firmware |

### Safety rules: please follow these
- **Never use "bulk erase".** It wipes everything.
- **Never reflash the BL616** (the board's own USB chip). This guide never needs it.
- Only write TOS (`0x500000`) or the helper (`0x600000`) when you mean to.
- Type the addresses carefully: `0x600000`, not `0x6000000`.

On Linux, run these from `/opt/gowin/Programmer/bin` as root (`sudo`), and type `./programmer_cli`. On Windows use
`programmer_cli.exe` from the Gowin Programmer folder.

1. **Find the board.** Do this every time, because the number changes:
   ```
   ./programmer_cli --scan-cables
   ```
   Note the "location" number it shows. Below we write `LOC`: replace it with your number. On David's board it is currently **4369** (older notes say 417;
   that number is out of date: it changes after reboots and replugs).
2. **Flash the bitstream** (takes a few minutes, allow up to 5):
   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 53 --fsFile st_helper.fs
   ```
   It should end with "Program Flash finished". The end address it prints must be below `0x500000`.
3. **Flash TOS** (only the first time, or when changing TOS):
   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 56 --mcuFile emutos256k.bin --spiaddr 0x500000
   ```
4. **Flash the helper** (only the first time, or when the helper changes):
   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 56 --mcuFile helper_companion.bin --spiaddr 0x600000
   ```
5. **Restart the FPGA from flash:**
   ```
   ./programmer_cli -d GW5AST-138C --location LOC --run 1
   ```
6. **Linux only:** the programmer disconnects the helper's console port. Bring it back with:
   ```
   sudo modprobe ftdi_sio
   ```

---

## Part 7: First boot check

1. Put the SD card in. Connect HDMI, keyboard and mouse.
2. Open the helper console: a serial terminal on the board's USB port (Linux usually `/dev/ttyUSB1`),
   speed **115200**, settings **8N1**. For example:
   ```
   screen /dev/ttyUSB1 115200
   ```
3. Type `c` and press Enter. This restarts the Atari side with the stronger of the helper's two resets (`w` is the
   lighter one). It is **not** the same as switching the power off and on. **GAP for David:** exactly what `c`
   clears that `w` does not (the code just sends reset code 3 instead of 1).
4. You should see the memory test and then the **GEM desktop** on the HDMI screen.
5. To load a floppy image, type `mount a yourgame.st` in the console, or press **F12** for the on-screen menu.

Handy console commands: `c` full reset of the Atari side, `w` warm reset, `ls` list SD card, `mount a <file>`, `eject`, `save`.

---

## Part 8: Common problems

| Problem | What to try |
|---|---|
| No picture on HDMI after flashing | Reload the FPGA (step 5 of Part 6) again. It can take **about 3 reloads** before HDMI comes up. |
| Helper console does not answer after flashing | Run the reload (`--run 1`) once more; on Linux also `sudo modprobe ftdi_sio`. |
| Stops at "System halted!" | Type `c` in the helper console. If it still halts, switch the board off and on. |
| Programmer cannot find the board | Run `--scan-cables` again and use the new location number. |
| Programmer refuses the TOS file | The file name must end in `.bin`. |
| Build fails the timing check | Switch `place_option` between 1 and 3 (Part 3, step 6). Do not change the timing rules. |
| A program crashes in strange ways | Check the floppy image is not damaged (`crc <file>` in the console). A bad image once looked like a CPU bug for days. |
| Helper build warns "no .bootloader section" | Do not flash it. Check the toolchain and BSP paths (Part 4). |

---

## Gaps for David (not confirmable from the repo)
- Download locations and licence for Gowin EDA V1.9.12.03 and RiscV_AE350_SOC_V1.3.
- Windows paths for the helper `.bat` build.
- Which EmuTOS 256K file to use.
- The timing pass rule for builds with negative slack (see Part 3).
- What `c` resets compared with a power cycle.
- The fix for HDMI needing several reloads.
