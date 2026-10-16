# Prefetch at change of flow (TODO item 2)

Branch `prefetch-cof` (off main 9e27c24). Unconditional correctness/behaviour fix, no build switch.

## What a real 68030 does
- MC68030 UM §1.8/§11.2: three-word instruction pipe (stages B, C, D) fed by long-word prefetches through
  the instruction fetch pending buffer; operand accesses have priority over prefetches. A change of flow
  (Bcc taken, BRA, BSR, DBcc taken, JMP, JSR, RTS/RTD/RTR, RTE, traps, SR writes) flushes the pipe and the
  refill starts at the target; the UM timing tables for taken branches/jumps count only the target refill.
- The same Motorola pipeline description (CPU32 / MC68340 UM §5.7.1.3, which documents the shared
  M68000-family prefetch controller in more detail) states it explicitly: "the instruction pipeline is
  capable of recognizing instructions that cause a change of flow. It informs the bus controller when a
  change of flow is imminent, and the bus controller refrains from starting prefetches that would be
  discarded", and "will schedule a prefetch only when the next instruction is not a change-of-flow
  instruction". Words that are already on the bus when the change is known are still completed.
- On a 16-bit port (the ST bus) every long prefetch is two 500 ns ST cycles, so each useless prefetch
  costs 1 us.

## What the core does now (F62 prefetch queue, `wf68k30L_bus_interface.vhd` P_QUEUE)
- The queue fetches the stream eagerly (PF_REQ: stream valid, nothing in flight, Q_CNT <= 1) whenever the
  bus is free, plus the decoder's own look-ahead requests (IPIPE fill to 3 words) go through the same path.
- Nothing tells it a branch is executing: while the control unit executes BRA/Bcc/JSR/RTS... (between
  START_OP and the IPIPE_FLUSH) the queue keeps starting long fetches past the instruction. An in-flight
  fetch must finish before the target fetch can start (INFL_STALE just discards the data), so a branch
  typically costs 1-2 extra long fetches = 2-4 ST cycles (1-2 us) on top of the refill.
- Bus trace (docs/BUSTRACE.md): the 030 issues 1.2-1.5x the ST cycles of a 68000 on the slow display
  tests, 72-87% of them program fetches.

## Change
- Control unit output COF_PEND: the executing instruction is a change of flow that will be taken and no
  further instruction-stream words are needed by it: OP in {BRA, BSR, JMP, JSR, RTS, RTD, RTR}, Bcc with
  the condition true, DBcc with the condition false (not in loop mode), in the fetch states after the
  extension words are consumed (INIT_EXEC_WB, SLEEP, FETCH_OPERAND, SWITCH_STATE).
- Bus interface: PF_REQ and the F65 prefetch-to-prefetch chain are held off while COF_PEND = 1. Demand
  and look-ahead fetches share PF_REQ, so no stream word past the branch is started. A decoder request
  left pending is dismissed by the existing OPCODE_FLUSH/Q_DUMMY path at the flush.
- Safety: COF_PEND only blocks starting *instruction* fetches; operand cycles are untouched, and the
  control unit never waits for the decoder in those states, so it cannot deadlock. A wrong COF_PEND changes timing only, never results.

## Status / measurements (in progress)
- Step 1 (commit 833183b): control-unit hold (COF_PEND -> decoder PF_HOLD, registered; lifted by any
  operation/extension word wait, exceptions, loop mode, the flush). RTL: all cmp_wr programs give the same
  writes as main; run_rtl PASS. Gains 2-9% on call/return-heavy RTL programs (prog_pushrts -8..-10%,
  prog_spwb -7%, prog_branch -2..-3%).
- Whole-ST bench (netlist with FAST_HANDOFF=1 as on the board, DIAG_BUSTRACE bridge). An earlier run that
  showed +4..13% was invalid: the new netlist had FAST_HANDOFF=0 (see FALCON_LESSONS; wf030_syn.tcl fixed).
  | program | main 9e27c24 | step 1 (833183b) |
  |---|---|---|
  | prog_bus.s (dbra loops, ROM) | 10101 ST cycles, 6.808 ms | 10101, 6.808 ms (unchanged) |
  | prog_cof.s (bsr/rts/jsr/jmp table/Bcc, ROM) | 2227, 1.185 ms | 2167 (-2.7%), 1.164 ms (-1.8%) |
  Results (R1000 words) identical. Words fetched past a change of flow in prog_cof: 337 -> 291.
