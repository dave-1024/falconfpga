# CONTEXT

Engineering handoff. Not a product page. Not a build request.

A new chat says: **read CONTEXT.md and continue.** Update this file when a bug, a test, a pinned idea, or the work state changes. Bump `HANDOFF` when you do. The bot re-reads this every poll and echoes `HANDOFF_SEEN`. A new id means the chat changed or the state file moved. It does not mean build.

```
HANDOFF: 2026-09-26-2
UPDATED: 2026-09-26
```

## Current work

Prove stock MiSTeryNano on David's Tang Console. Nothing else is open.

- IDE build of `misterynano_tc138k` succeeded 2026-09-26, after SystemVerilog 2017, top module `top`, and the dual-purpose pin list below.
- Not flashed. Not a desktop yet.
- `Hybrid030/` is frozen history. Do not reopen it as the live target.
- `rigsdram/` is the known-good 030 oracle. Leave it alone unless the Nano test dies and we need the isolated core.
- Public repo, follow-only. No support. Source only.

## Testing in flight

**Nano bring-up. Not started on silicon.** Next bench session, not a compile:

1. SDRAM module fitted in **J9**. This bitstream will not run with the socket empty.
2. Flash the local IDE bitstream. Bot's last matching build was `atarist_tc138k.fs`, 36538618 bytes, not flashed.
3. Companion / BL616 already on the board if the last partner flash is still there. Companion is not in this repo. OSD, keyboard, and TOS load need it.
4. TOS goes in **SPI flash**, not on a hybrid `FALCON.CFG` card. A hybrid SD card will not boot this bitstream.
5. TOS offset is still a measurement, not a number. HDL map is the `0x500000` family if `flash_dspi.v` stays. Some docs say `0x900000`. Measure `.fs` size before flashing TOS.
6. Acceptance is **repeated cold boots to a GEM desktop**, not one boot. Stock `top.sv` already ties reset/user to 0 "to fix tc138k booting". Cold boot on this SOM is an open item.

No other test is in flight. Do not start the 030 splice, a Line-F pipe trace, or a TT while this is open.

## Unresolved bugs

Found, not fixed. Do not rediscover them. Do not patch them sideways into the Nano test.

**1. wf68k30L cold boot. Core-level. Still open.**

Last accepted silicon boots only with the AUTO_WARM broker pulse (`rigsdram`, `IMG=74D8E373`, UART `12345`, T0–T11 PASS). `112345` means that pulse fired late. A later patch was flashed and did **not** remove the need for a soft reset: cold power-on produced nothing. The flip-flop chase after that was not confirmed on the board. Older F42–F45 simulations did not retire this on silicon. AUTO_WARM is a board workaround. David does not want it as the product.

**2. False Line-F at `$406`. Parked. Next instrument is a pipe trace.**

Vector 11 on opcode `247C` (not an `Fxxx` pattern). Warm executes the same word and continues. `SR_CPY=$0000` in the stacked frame despite FC=6 fetches. Only pre-fault divergence is one cycle of DELTA at `$406` (`000C` cold vs `000B` warm). A7 is exonerated. Do not patch another initialiser. Capture `IPIPE.D`, `OW_REQ`, `OP_I`, `TRAP_CODE_I` on cold silicon.

This fault travels with the core. Nano's top may cold-boot fx68k and still not save us once wf68k30L is spliced in. Acceptance for that splice is repeated cold boots, not one warm desktop. Fix it with a pipe trace before Falcon depends on it.

**3. Nano TOS offset. Unresolved on purpose.**

See the in-flight test. Do not guess `0x500000` vs `0x900000`.

**Locked, not open — do not re-investigate:**

- DDR3 shared write lane 4 dead. Never use.
- 64-bit DDR3 read upper half dead. 32-bit lanes only.
- Extended AHB HWDATA upper 32 dead. 32-bit HSIZE, payload at +0/+8 only.
- `WBINVAL_ALL` at 60 Hz kills bandwidth. CCTL range flush only.
- Unmapped Falcon IO must BERR or TOS sees phantom chips.

## Pinned ideas

Not work. Do not open them.

