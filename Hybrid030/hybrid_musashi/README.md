# hybrid_musashi

Frozen archive of the **C guest** that ran on the AE350: Musashi 68030 + Falcon glue (`falcon_m28.c` and friends).

This is **not** the destination CPU. Do not treat a successful `.bin` as a substitute for `rigsdram/`.

`build_falcon_m28.bat` is portable: copy `env.bat.example` to `env.bat` and set three paths. It compiles `emutos_rom.c` from this folder. It does **not** read `emutos.map`, `etos512uk.img`, `falcon_diskA.c`, or `falcon_idex.c` — those were dropped.

## TOS and the SD card

Any TOS image can be loaded from an **SD card** if the user supplies it. See **[HOWTO.md](HOWTO.md)**.

EmuTOS 1.4 ships as `emutos_rom.c` (GPL-2, https://github.com/emutos/emutos tag `VERSION_1_4`, licence in `LICENSE.TXT` in this folder). Atari TOS is not in git.

## Compile

1. [FIRST_TIME.md](FIRST_TIME.md) — unpack toolchains, **do not install AndeSight**.
2. Copy `env.bat.example` to `env.bat`.
3. [COMPILE.md](COMPILE.md) — run `build_falcon_m28.bat`.
4. Flash `output\falcon_m28.bin` to **0x600000**.

`env.bat` and `output/` stay off git.