- Variants tried (same benches): A = also detect BRA/BSR/RTS/RTE/RTR/RTD/JMP (An)/JSR (An)/DBF at the head
  of the decoder pipe; B = eager queue prefetch only when the queue is empty (Q_CNT = 0). Both gave exactly
  the step-1 numbers on prog_cof (B: 10099 cycles on prog_bus, same time), so step 1 is kept as the
  simplest form. The remaining waste happens before the branch reaches the pipe head: the long fetch that
  carries the branch's last word also brings the next word, and the queue starts the following long while
  the branch is still behind the running instruction.
- Potential (trace analysis, docs/prefetch_cof/waste.py): in prog_bus 1973 of 10101 ST cycles (19.5%)
  are instruction words fetched past a change of flow and thrown away.
- Timing (p3, hdn build): clk_cpu030 20.711 MHz (constraint 16 MHz; main 20.901), clk32 36.031 MHz, TNS 0.

## Board test of step 1 (st_helper_hdn_pfcof_833183b_p3.fs, sha256 e8ea0de2..., 16 Oct 15:48-16:10 BST)
- op 53 at 4193 after cable rescan, flash ended 0x04B9D00, core/reload rc 0.
- `c` cold boot: desktop. Reloads r1-r5: desktop. **r6-r10: "System halted!"** right after the
  ST_HELPER mailbox self-test line ("-- mailbox test done, TOS continues --"), every reload.
  A `c` cold boot afterwards reached the desktop again. Warm resets and GEMBENCH not run.
- The same sequence on de35f5f (posted writes, main) gave 10/10 reloads + 3/3 warm resets. Treated as a
  failure of step 1: rolled back to st_helper_hdn_ph2wp_de35f5f_p3.fs. Cause not yet known (EmuTOS
  halts after an unexpected exception; the mailbox code runs in cartridge ROM space).

## Step 2 (predecode of pipe + queue), 2026-10-16 evening — WIP, not flashed
Decoder scans IPIPE D,C,B + queue W0..3 (exported Q_STREAM/Q_COUNT) for a complete COF opcode
(RTS/RTE/RTR/RTD, JMP/JSR (An)/d16(An)/abs/d16(PC), BRA/BSR, backward Bcc.B; DBcc excluded) and ORs
it into the registered PF_HOLD (PF_DEMAND still lifts it, so no deadlock; results cannot change).
RTL cmp_wr, writes all SAME vs main:

| prog | WS | main | step2 |
|---|---|---|---|
| prog_loop | 3 | 31608 | 35309 (+11.7%) (with DBcc: 37773) |
| prog_branch | 3 | 8518 | 8349 |
| prog_pushrts | 3 | 67863 | 62946 |
| prog_gap | 3 | 3848 | 3834 |

prog_loop regression is the open problem (likely hold active on stale stream words in the cycle
after a flush, or backward Bcc predicted taken in loop bodies). Not synthesized/flashed: step 1's
board halt on reloads is still unexplained and step 2 uses the same hold path.

## Step 2 rev 2 + step 1 halt investigation (16:15-16:50 UK)
- de35f5f reload control: 8/8 reloads reached the desktop (ctl.log). The reload halt is specific to step 1 (833183b).
- prog_loop slowdown cause: `bne.s l0` (backward, NOT taken in the loop) was predecoded as a COF and held the
  fetch of the following `dbf`. Fix: predecode only unconditional COF (BRA/BSR/JMP/JSR/RTS/RTE/RTR/RTD); Bcc and DBcc are
  left to step 1's execution-stage hold (no branch prediction, as on a real 030). prog_loop WS3 31608 -> 31613.
- Hold also gated with EXH_REQ='0' (an exception waiting in IDLE for BUSY_OPD needs the pipe filled). A sim probe
  (report when the hold would be set with EXH_REQ=1) fired 0 times for step-1 conditions over trapirq/berrwb/linea/
  wpberr/srmask_a/pushrts, and once for COF_Q (linea, PNTR=2, harmless). So it is a safety guard, NOT the proven cause.
- Step 1 halt root cause: NOT found. Not reproduced in RTL sims. Candidates left: PF_CHAIN_GO gating mid-handoff
  in the netlist, hold vs in-flight prefetch bus-error/retry. No flash done (rule: flash only once the cause is fixed).
