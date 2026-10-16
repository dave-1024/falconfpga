# Lessons for the Falcon core

What we learned on the 030 ST core (Atarist_030_wip, Tang Console 138K, AE350 helper) and want to keep
doing from day one on a Falcon core. Background: `BUILD.md`, `float_panic/FLOAT_PANIC.md`, `float_panic/BLITTER_REVIEW.md`.

## Build and switches
1. **Make every major path a compile-time switch.** CPU type (`ST_CPU_68000` vs 030), bridge, `BRIDGE_EARLY_AS`,
   `WF030_FAST_HANDOFF`, cartridge, caches, diag probes. Never hard-code `CPU_030`.
   *Why:* every A/B test (F62d vs early-AS vs F65, cart vs no cart, 68000 vs 030) only took a rebuild, not a code edit.
   *How:* one `build_*.tcl` per variant, writing `build_sel.vh` (Gowin has no command-line define).
2. **Gate shared 030-tuned logic too.** The double cold-start reset and the early SDRAM path (`RAM_EARLY`, reset gap)
   run in every build. On a 68000 they can produce a different boot fault (we saw exception 33 / TRAP #1, a GEMDOS
   call before GEMDOS was ready). Put them behind the CPU switch, or expect that.
3. **Keep the cartridge and helper hooks optional.** An autoboot cartridge runs before the memory test and before AUTO
   programs, so it changes boot order. Have a no-cart build ready, and remember the remote driving needs the mailbox.

## Flashing and the board
4. **Always leave the board on a working build.** Flash only with op 53 `--fsFile`. Never bulk erase. Never write 0x500000
   (TOS) or 0x600000 (helper firmware). Never reflash the BL616. Keep the last good `.fs` (now `st_helper_sdw_p3.fs`) as the fallback.
5. **Rescan the cables every time.** The location changes after reboots or replugs (289, 417, 4225 ...).
6. **A partial flash doesn't lose the debugger.** The FT2232 shows up on USB whatever is in flash. If it's missing
   from `lsusb`, the board has no power or the cable/port is bad. A bad flash only gives a black screen.
7. **Capture:** the Hagibis (345f:2130) needs explicit v4l2 settings and warm-up frames:
   `ffmpeg -f v4l2 -input_format yuyv422 -video_size 1920x1080 -framerate 60 -i /dev/video0 -vf 'select=gte(n\,60)' -frames:v 1 out.png`
   (`~/fpga_tools/grab.sh`). A black frame on its own doesn't prove the core is dead.

## Debugging
8. **Probe what you can't see.** A CPU-side write watch misses floppy DMA, blitter and helper writes. Watch at the RAM
   port and tag every entry with its master (CPU/DMA/blitter). Check that the probe's own decoder is right too: our
   "address corruption" was a bit-18 misread in the decoder.
9. **Don't trust software labels alone.** Read the raw cookies (`_CPU`, `_FPU`, `_MCH`, `_SND`) and test Line-F
   directly (FNOP must trap to vector 11). A wrongly answered probe might not show any FPU type in a sysinfo tool.
10. **Bus-error reads must not write back.** After a read that bus-errors, the destination register must be unchanged.
    Our core put `$FFFF` in D0 after `move.w $FFFA40,d0`. Falcon software probes a lot of addresses, so fix this before reusing the core.
11. **Match Hatari exactly before comparing.** Same machine type (`_MCH`, ST vs STE vs Falcon), `_SND`, TOS version,
    RAM size, cartridge image and resolution. STE vs ST changes software paths. Note that Hatari forces EmuTOS 192 to a 68000.
12. **Cross-check differences in a differential harness first.** Musashi vs the RTL bench (`float_panic/diff/`) cleared the
    CPU in a few hours. Then move to the board-only differences (DMA, blitter, helper, IRQ sources).
13. **Bus arbitration must be cycle-correct.** Blitter HOG/BUSY, BR/BG/BGACK through the 030 bridge, and floppy DMA must
    never own the bus together. The Falcon adds more masters (DSP, sound DMA, VIDEL), so plan arbitration and tags in from the start.

## Process
14. **Don't merge half-fixes.** The SD write fix went to main only with its error path to the FDC (`ST_SD_HARDEN`).
    Test new data paths on small chunks first.
