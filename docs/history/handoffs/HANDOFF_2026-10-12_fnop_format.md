# HANDOFF 2026-10-12: F65 done, FNOP frame fault open (for Grok Bot)

> **Superseded (moved here 23 Oct 2026).** Dated handover, kept as a record; flashing details (laptop, cable 417, "never write 0x600000") are out of date. Current state: [`handoff/CONTEXT.md`](../../../handoff/CONTEXT.md).

This file is self-contained. Grok Bot has the repo and the board. David is new
to Git. Paths are relative to the repo root unless they start with `C:\`.

## What this session did

Two things. The first is finished and on `main`. The second is open and is the
reason for this handback.

### 1. F65, the prefetch handoff (DONE, on main)

The URGENT item in `Atarist_030_wip/docs/TODO.md`. The next prefetch starts
straight after S5 when one is pending, the way a real 68030 does, with no idle
states between prefetch transfers.

- Branch `f65-handoff`, merged to `main` as `bb9baa2`.
- Switch `WF030_FAST_HANDOFF`, default on. `BRIDGE_EARLY_AS` stays independent
  and is also on. Both are in `Atarist_030_wip/build_st_helper.tcl`.
- Prefetch-to-prefetch only. Operand cycles still go through IDLE. HALT, BG,
  retry, BERR, queue miss, flush and RMC still take IDLE.
- The chain arms only when the queue is empty at S3 (`Q_CNT = 0`), so a long
  word already on the bus cannot overflow the 4-word queue. An earlier arm at
  `Q_CNT <= 2` overflowed to 6. That was the review failure; it is fixed.
- `PF_CHAIN_GO` is registered. No combinational loop through `BUS_BSY`.
- Simulation passed: `run_rtl.sh` and the whole-ST bench, prefetch on and off.
- Timing clean. Board boots. GEMBENCH 4.03 ran to completion on TOS 2.06.

Kept, as required: the F62/F62b/F62d prefetch fixes, the JSR SP writeback fix,
the CHK fix. No compatibility hacks. Contributor credits kept.

### 2. GEMBENCH, and the FNOP fault (OPEN)

GEMBENCH 4.03 (not 6.32; the title shows no version, the disk is `gb403.st`)
ran with both switches on. Two things came out of it.

**The blitter.** Under TOS 2.06 the blitter checkbox works and the numbers
move. Under EmuTOS 256K it is greyed out. The HDL path was inspected and is
correct: FC=101, `$FF8A00`-`$FF8A3F`, combinational DTACK. Not chased further.

**Float Math.** The timer reads 65.535 s, which is a saturated counter. Under
TOS 2.06 three bombs appeared as the test changed from float math to RAM
access, and the suite continued. Under EmuTOS it panics and does not continue.

The float test is `AUTOFPU.BIN`, a Lattice C program. It probes for a 68882 by
installing a handler on vector 11 and executing `FNOP` (`$F280 $0000`). The
handler does `MOVE.L A2,2(SP)` and `RTE` to skip the FPU opcodes and take the
software path. The flag at `A4+$1DC` selects the path. The IEEE 1.0 constant
`$3FF00000` appears in the panic dump.

## What the investigation found

### The CPU core is right, in simulation

GHDL, the RTL bench `Atarist_030_wip/hdl/cpu030/sim/rtl/tb030.vhd`.

- A bare `FNOP` takes a format 0 Line-F, vector 11, vector offset `$2C`,
  stacked PC equal to the `FNOP`. No bus error, no CPU-space cycle.
- The real probe sequence does too: `PEA`, `MOVE.L #$5000B,-(SP)`,
  `ORI.W #$700,SR`, `TRAP #13`, the `(SP)` writes, `LEA`, `FNOP`, and the
  handler's `MOVE.L A2,2(SP); RTE`. It returns to the skip address.
- The decoder maps every `$Fxxx` to `UNIMPLEMENTED` to `T_1111`. The exception
  handler builds a 4-word format 0 frame for `EX_1111`. `RTE` reads the PC
  from offset 2.

