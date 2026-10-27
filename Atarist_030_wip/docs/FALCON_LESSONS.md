# Lessons for the Falcon core

What we learned on the 030 ST core (Atarist_030_wip, Tang Console 138K, AE350 helper) and want to keep
doing from day one on a Falcon core. Background: `BUILD.md`, `docs/history/investigations/float_panic/FLOAT_PANIC.md`, `docs/history/investigations/float_panic/BLITTER_REVIEW.md`.

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
12. **Cross-check differences in a differential harness first.** Musashi vs the RTL bench (`docs/history/investigations/float_panic/diff/`) cleared the
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
- **Posted-write frame DOB (phase 2, option b).** *Symptom:* after a write bus error the stacked format B frame's data output buffer held the data of an older write (e.g. `$11112222` instead of `$33334444`). *Cause:* with writes completing at S3, the core still runs the next instruction's operand cycle before it takes the exception, and that cycle reloaded WP_BUFFER. *Fix:* DOB_HOLD keeps OUTBUFFER until the exception (BUSY_EXH) (`dfa0f15`, bench prog_wpberr.s `de35f5f`). The late fault and the $B-only frame were fixed by FLT1/FLT2 (next entry).

- **Data write fault taken after the next instruction (FLT1/FLT2, 17 Oct 2026).** *Symptom:* after `move.w d1,$20000` (BERR) the next instruction's operand read ran and changed D3/CCR before the frame was stacked, the frame PC pointed at it (RTE would run it twice), a MOVEM kept writing after its first fault, and a write fault always stacked format $B. *Cause:* the faulting write runs in the write-back stage while the fetch side already works on the next instruction; the exception handler only started once the control unit was idle. *Fix:* no program bus cycle after a faulted data write; a write fault at an instruction boundary stacks the short $A frame (MC68030UM 8.1.2, Table 8-6). Unconditional (`f045aa9`, merged on main with `caches`), bench `prog_fault.s`; FAULT_FIXES.md. *Lesson:* with a pipelined write-back, "wait until idle" is not "take the exception for the faulted cycle".

- **Core-side cycle savings are masked by the ST bus (option (a), 17 Oct 2026).** Saving 1 clock per MOVEM transfer (writes 4 -> 3, reads 7 -> 6 clocks) left the whole-ST bench cycle-identical and moved GEMBENCH by 1%: the next AS still misses the same ST en1 slot. *Lesson:* before a core pipelining change, check against the bridge timing whether the saving crosses a 500 ns slot boundary; bigger core-side gains need the caches.

- **The F62 misaligned stream and the I cache (17 Oct 2026, branch `caches`).** *Finding:* a stream that starts at a
  4n+2 branch target stays misaligned for good (F_ADR steps by 4 from 4n+2), so every bus prefetch holds halves of two
  long words. With per-long valid bits the first cache version filled nothing at all in such streams. *Fix:* the cache
  keeps the second word of a misaligned fetch and stores the long when the next fetch brings its first half; only the
  stream's first long is lost (ICACHE_DESIGN.md Q1). *Lesson:* a cache on the queue must handle every fetch shape the
  queue makes, not only the aligned one a 68030 makes.
- **Direct-mapped test layout (17 Oct 2026).** *Symptom:* the freeze case of the first I cache test missed although the
  cache was right. *Cause:* the test's own driver code shared a 16-byte line index with the loop (256-byte
  direct-mapped cache) and evicted it just before FI was set. *Fix:* driver code in an uncached area (prog_icache.s).
  *Lesson:* in a cache test, check which other code maps to the same lines before calling a miss a bug.
- **Bus-error frame stage B/C and rerun bits (FRM, 20 Oct 2026, frame-fix).** *Symptom:* the long frame took $0C/$0E
  from BIW_1/BIW_2, so for instructions shorter than three words stage B ($0E) was a word of an earlier instruction
  (prog_movemx: $6000 or $0536 depending on prefetch timing); RC/RB were latched from IPIPE_C/B at the last pipe
  request (pipe progress, not the faulted fetch), and FC/FB were never set for a faulted extension word taken by an
  extension-word request (`move.w #imm,d0` with the immediate faulting stacked SSW $2005, `move.l #imm,d0` with
  the 2nd word faulting $0005). *Fix:* the decoder records the words at PC+2/PC+4 of the issued instruction and their
  fault flags as they reach the pipe (P_STAGE; FC/FB = the instruction used that word and it faulted), the top level
  takes words not yet in the pipe from the prefetch queue by address (P_QSTAGE, Q_HEAD/Q_FAULT), frozen while the
  frame is stacked; RC/RB = the word came from a faulted fetch (MC68030UM 8.2). Unconditional. Bench prog_frame.s:
  stage C fault $B005, stage B fault $5005 with stage C = the 2nd word, data read faults with stage C/B = the next
  words, a write fault, an opcode-word fault, each RTE re-run; same frames at WS 0/1/3/7, CIMODE 1, random waits.
  *Lesson:* a frame field copied from a register "that usually holds it" is a timing bug; derive it from the
  address it is defined by. Not yet checked on the A1200 (real silicon decides): the open question is RB for a fault
  on the opcode word (prog_branch case 9: the frame PC is the faulted opcode $10000, RC from the same long, RB
  because the core refetches $10004 before the exception and that fetch faults too: SSW $2005 -> $3005).

### Debug tooling

- **Decoder bit-18 mask.** *Symptom:* an apparent A23:16 address corruption. *Cause:* our overlay decoder masked bit 18 (row d, bit 20), so the address "corruption" was a decode error. *Fix:* `86882a8`, re-read in `5e855f4`. *Lesson:* check your probe before you believe it.
- **Stability script without the cold boot (16 Oct 2026).** *Symptom:* every reload of the option (b) build showed "System halted!" after the cartridge self-test, and the known-good 5246d00 rollback did too. *Cause:* the script dropped the initial `c` cold boot of the earlier procedure; a bare reload after a flash or after a halt keeps halting (stale state) until `c`. *Fix:* `c` first (gb/wp/stab.sh); then 10/10 reloads and 3/3 `w` were clean on the same bitstream. Lesson: compare against the rollback on the same procedure before calling a build bad.