15. **Leave a trail.** Before any overnight or token-limited run, write the state into the notes (board build, bitstream
    names, what's next) and keep the bitstreams in `~/fpga_bitstreams`, so work can pick up cold. Always end on the fallback `.fs`.
16. **Run the rollback on the same procedure before blaming a build.** A failure that the known-good bitstream shows too is the setup, not the change (the missing `c` of 16 Oct 2026).
17. **Keep credits.** Keep the original authors' headers and `LICENSE-NOTES.md` up to date as cores are borrowed (WF68K30L, fx68k, FX blitter, MiSTeryNano).

## Bugs found (ST/030 core)

Each entry gives the symptom, the cause, the fix or current status, and the commit. Where it says "n/a", the fix was a patch outside this branch (for example `reset_fix.patch` or `doublereset.patch` on the box) or isn't committed yet. The full story is in `HISTORY.md` and `docs/float_panic/FLOAT_PANIC.md`.

### CPU core (WF68K30L) and its timing

- **Two idle bus states, and the request handoff after S5.** *Symptom:* the 030 ran slower than a real one; the AS-to-AS gaps missed ST bus slots. *Cause:* the core spent idle clocks between bus requests instead of starting the next cycle straight after S5, and it put idle clocks between the halves of a long fetch. *Fix:* the F62 prefetch queue does aligned long-word fetches with no idle clocks (`8f104b3`/`973c1df`). F65 rolls a prefetch's S5 straight into S0 of the next one, behind the `WF030_FAST_HANDOFF` switch (`3921274`, `a4da0c5`, merged `bb9baa2`). Operand cycles still go through IDLE, so the full handoff rework is still open (`c179218`, `handoff/HANDOVER_2026-10-09_cpu_rework.md`). *Lesson:* make the core's request timing match the 030 before tuning the bridge.
- **The prefetch restart and the 4n+2 target.** *Symptom:* black screen at boot with TOS 2.06 UK. *Cause:* F62 made the vblank-sync loop at `E013F6` (a 4n+2 target) 24% slower, too slow to catch the 60 Hz blank. *Fix:* F62b restarts the stream with a long fetch at the requested word (`7a53162`/`9e612d5`), with `prog_loop.s` as a guard.
- **The prefetch flush flag.** *Symptom:* stale or extra fetches after a flow change. *Cause:* the queue used its own copy of the flush condition. *Fix:* F62c uses the decoder's `OPCODE_FLUSH` directly (`d7b6b8d`/`ef56b11`).
- **Prefetch fault handling** (fixed in F62). An unused prefetch fault no longer fails the next data read (`DATA_VALID`). A faulted opword now gives BERR instead of Line-F, and there's no stale Line-F trap after a BERR.
- **JSR and the SP writeback.** *Symptom:* a crash on program exit and a GEMBENCH menu freeze (TOS 2.06 AES Pexec wrapper at `E21C0C`). *Cause:* in `ADDA.W #16,SP; JSR (d16,PC)`, the A7 writeback and the JSR predecrement landed in the same clock, and the decrement was lost. *Fix:* JSR waits for a pending A7 writeback, as BSR already did (`79f5951`/`75bfc8c`, F62d), with the `prog_spwb.s` bench. The bug was latent on main and the faster prefetch exposed it.
- **F65 "desktop stop".** *Symptom:* after the F65 handoff flash, the board stopped at the desktop. *Cause:* an SD card fault, not the handoff (`2c9b35b`). *Fix:* none in the core; F65 merged as `bb9baa2`.
- **CHK operand.** *Symptom:* spurious CHK traps (GEMBENCH 6 "Subscript out of range"). *Cause:* ALU operand 2 came from A0 (AR port 2) instead of Dn. *Fix:* F60 `87fac46`.
- **Bus-error destination writeback.** *Symptom:* after the `$FFFA40` SFP004 probe bus-errors, the target register holds `$FFFF` (`moveq #0,d0; move.w $FFFA40,d0` gave D0 = `$0000FFFF`; logged in `9653a01`). *Cause:* upstream WF68K30L control's bus-error branch in `STATE_REGs` tests `DATA_RD_I = '1'` together with `RD_RDY = '1'`, but `DATA_RD_I` is forced to 0 while `DATA_RDY` is high, so it never fired: the faulted read went on to INIT_EXEC_WB and the ALU wrote the bus value. A real 030 leaves the register unchanged. *Fix:* F66, unconditional core fix: a faulted operand read (FETCH_OPERAND/FETCH_MEMADR) returns the fetch FSM to START_OP; the write-back stage keeps finishing the previous instruction (`7e3660e`, merged `1e0e229`). RTL bench `prog_berrwb.s` (Dn .b/.w/.l, MOVEA, ADD, MOVEM, (An)). Board 15 Oct (`st_helper_hdn_berr_7e3660e_p3.fs`): COOKIEFP D0 stays 0, GEMBENCH all tests 123%, Float Math 13.080 s (101%), unchanged. *Lesson:* check that an upstream error branch can actually fire.
- **Float Math bus error / panic (gb403).** *Symptom:* GEMBENCH Float Math panics (CHK `$4320` executed from data, vector 6, bad A5, `jsr $416528`, BERR). *Cause:* not the CPU. AUTOFPU.BIN on the SD card's gb403.st had desktop INF text (`#a000000`...) written into it at offset $400 by the runtime-swap disk-change bug (see "AE350 helper and SD"). *Fix:* clean image (CRC 791ee820) plus `ST_FLOPPY_MEDIACH`. Float Math passes on p3: 13.075 s, and 13.080 s on the hardening build (`3b9b8d2`, `9a3d030`). *Lesson:* checksum test images before chasing a CPU fault.
- **Bus-width register on a chained long read that bus-errors (phase 2).** *Symptom:* in the prog_berrwb bench the format B frame's data input buffer was only half filled. *Cause:* P_BUSWIDTH kept the ending cycle's DSACK ("01", word port) on the chain edge, because the DSACK sample is still the old one there; the chained cycle then ran as a word port until its own DSACK. F65's prefetch chain had the same latent bug (harmless with a single 16-bit port). *Fix:* the chain edge resets DSACK_MEM first (`6b4f100`).
- **Posted-write frame DOB (phase 2, option b).** *Symptom:* after a write bus error the stacked format B frame's data output buffer held the data of an older write (e.g. `$11112222` instead of `$33334444`). *Cause:* with writes completing at S3, the core still runs the next instruction's operand cycle before it takes the exception, and that cycle reloaded WP_BUFFER. *Fix:* DOB_HOLD keeps OUTBUFFER until the exception (BUSY_EXH) (`dfa0f15`, bench prog_wpberr.s `de35f5f`). Still open: the data fault itself is taken one cycle late and the frame is always $B (TODO.md).

### Debug tooling

- **Decoder bit-18 mask.** *Symptom:* an apparent A23:16 address corruption. *Cause:* our overlay decoder masked bit 18 (row d, bit 20), so the address "corruption" was a decode error. *Fix:* `86882a8`, re-read in `5e855f4`. *Lesson:* check your probe before you believe it.
- **Stability script without the cold boot (16 Oct 2026).** *Symptom:* every reload of the option (b) build showed "System halted!" after the cartridge self-test, and the known-good 5246d00 rollback did too. *Cause:* the script dropped the initial `c` cold boot of the earlier procedure; a bare reload after a flash or after a halt keeps halting (stale state) until `c`. *Fix:* `c` first (gb/wp/stab.sh); then 10/10 reloads and 3/3 `w` were clean on the same bitstream. Lesson: compare against the rollback on the same procedure before calling a build bad.

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
- **SD write jam.** *Symptom:* the card stuck in state 13, followed by floppy errors (`b5a7f96`). *Cause:* sd_rw issued CMD17/CMD24 while DAT0 was still busy. *Fix:* `ST_SD_WRITE_FIX` waits for "not busy", retries CMD24 a bounded number of times, and completes a failed write (`7e3d5dd`, board result in `f2b13e6`). *Status:* on main (15 Oct 2026). No jam in stress tests on the debug build (runtime mounts, 2x 737 KB uploads, desktop saves mid-upload). Hardening (token check, error flag) is now on main, see the next entry.
- **Runtime image swap corrupts the new disk (the gb403 / AUTOFPU.BIN corruption, GEMDOS -35).** *Symptom:* desktop INF text inside another file (`#a000000`... in AUTOFPU.BIN), foreign directories, -35 / "not readable" after a runtime mount. Never after an `atarist.ini` power-up mount. *Cause:* not the SD write path. Every write went to base + image sector (SD_WRITE_DEBUG ring). TOS notices a disk change only by the write-protect line changing while a disk goes in. The helper swaps images instantly and the core held WP at the static OSD value, so TOS kept the old disk's FAT/directory cache and wrote it into the new image. Reproduced: save on tools2.st, `mount a gbsnap.st`, save. gbsnap's root became tools2's, and the INF landed in GEMBENCH.RSC. *Fix:* `ST_FLOPPY_MEDIACH` holds WP for about 0.75 s after each insert (`7df7f29`, on in `build_st_helper.tcl`). Board retest: the swapped image keeps its own directory, the INF goes to that image's free clusters, and GEMBENCH loads from a runtime-mounted disk. *Lesson:* emulated media must signal a disk change the way the real drive does. A corrupt disk image can pose as a CPU bug (the float panic) for days.
- **FNOP "format error" was the probe.** *Symptom:* RTE after FNOP took exception 14 on the board. *Cause:* the hand-built probe wrote the skip address to 2(A2) instead of 2(SP) and printed the format nibble wrongly. *Fix:* none needed in the core. `sw/fnop_probe/fnop4.s` shows Line-F, format 0, offset $2C, and RTE to the patched PC on the board. *Lesson:* keep probe source in the repo and disassemble a probe before trusting its result.
- **SD hardening and the FDC error status (`ST_SD_HARDEN`).** *Symptom:* a rejected or unanswered block was silently counted as written, read timeouts retried forever, and the FDC sector could move between request and hand-off. *Fix:* sd_rw checks the data-response token, re-inits the card (CMD0) and re-issues the request (2 re-inits, then gives up), and bounds the CMD17/read-timeout retries. sd_card latches the sector at the request edge. A give-up now raises `sd_err`, which reaches fdc1772 as status bit 3 (CRC error), so TOS reports a disk error instead of using bad data. Multi-sector commands stop at the failing sector (`054b0b6`, `917668c`, benches `tb_sd_harden.v` and `fdc1772/sim/tb_fdc_sderr.v`). *Board (15 Oct 2026):* runtime mounts/swaps/saves, a 737 KB upload with saves injected mid-upload (CRC ok), and Float Math 13.080 s. 0 WERR, 0 give-ups, 0 timeouts, max 580 clocks in CMD24, gbref still 791ee820. The give-up path itself was only fault-injected in simulation.
