# Compile the hybrid RISC-V guest (Windows)

The guest is C, not Andesight. One batch file. Flash the `.bin` to **0x600000**.

Never installed the Andes/Gowin RISC-V kit before? Start with **FIRST_TIME.md** (downloads, folder names, what to click).

## Once per machine

1. Unpack Andes `nds32le-elf-newlib-v5` and its `cygwin\bin` (no IDE). See FIRST_TIME.md.
2. Unpack **RiscV_AE350_SOC_V1.3** SDK zip only. You need `library\bsp`.
3. Copy `env.bat.example` to `env.bat` in this folder.
4. Edit the three `FALCON_*` lines so they point at *your* copies.
5. Run:

```
build_falcon_m28.bat
```

Output: `output\falcon_m28.bin`.

If gcc or `cygwin1.dll` is missing, the bat stops and prints the path it tried. Fix `env.bat`, run it again.

## What you do not need

- AndeSight IDE
- Gowin (that builds the FPGA fabric, not this `.bin`)
- Linux / WSL (this gcc is a Windows+Cygwin binary)

## What you must not commit

`env.bat`, `output\`, `*.elf`, `*.bin`, `*.o`, TOS/EmuTOS ROM blobs if they were generated rather than source.

## Flags that are load-bearing

Leave `-O2` on **both** `CFLAGS` and `LDFLAGS`. gcc honours the last `-O` on the link line. `-DFALCON_NO_FPU` is the boot-timing label used on the proven image.