- **Prefetch hold must not cancel a decided S5 hand-over (16 Oct 2026, prefetch-cof).** *Symptom:* step 1 (833183b)
  halted with "System halted!" on reloads r6-r10 after a `c` cold boot; de35f5f did 8/8 under the same procedure.
  *Cause:* the change-of-flow hold was also ANDed into PF_CHAIN_GO, so a prefetch-to-prefetch hand-over armed at S3
  could be refused at S5 when the hold rose in between. Not reproduced in RTL; narrowed on the board: the same RTL
  with PF_HOLD removed from PF_CHAIN_GO (vchain) did 10 reloads, 3 warm resets and GEMBENCH clean. *Fix:* the hold
  only stops new requests (PF_REQ and the S3 arm), never the S5 decision, as on a real 030. *Lesson:* a gate added to an
  S3-armed/S5-decided path must apply at the arm only.
### Bridge, bus and RAM

- **Early AS in the bridge.** *Status:* F64, behind `BRIDGE_EARLY_AS` (AS and read DS at S0 en2, write DS at S2 en2), off by default (`d43f5fd`). F62d and the early-AS build both still hit the float panic, so this isn't its cause.
- **F61 bridge read timing.** *Symptom:* wrong RAM reads in the bench. *Cause:* F61 took the data at A+375, but it only reaches the ST bus at A+406. *Fix:* reverted (`6611246`). Reinstated together with the SDRAM early start (F63 `f484271`, `RAM_EARLY`), which moves the data to A+344. The bench RAM model was also wrong: it never wrote anything (`016016e`).
- **Exception 33 (TRAP #1) on the 68000 build** (open). *Symptom:* `68000_cmp` doesn't boot. *Suspects:* the 030-tuned shared logic (`DR_GAP` double reset, `RAM_EARLY`) running on a 68000. The cartridge isn't in that build. *Status:* the new `ST_CPU_68000` switch (`cc2ee21`) is being built for the test.

- **Board test false halts (16 Oct 2026).** The HDMI capture gives single all-black frames on every build, and after a
  USB/FT2232 event it stayed black (and `v4l2-ctl --query-dv-timings` reads 0x0 even with a picture). The helper serial
  went silent once (no reply to `s`; warm resets sent then never happened); an op 1 reload brought it back. *Rules:*
  count a halt only if 5 grabs over ~40 s are all non-desktop (rl.sh), check the serial with `s` before relying on `c`/`w`,
  and confirm a known-good build shows a picture before blaming a test build.
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
- **Whole-ST netlist bench needs FAST_HANDOFF in the netlist (16 Oct 2026, prefetch-cof).** *Symptom:* a CPU change looked 4-13% slower in `run_bus.sh`, every prefetch-to-prefetch transition 250 ns late. *Cause:* `wf030_syn.tcl` synthesises `WF68K30L_TOP` with its generic default `FAST_HANDOFF = 0`; the bridge's `WF030_FAST_HANDOFF` parameter is ignored by a netlist. The baseline netlist had been made with a hand-edited default of 1, so the comparison was invalid. *Fix:* synthesise every netlist for comparison with `FAST_HANDOFF := 1` (as the board builds). *Lesson:* check that both sides of an A/B netlist comparison were built with the same generics.
- **Helper serial silent after the first warm-reset attempt (OPEN, 16 Oct 2026).** *Symptom:* on vchain db04754 (20:40 UK) and again on option-a 08e1cf8 (23:15 UK), the first `w` after a run of op 1 reloads left the helper UART silent: no reply even to `s`, while the ST kept showing the desktop (so the reset may not have happened). ftdi_sio was loaded and /dev/ttyUSB1 present. *Workaround:* an op 1 reload restores the serial; after `c`, three `w` in a row all answered "ST reset via sysctrl" and reached the desktop. *Cause:* unknown (helper firmware or USB-serial, not the CPU core: the same on two different cores). *Clue (17 Oct 00:30 UK, oa 039c710):* the first `w` after 10 reloads was answered with the helper's command help line ("w / c  reset / cold-boot the ST ...") instead of "ST reset via sysctrl", i.e. the first command after reloads arrives garbled or is taken as unknown; the serial stayed alive this time and the next `w`s worked. *Lesson:* check `hc.sh s` and the `w` reply before counting a warm reset; a DESK grab alone does not prove one happened.
- **Gowin synthesis segfault on a 2-D valid-bit array (17 Oct 2026, caches).** *Symptom:* `gw_sh build_st_helper_hdn.tcl` crashed (rc 139) about a minute in, always right after "Running inference ...", on the I cache branch; the standalone `wf030_syn.tcl` of the same core synthesised fine. *Bisection (syn only):* not the unused dcache file, not `-rw_check_on_ram`/`-replicate_resources`, not RAM init values; a stub I cache built cleanly. *Cause:* the valid bits as `array (0 to 15) of std_logic_vector(3 downto 0)` with a dynamic two-index bit write (`VALID(line)(lw) <= '0'`) and a whole-row read-modify-write. *Fix:* one flat `std_logic_vector(63 downto 0)` written bit by bit in a loop (`75c4c18`), same behaviour (I cache tests and the 92-run regression unchanged). *Lesson:* keep small flag arrays flat in VHDL for Gowin, and run the full ST synthesis, not only the core alone, before calling a core change buildable.
- **Active-low cache pin inverted in the bridge (17 Oct 2026, caches).** *Symptom:* none in the RTL regression (tb030 drives CIINn itself), and the netlist unit bench passed; only a gate-level cache test through the bridge showed ST ROM code being filled while the reserved fast-RAM range was inhibited. *Cause:* `CIINn = ~fast_sel` (CIIN is active low: negated = cachable). *Fix:* `CIINn = fast_sel` (`47eba71`), plus `sim/run_icache_net.sh`. *Lesson:* test every new bridge signal end to end at gate level with a case where it must change behaviour, not just "nothing changed" benches.
- **D cache lookup bypassed by chained cycles (17 Oct 2026, caches).** *Symptom:* the first D cache unit test had no hits at all, and later a read right after a posted write still missed. *Cause:* reads that chain from S5 (OP_CHAIN) or start from IDLE after a posted write (PW_GO) never went through the START_CYCLE path where the hit was checked. *Fix:* a registered lookup on the next address, a hit check at S5 for chained reads, and PW_GO only for writes while the D cache is on (`1cbfdcf`). *Lesson:* every path that can start a bus cycle must pass the cache lookup.
- **Cache commit stall changed ST timing (17 Oct 2026, caches).** *Symptom:* prog_berrwb, prog_fault and prog_fpuprobe changed cycle counts with the D cache off. *Cause:* the one-clock IDLE stall after a cache commit fired after every read. *Fix:* commit only when the cache is on and something cachable or a bus error was seen (`706a0aa`); regression 92/92 identical again. *Lesson:* a disabled cache must cost zero clocks; check with the whole-log compare, not only PASS/FAIL.
- **D cache data in flip-flops instead of RAM16 (17 Oct 2026, caches).** *Symptom:* the first D cache build used 2048 DFFCE and ~6k LUTs for 256 bytes. *Cause:* each bank was written through two index ports, and the lanes were read through a VHDL function that took whole arrays as arguments, so Gowin did not extract them as RAM (the syn log has no "Extracting RAM" line for them). *Fix:* one write port per bank (no write split needed: the two entries of an operand are always in different banks) and direct indexed reads (`cbfcedb`, `ff6af03`): 74 RAM16SDP4, -4.4k LUT, -2.4k registers, timing unchanged. *Lesson:* check "Extracting RAM for identifier" in the Gowin syn log for every array meant to be RAM.
- **TOS 2.06 turns the caches on at boot (17 Oct 2026, board dc_ff6af03).** *Finding:* the desktop Options menu shows "Cache" ticked after a cold boot, so TOS 2.06 writes CACR itself (the TOS code writes $3919 with Cache on, which includes WA). GEMBENCH stayed at 133% because every ST-side cycle is cache-inhibited. *Lesson:* a cache that is "only enabled by software" is enabled on the first boot; WA write allocation still creates entries for ST writes (CIIN is ignored on writes), so D-Q2 needs a board check (TODO.md).
- **MOVEM -(An) decremented twice with one register (18 Oct 2026, f1-movem-timing, caught in sim before commit).** *Symptom:* prog_movemw differed from the old core for `MOVEM.L Dn,-(An)` with a single register: An ended 4 too low. *Cause:* with the new priority encoder the list ends one clock earlier, and the old last-write test (`MOVEM_LAST_WR`, a registered "last bit" flag) came one clock late, so the predecrement ran once more. *Fix:* drive the -(An) stop from `MOVEM_END` (no list bit above the current index, combinational) and drop `MOVEM_LAST_WR`; prog_movemx.s now covers every single register with every base in -(An)/(An)+. *Lesson:* when a state machine gets faster, re-check every registered "last step" flag that was timed against the old sequence.
- **Read-ahead moved prefetches into the bus-error frame (18 Oct 2026, f1-movem-timing).** *Symptom:* prog_movemx frames differed only in the DIB ($2C) after a bus error on a MOVEM read. *Cause:* a read-ahead runs before the control unit asks for that register, so the prefetch pair that used to run before the faulted read now ran after it, before BUSY_EXH froze INBUFFER. *Fix:* `RA_DIB_HOLD` freezes INBUFFER from the clock after a faulted read-ahead until BUSY_EXH (or a drop). Left-over bytes (DIB high word of a .W read, DOB of a read fault) still differ; the 68030 does not define them for a read fault, and all handler-visible fields are identical. *Lesson:* any change in bus-cycle order shows up in the frame buffers first; compare whole frames, then judge field by field which ones are defined.
- **Benchmark names and the blitter (18 Oct 2026).** *Finding:* the image we called "GEMBENCH 6" for weeks (`gbref.st`) holds GEMBench 4.03; GEMBENCH 6.08 is `gb608.st` (title bar "GEMBENCH 6.31"). Its RAM/ROM tests (MOVEM loops) showed a 71/73% gap the 4.03 tests (MOVE loops, 115%) never showed. GEMBENCH 6 also reports "BLiTTER NP" on our system, so its Display group against a blitter STE (46%) mostly measures the missing blitter; against a blitter-less ST it is 93%. *Lesson:* name a benchmark by program and version, keep its image CRC, and pick the reference machine that matches the hardware features actually in use (CPU clock, bus, blitter) before reading a gap as a CPU problem.
- **F3 needed no write queue (18 Oct 2026, f3-write-queue).** *Finding:* the F3 plan assumed the next MOVEM write had to be set up before the current one's outcome was known, which would need a queue and an undo of the (An)/-(An) step on a fault. Tracing the p608w loop cycle by cycle showed the posted write's outcome is already final in its S3 clock (WP_GO), one clock before DATA_RDY, and that is early enough for an S5 chain. *Lesson:* before designing speculation and undo, trace when the outcome is actually known; a signal named "ready" may be a registered copy of a decision made a clock earlier. Also: the GitHub connector's push re-encodes latin-1 bytes to UTF-8 and drops CRLF, so check `git diff -w` after every push.
- **CAS2 wrote the wrong operands and hung back to back (19 Oct 2026, fix-c-indirect, ISA audit).** *Symptom:* `cas2.w` that succeeded wrote Du1 to (Rn2) and Du2 to (Rn1); a second CAS2 right after the first wrote to a stale address and hung the core; a failed CAS2 loaded Dc1/Dc2 swapped; CAS/CAS2 N, V, C were metavalues in simulation; the CCR of a CAS2 whose first compare failed was overwritten by the second compare. Pre-existing (F1 and F3a). *Causes:* (1) the first compare was treated as final whenever the fetch side was in FETCH_OPERAND, so in CALC_AEFF the stale CAS2_COND of the previous CAS2 let writes start during the second read; (2) ADR_EFF_WB is loaded one clock after ADR_MARK_USED, the write went out with the previous address; (3) the Dc selector is latched at DR_MARK_USED in the order EXECUTE then WRITEBACK and named Dc1 first while the data order is (Rn2) first; (4) CAS/CAS2 missing in the ALU's RM/SM/DM case; (5) the CCR suppress terms tested a fetch state the pipelined CAS2 no longer meets. *Fix:* first compare goes to IDLE unless FETCH_STATE = SLEEP, a registered one-clock CAS2_WGAP before each write, Dc2 then Dc1 (UM: with Dc1 = Dc2 operand 1 wins), CAS/CAS2 in the flag case, a registered CAS2_CCHOLD. Regression `prog_cas2.s` in run_rtl. *Lesson:* rarely used multi-operand instructions need a result-checking test (memory, registers and CCR) for every outcome, not just a timing run; a hang in a timing suite is a correctness bug first.
- **Memory-indirect pointer read used a stale address (19 Oct 2026, fix-c-indirect).** *Symptom:* the third `move.w ([bd,An]),Dn` in a row read its pointer at the previous instruction's final operand address (bus error); `jmp ([bd,An])` never read its pointer and hung; `jsr ([bd,An])` jumped to the pointer address; `sub.w d0,([bd,An])` never re-read its pointer. Pre-existing. *Causes:* ADR_EFF is registered, so in the first FETCH_MEMADR clock it still holds the last value (with an idle bus the read went out at once); MEMADR_RDY was set by any DATA_RDY, so the acknowledge of an earlier write that finished while the instruction waited (ADR_IN_USE) counted as the pointer read (JMP hang, RMW without pointer read); JMP/JSR loaded MEM_ADR from ADR_EFF instead of the bus; CLR/JMP/JSR/Scc/MOVE from SR went from FETCH_MEMADR straight to INIT_EXEC_WB, before pointer + od was computed. *Fix:* registered MEMADR_IN gate on the pointer read, MEMADR_RDY only from a read, DATA_TO_CORE before ADR_EFF in the AR_IN_1 mux during FETCH_MEMADR, one SWITCH_STATE address clock for those ops. Regression `prog_memind.s`. *Lesson:* every registered address needs one clock between the state that selects its inputs and the bus request that uses it; check "ready" flags against the cycle type (read vs write).
- **Interrupt one instruction after the mask drop is correct (19 Oct 2026).** A pending interrupt after `move #$2000,sr` is taken after the next instruction. MC68030UM 8.1.9 (Fig. 8-4 to 8-6): IPEND asserts only after IPL is synchronised with the new mask and is checked once per instruction, so the interrupt is taken at STAT1 (example 1). Not changed. *Lesson:* check "late" exceptions against the manual's boundary rules before fixing them.


## T6 timing padding (19 Oct 2026)
- Pad in the ALU with a registered down counter loaded at ALU_INIT; never pad an op whose result drives a control
  decision at ALU_ACK (CHK trap): parking it let the next instruction run before the trap.
- Holding OPCODE_REQ does nothing for memory-indirect; prefetches chain inside the bus interface. Hold PF_HOLD instead.
- CAS2/CAS/TAS are RMC sequences on the 68030: no prefetch may sit between their reads and writes.
- Rebuild sim benches into separate dirs; editing sources mid-run produced a spurious all-FAIL run_rtl.
- A padded ALU op whose result decides control flow (CHK trap) needs the control unit to wait for ALU_ACK
  (CHK now waits in SLEEP like DBcc), not just the ALU to hold BUSY.
- Barrel shifter correctness: check against the old bit-serial core over every op x size x count (incl. 0,
  size, size+1, 63) with CCR (prog_shift); ROXx period is size+1.
- On linserver use `pgrep -x gw_sh`: `pgrep -f "gw_sh build"` matches its own ssh command line.

## TT-RAM detection (20/21 Oct 2026)
- **Root cause: CPU bug [C2].** WF68K30L computed the CMPA.W flags from bit 15 (MSB by operand size) instead of all
  32 bits of An. EmuTOS sizes TT-RAM with `cmpa.w #0,a2; bgt` and a2 = `$010FFFFF` (low word `$FFFF`), so the
  loop ended at once and `_ramtop` stayed 0. Fixed in the ALU (no switch): CMPA takes N/Z/V/C from bit 31 and the
  unextended An. *Lesson:* sized-compare flags for address ops are always 32-bit; check An-destination ops
  (CMPA/ADDA/SUBA) against values whose low word has the opposite sign.
- Found by calling EmuTOS's own routines from the boot cartridge (`ttram_detect` at `$E0CE08`, `is_bus32` at `$35C2`
  in the 1.4 256K UK image) and comparing with a hand-written copy of the probe that used long compares.