- **030 splice,** after Nano is a proven desktop. Freeze that tree, clone it, then splice wf68k30L with TF534 arbitration. Not a drop-in of fx68k. Bus is `SIZ` / `DSACKn` / `FC`. First clock **8 MHz**, chipset stock. Then **16 MHz** CPU, chipset still stock ST speed. Caches off. PMMU off.
- **32 MHz core Fmax.** Realistically possible on this SOM later. Not free, not the ST goal. Critical-path work, not a placer flag. In-tree comment is still about 22 MHz. Replicate Resources stays TRUE.
- **TT030.** Later third machine. Real TT is a 32 MHz 030, TT shifter, SCSI, ST-RAM / TT-RAM split, TOS 3. Clock is the easy part. Chipset is the project. Not Falcon, not MiSTeryNano.
- **PMMU.** Fabric flat protection plus a RISC-V walk, not inside the core. Starts when MiNT is next. First task is a PTEST source audit.
- **Falcon HDL** only after the ST desktop has validated this 030.

## Who does what

- David owns the board, the flashes, and what counts as known-good.
- Grok chat writes HDL, docs, this file, and `BUILD_REQUEST.md`.
- Grok bot compiles when a request says so, and writes `BUILD_REPORT.md`. Bot does not invent HDL and does not edit this file.
- David has little HDL experience. Chat owns HDL guidance and review.

## Hardware

- Sipeed Tang Console + GW5AST-138 SOM. Device `GW5AST-LV138PG484AC1/I0`, **Version C**. Gowin **V1.9.12**.
- Windows IDE on David's machine. A Linux box runs `gw_sh` only.
- C builds use Windows bats + `riscv32-elf-gcc`. **Do not install AndeSight.**

**SDRAM module** means the plug-in in **J9**, not the DDR3 on the SOM.

- `Hybrid030/` does **not** need it. RAM is SOM DDR3 via the AE350.
- Every HDL build from here **does**. Do not flash those with J9 empty.

Hybrid audio is the Console **speaker header**, not HDMI. Do not mix that with the Nano audio path.

## Trees

| Path | What it is | Now |
|---|---|---|
| `Hybrid030/` | Frozen scaffold. Musashi on AE350 + REV11b fabric. | History. No SDRAM module. |
| `rigsdram/` | Re-engineered, instruction-audited wf68k30L + SDRAM guest. | Known-good oracle. Needs J9. |
| `misterynano_tc138k/` | Stock MiSTeryNano, fx68k, Console 138K only. | Built, not proven. Needs J9. |

Do not splice the 030 into `misterynano_tc138k/`.

Known-good `rigsdram` silicon:

```
12345
RIGSDRAM GUEST
IMG=74D8E373
T0–T11 PASS
DONE P
```

That guest is the embedded T0–T11 image, not a shorter test uploaded the same day. CPU was audited against an Amiga A1200 + ACA1230-55N. Do not drop upstream wf68k30L back on this tree.

## Locked rules

- Silicon first. A passing Gowin log is not a passing board.
- One golden guest at a time.
- Destination CPU is wf68k30L in `rigsdram/`, not a Musashi rewrite, not fx68k.
- PnR: **Replicate Resources = TRUE**. Do not flip it to compare old reports. Judge by Fmax.
- Git is source only. No `*.fs`, `impl/`, TOS images, disk images.
- Public repo is follow-only. This is not a product. No support.

## Nano IDE traps

`build_tc138k.tcl` sets these. The `.gprj` does not. Check these before editing source:

- Synthesize: **SystemVerilog 2017**.
- Top module is exactly `top`. A wrong top is a wall of `CT1135`. `jt49_dcrm2` is the YM filter.
- Dual-purpose **on**: JTAG, DONE, READY, MSPI, SSPI, CPU.
- Dual-purpose **off**: MODE, I2C.
- Device version **C**.
- Ignore: `old_flg`, `fdc1772` always-loop, `rtc_index`.

## Hybrid contract

FAT32 in the TF slot. `FALCON.CFG` in the root. Firmware never writes the FAT. Solid green LED means safe to eject. Any user-supplied TOS. Atari TOS is not in git.

- `LOG=1` is the default and makes the guest feel slow with no serial cable. Desktop cards want `LOG=0`.
- `DISKB=` works on EmuTOS, not TOS 4.04.
- Embedded EmuTOS is an older 1.4, SD-fail fallback only. Use a current 512K 1.4 from the card.
- `HD0NAME=` is the IDE IDENTIFY model, not the filename.
- Host keys: **F10** 50/60, **F11** PSG vs 440 Hz tone, **F12** log, **Print Screen** joystick 1.

Details: `Hybrid030/HOWTO.md`.

## Where to look

| File | Use |
|---|---|
| `README.md` | Public description |
| `Hybrid030/HOWTO.md` | Hybrid SD card |
| `AGENT_PROTOCOL.md` | Chat / bot handshake |
| `BUILD_REQUEST.md` / `BUILD_REPORT.md` | Current compile cycle |
| `NOTICE.md` | Upstream licenses |
