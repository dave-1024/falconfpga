# CPU rework phase 2: the next bus cycle straight after S5

Branch `cpu-phase2` (from `main` 4d0157d), 16 Oct 2026. Tag in the code: `[PH2]`.
WF68K30L by Wolfgang Foerster (CERN OHL v1.2); headers and revision blocks kept, PH2 lines added.

## 1. The handoff before phase 2

Bus interface FSM (`wf68k30L_bus_interface.vhd`): `IDLE -> START_CYCLE -> DATA_C1C4`, T_SLICE S0..S5
(two slices per clk_cpu, the odd ones on CLK_F). At the S5 edge of the last portion the FSM returns to IDLE.

- `wf68k30L_top.vhd` P_BUSREQ: RD_REQ/WR_REQ/OPCODE_REQ are masked while BUS_BSY = 1, and ADR_LATCH/FC_LATCH only
  load while BUS_BSY = 0. A request that is already waiting when a cycle ends must therefore pass IDLE (latch, see it)
  and START_CYCLE (latch ACCESSTYPE, SIZE_N, SSW_80, WP_BUFFER, AERR, PF_START) before S0: **2 idle clk_cpu**.
- DATA_RDY is registered on the S5 edge, so the control unit only issues its next operand request after the cycle.
- F65 (`WF030_FAST_HANDOFF`, on in the board builds) already rolls a queue prefetch S5 into the next prefetch S0.

Measured with the new gap monitor (tb030 `GAPLOG`, `sim/rtl/gap.sh prog_gap`): clock edges with AS negated between
two cycles. 1 = back to back (only the S5 half), each idle clk_cpu adds 1.

| transition | old (main) | phase 2 |
|---|---|---|
| prefetch -> prefetch (request waiting) | 1 (F65) | 1 |
| prefetch -> operand (operand request waiting) | **3** (2 idle clocks) | **1** |
| operand -> prefetch (queue prefetch waiting) | **3** | **1** |
| operand -> operand | 5..29 | 5..29 (unchanged, see 5) |
| halves of one long/misaligned operand | 1 | 1 |

(prog_gap at WS 0 and 3; histograms in section 6.)

## 2. What the 68030 does (MC68030UM ch. 7)

- 7.3.1/7.3.2 asynchronous read/write: AS asserted S0/S1 to S5-ish; DSACKx sampled on the falling edge of S2 (wait
  states inserted in pairs until seen), data latched at the end of S4; AS/DS negated in S5. The processor
  begins the next cycle's S0 directly after S5 when the bus controller has a request pending; between cycles AS is
  negated for about one clock (spec #13/#14). Here it is one half clock (S5), as with F65.
- 7.3.x synchronous (STERM) cycles: two-clock cycles, same back-to-back rule. Not used on the ST bus.
- Back-to-back and prefetch/operand overlap: the 68030 bus controller is decoupled from the sequencer; the instruction
  pipe and the operand requests compete for the bus controller, which starts whichever is pending at the end of S5.
  Operand requests have priority; a prefetch that is already running is completed first.
- Dynamic bus sizing (7.2): the portions of one operand already run back to back (unchanged here).
- 7.5 bus exceptions: BERR terminates with an exception, BERR+HALT is a retry (rerun the cycle), HALT alone stops
  the bus between cycles. A new cycle must not start while HALT is asserted.
- 7.6/7.7 arbitration: BR is granted between cycles (not during RMC). A chained start would skip the grant point,
  so chaining is suppressed when BR/BGACK is active.
- 7.3.4 read-modify-write (TAS, CAS, CAS2): RMC locked, no arbitration inside; chaining is not used while RMC = 1,
  the locked sequence keeps its old path.

## 3. The change (unconditional, a 68030 bus-timing correctness fix)

Two new S5 decisions in the bus interface, next to F65's PF_CHAIN/PF_CHAIN_GO and built the same way (armed by a
register at S3, confirmed with the live conditions on the S5 edge):

1. **OP_CHAIN** (prefetch -> operand): a queue prefetch ends while the control unit holds an operand request
   (`OP_RD`/`OP_WR`, the live DATA_RD/DATA_WR that P_BUSREQ masks). On the S5 edge the FSM stays in DATA_C1C4 and
   loads what START_CYCLE would have: READ_/WRITE_ACCESS (read first, as START_CYCLE), PF_ACC/OPCODE_ACCESS = 0,
   SIZE_N from OP_SIZE, SSW_80 (FC from the new FC_NXT), WP_BUFFER = DATA_FROM_CORE, ADR_OFFSET = 0,
   DSACK_MEM = 11, OCS_INH = 0, RDY_VAR = 1, and the queue flush when a write hits the queued words (`WDIST2`).
   The top level loads ADR_LATCH/FC_LATCH from the unmasked request address (`ADR_NXT`, `FC_NXT`) on the strobe
   `OP_CHAIN_LD`, so ADR_IN_P carries the operand address from S0.
