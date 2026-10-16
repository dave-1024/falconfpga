# Option (a): pipelined control unit (design note, branch option-a off main 705db1a)

Status: design (16 Oct 2026, 22:25 UK). Checkpoints are appended at the end.

## 1. What a real 68030 does
- MC68030UM §11.1 ("Instruction pipe") and §6.1: the sequencer, the execution unit and the bus controller are separate.
  The pipe holds three words (stages B, C, D). The bus controller runs the cycles that the sequencer queued. The
  sequencer computes the next effective address and queues the next operand or prefetch request while the current
  cycle is still on the bus.
- §7.2 (asynchronous cycles): DSACK is sampled on the falling edge of S2 (and every later half clock). Data is
  latched on the falling edge of S4, and the cycle ends with S5. BERR may arrive up to one clock after DSACK (late
  bus error), so a read is final only at the data latch edge. A write is final when DSACK is seen without BERR.
- So on a real 030 the next bus cycle can start in the clock after S5 (back-to-back operand cycles). Instruction
  timings in §11 count that overlap.

## 2. What the WF68K30L does now (main 705db1a)
- Requests: `DATA_RD`/`DATA_WR` come from the control unit's FETCH_STATE/EXEC_WB_STATE. Top P_BUSREQ passes them
  straight through while BUS_BSY = 0 and holds them while the bus controller is busy.
- Ending: the bus interface strobes DATA_RDY on the S5 edge (a posted write on S3, PH2-WP). In the DATA_RDY clock the
  control unit drops DATA_RD/DATA_WR (DATA_RD_I/DATA_WR_I are forced low on DATA_RDY), clears READ_CYCLE/WRITE_CYCLE
  (CYCLECONTROL), then moves FETCH_STATE / EXEC_WB_STATE and the address registers. The next request appears 3 clocks
  after DATA_RDY for MOVEM (PHASE2_DESIGN.md, posted-write finding), more for others:
  1. DATA_RDY clock: request dropped, READ/WRITE_CYCLE cleared, state change decided.
  2. New FETCH/EXEC state, address register update (MOVEM An+/-, (An)+, -(An)), ADR_EFF recomputed.
  3. ADR_IN_USE (pending address writeback vs the new effective address) clears, and DATA_RD/DATA_WR rise.
  PH2 / PW_GO then take the request into S0 without the IDLE/START_CYCLE clocks, so the gap after the bus cycle is 4..9 clocks.
- Whole-ST bench (main): 030 AS negate -> next AS is 156 ns in 702 cases and 719 ns in 1149 cases. Each gap that misses
  the ST S6 -> S0 en1 costs 125 ns or a whole 500 ns slot (ST AS->AS 625 ns: 723, 750/875 ns: 1104).

## 3. Proposed change (no switch)
Split "the cycle is accepted" from "the data is here":
- **A1. DATA_ACK strobe (bus interface).** One clock pulse when the outcome of the current operand cycle's last portion is
  final and its request may be dropped:
  - write: the posted-write point (S3, DSACK, no BERR/retry/halt/RMC/STERM). This is the same condition as PH2-WP.
  - read: the S5 edge as now. A read's data and late BERR are only final there, so a read gets no earlier ACK. This is
    030-correct: the 030 also latches the data at S4 falling.
  DATA_RDY keeps its meaning (data valid / cycle over) for loads and LOAD_OPx.
- **A2. Control unit runs ahead on DATA_ACK.** For sequences whose next request does not depend on the current read
  data, FETCH_STATE/EXEC_WB_STATE and the address update advance on DATA_ACK, and DATA_RD/DATA_WR are not dropped for a
  clock: the next request is valid in the same clock. Covered first:
  - MOVEM (register list): next address = current ± size, register select from the mask.
  - Writes of -(SP) pushes and PEA/LINK/BSR/JSR return-address pushes.
  - The write after a read-modify-write is NOT covered: it needs the read data. CAS/CAS2/TAS keep RMC and stay serial.
  The data load (register write from DATA_IN) stays on DATA_RDY. So for a read sequence the load of word n happens
  while request n+1 is already queued, which is the 030's overlap.
- **A3. Hazard check.** ADR_IN_USE is computed from the next effective address in the same clock as the state advance
  (or registered one clock earlier), so it no longer costs a clock when there is no conflict. When there is a conflict
  (the pending writeback hits the next address), it still holds the request.

## 4. Hazards and how each is covered
- **Bus error / retry / halt / reset:** DATA_ACK is never given on BERR/retry/halt/RMC/STERM (PH2-WP rule). A read
  gives ACK only together with DATA_RDY. After a fault, the run-ahead request must not reach the bus: BUS_FLT forces
  the control unit's request low (as now, via the exception handler's BUSY_EXH and RESTORE path). The frame must show
  the faulting cycle's address and DOB, not the queued one's. The F66 write rollback stays (writes are posted already).
- **Exceptions:** an interrupt or trace taken at the instruction boundary is unaffected: run-ahead stays inside one
  instruction, and the last request of an instruction is not run ahead into the next instruction.
- **RMW (TAS/CAS/CAS2):** excluded (RMC = 1 → no early ACK, serial as now).
- **Address-register writeback order:** (An)+/-(An) and MOVEM updates happen in the same order as now, only earlier.
  ADR_IN_USE (and AR_IN_USE/DR_IN_USE) keep catching a write to a register that the next EA uses.
- **Posted writes:** A1 for writes = the posted-write point. PW_GO stays (the request is then already there at S3/S5,
  so the OP_CHAIN path at S5 takes it directly: back-to-back operand writes at the 030 minimum).
