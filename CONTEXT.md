# CONTEXT

Engineering handoff for a new chat. Not a product page. The public description is `README.md`. This file is the blunt state.

Read this when the chat has no history. Update it when a durable fact changes (silicon result, locked decision, do-not). Do not use it as a build request. Builds go through `BUILD_REQUEST.md`.

Last updated: 2026-09-26.

## Who does what

- David owns the board, the flashes, and what counts as known-good.
- Grok chat writes HDL, docs, and `BUILD_REQUEST.md`.
- Grok bot compiles when a request says so, and writes `BUILD_REPORT.md`. Bot does not invent HDL and does not edit this file.
- User has little HDL experience. Chat owns HDL guidance and review.

## Hardware

- Sipeed Tang Console + GW5AST-138 SOM.
- Device `GW5AST-LV138PG484AC1/I0`, **Version C**. Gowin **V1.9.12**.
- Windows IDE on David's machine. A Linux box runs `gw_sh` only.
- C builds use Windows bats + `riscv32-elf-gcc`. **Do not install AndeSight.** It broke USB drivers.

**SDRAM module** means the plug-in in **J9**, not the DDR3 on the SOM.

- `Hybrid030/` does **not** need the module. RAM is SOM DDR3 via the AE350.
- Every HDL build from here **does**: `misterynano_tc138k/`, `rigsdram/`, the 030 splice, later Falcon HDL. Do not flash those with J9 empty.

Hybrid audio is the Console **speaker header**, not HDMI. Nano is a different audio path. Do not mix the two how-tos.

## Trees (do not merge them)

| Path | What it is | Now |
|---|---|---|
| `Hybrid030/` | Frozen scaffold. Musashi C on AE350 + REV11b fabric. | History. Not a live Gowin target. No SDRAM module. |
| `rigsdram/` | Re-engineered wf68k30L + SDRAM guest tests. | Known-good silicon. Destination CPU lives here. |
| `misterynano_tc138k/` | Stock MiSTeryNano, fx68k, Console 138K only. | Built. Not yet a proven desktop. |

Do not splice the 030 into `misterynano_tc138k/`. Freeze a working Nano, then clone.

## Current rung

1. Prove stock MiSTeryNano: repeated cold boots to a GEM desktop.
2. Freeze that tree. Clone it.
3. Splice wf68k30L using TF534 arbitration. Not a drop-in of fx68k. 030 bus is `SIZ` / `DSACKn` / `FC`.
4. First splice: **8 MHz CPU**, stock ST chipset. Caches off. PMMU off.
5. Then **16 MHz CPU**, chipset still stock ST speed.
6. Only after that desktop: Falcon glue.

`rigsdram/` stays alive the whole way. If the ST desktop dies, that is the isolated 030+SDRAM check.

**2026-09-26:** David's IDE build of `misterynano_tc138k` succeeded after the options below. Not flashed. TOS in SPI flash and a cold-boot count are still ahead. Companion firmware is not in this repo.

## Known-good and parked

`rigsdram` last treated-as-good silicon, cold and warm:

```
12345
RIGSDRAM GUEST
IMG=74D8E373
T0–T11 PASS
DONE P
```

`12345` is healthy. `112345` only means the AUTO_WARM broker pulse fired late. That guest is the embedded T0–T11 image, not a shorter test uploaded the same day.

Parked, not fixed: false Line-F (vector 11) at `$406`, opcode `247C`, `SR_CPY=$0000` despite FC=6 fetches. One-cycle DELTA at `$406` (`000C` cold vs `000B` warm) is the only pre-fault divergence. A7 exonerated. Next instrument is a pipe trace of `IPIPE.D` / `OW_REQ` / `OP_I` / `TRAP_CODE_I`, not another reset patch. AUTO_WARM is a board workaround, not a core fix. David does not want the double-reset as the product.

PnR: **Replicate Resources = TRUE**. Do not flip it to compare old reports. Judge by Fmax. CPU target for the ST splice is **16 MHz**. In-tree comment still records synthesis Fmax about **22 MHz**. 32 MHz is realistically possible later (critical-path work, not a placer flag) and is **not** the next goal.

