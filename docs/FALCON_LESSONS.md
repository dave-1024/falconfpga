# Lessons for the Falcon core

Practical notes from the ST/030 core (Tang Console 138K + AE350 helper), for David and the assistant when starting the Falcon core. Sources: `docs/float_panic/FLOAT_PANIC.md`, `docs/float_panic/BLITTER_REVIEW.md`, build notes.

## Design

1. **Put every major path behind a compile-time switch.** CPU type (`ST_CPU_68000` vs the 030), bridge, early AS, fast handoff, cartridge, caches, debug probes. *Why:* when the 030 build panicked, the quickest way to split the problem was to rebuild without one piece. *How:* `` `define `` the switch in `build_sel.vh` from a per-variant `build_*.tcl`. Never hard-code `CPU_030`.
2. **Bus-error writeback must leave the destination untouched.** On a real 030, a read that bus-errors does not change the target register. Our core wrote `$FFFF` after the `$FFFA40` (SFP004) probe. Detection code relies on this behaviour, so it has to be right.
3. **Blitter, CPU bridge and floppy DMA arbitration must be cycle-correct.** HOG/BUSY, BR/BG/BGACK, and the order of handover in both directions. *Why:* the Falcon adds more bus masters (DSP, DMA sound, VIDEL). *How:* follow the hardware handshake. Don't add "data wins" muxes. Today, if DMA and the blitter were ever active together, the DMA data would win.
4. **Gate 030-tuned shared logic.** The double cold-start reset (`DR_GAP`) and the SDRAM early start (`RAM_EARLY`) run in every build. On a 68000 they can give different boot faults (for example exception 33, TRAP #1 taken before GEMDOS sets up its handler). Tie them to the CPU switch, or expect this.
5. **Keep the autoboot cartridge and helper optional.** The cartridge runs before the memory test and before AUTO programs, so it changes the boot order compared with Hatari. Always keep a build without the cartridge so this can be ruled out.

## Debugging

6. **Probe what the CPU can't see.** A CPU write-watch misses floppy DMA, the blitter and the helper. Put watches on the RAM port, tagged with which master did the write (`DIAG_DMAWATCH`), and decode them with the `pages_*.py` scripts.
7. **Don't trust software labels alone.** Read the raw cookies (`_FPU`, `_CPU`, `_MCH`, `_SND`) and test Line-F behaviour directly. A wrong probe answer may show "no FPU type" but still change software paths. There is one cookie, `_FPU`; the type is packed into its high word.
8. **Make the Hatari comparison match the board.** Use the same machine type (`_MCH`/`_SND`, since STE vs ST changes software paths), the same TOS, RAM size and cartridge image, and compare the same memory layout. Without this, a "Hatari passes" result means little.
9. **Avoid adding new unknowns while hunting a bug.** No hard disk drivers (HDDriver, ICD) during a hunt. Dump small RAM ranges to a floppy image instead.

## Board and flash

10. **Always leave the board on a working build, and keep a known-good `.fs` as the fallback** (currently `st_helper_sdw_p3.fs`).
11. **Flash rules:** use only `programmer_cli` op 53 with `--fsFile`. Never bulk erase. Never write `0x500000` (EmuTOS/TOS) or `0x600000` (helper firmware). Never reflash the BL616.
12. **Rescan the Gowin cables every time.** The cable location changes (it was 4225 recently).
13. **A partial flash doesn't lose the debugger.** The FT2232 shows up on USB whatever is in the bitstream. If it's missing from `lsusb`, check power or the cable, not the flash.
14. **The Hagibis capture (345f:2130) needs an explicit format.** Use `-f v4l2 -input_format yuyv422 -video_size 1920x1080 -framerate 60` and skip about 60 warm-up frames (`select=gte(n\,60)`). See `~/fpga_tools/grab.sh`.

## Process

15. **Don't merge half-fixes.** The SD write fix still needs its error flag before it goes to main, and long uploads can still jam. Test new transfer paths on small chunks first.
16. **Leave a trail for overnight work.** Write notes in `docs/`, keep bitstreams in `~/fpga_bitstreams` with names that say what they are, push the branch, and record what is flashed now, so the next session can pick up without rediscovering anything.
17. **Builds take a while.** Run `gw_sh` in the background with `QT_QPA_PLATFORM=offscreen` (11 to 55 minutes). The ssh session can drop during routing, so log to a file.

## Bugs found (ST/030 core)

Each entry gives the symptom, the cause, the fix or current status, and the commit. Where it says "n/a", the fix was a patch outside this branch (for example `reset_fix.patch` or `doublereset.patch` on the box) or isn't committed yet. The full story is in `Atarist_030_wip/docs/HISTORY.md` and `docs/float_panic/FLOAT_PANIC.md`.

### CPU core (WF68K30L) and its timing

- **Two idle bus states, and the request handoff after S5.** *Symptom:* the 030 ran slower than a real one; the AS-to-AS gaps missed ST bus slots. *Cause:* the core spent idle clocks between bus requests instead of starting the next cycle straight after S5, and it put idle clocks between the halves of a long fetch. *Fix:* the F62 prefetch queue does aligned long-word fetches with no idle clocks (`8f104b3`/`973c1df`). F65 rolls a prefetch's S5 straight into S0 of the next one, behind the `WF030_FAST_HANDOFF` switch (`3921274`, `a4da0c5`, merged `bb9baa2`). Operand cycles still go through IDLE, so the full handoff rework is still open (`c179218`, `handoff/HANDOVER_2026-10-09_cpu_rework.md`). *Lesson:* make the core's request timing match the 030 before tuning the bridge.
- **The prefetch restart and the 4n+2 target.** *Symptom:* black screen at boot with TOS 2.06 UK. *Cause:* F62 made the vblank-sync loop at `E013F6` (a 4n+2 target) 24% slower, too slow to catch the 60 Hz blank. *Fix:* F62b restarts the stream with a long fetch at the requested word (`7a53162`/`9e612d5`), with `prog_loop.s` as a guard.
- **The prefetch flush flag.** *Symptom:* stale or extra fetches after a flow change. *Cause:* the queue used its own copy of the flush condition. *Fix:* F62c uses the decoder's `OPCODE_FLUSH` directly (`d7b6b8d`/`ef56b11`).
- **Prefetch fault handling** (fixed in F62). An unused prefetch fault no longer fails the next data read (`DATA_VALID`). A faulted opword now gives BERR instead of Line-F, and there's no stale Line-F trap after a BERR.
- **JSR and the SP writeback.** *Symptom:* a crash on program exit and a GEMBENCH menu freeze (TOS 2.06 AES Pexec wrapper at `E21C0C`). *Cause:* in `ADDA.W #16,SP; JSR (d16,PC)`, the A7 writeback and the JSR predecrement landed in the same clock, and the decrement was lost. *Fix:* JSR waits for a pending A7 writeback, as BSR already did (`79f5951`/`75bfc8c`, F62d), with the `prog_spwb.s` bench. The bug was latent on main and the faster prefetch exposed it.
- **CHK operand.** *Symptom:* spurious CHK traps (GEMBENCH 6 "Subscript out of range"). *Cause:* ALU operand 2 came from A0 (AR port 2) instead of Dn. *Fix:* F60 `87fac46`.
- **Bus-error destination writeback** (open). *Symptom:* after the `$FFFA40` SFP004 probe bus-errors, the target register holds `$FFFF`. *Cause:* the core writes back on a faulted read; a real 030 leaves the register unchanged. *Status:* logged in `9653a01`, not fixed yet.
- **Float Math bus error / panic** (open). *Symptom:* GEMBENCH Float Math panics. *Chain:* AUTOFPU's text at `$55C96-$55D20` gets overwritten, so a CHK `$4320` is executed from data, then vector 6, then the handler uses a bad A5, then `jsr $416528`, then BERR. *Status:* FPU cookies, the cartridge, the I-cache, branches, IRQs and prefetch are all ruled out. The remaining question is which bus master overwrites that memory: watch it with `DIAG_DMAWATCH` (`1e5c473`). The write-watch result is in `f408a15`.

