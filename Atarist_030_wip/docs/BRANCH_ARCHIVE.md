# Archived unmerged branches (removed 9 Nov 2026)

David asked to drop the leftover topic branches once `speed` had been merged to `main`
(`80fbd90`, tag `bank-2026-11-09-f156`) and to keep a document of what each one held
instead of archive tags. The branches listed here were deleted after this file was
committed. Hashes below are the tips at deletion time (UK times).

`sdram64` (`dec654f`, 31 Oct 2026 22:01 UK) is documented on its own, in enough detail
to restart that work, in `SDRAM64_NOTES.md`. It is not repeated below.

Merged remotes `cmpm-fix`, `pmmu` and `sd-write` were ancestors of `main` and were
deleted without a section here. `speed` was deleted and recreated at the new `main`
head after these docs landed.

## bus-trace

- **Tip:** `236c0167f0269f697337c471dcba3e7162e5def7`, 16 Oct 2026 14:02 UK (BST).
  Four commits ahead of `9e27c24`.
- **Purpose:** observation-only 030-bridge bus counters (`DIAG_BUSTRACE`, default off)
  to see where GEMBENCH display-test time goes. Readout reused SD_WRITE_DEBUG's SDC
  command 9 (`sdwlog 64`); reading entry 0 freezes the counters, the last byte of
  entry 63 clears them. Build `build_st_helper_bt.tcl`.
- **Findings:** 128 x 32-bit counters in `cpu030_st_bridge.v` (clk_32), driven from
  existing request/phase/arbitration/DTACK state only. Simulation matched the bench's
  own "030 AS -> ST S0" histogram. Board build `2f2f3be` p3: clk_cpu030 20.901 MHz,
  clk32_core 34.912 MHz, TNS 0; flashed, cold boot to the desktop.