2. **DP_CHAIN** (operand -> prefetch): an operand cycle ends while a queue prefetch is due (PF_REQ). The old IDLE
   clock would have started that same prefetch (the control unit drops its request in the DATA_RDY clock), so the
   bus order is unchanged and only the two idle clocks go. On the edge the queue does what PF_START does (INFL,
   F_CUR, F_ADR, F_FC, PF_FLT clear). Not during exception processing (BUSY_EXH = 1): the exception handler's
   requests are not dropped in the DATA_RDY clock and would have come first.

Cancels (all take the old IDLE path): wait states at S3, not the last portion, RMC, HALT, BR/BGACK/arbitration,
bus fault, retry, CPU reset, and for DP_CHAIN a queue miss/dismiss in the S5 clock.

No new combinational loop: the arm is a register; the S5 terms (OP_RD/OP_WR, PF_REQ, Q_MISS) come from registered
state of the control unit/queue, not from BUS_BSY. Gowin reports no loops.

**Bug found on the way:** P_BUSWIDTH kept the ending cycle's DSACK ("01") on the chain edge because the DSACK_In
sample is still the old one there; the chained cycle then ran as a word port until its own DSACK. A chained long
read that bus-errored filled only half the data input buffer (prog_berrwb frame). The chain edge now resets
DSACK_MEM first. F65's prefetch chain had the same latent bug (harmless with a single 16-bit port).

BRIDGE_EARLY_AS stays its own switch (unchanged), so the CPU change can be measured alone; F65's
`WF030_FAST_HANDOFF` switch is unchanged.

## 4. Risks

- Bridge: back-to-back AS negated for one clk_32 only. The bridge already handles this for F65 (request tag
  c_req_t/s_tag, c_open drops one clk_32 after AS rises, so the old DSACK cannot end the new cycle). Now writes
  and reads follow a prefetch directly: the whole-ST bus bench (sim/st/run_bus.sh) is the check (section 6).
- Undefined frame fields change: with the new timing a few internal stack-frame words that the 68030 documents
  as internal/undefined (format A stage C with RC = 1, i.e. refetched on RTE; format B data input buffer of an
  instruction fault) hold different stale data. All defined fields and all results are identical.
- Over-fetch past taken branches (TODO item 2) is a little more visible: an earlier prefetch leaves time for one more
  prefetch long before the branch target is requested. prog_loop at WS = 0 is 2.6% slower (22937 -> 23532 clocks),
  at WS >= 1 it is faster (WS 5: 42764 -> 40284). The ST bus is never zero wait state.
- Operand -> operand still has idle clocks (section 5).

## 5. Not done: operand -> operand (design fork)

The control unit issues its next operand request only after DATA_RDY (one clock after S5) and drops DATA_RD/DATA_WR
in that clock, so at the S5 edge no second operand request exists yet. Gaps measured 5..29 edges: the control
unit's own work, not just the handoff. Options:

- (a) **Pipelined control unit:** an "accepted" strobe (at S3 when no wait state) separate from DATA_RDY, so the
  control unit can present the next independent request (MOVEM, -(SP) pushes, the write of a read-modify) before the
  read data arrives; data still at the end. A real 68030 works this way (the sequencer runs ahead of the bus
  controller). Large change in `wf68k30L_control.vhd` (FETCH/EXEC_WB state machines, ADR_IN_USE hazards).
- (b) **Early DATA_RDY for writes only:** write data is in WP_BUFFER at S0, so the control unit could see a write as
  done at S3 and issue the next request for S5. Smaller, but the control unit can then run ahead of a write that
  later bus-errors (needs the F66-style rollback for writes; MOVEM/exception frames).