## Locked rules

- Silicon first. A passing Gowin log is not a passing board.
- One golden guest at a time.
- Destination CPU is **wf68k30L** in `rigsdram/`, not a Musashi rewrite, not fx68k.
- Stock wf68k30L was heavily re-engineered and instruction-audited against a real 030: Amiga A1200 + **ACA1230-55N**. Do not drop upstream wf68k30L back on this tree.
- Unmapped Falcon IO must BERR or TOS sees phantom chips.
- PMMU is fabric + RISC-V walk, not inside the core. Starts when MiNT is next. First task then is a PTEST source audit. Init all-pass. FC=7 and TT0/TT1 always pass.
- Git is source only. No `*.fs`, `impl/`, TOS images, disk images.
- Public repo is follow-only. David does not provide support. This is not a product.

AE350 / DDR3 / AHB errata, still in force on any RISC-V fabric path:

1. DDR3 shared write lane 4 is dead. Never use it.
2. 64-bit DDR3 read upper half is dead. 32-bit lanes only.
3. Extended AHB HWDATA upper 32 is dead. 32-bit HSIZE at 8-byte align, payload at +0/+8 only.

`WBINVAL_ALL` at 60 Hz kills bandwidth. Use a CCTL range flush.

## Clocks, and the parked TT

ST plan stays 8 then 16. Chipset stays stock ST speed, like a real accelerator.

A **TT030** is a possible later third machine, not an open workstream. A real TT is a 32 MHz 030, TT shifter, SCSI, ST-RAM / TT-RAM split, TOS 3. The 32 MHz clock is plausible on this SOM after path work. The chipset is the bulk of that project, and it is not the Falcon and not MiSTeryNano. Do not open it while the ST desktop is unproven.

## Nano IDE traps (2026-09-26)

`build_tc138k.tcl` sets these. The `.gprj` does not. If the IDE build fails, check these before editing source:

- Synthesize: **SystemVerilog 2017**. Verilog-2001 rejects `logic` / `.name` ports.
- Top module is exactly `top` (`tang/console138k/top.sv`). A wrong top produces a wall of `CT1135` "can't find object". `jt49_dcrm2` is the YM filter, not the design.
- Dual-purpose pins **on**: JTAG, DONE, READY, MSPI, SSPI, CPU.
- Dual-purpose pins **off**: MODE, I2C.
- Device version **C**.

Ignore upstream warnings: `old_flg`, `fdc1772` always-loop, `rtc_index`.

Nano TOS is **SPI flash via Companion**, not `FALCON.CFG`. A hybrid SD card will not boot this bitstream. TOS offset: HDL map is the `0x500000` family if `flash_dspi.v` stays; some docs say `0x900000`. Measure `.fs` size. Do not guess.

## Hybrid contract (frozen, still the SD how-to)

Card is FAT32 in the TF slot. `FALCON.CFG` in the root. Firmware never writes the FAT. Solid green LED means safe to eject.

- `LOG=1` is the default and makes the guest feel slow even with no serial cable. Desktop cards want `LOG=0`.
- `DISKB=` works on EmuTOS, not TOS 4.04. A Falcon has no second floppy.
- Embedded EmuTOS is an older 1.4, SD-fail fallback only. Use a current 512K 1.4 from the card.
- `HD0NAME=` is the IDE IDENTIFY model string, not the filename. Legacy tools (HDDRIVER, AHDI/HDX) care.
- Host keys: **F10** 50/60 Hz, **F11** PSG vs 440 Hz tone, **F12** log, **Print Screen** joystick 1 (arrows or numpad 8/2/4/6, fire Space or numpad 0).

Any TOS the user supplies can be loaded from SD. Atari TOS is not in git.

## Where to look

| File | Use |
|---|---|
| `README.md` | Public description, credits, disclaimer |
| `Hybrid030/HOWTO.md` | Hybrid SD card |
| `AGENT_PROTOCOL.md` | Chat / bot handshake |
| `BUILD_REQUEST.md` / `BUILD_REPORT.md` | Current compile cycle |
| `NOTICE.md` | Upstream licenses |
