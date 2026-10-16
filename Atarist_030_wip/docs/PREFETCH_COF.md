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
- Whole-ST bench (netlist, DIAG_BUSTRACE counters, prog_bus.s in ROM): 10101 -> 10085 ST cycles but
  6.808 -> 7.103 ms (+4.3%) - slower. The hold is only up 1-2 clocks (SLEEP of the branch), far too late:
  the words past the branch were fetched long before (decoder pipe 3 words + queue up to 3 + in-flight
  long), and a hold that coincides with the S3 arm of the prefetch-to-prefetch chain loses a 250 ns slot.
- Potential (trace analysis, docs/prefetch_cof/waste.py): in prog_bus 1973 of 10101 ST cycles (19.5%)
  are instruction words fetched past a change of flow and thrown away.
- Next: stop the look-ahead earlier (COF detected in the decoder pipe / shallower queue), see below.