- (c) Leave operand -> operand as it is (it is the control unit's internal latency, the bus handoff is now 68030-like).

## 6. Results (16 Oct 2026)

**RTL regression** (`run_rtl.sh`, tb030 now runs with FAST_HANDOFF = 1 like the board): PASS for main and phase 2.
prog_loop WS 5: 42764 (main, F65 on) -> 40284 (phase 2); the old limit is 45885.

**Write/exception sequence, main vs phase 2** (`cmp_wr.sh`, WS 0/1/3/7): identical for prog_chk, spwb, loop,
chkstale, linea, link, pushrts, smcstack, tas, gap and berrwb (after the DSACK_MEM fix). prog_branch differs only in
the undefined frame words of section 4 ($7FEC stage C with RC = 1; at WS 1 also the format B data input buffer);
its checked results (expect_branch.txt) match. All programs finish 2-11% earlier except prog_loop at WS 0.

**Gaps, prog_gap** (count of transitions per gap, edges with AS negated):
- WS 0: PD 3:32 -> 1:32, DP 3:24 -> 1:24; DONE 2845 -> 2765 clocks.
- WS 3: PD 3:36 -> 1:36, DP 3:28 -> 1:28; DONE 4074 -> 3948 clocks.

**Whole-ST bench** (`sim/st/run_bus.sh`, Gowin netlists of both cores with FAST_HANDOFF = 1, both clock phases):
register dump identical, 0 late reads; 030 AS-negate -> AS 156 ns (2 idle clocks) 2755 -> 702, 31 ns 6138 -> 8194;
ST AS->AS at the 68000 rate (500 ns) 5304 -> 7103; run 6970 -> 6808 us for the same 10.1k ST cycles (-2.3%).

**Build** (linserver, build_st_helper_hdn.tcl, place 3): `st_helper_hdn_ph2_6b4f100_p3.fs`, TNS 0 on all clocks,
recovery min slack 8.17 ns, removal 0.27 ns, clk_cpu030 16.845 MHz (main build of 4d0157d: 16.210), clk32_core
32.897 MHz (main: 32.133). Not flashed.

Reproduce with
`sim/rtl/run_rtl.sh`, `sim/rtl/gap.sh prog_gap <WS>`, `sim/rtl/cmp_wr.sh <old> <new> <prog> <WS>`.

## Fmax work

Board build `build_st_helper_hdn.tcl`, place_option 3. No constraint changes. Each step is
cycle-neutral: RTL regression (run_rtl.sh, plus cmp_wr.sh on 12 programs x WS 0/1/3/7 against
6b4f100) and the whole-ST bench (`sim/st/run_bus.sh`, netlist with FAST_HANDOFF=1), whose
register dump and both bus traces must be byte-identical to 6b4f100.

Commits:
- 5ca9e65 control: the register-mode PACK/UNPK START_OP address select drops its DR_IN_USE term.
  This breaks the chain DR_IN_USE -> AR_SEL_RD_1 -> AR_IN_USE -> NEXT_FETCH_STATE -> ADR_EFF.
- df0c6d7 atarist.v: gstmcu DIN no longer has the shifter_dout arm. That arm was selected only in
  RAM read cycles, and nothing that reads gstmcu DIN is active then.
- 61b0fd2 bus interface: the address and FC pins come from ADR_LATCH/FC_LATCH. They differ from
  ADR_P/FC_I only in IDLE, while AS is negated, so the control unit no longer reaches the ST bridge.
- 0913b33 + 5246d00 HD63701: ALU result/flags and operands are registered every clk32. Their
  inputs are stable for at least 5 clk32 before EN2, and only the EN2 block reads them.

| build (MHz) | clk_cpu030 | clk32_core |
|---|---|---|
| main 4d0157d | 16.210 | 32.133 |
| 6b4f100 PH2 handoff | 16.845 | 32.897 |
| 5ca9e65 | 18.814 | 32.962 |
| df0c6d7 | 20.558 | 33.150 |
| 0913b33 | 21.215 | 33.073 |
| 5246d00 p3 (final) | 22.179 | 32.985 |
| 5246d00 p1 / p4 | 20.848 / 22.986 | 32.003 / 33.540 |

clk_cpu030 has 39% headroom (target 16 MHz). clk32_core is limited to about 3% headroom by two paths:
- A half-period path from blitter bltState -> blitter address -> gstmcu I/O decode ->
  gamecart_r/mde0_r/mde1_r (register.v samples on negedge). 0.47 ns slack in 15.6 ns, mostly
  routing. A blitter can be bus master and write these registers, so its arm has to stay. A
  cycle-neutral fix would need register.v sampling moved, which changes timing. Open.
- jt49 register -> sd_card data_out at 1.2 ns slack (full period). Not yet looked at.
The 030 -> bridge path is now at about 14.7 ns slack (it was the critical path at about 0 ns).