- A bitstream reload does not clear SDRAM: TOS may reuse an old `_ramvalid`/`_ramtop`. The core now masks reads of
  memvalid (`$420`) and `_ramvalid` (`$5A8`) after por until their first write (sampled at CAS inside sdram.v), so
  every load re-probes. The earlier crash with the `$5A8` mask (tt5) was not TT-RAM use; that build had -8.2 ns.

## FrontBench prgflags 7 black screen (21 Oct 2026)
- **Root cause: CPU bug [C3].** In `wf68k30L_bus_interface.vhd`, the odd-opcode address-error check (AERR_I, the
  START_CYCLE abort, OPC_LEGACY) tested `ADR_IN_P(0)`. While the control unit requests data, `ADR_IN_P` is the
  *data* address, and a data-cache read hit drops `RD_REQ`. So an odd-address byte read that hits in the D-cache,
  with an opcode request pending, raised a false address error (vector 3, fault address = the data address). Fix:
  test `OPC_ADR(0)` (PC_L).
- Never seen before TT-RAM because the ST side is cache-inhibited (CIIN), so no data hit could happen. TT-RAM is
  the first cachable memory. Caches off (CACR 0) hid it; Hatari ran the same program fine.
- *Lessons:* any "no bus cycle" path (cache hit, held read-ahead) must not leave another request looking at the
  shared address bus. Test caches with **code running from cachable memory**, not only data: the bus-level and RTL
  benches passed while the test code was in uncached ROM, and failed at once with the code copied to TT-RAM
  (`sim/rtl/prog_ttcache.s`, tb030 now has a 32-bit cachable TT port at $01000000).
