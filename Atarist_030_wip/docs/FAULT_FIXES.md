# WF68K30L data-fault fixes (FLT1, FLT2), 17 Oct 2026

Branch `fault-fixes` off main b20331d. Unconditional (no switch). TODO "Phase 2 follow-ups" items 2 and 3.

## 1. What the MC68030 does (MC68030UM, NXP PDF)
- **8.1.2 Bus Error:** the exception is taken for the faulted bus cycle; the stacked PC is "the logical address of
  the instruction that was executing at the time the fault was detected. This is not necessarily the instruction
  that initiated the bus cycle, since the processor overlaps execution of instructions."
- "When the bus error exception is taken at an instruction boundary, less information is required to recover from
  the error, and the processor builds the **short bus fault stack frame**. When the exception is taken during the
  execution of an instruction, the processor ... uses the **long bus fault stack frame**."
- **Table 8-6:** format $A (16 words): "Address Error or Bus Error, Execution Unit at Instruction Boundary", stacked
  PC = next instruction. Format $B (46 words): "Instruction Execution in Progress", PC = instruction in execution.
- **8.2.3 (data faults):** "Data read faults only generate the long bus fault frame." So only write faults can give $A.
- No further bus cycles of the program run after the faulted one: the processor starts exception processing.

## 2. What the core did (main b20331d), confirmed with `prog_fault.s`
- **Bug 1 (write faults):** the faulting write runs in the write-back stage (EXEC_WB WRITE_DEST) while the fetch side
  already works on the next instruction. The exception handler only starts when the control unit is idle
  (`BUSY_MAIN = '0'`), so the next instruction ran to its end, including its operand reads and register updates,
  before the exception. Seen: `move.w d1,$20000` (BERR) then `move.l $4010,d3`: $4010 was read and D3/CCR changed
  before the frame was written, and the frame's PC pointed at that already executed instruction, so RTE would run it
  twice. A MOVEM into a fault area kept writing after the first fault (3 BERR writes, fault address of the last one).
  In `prog_wpberr.s` the next instruction (`lea 1f(pc),a2` of the following case) ran before the exception, so case 3
  was silently skipped (7 faults instead of 9) and case 9's results were wrong.
- **Bug 2:** a data write fault always stacked format $B. ($A existed only for a faulted opcode fetch at the boundary.)
- Data read faults were already right (F66: the instruction ends at the faulted read, frame $B).

## 3. Fix
### FLT1: no program bus cycle after a data write fault (control unit)
- `WR_FLT` = the control unit's write ends with DATA_RDY and DATA_VALID = '0' (BERR). `WFLT` holds it until the
  exception handler runs (`BUSY_EXH`).
- On `WR_FLT` (and while `WFLT`): FETCH_STATE <= START_OP and EXEC_WB_STATE <= IDLE (the next instruction is
  abandoned), DATA_RD/DATA_WR are blocked, no new ALU load (`ALU_TRIG`, and `ALU_BSY_M` of the MOVEM overlap needs a
  good write), and UNMARK releases the write's ADR_IN_USE mark. EXH_REQ already stops a new instruction from starting,
  so the handler starts the next clock.
- The abandoned instruction runs again after RTE (the stacked PC is its address). It has made no bus cycle. The only
  side effects it can have made are fetch-side address register updates (-(An) predecrement before CALC_AEFF, the SP
  step of BSR/JSR/LINK at its start); those cases stack $B (see FLT2), as on a 68030 where the instruction would be
  "in progress". The old core re-ran a whole completed instruction, so this is strictly closer.

### FLT2: short frame $A at an instruction boundary (control unit + exception handler)
- New control output `BERR_IBOUND` (strobe with BERR): the write fault is on its instruction's **last** bus cycle
  (`WR_LAST`: not CAS/CAS2/TAS, not a 5-byte bit field, not a MOVEM/MOVEP with transfers still to come) **and** the
  fetch side has changed no register for the following instruction (`FI_DIRTY` from AR_INC/AR_DEC/SP_ADD_DISPL since
  START_OP, plus the same clock). Then the execution unit is at the boundary and the PC register holds the next
  instruction.
- The exception handler sets its existing `IBOUND` flag on `TRAP_BERR and BERR_IBOUND`, which selects format $A
  (16 words) in the existing stack builder.
- Everything else (read faults, RMW, mid-MOVEM faults, dirty fetch side) keeps $B.

### Item 3 (stale BUS_FLT on a chained late BERR): not the same path, not changed
That is in the bus interface: P_SYNC copies BUS_FLT_N into BUS_FLT in every DATA_C1C4 clock, and a chained cycle
(OP_/DP_/PF_CHAIN_GO) stays in DATA_C1C4, so a BERR arriving at S5 after the chain was decided at S3 carries into the
chained cycle. FLT1/FLT2 work on the control unit's DATA_RDY/DATA_VALID and do not touch it. It needs its own bench
(late BERR on a chaining cycle in tb030) and a 030 decision (fault the old cycle or the chained one). Left open (TODO).

## 4. Tests and results
- New `sim/rtl/prog_fault.s`: 7 cases (word/long write fault as the last cycle with a reading next instruction,
  register-only next instruction, RMW read fault, plain read fault, MOVEM faulting on the 2nd of 3 writes,
  (An)+ source with faulting destination, CLR to the fault area). The bus log must show no marker read ($40x0)
  between the BERR and the stacking.
- Results (fixed core): no marker reads; frames: case 1 $A PC=next, 2 $A PC=moveq (not executed, D4 unchanged),
  3 $B, 4 $B, 5 $B with fault address $10000 (the first faulting write, no further writes), 6 $A (A1 incremented by
  the faulting instruction itself), 7 $A. Old core: $B everywhere, marker reads in cases 1, 6, 7, three MOVEM writes.
- Regression against main b20331d (run_rtl + cmp_wr, 19 programs × WS 0/1/3/7): run_rtl PASS; 17 programs SAME
  (cycle-identical DONE clocks); DIFF only in `prog_wpberr` and `prog_fault`, both write-fault programs, all
  differences explained above (fewer bus cycles, $A frames, the skipped case now run, case 9 data now right).
- Netlist and Gowin results: see the checkpoint below.

## Checkpoint: netlist and Gowin results

- Bitstream: `st_helper_hdn_flt_f045aa9_p3.fs`
- sha256: `f47644b5f327b1f0a980fd98d7d97c0e4160f0d933422b91e9d6a78e915a27e2`
- Fmax: clk_cpu030 22.045 MHz (oa_039c710: 21.725), clk32_core 35.279 MHz (35.255), TNS 0. No constraint changes.
- Unit netlist bench (run_unit.sh): ERRORS=0, all 6 phases.
- Whole-ST bus bench (sim/st/run_bus.sh): completes at 6809234375 ps. Not compared with main: the main netlist resynth produced no .vg.
- Not flashed.