- Regression rev 2: run_rtl PASS. cmp_wr prog_branch WS=1 DIFF: only the two internal words of a bus-error
  stack frame at $7FD0 (pipe stage contents 41FA00F2 vs 43F86000), i.e. which words were prefetched; the program
  results match expect_branch. Implementation-internal frame state, timing-dependent.

## Regression finish / boot sim / board narrowing (from 16:47 UK)
- Whole-ST boot sim with pre-filled RAM: not run. Icarus with the netlist runs prog_bus (6.8 ms ST time)
  in about 8 min; TOS boot to the ST_HELPER mailbox self-test is about 1-2 s ST time, i.e. 20+ hours per run.
  Going to the approved board narrowing test instead.
- Code review: every FSM/queue use of the S5 handoff is PF_CHAIN_GO (PF_CHAIN only arms), so a hold rising
  between S3 and S5 takes the plain IDLE path in RTL. Variant "vchain": PF_HOLD removed from PF_CHAIN_GO only.
- Regression rev 2 complete: run_rtl PASS; cmp_wr all SAME except prog_branch WS1 (accepted frame words);
  prog_linea WS7 "DIFF/no DONE" was a GHDL re-analysis error from touching sources mid-run, re-run SAME (19330 -> 18531);
  prog_fpuprobe/fpbr time out identically on main and new (as before).
- p3 8ed3aec: clk_cpu030 18.442 MHz (16 constraint), clk32 33.915, TNS 0. BUT the timer lists a derived clock
  "IPIPE_PNTR[1]": P_COF_Q inferred latches (variable S not assigned on all paths). Fixed (S cleared first) before any flash;
  8ed3aec bitstream discarded.
- 17:19 UK p3 builds of 04a79d6 (step 2, no latch) and db04754 (vchain) died: "License verification failed, server
  not responding". Restarted 17:38 UK (setsid nohup, sequential). Board untouched: still de35f5f (no test flash done yet).

## Board narrowing (18:00-18:40 UK)
- 04a79d6 (step 2, no latch) flashed 17:54 UK (op 53 @4193, ends 0x04B5F00, rc 0), c cold boot DESK.
  Reloads: r1-r4 DESK, r5 not captured (grab failed on network), r6-r10 DESK, r11 BLACK screen (no video after 5
  grabs over ~40 s), r12 DESK; warm resets w1-w3 DESK. NOT clean: 1 failure in 11 seen reloads (step 1: r6-r10 halted).
  p3 timing of this build not captured (worktree reused by the next build before reading the report).
- db04754 (vchain, PF_HOLD not applied to PF_CHAIN_GO) built 18:02 UK; flashing next.
- db04754 (vchain) flashed 18:28 UK (ends 0x04B2100, rc 0). c cold boot DESK; reloads v1-v3 DESK. Stopped after 3
  (time box; the screen grabs over the SOCKS link were slow). Not enough reloads to call it clean or not.
- Restored de35f5f at 18:47 UK + c cold boot (see the report). Next: finish 10 reloads on vchain; if clean, PF_CHAIN_GO
  gating is implicated (step 1 also gated it). Step 2's single BLACK reload (r11) has to be reproduced first.
- 18:47 UK de35f5f restored (ends 0x04B2100, core/reload rc 0); helper link OK (core status 5C 42). Two c cold boots,
  but the HDMI capture returns all-black frames (6 KB png) for >3 min, on the known-good de35f5f too. So the capture
  or HDMI link can go black on its own, and step 2's r11 BLACK is NOT proof of a CPU halt. Desktop on de35f5f not yet
  visually confirmed.

## Board run 3 (from 20:00 UK, after the capture/USB recovery)
- Capture check: de35f5f and 5246d00 both show the desktop; single black grabs occur on all builds (capture glitch).
  Halt criterion now: 5 grabs over ~40 s all non-desktop.
- vchain db04754 flashed 20:01 UK (sha f9f3742a..., ends 0x04B2100, rc 0). c DESK; reloads r1-r3, r5-r10 DESK
  (r10 on the 2nd grab); r4 not captured (every ssh grab failed for ~10 min, an empty png, not a black frame).
  No "System halted!". Step 1 halted on r6-r10 with the same procedure, so the hold at the S5 handoff decision
  (PF_CHAIN_GO) is the prime suspect for the step 1 halt. vchain is also the more 030-correct variant (a handoff
  decided at S3 completes).
- Next: 3 warm resets + GEMBENCH on vchain; then queue gating (see below).