- **Board (EmuTOS 1.4, 16 Oct 2026):** VDI Graphics 26.105 s / 72% (82% of ST cycles
  were ROM, 84% program fetch, 1.39x a 68000's cycle count); GEM Dialog 79%; GEM Window
  80%; software Blitting 91%; VDI Text 99%; ROM Access 115%. Idle GEMBENCH window:
  70% of clocks had no 030 request (STOP). Request-to-slot wait averaged 0.01-0.06
  clk32; 91% of starts were back-to-back (S6->S0); 0.086 wait states per cycle.
- **Root cause of the display gap vs a real STE:** the 030 issues *more* ST cycles than
  a 68000 would (1.2-1.5x on the slow tests). Long ROM fetches split into two 16-bit ST
  cycles, and the prefetch queue overfetches past taken branches. Each extra fetch costs
  a full 500 ns slot. Slot alignment and arbitration were not the problem (<=2%).
  Blitter share was unmeasured (EmuTOS reported no blitter).
- **Ranked next steps from that analysis:** (1) fast ROM / MapROM from SDRAM or BRAM;
  VDI Graphics estimated 72% -> 150%+. (2) Instruction cache done properly. (3) Stop
  prefetch past taken branches (10-30% fewer fetch cycles). (4) RAM slot-alignment
  tweaks, <=2%. (5) Request-to-slot latency: nothing left.
- **Reuse:** the counter map and parse scripts (`docs/bustrace/`, `BUSTRACE.md` on the
  tip); the ranking above still explains why ROM-resident VDI/AES code is slow. I-cache
  and later prefetch-COF work on `main` already took steps 2 and part of 3.

## diag-trace

- **Tip:** `6eafce634a16c5ed8754f732e7c0377ba60361c8`, 9 Oct 2026 15:45 UK (BST).
  Five commits ahead of `10c1dab` (includes F62 / F62b / F62c, which later landed on
  `main`).
- **Purpose:** in-fabric `WF030_TRACE` capture (HDMI bit-dump of a trace ring) to
  diagnose the F62c JSR SP-writeback bug, plus tools to decode the dump.
- **What it added on top of F62:** `cpu030/trace/wf030_trace_cap.v` and
  `wf030_trace_view.v`, `build_trace.tcl`, observation-only DBG ports,
  `gao_decode.py` (HDMI frames -> trace ring) and `opcheck.py` (delivered opwords
  vs the TOS ROM). `prog_spwb.s` came from that diagnosis.
- **Results:** F62 itself is the opcode prefetch queue (aligned long fetches, write
  snoop, per-half faults). F62b fixed the TOS 2.06 UK vblank-sync loop at `E013F6`
  (4n+2): F62 had made it 24% slower than the old core (black screen at 60 Hz boot);
  F62b restarts the stream with a long fetch at the requested word (now 3% faster).
  F62c uses the decoder's `OPCODE_FLUSH` directly. F62d (later, on `main`) made JSR
  wait for a pending A7 writeback; that was the GEMBENCH menu-bar / Pexec wrapper
  crash (`ADDA.W #16,SP; JSR (d16,PC)` after RTE).
- **Reuse:** `gao_decode.py` / `opcheck.py` and the cap/view RTL if another HDMI
  bit-dump capture is needed. Do not replay the F62 HDL from this tip; `main` is newer.

## exact-handoff

- **Tip:** `1714a8d9cfec947742934c15a00967ae22275d49`, 19 Oct 2026 23:06 UK (BST).
  Three commits ahead of `7a5fe19`.
- **Purpose:** cycle-exact 68030 bus hand-off versus MC68030UM chapter 11 (after
  `fix1` was shelved for going *faster* than a 68030).
- **XH1:** `PF_REQ_RAW` requests the next prefetch long at `Q_CNT<=2` outside
  exception processing (was `<=1`). After an operand cycle the 4-word queue often
  held 2-3 words while the control unit drained it, so the bus idled (W->R 8 clocks,
  MOVEM.W read 10.5, push/pop 6.9 at WS0). XH1 cut those: W->R 24.34 -> 19.39,
  R->R 19.50 -> 16.00, push/pop 34.89 -> 28.00 at WS0. TRAP/RTE stayed about +14
  over the bound (exception handler drops DATA_WR/RD in the DATA_RDY clock). The
  I-cache-on case did not change (no idle to remove). `prog_stkflt.s` compares a
  fault-while-stacking.
- **Later on `main` (not unique to this tip):** XH1 was merged (`c37774b`);
  exact-combined + XH3 (mask the early long on a change-of-flow) and XT1-XT4
  (earlier exception stack / vector / RTE requests) continued in
  `Atarist_030_wip/docs/EXACT_HANDOFF.md`. Combining T6 + XH1 without XH3 made
  taken branches slower (bra.w 20 -> 28) because the extra long was fetched and
  thrown away; XH3 restored those. A T6+XH1 synthesis also missed the Fmax floor
  (clk_cpu030 18.45 MHz).
- **Reuse:** the UM-bound tables and the "do not prefetch an extra long during
  BUSY_EXH or across a decoded COF" rule. `prog_stkflt.s` is already on `main`.

## exact-handoff-xh2

- **Tip:** `f02bbef3dee3db90c467df8bdf2bd3f782259444`, 19 Oct 2026 23:05 UK (BST).
  Same XH1 base, plus XH2.
- **Purpose:** request exception stack writes, the vector read and the RTE frame
  reads one clock earlier (`wf68k30L_exception_handler.vhd`,
  `wf68k30L_address_registers.vhd`).
- **Board:** 2 of 6 cold boots halted (black on boots 4/5); XH1 was 6/6. Not
  accepted at the time. RTL did not reproduce it (candidates: an early request
  meeting floppy DMA arbitration, or another cycle's DATA_RDY during BUILD_STACK
  on the real ST bus). Later `EXACT_HANDOFF.md` on `main` notes that the black>=4/5
  halt rule also false-positived on capture dropouts after the desktop had appeared
  (seen on XH3 too), so XH2's "2/6" may have been the same artifact. XT3/XT4 on
  `main` reused the early vector / RTE-read idea more carefully (ISP precomputed,
  registered DATA_RDY).
- **Reuse:** the one-clock-early exception request idea, via the XT series already
  on `main`, not by replaying this tip. Treat a "halt" as unproven unless a later
  grab still shows the desktop gone and the helper is silent.

## fault-fixes

- **Tip:** `2a3287e276d5a8e37116bd08c803fdf543ef15e3`, 17 Oct 2026 12:00 UK (BST).
  Two doc-only commits ahead of `667fcca`. The RTL (FLT1/FLT2, `f045aa9`) had
  already been merged to `main` via `caches` (`e51475f`).
- **Purpose:** record the board test of the write-fault fixes. FLT1: no operand
  cycle after a data write fault (exception straight after the faulted cycle).
  FLT2: short frame `$A` when the write fault is the instruction's last bus cycle
  and the fetch side has not dirtied a register. `prog_fault.s` (7 cases).
- **Board (17 Oct 2026, `st_helper_hdn_flt_f045aa9_p3.fs`):** first cold boot and
  reloads 1-10 reached the desktop; reload 11 stayed black on 5/5 grabs (~50 s),
  helper serial went silent, and a following `c` stayed black. Rolled back to
  `oa_039c710`, which then passed 12/12 reloads (some slow boots, desktop still
  appeared, helper always `link OK`). The hard halt looked build-specific but was
  one event in 11 reloads. Fmax of the fault build: clk_cpu030 22.045 MHz,
  clk32_core 35.279 MHz.
- **Open then (still a design note):** stale `BUS_FLT` on a chained late BERR
  (P_SYNC copies BUS_FLT_N every DATA_C1C4 clock) was not changed.
- **Reuse:** the 11+ reload control test on a known-good bitstream before blaming
  a new core; FLT1/FLT2 themselves are on `main` (later refined by F131).

## fix-hiword

- **Tip:** `43733934e23f71d67473a35b591382a17e737bf6`, 12 Oct 2026 20:22 UK (BST).
  Two commits: `STKTEST.PRG` and `sim/st/prog_stk.s`.
- **Purpose:** hunt the board fault where the high word of a stacked long read
  back wrong (`$0005xxxx` -> `$0041xxxx`, an XOR of `$440000`), seen as a
  GEMBENCH frexp panic. Tests: recursion, MOVEM + LINK/UNLK, TRAP/RTE, a frexp
  mix; plus a >4 MB BERR check in the whole-ST bench.
- **Outcome:** the float-panic investigation later showed the GEMBENCH frexp
  failure was a corrupt `AUTOFPU.BIN` on `gb403.st` (merged via `fix-float-hiword`,
  `FLOAT_PANIC.md` on `main`). The stack-integrity program itself never became a
  core fix.
- **Reuse:** `stktest.s` / `prog_stk.s` if a stack long-word integrity check is
  needed again. Do not treat `$440000` as an open CPU bug unless it reappears on a
  known-good image.

## fix1-write-handoff

- **Tip:** `f44934b359818e39c8641c3baf4d3ea53c95cbd7`, 19 Oct 2026 20:49 UK (BST).
  Two commits (fix1, then fix1d).
- **Purpose:** write hand-off (W->R and W->W) to the next instruction, taking a
  posted write's outcome in its S3 clock (`WR_GEN` from `WR_EARLY`), the same idea
  as F3's back-to-back MOVEM writes. W->R chaining only on a valid D-cache miss
  lookup (write-allocate entries exist even behind CIIN). fix1d: uses that do not
  need the early hand-off still see `WR_GEN` one clock later (`WR_GEN_D` /
  `DATA_RDY_L`, Fmax); W->R chain uses this clock's D-cache miss lookup; `WP_GO`
  pin terms come from one CLK_F flop. Local fix1d reported clk_cpu030 20.8 MHz.
- **Why it was shelved:** it removed idle clocks after writes but made RMW,
  `move (An)+,(An)+`, `bclr #,(An)` and `d16->d16` *faster* than a 68030
  (ST-model 83-100% vs a 73-83% estimate). The goal became cycle-exact chapter 11
  timing (Falcon/DSP), not "as fast as possible". Work moved to `exact-handoff`.
- **Reuse:** the rule that a W->R chain must consult the D-cache; keep early
  `WR_GEN` off the Fmax-critical uses (the fix1d split). Do not merge the raw
  "always hand off the next write" behaviour without a chapter 11 pad.

## prefetch-cof-qg

- **Tip:** `a263bf0f8edda7f4e887703f4a31788d28a6ed59`, 16 Oct 2026 21:38 UK (BST).
  Three commits off `prefetch-cof-vchain` (`db04754`).
- **Purpose:** step 3 of the prefetch change-of-flow work: gate the prefetch
  queue at *real* opcode positions (instruction-length tracking), not just a
  simple unconditional-COF predecode.
- **Design:** `NXT_OP` / `NXT_KNOWN` in the decoder track where the next operation
  word sits (`OP_LEN` of the word the control unit takes, minus `INSTR_LVL`, then
  decremented per extension; 0 after a flush). `OP_LEN` covers the common
  integer ops and brief-format EA extensions; anything unknown returns 0 and
  stops the look-ahead. `P_COF_Q` walks up to 4 operations from that point and
  holds on an unconditional COF whose words are all queued. Bcc/DBcc are not
  predicted. Hold when a COF is known to be next, not "hold until known not to
  be" (that would stall on every uncovered opcode).
- **Results:** run_rtl PASS; benches essentially the same as step 1 (prog_cof
  2227 -> 2166 cycles vs main 2227 / step 1 2167; prog_bus 10101 -> 10099). The
  leftover "words past the COF" are mostly the second half of the long that holds
  the COF's last word (a real 030 fetches that long too) and fetches already
  started. p3 `e77df9d`: clk_cpu030 **17.168 MHz** (62 logic levels; main at the
  time 20.901, step 1 20.711), about 7% headroom. **Not flashed.**
- **Sibling that did merge:** vchain (`db04754`) — 10 reloads, 3 warm resets,
  GEMBENCH 89/251/132 (= the then reference). Step 1 alone and step 2 without
  vchain were superseded; do not flash them (step 1 had reload halts attributed
  to gating `PF_CHAIN_GO` at the S5 decision).
- **Reuse:** only with a registered / pipelined length walk if 030-faithful
  queue gating is wanted. The cycle win on the existing benches is ~zero.

## rmw-timing

- **Tip:** `fab03442a57c1ce0d7f8adbf0182d32406c25c86`, 20 Oct 2026 17:53 UK (BST).
  Two commits.
- **Purpose:** RMW1 — start RMW memory forms in the operand `RD_RDY` clock
  (`RMW_EARLY`) instead of going through `INIT_EXEC_WB`: one clock less between
  the read and the write. Covers ADDQ/SUBQ/ADDI-class memory ops, ADD/AND/OR/EOR
  Dn,<ea>, BCHG/BCLR/BSET memory, and memory shifts. Gated on `DATA_VALID`, ALU
  idle, no pending write fault and the data register free; the ALU operand buffer
  forwards the value loaded in the same clock as `ALU_INIT`. 17 audit tests
  became faster; none went below the MC68030UM worst column (`audit/gap.py`).
- **Board:** first note (1186f04) was 4/5 cold boots to the desktop (boot 2
  black) and said do not merge. The tip supersedes that: 10/10 cold boots on a
  final desktop check (the earlier single black final was a capture-device
  fault). GEMBENCH 6.08 46/175/90 and 4.03 91/225/127, equal to the then
  frame-fix. clk_cpu030 Fmax 19.34 MHz (frame-fix 23.43). Never merged; later
  timing work preferred explicit chapter 11 padding over this -1 clock.
- **Reuse:** `RMW_EARLY` / `INIT_LIKE` in `wf68k30L_control.vhd` if the issue
  loop still has a spare clock on those forms and the audit still says they are
  not below the manual. Re-check Fmax; it cost about 4 MHz on that tree.

## speed-wip

- **Tip:** `510e03405cccfeb8a2d2de2a038554ba6237fcb7`, 4 Nov 2026 04:40 UK (GMT).
  Two commits (a stash-style "On speed: F143 WIP" plus the index note). Off
  `716b420`.
- **Purpose:** parking F143 while it was still under regression: F141 early
  issue (`EARLY_OW` in `INIT_EXEC_WB` for register-only ops) disabled via
  `EARLY_ISSUE := false` after the F142 board build reached the desktop but no
  AUTO program (TTRAM.PRG, LOOPTEST.PRG) would run. The MOVEQ hazard change was
  kept. Sim had not reproduced the AUTO failure.
- **Superseded:** F143 was finished on `speed` the same day and is on `main`
  (see `SPEED_OVERHAUL.md`). The later board bisect found the real F141/F143
  fault in ADDQ/SUBQ #,An, not in this WIP tree. F144 and on continued from the
  completed F143, not from `speed-wip`.
- **Reuse:** nothing from this tip. Use `SPEED_OVERHAUL.md` on `main`.

## tidy-build-scripts

- **Tip:** `08021c3e5dafc1e919e70be8029d09d4bad1443b`, 20 Oct 2026 10:00 UK (BST).
  Fourteen commits that moved legacy/debug `build_st_helper_*.tcl` and
  `build_ae350_serial.tcl` into `Atarist_030_wip/build_legacy/`, updated
  `BUILD.md` and a few handoff paths, then deleted the old locations.
- **Outcome:** `main` already has `Atarist_030_wip/build_legacy/` with those
  scripts. This branch was leftover housekeeping after that move.
- **Reuse:** none. Follow `BUILD.md` on `main`.

## trace-f120

- **Tip:** `23b444e0989d6317636f857b8eb338ef4a84638d`, 31 Oct 2026 21:08 UK (GMT).
  One commit off `dd24508` (F121). Explicitly "not for main".
- **Purpose:** diagnostic capture used to hunt the F117-F120 MiNT/XaAES/TeraDesk
  faults (the F121 immediate-as-extension-word bug). Defines stacked in
  `cpu030_st_bridge.v` / `atarist.v` / `sd_card.v`:
  - `PC_SAMPLE` (F111): 030 register snapshot every 2^19 clk_cpu (~33 ms), SDC
    commands 10/11.
  - `BYTE_CAP` / `FAULT_CAP` (F115): last 32 data bus cycles (no program fetches,
    no CPU space) up to the first vector-2 exception with a MiNT handler.
  - `BR_TRACE` / `BR_TRACE2` (F119/F120): 2048-entry BRAM ring of `{from PC, to
    PC}` for non-sequential PC changes. Armed at the first user-mode PC in
    TeraDesk text (`$0002A000-$000CFFFF` on F120j; earlier F120b used
    `$000A0000-$000CFFFF`), then frozen by `fc_hit` / `fc_hit3` (vector-2 with
    the MiNT handler fingerprint). Read with repeated `sdwlog 64` (one byte per
    2^17 clk, oldest first).
- **Results:** these rings were how F117-F120 were captured; the actual fix is
  F121 on `main` (`dd24508`). The capture RTL was never meant to ship.
- **Reuse:** the arm-after-TeraDesk and `fc_hit` trigger ideas if a similar
  user-mode fault needs a branch ring again. Keep it behind a define and off
  the default build.

## trace-linux

- **Tip:** `aa2b6edc325af08ee0d9b893ddff5e86298b4ee9`, 2 Nov 2026 16:29 UK (GMT).
  Four commits (includes the f120k capture, then `LINUX_TRACE`). Off `92cbe18`.
  Also "not for main".
- **Purpose:** a 2048-entry ring of branches, exceptions, chipset I/O and BERR
  while Linux boots, armed when the PMMU is enabled, streamed the same way as
  `BR_TRACE2`.
- **Revisions worth remembering:**
  - First cut: arm at PMMU enable; freeze on halt, a "bad" vector, or ~16 s.
  - lt1: arm only when `TC.E` rises with PC already in TT-RAM (otherwise TOS
    2.06's own PMMU init armed it too early).
  - lt3: do **not** treat vector 4 as a trigger (NatFeats `nf_get_id_phys` is an
    expected illegal instruction); filter I/O as `$FFFFxxxx` only (not any
    `$xxFFxxxx`); timeout ~67 s (`2^31` clocks) so the ring lasts through a
    long Linux boot.
  - Record format (64-bit entries): branch `{from,to}`; `EC` exception
    `{vector, SR, PC}`; `EF` fault address after a vector 2/3 `EC`; `EE`/`ED`
    write/read of chipset I/O; `EB` any BERR cycle. Loop-squash skips a branch
    pair equal to one of the last four.
- **Reuse:** lt3's arm/trigger rules if Linux boot has to be traced again.
  Linux on F156 no longer needs this ring for the old F122-F131 class of bugs.

## warm-reset

- **Tip:** `65e8b32e8416207368b6dd3816c0503af903c818`, 15 Oct 2026 22:27 UK (BST).
  Ten commits. The long note is `RESET_PATHS.md` on that tip (not copied onto
  `main`). **These F67/F68 numbers are the October reset-filter work, not the
  later F67/F68 IDs reused on `main` for unrelated MMU/fill changes.**
- **Purpose:** TOS/EmuTOS "System halted!" on reload / warm reset. Compare our
  RESET/HALT wiring with a real STE (C300780) and the TF534.
- **Design notes:** on a real STE the RESET instruction pulls only XRESET (124
  clocks) and does **not** reset the CPU (XHALT is not driven). Our 030 sits on
  the ST RESET+HALT pair, like the TF534. Upstream `RESET_FILTER` ignored
  `RESET_IN` during the 512-clock `RESET_OUT`, so an ST reset arriving during
  EmuTOS's early RESET (the cold-start second pulse) was lost.
  - **F67:** honour external RESET+HALT even while RESET_OUT is running
    (`prog_wreset.s`; run_rtl PASS).
  - **F68:** clear `RESET_TIMER` when `RESET_CPU` asserts, so RESET_OUT does
    not run on into the next boot (on F67 alone, RESET_OUT stayed high ~46 us
    after RESET_INn released). run_rtl PASS.
  - **ST_DR_PRECPU:** fire the cold-start second chipset reset 64 clk_32 after
    the first release, while the 030 is still held, so the chipset is reset
    twice but the CPU is released once (`run_dr_gap.sh` PASS).
- **Board:**
  - F67 alone: almost every reload / `w` / extra `c` halted. Rollback to F66
    after a halt could itself halt until a `c` — that was **stale SDRAM**:
    contents survive an FPGA reload, `ram_scramble` goes back to 0, and EmuTOS
    sees valid memvalid words and takes the warm path through the previous
    crash. Always `c` (or power cycle) after a failing reset experiment.
  - F67+F68: `c` desktop; reloads r1-r7 desktop; r8-r10 halted; following `w`
    sticky-halted.
  - F67+F68+DR_PRECPU: r1-r9 desktop, r10 halted, then `w` sticky. Rate better
    (1/10 vs 3/10) but F66 still did 10/10.
  - DIAG_OVERLAY builds of F67+F68 (19c97b2, 60127c0): 21 reloads, **no**
    "System halted!". Counted "halts" were completely black 1080p frames
    (capture loss — the overlay is generated by the HDMI path even if the CPU
    has stopped). Good-boot overlay: row b = `DA000073` (cmdload 0, EXEC /
    P1RET / AES / E0ROM / CMDRD), memvalid magics `7520`/`2376` after reload
    or `w`, zeros after `c`. Overlay Fmax was higher (clk32_core 32.68 vs
    32.04 MHz), so the remaining halt was thought to be **timing-dependent**,
    not a pure reset-path logic error. A place/seed sweep of the plain F67+F68
    build was the suggested next step and was not done.
- **Reuse:** `RESET_PATHS.md`'s STE vs TF534 vs our bridge table; `prog_wreset.s`
  and `run_dr_gap.sh`; the overlay decode (`dec.py` / `DIAG_OVERLAY.md`); the
  rule that a black grab is not a halt if the overlay (or a later grab) still
  shows a desktop. F67+F68 were rolled back to F66 on the board and never merged.