- **Prefetch-COF hold:** unchanged. The hold concerns PF_REQ only, and operand requests have priority.
- **Fmax:** the run-ahead adds the hazard compare into the request path. The budget is clk_cpu030 ≥ 19 MHz
  (constraint 16, caches need margin). The current worst path is decoder → control → ADR_EFF (TODO follow-up 5).
  Any new request path must be registered where it touches ADR_EFF; check p3 after each step.

## 5. Expected gain
- RTL (prog_gap, prog_pushrts): operand → operand gaps after writes 4 → 1..2 clocks, MOVEM read sequences 9 → 2..3.
- Whole-ST: only where a gap now misses the en1 (156 ns cases, 702 in prog_bus) → about -125 ns each, roughly 1-2%
  of ST time on prog_bus. GEMBENCH likely unchanged (ST-bus bound), more once caches or fast RAM exist.

## 6. Plan (small commits)
1. A1: DATA_ACK in the bus interface (write = WP point, read = DATA_RDY), wired to the control unit, unused. Regression = identical.
2. A2 for MOVEM writes (register to memory, predecrement); regression, gap.
3. A2 for MOVEM reads and the push sequences; regression.
4. A3 hazard compare; regression; p3 timing (≥19 MHz).
5. Board (approved if regression and timing pass): rl.sh, 3 warm resets, gembench.sh; roll back to vchain on failure.

## Checkpoints
- 22:25 UK: design note written; branch option-a created off 705db1a.
- 22:40 UK, code reading:
  - **A1 is already in place for writes.** PH2-WP strobes a write's DATA_RDY at the S3 posting point (`WP_GO`,
    PREFETCH_BUFFERS). For reads, DATA_RDY at S5 is the earliest 030-correct point. So no new DATA_ACK signal is needed;
    step 1 is dropped.
  - **Where the 3 clocks go for MOVEM register-to-memory.** Each register makes one round trip through
    FETCH_STATE INIT_EXEC_WB → ALU (ALU_INIT / EXECUTE, ALU_BSY handshake) → EXEC_WB_STATE WRITE_DEST.
    MOVEM_CONTROL advances MOVEM_PNTR only in INIT_EXEC_WB with ALU_BSY = '0', i.e. after the previous WRITE_DEST
    got WR_RDY and ALU_ACK. The predecrement of An happens on ALU_INIT_I. So the next write request exists only after
    INIT_EXEC_WB → EXECUTE → WRITE_DEST again.
  - **Revised A2 (030-like overlap) for MOVEM writes.** Let FETCH run the next register's INIT_EXEC_WB / ALU pass
    while EXEC_WB is still in WRITE_DEST of the current one. This needs a second ALU result/operand latch (or the ALU
    result held in the write buffer, which PH2-WP already does: the written data is in WP_BUFFER from S0). MOVEM_PNTR and
    the -(An) decrement then advance on ALU_ACK of the current register instead of after WR_RDY. The ordering rules
    stay: register writeback of An only at the end (MOVEM_INH_WR), ADR_IN_USE for the next EA.
  - Same pattern for -(SP) pushes inside one instruction (exception stacking is the exception handler's own sequence,
    which is not covered).
  - Next run: a sim probe (per-clock FETCH_STATE/EXEC_WB_STATE/ALU_BSY/DATA_WR/DATA_RDY on prog_pushrts) to confirm
    the 3-clock breakdown before RTL. The board stays on vchain db04754.
- 23:10 UK, sim probe (prog_gap, WS0, P_DBG copy of control.vhd):
  - MOVEM read: DATA_RDY → INIT_EXEC_WB(ALU_INIT) → SWITCH_STATE(EXECUTE) → CALC_AEFF(WRITEBACK) → FETCH_OPERAND
    (DATA_RD=1): 4 clocks.
  - MOVEM write: DATA_RDY → EXEC_WB IDLE (ALU_INIT) → EXECUTE → WRITE_DEST (DATA_WR=1): 3 clocks.
- 23:25 UK, **A2 for MOVEM register-to-memory implemented (08e1cf8)**:
  - New `ALU_BSY_M` in the control unit: '0' when the ALU is idle, or when OP = MOVEM register-to-memory and the
    current WRITE_DEST gets WR_RDY (that is the ALU_ACK clock). It replaces ALU_BSY in ALU_TRIG, the MOVEM
    ADDRESS_OFFSET increments, MOVEM_CONTROL (MOVEM_PNTR), ADR_MARK_USED_I and the MOVEM branch of FETCH_DEC.
  - EXEC_WB_DEC: WRITE_DEST with WR_RDY goes straight to EXECUTE when ALU_INIT_I = '1' (OP_WB = MOVEM), so there is
    no IDLE clock and no UNMARK in between (the next mark follows from ADR_MARK_USED one clock later, as before).
  - ALU P_BUSY: ALU_INIT together with ALU_ACK for MOVEM re-arms ALU_REQ (ALU_BSY already had INIT priority).
  - Why it is 030-correct: the write's DATA_RDY is the posting point (PH2-WP; data and address are latched in the bus
    interface), or the end of the cycle when not posted. So the next register is loaded only after the current write
    is committed, never ahead of a possible BERR on a non-posted write. Late BERR on a posted write is unchanged
    (prog_wpberr).
  - Result: MOVEM write DD gap 4 → 3 clocks (prog_gap: 17 transfers, DONE 2657 → 2636 at WS0). New test
    `prog_movemw.s` covers long/word, (An), -(An) with An in the list, d16(An), (d8,An,Xn), abs, single/sparse masks:
    writes identical to main at WS 0/1/3/7, about 100 clocks faster.
  - Not done this run: MOVEM reads (4 clocks; needs the read data path, larger change) and run-ahead requests (A3).