So the core, on its own, does what `AUTOFPU.BIN` is written for.

### The board does not

Three probes were written and run from the desktop. They are TOS programs,
built by hand because the m68k assembler on the chat machine needs a newer
glibc. The last one is `fnop.prg` (David renamed copies `fnop2.prg`,
`fnop3.prg`).

- The first probe froze after the title. It was stuck inside `Supexec`.
- The second printed a row of `F`s and looped. `FNOP` took Line-F, but the
  handler's `TRAP #1` (the print) destroyed `A2`, so the `RTE` came back to
  the `FNOP`. That loop was the probe, not the core.
- The third saved `A2` and still looped. The `RTE` ignored the patched PC.
- The fourth printed the format nibble, then the handler letter. It printed
  `xB` and then EmuTOS panicked: exception 14, format error, at `$00013556`,
  SR `$2300`.

Exception 14 is the format error. `RTE` reads the nibble at offset 6 and
accepts only `0`, `1`, `2`, `9`, `A` and `B`. The `B` is the bus error
handler, so on that run `FNOP` took vector 2, not Line-F, and the format word
stacked for it was not `A` or `B`. The `RTE` faulted on the format before it
read the PC. That is why patching offset 2 never lands.

### Where the format word is built

`Atarist_030_wip/hdl/cpu030/wf68k30L_top.vhd`, the `DATA_EXH` multiplexer:

```
SR_CPY & PC(31 downto 16) when STACK_POS = 2 else
PC(15 downto 0) & STACK_FORMAT & "00" & IVECT_OFFS when STACK_POS = 4 else
```

`STACK_FORMAT` is set in `wf68k30L_exception_handler.vhd`, `STACK_CTRL`. A
Line-F sets it to `0`. A bus error sets it to `A` or `B`. The selection is
correct. The board stacked neither. The fault is that `STACK_FORMAT` is not
one of those values when the write at `STACK_POS = 4` happens, or the write
does not land. Not yet found. Do not guess a fix. Forcing a format here would
touch the bus error and address error frames, which use the same write.

## Other faults, already logged

- **Helper SD write timeout.** `sd_card.v` sticks in state 13 and only a core
  reload clears it, so the next floppy read fails. This is the read error
  after a write. TOS error #35 (GEMDOS -35) on launching GEMBENCH is the same
  family: runtime mount, or a mount after a write. It does not happen when the
  image is mounted from `atarist.ini` on an FPGA power cycle. Logged in
  `b5a7f96` and in `TODO.md` item 6. Not a CPU bug.
- **Blitter greyed out under EmuTOS 256K.** Works under TOS 2.06. HDL path
  inspected and correct. Not chased.

## State of the tree

- `main` is `bb9baa2` plus `b5a7f96` (the SD note). Both switches on.
- Known-good image is still the one from before this session. Do not write
  exFlash. SRAM only, cable 417, never 418.
- TOS slot stays 256K EmuTOS at `0x500000`. Do not replace it with TOS 1.04.
- The probes are not in the repo. They were built in the chat and handed to
  David as `fnop.prg`. Rebuild from the description above if needed.

## What the bot should do

1. Read this file and `handoff/HANDOVER_2026-10-09_cpu_rework.md`.
2. Find why `STACK_FORMAT` is not `0`, `A` or `B` when the frame for an `FNOP`
   is written. The selection in `STACK_CTRL` is right. The board result says
   the value at the write is not. Look at the stacking sequence, not the
   decoder.
3. Do not change the operand path. Prefetch-to-prefetch only, as in F65.
4. Keep `WF030_FAST_HANDOFF` and `BRIDGE_EARLY_AS` switchable and independent.
5. No compatibility hacks. A 68030 with no FPU takes Line-F on `FNOP`, format
   0, and `RTE` returns to the patched PC. That is the target.
6. When a patch is ready, the handoff order is `run_rtl.sh`, then the whole-ST
   bus bench, then the build timing check. David tells the bot. The bot does
   not poll.