### Debug tooling

- **Decoder bit-18 mask.** *Symptom:* an apparent A23:16 address corruption. *Cause:* our overlay decoder masked bit 18 (row d, bit 20), so the address "corruption" was a decode error. *Fix:* `86882a8`, re-read in `5e855f4`. *Lesson:* check your probe before you believe it.

### Bridge, bus and RAM

- **Early AS in the bridge.** *Status:* F64, behind `BRIDGE_EARLY_AS` (AS and read DS at S0 en2, write DS at S2 en2), off by default (`d43f5fd`). F62d and the early-AS build both still hit the float panic, so this isn't its cause.
- **F61 bridge read timing.** *Symptom:* wrong RAM reads in the bench. *Cause:* F61 took the data at A+375, but it only reaches the ST bus at A+406. *Fix:* reverted (`6611246`). Reinstated together with the SDRAM early start (F63 `f484271`, `RAM_EARLY`), which moves the data to A+344. The bench RAM model was also wrong: it never wrote anything (`016016e`).
- **Exception 33 (TRAP #1) on the 68000 build** (open). *Symptom:* `68000_cmp` doesn't boot. *Suspects:* the 030-tuned shared logic (`DR_GAP` double reset, `RAM_EARLY`) running on a 68000. The cartridge isn't in that build. *Status:* the new `ST_CPU_68000` switch (`cc2ee21`) is being built for the test.

### Reset, clocks and timing constraints

- **rigsdram double cold-start reset.** *Why:* the SDRAM isn't always ready on the first reset after power-up. *How:* after the first ST reset, the CPU runs for `DR_GAP` clk32 cycles (1536), then gets a second reset (`atarist.v`; ported from rigsdram, `doublereset.patch`). It is tuned for the 030 and may hurt a 68000.
- **`bl616_jtagsel` in POR.** *Symptom:* resets or hangs at power-up. *Cause:* `bl616_jtagsel` (which idles high) was part of the POR term. *Fix:* removed from POR (`reset_fix.patch`; see DEBUG2 7m). It stays on pin logic only.
- **Reset synchronisers.** *Symptom:* recovery and removal timing failures (−5.4 ns / −1.4 ns) and a `pll_init` hold miss. *Cause:* the raw POR went straight into the clk32 and flash_clk domains. *Fix:* 3-flop async-assert/sync-deassert chains, and the clk_osc loads moved onto the global network (`382524f`). Also `place_option 1` for a clk_osc hold miss (`6c706f0`).
- **SDC clocks.** *Symptom:* STA found clocks that nobody had created (TA1132), so those paths went unchecked. *Fix:* created ae350_flash_clk, st_flash_clk, spi_io_clk, ddr3_sysclk, i2s_bclk_d and ds2_clk_spi, with groups (`6fd2bad`). *Lesson:* every clock in a design needs an SDC entry.

### AE350 helper and SD

- **AE350 boot from flash.** *Symptoms:* the AE350 couldn't read flash, CS# stuck low, no UART. *Causes and fixes:* the flash and ready-mark IOBUFs blocked fabric reads (`949bd27`). MSPI is now lent to the AE350 after `flash_ready` and reinitialised before the 030 is released (`11e3f28`/`9790cc1`), and the AE350 starts from S1 after the 030 has booted (`b3283fc`). Flash SPI is at `0xF0F00000`, CS# is released before `0xA5`, and the switch is forced if CS# stays low (`269bff8`). The ready stub got the UART2 offsets and the loader (`02e2c92`).
- **Mailbox lost byte.** *Cause:* the RX ring wasn't drained while transmitting. *Fix:* `3e0d6b8`.
- **SD write jam.** *Symptom:* the card stuck in state 13, followed by floppy errors (`b5a7f96`). *Cause:* sd_rw issued CMD17/CMD24 while DAT0 was still busy. *Fix:* `ST_SD_WRITE_FIX` waits for "not busy", retries CMD24 a bounded number of times, and completes a failed write (`7e3d5dd`, board result in `f2b13e6`). *Status:* not on main yet, because an SD error flag is still needed. A long upload jammed once even with the fix in.