- Bisect on the board with a small AUTO menu (SEL.PRG: CACR before Pexec) instead of desktop clicks.

## Incomplete sensitivity lists: RTL sim can differ from hardware (21 Oct 2026)

- Gowin EX4749 flagged `CHK2_RN` missing from the ALU COND_CODES process list (CHK2/CMP2 Z flag). A script audit
  (`sens.py`: signals read in each combinational process vs its list) found two more: `OPC_ADR` in BUS_IF
  BUS_CTRL_DEC (added with [C3]) and `MOVEM_FIRST_RD` in CONTROL FETCH_DEC (MOVEM memory-to-register path).
- Synthesis ignores sensitivity lists, so the hardware was always combinational; only the RTL simulation could lag.
  An RTL bench that "passes" proves nothing about a path whose process misses a signal.
- *Lessons:* whenever a signal is added to a combinational process, add it to the list (or use `process(all)`
  under VHDL-2008), and treat every "may differ" synthesis warning as an error. Rerun the audit after core edits.
  CHK2_RN is not the TT-RAM cause (no test uses CHK2/CMP2).

## TT-RAM caches-on SP -2 slip: block-RAM read-during-write in the I-cache (21 Oct 2026)

- **Root cause [C10].** `WF68K30L_ICACHE` describes DATA_RAM as an asynchronous-read array, but Gowin mapped it
  to a block RAM (SDPB, READ_MODE 0) and retimed the read address onto the D input of the F_ADR register, so the
  read is sampled at the clock edge. When a prefetch fill writes a long at edge E and the queue looks up the same
  long right after E (a taken branch to 4n+2 inside the long just fetched, e.g. TTM1 `beq` to 010001CE), the block
  RAM returns the OLD long (no write-through) while VALID and TAG, which are flip-flops/LUT RAM, already say hit.
  The decoder got `3F3C` (move.w #2,-(sp) from 010003CE, the previous tenant of slot C3) instead of `5888`, so SP
  slipped by 2 and the next rts faulted (EXC 2 frame 2704FFC6 0100A008 FFFF3005).
- Fix: a write-to-read forwarding register (FW_V/FW_IDX/FW_DATA) in front of HIT_DATA. RTL behaviour is
  unchanged; it holds for any RAM mapping. tt19 (71624aa): TTM1 caches on, I-only and D-only all pass.
- How it was found: RTL, gate-level reviews and STA all looked clean. A DIAG ring of the decoder word stream
  (Q_HEAD, opword, queue flags, I-cache index fields, ISP, cycle stamps) caught the wrong word and its exact index.
  Then the synthesis netlist (`.vg`) showed the DATA_RAM primitive.
- *Lessons:* the RTL simulation of an inferred RAM is not the hardware when synthesis may pick a block RAM: check
  the `.vg` for which primitive each array became (SDPB/DPB = synchronous read). For a write and a read of the same
  address in neighbouring clocks, either add forwarding or force distributed RAM explicitly. Alignment-dependent,
  layout-dependent, deterministic board failures that RTL cannot reproduce point at primitive semantics, not at
  timing.

## A false-by-opcode path can be the worst path: CHK2/CMP2 term carried the MOVEM F3 decision (22 Oct 2026)

- **Symptom.** tt20 worst setup path -4.887 ns, a half-cycle clk_cpu030_n[R] -> clk_cpu030[R] path (31.25 ns budget,
  36.085 ns data delay): `SLICE_CNT_N_2` -> `T_SLICE` -> `WR_EARLY` -> (F3_EARLY, ALU_BSY_M) -> `ALU_INIT`
  (fanout 393) -> `USE_DREG` -> `AR_IN_1` -> `ADR_MUX` -> `+BASE_DISPL` -> `ADR_EFF_VAR` -> `+ADR_OFFSET` ->
  `ADR_EFF_I_27`. About 19 LUT levels plus two 32-bit carry chains.
- **Cause.** `USE_DREG`'s CHK2/CMP2 arm used `ALU_INIT_I`, and `ALU_INIT_I` includes the [F3] MOVEM back-to-back term
  (`WR_EARLY`, valid only in the S3 half clock). OP cannot be MOVEM and CHK2/CMP2 at once, so the path can never
  carry a transition, but STA times it.
- **Fix [T7].** `ALU_INIT_C2`: the same function as `ALU_INIT_I` for CHK2/CMP2 (ALU_BSY = 0, INIT_EXEC_WB, no write
  fault, PHASE2), without the MOVEM term. No switch; behaviour identical (a clock-sampled simulation assert checks
  `ALU_INIT_C2 = ALU_INIT_I` whenever OP is CHK2/CMP2). New bench `prog_chk2.s` (CHK2/CMP2 coverage; none existed).
- **Lesson.** Before pipelining a failing path, read the netlist cell names along it and ask whether every leg can
  really be active in the same clock. A shared "init" strobe with a fast MOVEM term leaked into an unrelated
  opcode's address mux; giving that opcode its own strobe removes the path without changing a single cycle.

## Second false-by-opcode leg: UNLK's SP write carried NEXT_FETCH_STATE (22 Oct 2026)

- **Symptom.** After [T7], tt21 worst -1.010 ns, same half-cycle clk_cpu030_n -> clk_cpu030 shape: `DSACK_In_0` ->
  `WR_EARLY` -> `F3_EARLY` -> `MOVEM_PVAR` -> `NEXT_FETCH_STATE` -> `AR_WR_1` -> `AR_IN_1` -> `ADR_MUX` -> adders ->
  `ADR_EFF_I_26`.
- **Cause.** `AR_WR_I`'s UNLK arm tested `NEXT_FETCH_STATE /= SWITCH_STATE`, and NEXT_FETCH_STATE carries the MOVEM
  F3 decision. For UNLK, FETCH_DEC always goes SWITCH_STATE -> CALC_AEFF, so the term was constant '1'.
- **Fix [T8].** Drop the constant term. No switch, behaviour identical (clock-sampled sim assert that UNLK never
  stays in SWITCH_STATE).
- **Lesson.** Same as [T7]: a fast, late signal (here via the next-state decode) shared into an unrelated opcode's
  enable is a timing path even when it is logically constant there.

## Third half-cycle leg: CLK_F-sampled pins into WP_GO (22 Oct 2026)

- **Symptom.** tt23 (265e3fb, cartridge off) worst -1.203 ns, clk_cpu030_n -> clk_cpu030 half cycle:
  `HALT_In` -> `WR_EARLY` (3 LUTs) -> `F3_EARLY` -> `MOVEM_INH_WR` -> `NEXT_FETCH_STATE` -> `IPIPE_FLUSH` -> `PC_I` adder ->
  `PC_I_27`. tt22 had the same path at +2.879 ns; removing the cartridge only moved placement.
- **Cause.** `WP_GO` (= `WR_EARLY`) combined several flip flops clocked on CLK_F (`HALT_In`, `DSACK_In`, `STERM_In`,
  `BUS_FLT_N`, `SLICE_CNT_N` through `T_SLICE`) with CLK registers in about three LUT levels, all inside the half
  cycle before the rest of the [F3] MOVEM decision.
- **Fix [T9].** One CLK_F flip flop `WP_NEG` holds the S3 test and the pin terms, computed on the same edge from the
  same pins (SLICE_CNT_N <= SLICE_CNT_P there, and SLICE_CNT_P only changes on CLK). The redundant `WAITSTATES = '0'`
  term (implied by S3, DSACK, RESET_OUT_I = 0) is dropped. No switch, behaviour identical: a clock-sampled sim
  assert compares WP_GO with the original decode every clock; run_rtl PASS, cmp_full all progs x WS 0/1/2/3/7 SAME,
  movemx SAME.
- **Lesson.** In a half-cycle path, fold the negative-edge inputs into a single negative-edge flip flop at their
  source, so only one LUT level is left before the CLK-domain logic.

## TOS 2.06 hangs with TT-RAM: tagged exception vectors (22 Oct 2026)

- **Symptom.** tt24 (TTRAM) + plain TOS 2.06: static ATARI logo after the memory test, no bombs. tt24n (no TTRAM)
  boots to the desktop. EmuTOS is fine on both.
- **Bisection on the board.** Patched-ROM checkpoints (a stub fills the screen with stripes and halts) narrowed it:
  the ACSI/IDE boot loop is fine, AUTO is reached, and it hangs inside the first GEMDOS Pexec (`$E011F8`) before GEM.
- **Cause.** At `$E004E0`, TOS 2.06 fills vectors 2..63 with `$E010E2 + (n << 24)`. The bomb handler reads the
  vector number back from the high byte of the PC, which only works because a 68000 ignores A31:24. With TTRAM the
  bridge sent every A31:24 other than $00/$FF/$01 to a bus error. So the first exception taken through one of these
  vectors fetched `$nnE010E2`, which bus-errored, and vector 2 (`$02E010E2`) bus-errored again: an endless BERR loop.
  Without TTRAM the 24-bit wrap hides it.
- **Fix [T10].** Program-space cycles (FC 2/6) with A31:24 other than $01 take the ST side (24-bit wrap, as on a
  68000). Data cycles still bus-error, so TT-RAM sizing is unchanged: EmuTOS reads up from $01000000 until a BERR
  at $02000000, and IS_BUS32 uses $0100000C. No switch. ST timing is unchanged (the ST side ignores A31:24).
  prog_tt.s checks a jump to `$03E0xxxx` ($132C = 1) and the $02000000 data BERR ($131C = 1). run_rtl PASS; the
  core VHDL is unchanged.
- **Second tag [T10b].** With T10 the boot showed 2 bombs. A ROM stub that dumps the saved frame at the bomb exit
  gave PC = `$E00D80`, `movea.l (a0),a0`, in the BIOS/XBIOS trap dispatcher. Table entries with bit 31 set are
  indirect (for example `$80000472`), and the dispatcher reads them through that tagged address. So A31 = 1
  ($80..$FF) now always takes the ST side, and the data BERR is kept only for $02..$7F (TT-RAM sizing, TT_RING
  $7E). prog_tt.s also checks that a data read at `$80001330` returns ST `$1330` ($1334).
- **Lesson.** On a 32-bit bus behind 68000-era TOS, high-byte-tagged pointers are real (bomb vectors, $80
  BIOS indirections). Keep the 24-bit wrap for instruction fetches and for A31 = 1; bus-error only the data range
  that memory sizing probes. To bisect a silent hang, patch ROM checkpoints and dump the saved exception frame.

## TODO 9: blitter hang in the TOS VT52 scroll = RMC/BR deadlock in the bridge [T9b]

- **Symptom.** With Blitmode(1), the first TOS console scroll hung the machine hard, even at IPL 7, and a timer
  A watchdog never ran. The same blits from RAM code (scroll, clear, HOG font blits, back to back) always passed.
  Running TOS's own restart loop (`move.w d2,(a5)` / `tas (a5)` / `nop` / `bmi`, at $E06670) hung, which also
  reproduced in the full ST bench (`prog_scrom2.s`, exact TOS alignment: tas at 4n+2): no ST cycle after the
  prefetch at `$E000EC`.
- **Cause.** The WF68K30L asserts RMCn early, during the blitter start write and the prefetches before the TAS
  read. The blitter asserted BR right after the start write. The bridge then refused a grant (bg_block includes
  rmc_lock) and also refused to start the 030's next cycle (`bus_avail` needed BRi high). The 030 waited for
  its prefetch and the blitter waited for BG: a deadlock. From RAM the timing differed and the window was missed.
- **Fix.** `bus_avail = (BRi | rmc_lock) & BgackI & (arb == A_IDLE)`. While RMC is held, the 030 keeps the bus as
  a 68000 does through an RMC sequence, and BR is served once RMC is released. No switch. flash_dspi was checked
  and is not involved (no missed or short ROM selects in the bench).
- **Lesson.** Any arbiter that blocks the grant during a lock must not also block the lock holder: check both
  sides of every hold condition. A loop that hangs only from ROM points at timing, so reproduce it with the
  exact code and alignment.

## TODO 9 follow-up: cycle-correct RMC in the WF68K30L [RMC1]

- **Problem.** The control unit's `RMC` was high for the whole TAS/CAS/CAS2 instruction, and the bus interface
  drove `RMCn` and its own bus lock straight from it. RMCn went low on prefetches and on the previous
  instruction's writes, before the locked read, and the core refused BR there (the root of the [T9b] deadlock).
  The prefetcher also ran between the locked read and its write (`RD, PROG, PROG, WR` with RMCn low).
- **Change (bus_interface).** `RMC_PIN` drives RMCn, the BR hold in the bus controller and the arbiter:
  low from S0 of the first operand read while RMC is set, held through the reads and writes, and released
  after S5 of the write that matches the last locked read (`RMC_NR`/`RMC_NW` cycle counts; CAS2 = R R W W).
  If no write comes (failed compare), it is released when RMC drops. While the lock is held and writes are
  still owed, no opcode cycle may start (`PF_REQ`/`OPC_LEGACY` masked by `RMC_HOLD`). MC68030UM 7.6.
- **Latent race found (control).** Without a prefetch between read and write, CAS requested its write in
  the clock that ADR_EFF_WB is loaded (one clock after ADR_MARK_USED) and wrote to the previous instruction's
  address. CAS2 already had the fix ([C1] `CAS2_WGAP`); it now covers CAS too.
- **Checks.** GHDL bench, old core vs new, programs prog_* at 0/1/3 wait states: every log identical except
  prog_tas/prog_cas2/prog_dcache (the RMC programs), whose write sequences (address, size, data) are
  identical; RMCn falls with AS of the locked read and rises one half clock after AS of the last write.
  Full ST bench prog_scrom2 (exact TOS tas loop, blitter): completes (600DC0DE, 39 blits, same checksum),
  ~260 us sooner than before; identical trace with and without the [T9b] bridge change, so the deadlock
  window is gone in the core itself. The bridge change stays as a guard.
- **Lesson.** A pin that only means something per bus cycle must be derived from the bus cycle, not from the
  instruction state. Removing a cycle from a sequence can expose address/data races the cycle used to hide.

### Failed CAS/CAS2 compare: no write cycle [RMC2]

- **Rule.** MC68030UM 3.2.11 (Table 3-11: CAS "destination - Dc -> CC; if Z then Du -> destination") and
  7.3.3 (the RMW cycle "conditionally modifies the data ... and may write the data out to memory"; Fig. 7-29:
  no write -> negate RMC, unlock the bus). Only the MC68040 writes the operand back on a failed compare.
- **Bug found (alu).** The structure was already right (EXECUTE -> WRITEBACK on ALU_COND = false, and
  [RMC1] releases RMCn when RMC drops with no write owed), but `ALU_COND_I` for CAS had an unsized byte term:
  `OP = CAS and RESULT(7 downto 0) = 0`. A word or long CAS whose low bytes matched (e.g. mem $1234, Dc $5634)
  counted as equal: it wrote Du to memory and did not load Dc, while the CCR (full width) said Z = 0. prog_cas2
  case 7 hid it because Du happened to equal the memory value. Fix: the byte term tests `OP_SIZE = BYTE`.
- **Checks.** prog_cas2 case 8 (word CAS fails, low bytes equal: memory unchanged, Dc = memory, N C set) passes at
  WS 0/1/3/7; on dade512 it writes $9999. RMC windows (RMCMON) at WS 0/1/3/7: TAS RW x30; CAS ok RW, CAS fail R;
  CAS2 ok RRWW / RRRRWWWW, CAS2 fail RR; no PROG inside a window; after a failed compare RMCn rises before the
  next opcode cycle and RMC_LK/RMC_DONE/counters clear with RMC (no lock held over). Old (dade512) vs new full
  logs at WS 0/1/3: all prog_* identical except prog_cas2 (the failing-CAS write is gone, 4 cycles fewer).
- **Lesson.** Check a condition flag against the flag register it is meant to agree with: here Z and ALU_COND
  disagreed and nothing compared them.

## WF68K30L: CpID 0 (PMMU) F-line must be privileged; PMMU stage 1 (branch pmmu)
- Symptom: user-mode `$F0xx` (CpID 0, MMU) opcodes took Line-F (vector 11). MC68030UM p. 9-65 says every MMU
  instruction is privileged: in user mode they must take privilege violation (vector 8) first. Fixed unconditionally.
- Stage 1 PMMU adds PMOVE TC/TT0/TT1/MMUSR/CRP/SRP with manual masks (TC $83FFFFFF, TTx $FFFF8777,
  MMUSR $EE47, CRP/SRP $FFFF0003_FFFFFFF0). TT0/TT1 matches with CI=1 drive CIOUTn and block cache fills.
  No ATC or table walk yet: TC.E is stored but translation is identity. EmuTOS 1.4 (CONF_WITH_68030_PMMU)
  writes CRP/TC/TT0/TT1 with PMOVE abs.L at boot, so CRP/SRP had to be in stage 1. TOS 2.06 has no PMOVE.
- Lesson: PMOVE reuses the MOVES operand path; the R/W bit is ext-word bit 9 (not MOVES bit 11). Any mux keyed on the
  direction must check BIW_1(9), or data reads back as 0.

## WF68K30L: a TT cache-inhibited write must not touch the data cache (branch pmmu, e68e21f)
- Rule: MC68030UM 6.1.2 p6-8: "when CIOUT is asserted, the data cache is completely ignored, even on write
  cycles operating in the write-allocation mode". 6.1 p6-3: a read that hits the cache ignores the MMU, so CI bits only
  matter for accesses that go to the bus.
- Bug: stage 1 fed TT CI only into CIIN (fills). A write into a TT CI block still updated a hit, or allocated with
  CACR WA set. Fix: DC_WR_GO is gated by a TT CI match on the write's own address and FC. prog_pmmu case: write-allocate
  $1111, TT CI write $2222, the hit then reads stale $1111 (as the manual says), and $2222 after CD.
- Lesson for tests: after changing TTx/TC, clear the caches (CACR CI/CD) before timing a cache-inhibited region,
  or the old lines keep hitting (the first PMMUTEST board run "failed" this way).

## WF68K30L: MMU between the bus interface and the pins; a running cycle keeps its translation (branch pmmu, stage 2b)
- Design: `wf68k30L_mmu.vhd` (22-entry ATC, table walker) sits between the bus interface and the CPU pins. With TC.E = 0
  it is a plain wire, so every old sim program gives a byte-identical bus log (cmp_full.sh, all prog_*.s, WS 0 and 3).
- Bug found in sim (WS >= 3 only): the PMOVE to TC writes back while the next prefetch is already on the bus. TC.E going
  to 1 in the middle of that cycle switched the address mux and blocked the cycle half way, and the table walker then
  took the old cycle's DSACK as its own and read garbage descriptors. Fix: a cycle the pins already run keeps the
  translation (pass-through / physical page / CI) it started with until AS negates; only new cycles see the new TC,
  TTx or a flush. Same rule protects against PFLUSH/PMOVE flushes in the middle of a cycle.
- Bug: a write through a root-pointer page (CRP DT = 1, no descriptor in memory) stored an ATC entry with M = 0, so the
  retried write missed again (write + M = 0 must search) and the walker looped forever. Fix: the entry made by a write's
  search is marked modified. (The manual: the M bit in the ATC records that the page descriptor's M is already set.)
- Lesson for sims: a test that briefly enables TC (stage-1 prog_pmmu/prog_mmucfg) needs a valid root pointer once
  translation is real; they now load an identity CRP (DT = 1) first.
- Known deviation (core, not MMU): RTE does not rerun a faulted *write* (SSW DF); a faulted read is rerun. Demand paging
  of writes needs that; listed for stage 3.
- Bug (board, PMMUTEST pmmu3): PFLUSH/PLOAD/PTEST are decoded as an F-line LEA with the An write switched off. The data
  register write strobe is "on at every writeback unless an An write locks it out", so with the An write gone the
  instruction wrote its EA into Dn (d5 = $00029000 after `move.l (a1),d5; ptestr #5,(a1),#7`). Fix: the MMU LEA
  never writes a register; prog_pmop now checks a data register across a PTEST.
- Lesson: when an instruction borrows another's path and switches one write off, check every strobe that was keyed on
  the one you removed (here DR_WR_1 used AR_WR as its lock).
- Bug (sim, prog_xlate2): the walker checked a table's LIMIT only when the *next* table was long. MC68030UM 9.5.1.x: the
  limit belongs to the long descriptor (or root pointer) that points to the table, whatever that table's format. A long
  table descriptor with DT = 2 (short next table) ignored its limit. Fix: the check depends only on the limit coming from a
  long descriptor / root pointer (LIM_ON).
- Bug (sim, prog_xlate3, stage 3): the walker ORed bit 2 (WP) of *every* valid descriptor into the walk's WP, including an
  indirect descriptor. In an indirect descriptor bits 31-2 are the address of the page descriptor (MC68030UM 9.5.1.11/12,
  Figures 9-17 and 9-18), so a pointer such as $6906 made the page look write protected (PTEST gave W). Fix: only table and
  page descriptors add to WP (and S on long ones); prog_xlate3 has an indirect pointer with bit 2 set.
- Lesson: a descriptor field is only that field for the descriptor types that have it; check the DT before reading flags.
- Stage 3: RTE of a format $A frame now reads the SSW ($0A); with DF = 1 and RW = 0 it reads the fault address ($10)
  and the data output buffer ($18) and reruns the write with the SSW's FC and size before restoring PC and SR
  (MC68030UM 8.1.2, 8.2.1). Before this a demand-paging handler that fixed a page saw the faulted write lost.
  prog_df covers word, odd byte and long writes with the handler fixing WP and TC left on; prog_xlate's WP case now
  expects the rerun. Limits: format $B frames still restart (no rerun); a rerun that faults again takes a new bus error.
- Bug (review against the M68000PRM, stage 3): the decoder accepted PMOVE with (An)+ and -(An) for TC, TT0/TT1 and
  MMUSR. The 68030 PMOVE takes control alterable modes only (PRM pp. 6-48..6-50; MC68030UM 11.7.1 has no such form), so
  those encodings must take the F-line trap. Fix: decoder; sims rewritten to (An) + ADDQ; prog_pmmu and PMMUTEST T_prm
  check the F-line.
- Bug (same review): the MMU took PFLUSHA as mode 010; it is mode 001 ($2400, PRM p. 6-34). PFLUSHA still flushed every
  entry through the FC/mask path (mask 000), so only its 11.7.2 timing was wrong. Fix: mode 001.
- Lesson: check every encoding against the PRM's field tables, not against what the assembler happens to emit, and test
  the forms that must trap as well as the ones that work.
