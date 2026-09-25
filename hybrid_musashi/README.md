# hybrid_musashi

Frozen archive of the **C guest** that ran on the AE350: Musashi 68030 + Falcon glue (`falcon_m28.c` and friends).

Source and `build_falcon_m28.bat` are not in this folder yet. They arrive with David’s final tree. The compile notes below are ready now.

This is **not** the destination CPU. Do not treat a successful `.bin` as a substitute for `rigsdram/`.

## TOS

Any TOS image can be loaded from an **SD card** if the user supplies it. That is how the hybrid was designed. This repo may include an **EmuTOS 1.4** C array (GPL-2, source: https://github.com/emutos/emutos tag `VERSION_1_4`). It does **not** ship Atari TOS. Put TOS 4.04 (or any other TOS you own) on the card yourself.

## Compile (when the bats are here)

1. First machine: [FIRST_TIME.md](FIRST_TIME.md) — unpack toolchains, **do not install AndeSight**.
2. Copy `env.bat.example` to `env.bat` and set three paths if you did not use `C:\Dev\...`.
3. [COMPILE.md](COMPILE.md) — run `build_falcon_m28.bat`.
4. Flash `output\falcon_m28.bin` to **0x600000**.

`env.bat` and `output/` stay off git.
