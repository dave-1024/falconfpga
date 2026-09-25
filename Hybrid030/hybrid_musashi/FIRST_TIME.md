# First time: what to download and where to put it

You need a **Windows 10 or 11 PC**. You do not need to be a programmer.

**Do not install AndeSight. Do not install Gowin RDS / “AE350 RDS IDE.”** Those installers register USB and JTAG drivers and have broken ports on the machine that built this project. You only unpack two zip/txz files into folders. You never run their IDE.

## What you are collecting

| Piece | What it is | Where it comes from |
|---|---|---|
| **A. The compiler** | A folder containing `riscv32-elf-gcc.exe` and a folder containing `cygwin1.dll` | Andes “Development Kit” **toolchain archives**, not the IDE |
| **B. The board library** | Headers and `ae350-ddr.ld` | Gowin **RiscV_AE350_SOC V1.3 SDK zip only** |

## Make the folders first

In Explorer, create:

```
C:\Dev
C:\Dev\AndeSight_RDS_v511
C:\Dev\RiscV_AE350_SOC_V1.3
```

The name `AndeSight_RDS_v511` is only so the default script paths match David’s PC. You are **not** installing AndeSight into it. It is an empty box you fill with two unpacked folders.

## Download A — compiler, no installer

1. Open a browser and go to
   https://github.com/andestech/Andes-Development-Kit/releases
2. Open a **Windows** release (look for `release-windows` in the name). A recent one is fine.
3. Download **only** the archive whose name is
   `nds32le-elf-newlib-v5`
   (ends in `.txz` or `.zip`).
   Do **not** download AndeSight setup. Do **not** pick `mculib` unless `newlib-v5` is missing — this project was built with **newlib-v5**.
4. Unpack it. Windows may need 7-Zip for `.txz`.
5. Hunt in the unpacked tree until you find `riscv32-elf-gcc.exe`. Put that file’s folder here (create `toolchains\nds32le-elf-newlib-v5\bin` if needed):

   `C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin\riscv32-elf-gcc.exe`

6. Hunt for `cygwin1.dll`.
   - Often it sits in a `cygwin\bin` folder next to the toolchain, or inside the same Development Kit download as a separate Cygwin archive.
   - Copy that folder to:

   `C:\Dev\AndeSight_RDS_v511\cygwin\bin\cygwin1.dll`

   You want the `.dll` itself. Do not run Cygwin setup. Do not plug a board in while doing this.

If a Windows release has no `cygwin1.dll` at all, use another **Windows** Development Kit release on that same GitHub page until you find one that includes Cygwin files. Still do not run an IDE installer.

## Download B — Gowin library zip only

1. Open Gowin’s download library and sign in (free account):
   https://gowinsemi.com/en/document/main/database/
2. Find **Gowin RiscV AE350 SDK** / **RiscV_AE350_SOC_V1.3**.
   Download the **SDK zip**.
   Skip anything named **RDS**, **IDE**, or **AndeSight**.
3. Unzip so this file exists:

   `C:\Dev\RiscV_AE350_SOC_V1.3\library\bsp\sag\ae350-ddr.ld`

   Also expect `library\bsp\ae350` and `library\demo\stubs`.

   If the zip created an extra nested folder with the same name, move the inner folder up so the path above is exact.

## Point the project at those folders

In the hybrid source folder (next to `build_falcon_m28.bat`):

1. Copy `env.bat.example` and name the copy `env.bat`.
2. If you used `C:\Dev\...` exactly, save — the example already matches.
3. If not, edit only:

```
set FALCON_TC=C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin
set FALCON_CYGBIN=C:\Dev\AndeSight_RDS_v511\cygwin\bin
set FALCON_SDK=C:\Dev\RiscV_AE350_SOC_V1.3
```

`FALCON_TC` = folder that contains `riscv32-elf-gcc.exe`
`FALCON_CYGBIN` = folder that contains `cygwin1.dll`
`FALCON_SDK` = folder that contains `library\bsp`

Do not put `env.bat` on git.

## Build

Double-click `build_falcon_m28.bat`. First compile takes several minutes. Success is:

`output\falcon_m28.bin`

- “gcc not found” → compiler folder is wrong
- “cygwin1.dll not found” → Cygwin folder is wrong
- missing `ae350-ddr.ld` → SDK zip nested or not version 1.3

## Do not download

- AndeSight IDE (any version)
- Gowin **RiscV AE350 RDS IDE**
- Random “riscv gcc” from other websites
- Compiler source code / “build it yourself”

## Already have AndeSight installed?

Do not run it. You may **copy** `toolchains\nds32le-elf-newlib-v5` and `cygwin\bin` out of that install into `C:\Dev\...` and use those copies. Leave the IDE closed.

## Flash note

`falcon_m28.bin` is AE350 firmware at **0x600000**. It is not the FPGA bitstream and not TOS.
