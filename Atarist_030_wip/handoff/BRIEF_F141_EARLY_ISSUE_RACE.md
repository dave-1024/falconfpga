# Brief: F141 early issue (EARLY_OW) for ADDQ/SUBQ #,An breaks AUTO on the board, all sims pass

Repo falconfpga, branch `speed`, core `Atarist_030_wip/hdl/cpu030` (WF68K30L 68030 VHDL, Gowin GW5AST-138, Gowin V1.9.12.03).
Clocks: clk_cpu030 about 20.7 MHz (plus clk_cpu030_n), bridge on clk32_core. TOS = EmuTOS 1.4 (etos256uk.img, ROM $E00000).

## Goal
Find why enabling F141 early OW_REQ (`EARLY_OW`, `constant EARLY_ISSUE`) for **ADDQ/SUBQ #,An alone** makes the board
skip AUTO programs (LOOPTEST.PRG not run, desktop comes up, no crash, no exception), while every simulation passes.
Deliver: (1) ranked hypotheses with reasoning; (2) a concrete minimal VHDL fix tagged `[F145]` with a revision line;
(3) a sim test that reproduces it (GHDL tb030, see below) and a board check that confirms it.

## What F141 does
In INIT_EXEC_WB of a register-only instruction that goes to START_OP, OW_REQ for the next opword is raised one clock
early (2-clock issue, MC68030UM 11.6). Disabled on `speed` today (F143: `EARLY_ISSUE := false`).

## Evidence
Board bisect (each a full build, SRAM load, cold boot of an AUTO LOOPTEST floppy):

| build | early-issue set | result |
|---|---|---|
| bld_a | group A | pass |
| bld_b | group B (ADD/SUB/... incl. An forms) | **fail** |
| bld_c | group C | pass |
| D+E+F | groups D,E,F | pass |
| bld_bdn | group B, Dn destination only | pass |
| bld_ban | group B, An involved | **fail** |
| ADDA/SUBA only | | pass |
| **bld_aq** | **ADDQ/SUBQ #,An only** | **fail 2/2 cold boots** |
| **aqt4** | **bld_aq logic exactly + DIAG_TRACE/DIAG_HEARTBEAT/DIAG_DUMP logger** (observation only) | **pass 3/3** (LOOPTEST numbers equal to bld144) |
| bld144 | F143 (early issue off) + F144 | pass (reference) |

Earlier B2 build: MiNT panic "bus error addr=$E1091C pc=$E0F89E sr=2300 ssr=0115" (a byte write into ROM).

- So the same CPU logic passes or fails depending on place-and-route, the same way every time.
- **Timing:** both builds pass every constrained pair. bld_aq worst cases: clk_cpu030 to itself setup 9.717 ns,
  falling to rising 11.468, rising to falling 5.339, hold 31.5. aqt4: 12.748 / 11.193 / 6.125.
  No unconstrained paths are reported. clk_cpu030, clk_cpu030_n and clk32_core are one synchronous group (the CDC
  to the bridge is timed); the asynchronous groups only cut HDMI, AE350/DDR3 and flash.
  The only CPU relaxation is an F66 multicycle-2 path through MMU XLATE_PIN/BLK_PIN/H_PA, constant while TC.E=0
  (not applicable at boot).
- F141 added no registers (EARLY_OW is combinational), so a lost power-up value is unlikely.
- **Gowin synth log (bld_aq):** no inferred latches or combinational loops in the CPU. Incomplete sensitivity lists
  (EX4749, synthesis assumes complete; sim may differ):
  `MV_RW_WB` at wf68k30L_control.vhd:3086 (EXEC_WB_DEC), `EX_P_MMUCFG` at wf68k30L_exception_handler.vhd:900,
  `BM_CNT` at wf68k30L_mmu.vhd:250. Several EX4967/EX4664 out/buffer port-read warnings (bus_interface 637
  ssw_80, decoder 504-507 stg_cf/stg_bf, mmu 221). The process(all) variant of the core passes the full RTL suite.
- **Board trace (cpu_trace, aqt3/aqt4):** EmuTOS's AUTO loop ($E0162C-$E01690) finds the program: Fsfirst d0=0,
  PC reaches $E01656. The loop then does strcpy, strcat ($E13DC2: `movea.l a1,a0; lea 1(a0),a1; tst.b (a0); bne`)
  and Pexec ($E13C54) at $E01674. The trace build itself passes, so the failing step has not been traced.
  EmuTOS's CPU probe (illegal $7300 at $E0A536 right after `subq.l #4,sp`) stacks at the correct SP.
- **Sim (GHDL, tb030):** randomized differential tests compare F143 against the early cores (ADDQ/SUBQ An weighted,
  user and supervisor mode, interrupts, wait states 0-8, I-cache on with CIMODE=1 and code at $FD0000). Directed
  tests: `addq #6,sp; trap`, ADDQ An + TRAP/line-A, and the full run_rtl suite. All identical.
  Early issue only gains cycles in sim when the I-cache feeds the stream.
  An assert for AR_MARK_USED and UNMARK in the same clock never fired.

## How bld_aq differs from `speed` (the build that fails)
```diff
--- hdl/cpu030/wf68k30L_control.vhd	2026-11-04 04:38:11.061873499 +0000
+++ /workspace/bld_aq/hdl/cpu030/wf68k30L_control.vhd	2026-11-04 09:48:35.582717145 +0000
@@ -157,7 +157,6 @@
 --   2026-10-09 F62d: JSR waits for a pending A7 writeback.
 --   2026-10-15 F66: a bus-errored operand read ends the instruction, no register writeback (MC68030).
 --   2026-10-16 PH2-FMAX: register-mode PACK/UNPK START_OP address select without the DR_IN_USE term (timing, same cycles).
---   2026-11-04 F143: F141 early issue disabled (EARLY_ISSUE = false) after the board AUTO failure; MOVEQ hazard change kept.
 --   2026-11-04 F142: CMPA Rn,An one clock longer (4, as the manual; it was faster).
 --   2026-11-04 F141: early OW_REQ in INIT_EXEC_WB for register-only instructions (2-clock issue, MC68030UM 11.6).
 --
@@ -428,7 +427,6 @@
 signal CAS2_WGAP            : bit := '0'; -- [C1]
 signal CAS2_CCHOLD          : bit := '0'; -- [C1]
 signal EARLY_OW             : bit; -- [F141]
-constant EARLY_ISSUE        : boolean := false; -- [F143] F141 early OW_REQ disabled (board failure).
 signal CMPA_DLY             : bit := '0'; -- [F142]
 signal MEMADR_IN            : bit := '0'; -- [C2] FETCH_STATE was FETCH_MEMADR last clock.
 signal MEMADR_Q1, MEMADR_OK : bit := '0'; -- [F130] base/index register final for the pointer read.
@@ -489,19 +487,17 @@
     -- flow, touch the SR or memory; never with trace on or an interrupt that may be taken after this
     -- instruction (IRQ_HOT, INT_TRIG is evaluated in INIT_EXEC_WB), so the stacked PC and the exception order
     -- are those of the normal path.
-    -- [F143] Early issue is off: the F142 board build ran the desktop, but no AUTO program (TTRAM.PRG, LOOPTEST.PRG)
-    -- ran; the same build with EARLY_OW = '0' runs them (board bisect 2026-11-04). Root cause not reproduced in sim yet.
-    EARLY_OW <= '0' when EARLY_ISSUE = false or TRACE_MODE /= "00" or IRQ_HOT = '1' else
-                '1' when OP = MOVEQ or OP = EXG or OP = SWAP or OP = EXT or OP = EXTB else
+    EARLY_OW <= '0' when TRACE_MODE /= "00" or IRQ_HOT = '1' else
+                '0' when OP = MOVEQ or OP = EXG or OP = SWAP or OP = EXT or OP = EXTB else
                 '1' when (OP = ADD or OP = ADDA or OP = ADDQ or OP = SUB or OP = SUBA or OP = SUBQ or OP = AND_B or OP = OR_B or
                           OP = EOR or OP = CMP or OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST) and
-                         (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") else
-                '1' when (OP = ADDI or OP = SUBI or OP = ANDI or OP = ORI or OP = EORI or OP = CMPI) and BIW_0(5 downto 3) = "000" else
-                '1' when (OP = MOVE or OP = MOVEA) and (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") and
+                         (OP = ADDQ or OP = SUBQ) and BIW_0(5 downto 3) = "001" else
+                '0' when (OP = ADDI or OP = SUBI or OP = ANDI or OP = ORI or OP = EORI or OP = CMPI) and BIW_0(5 downto 3) = "000" else
+                '0' when (OP = MOVE or OP = MOVEA) and (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") and
                          (BIW_0(8 downto 6) = "000" or BIW_0(8 downto 6) = "001") else
-                '1' when (OP = ASL or OP = ASR or OP = LSL or OP = LSR or OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and
+                '0' when (OP = ASL or OP = ASR or OP = LSL or OP = LSR or OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and
                          BIW_0(7 downto 6) /= "11" else
-                '1' when (OP = BTST or OP = BCHG or OP = BCLR or OP = BSET) and BIW_0(5 downto 3) = "000" else '0';
+                '0' when (OP = BTST or OP = BCHG or OP = BCLR or OP = BSET) and BIW_0(5 downto 3) = "000" else '0';
 
     DATA_AVAILABLE: process
     -- These flip flops store the information whether the data required in the different

```

## Code

#### F141 OW_REQ_MAIN / EARLY_OW: `hdl/cpu030/wf68k30L_control.vhd` lines 476-505
```vhdl

    OW_REQ <= '0' when BUSY_EXH = '1' else
              '0' when EXH_REQ = '1' and LOOP_BSY = '0' else -- Non interrupt exception requests, loop has priority.
              '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' else -- [PMMU2] PMOVE to the MMU: no next opcode before its writeback (8.1.10).
              '0' when OPD_ACK = '1' or OW_RDY = '1' else
              '1' when NO_PIPELINE = true and FETCH_STATE = START_OP and ALU_BSY = '0' else
              '1' when NO_PIPELINE = false and FETCH_STATE = START_OP else
              '1' when NO_PIPELINE = false and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE = START_OP and EARLY_OW = '1' else '0'; -- [F141]

    -- [F141] Early issue. A register-only instruction that leaves INIT_EXEC_WB for START_OP asks for the next
    -- operation word in INIT_EXEC_WB already, so the decoder's (registered) acknowledge arrives in the START_OP
    -- clock and the next instruction can initialise one clock later: two clocks per instruction as the 68030
    -- (MC68030UM 11.6.6-11.6.12, I-cache case). Only instructions that cannot take an exception, change the
    -- flow, touch the SR or memory; never with trace on or an interrupt that may be taken after this
    -- instruction (IRQ_HOT, INT_TRIG is evaluated in INIT_EXEC_WB), so the stacked PC and the exception order
    -- are those of the normal path.
    -- [F143] Early issue is off: the F142 board build ran the desktop, but no AUTO program (TTRAM.PRG, LOOPTEST.PRG)
    -- ran; the same build with EARLY_OW = '0' runs them (board bisect 2026-11-04). Root cause not reproduced in sim yet.
    EARLY_OW <= '0' when EARLY_ISSUE = false or TRACE_MODE /= "00" or IRQ_HOT = '1' else
                '1' when OP = MOVEQ or OP = EXG or OP = SWAP or OP = EXT or OP = EXTB else
                '1' when (OP = ADD or OP = ADDA or OP = ADDQ or OP = SUB or OP = SUBA or OP = SUBQ or OP = AND_B or OP = OR_B or
                          OP = EOR or OP = CMP or OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST) and
                         (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") else
                '1' when (OP = ADDI or OP = SUBI or OP = ANDI or OP = ORI or OP = EORI or OP = CMPI) and BIW_0(5 downto 3) = "000" else
                '1' when (OP = MOVE or OP = MOVEA) and (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") and
                         (BIW_0(8 downto 6) = "000" or BIW_0(8 downto 6) = "001") else
                '1' when (OP = ASL or OP = ASR or OP = LSL or OP = LSR or OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and
                         BIW_0(7 downto 6) /= "11" else
                '1' when (OP = BTST or OP = BCHG or OP = BCLR or OP = BSET) and BIW_0(5 downto 3) = "000" else '0';

```

#### AR read/write selects, AR_WR_1: `hdl/cpu030/wf68k30L_control.vhd` lines 806-836
```vhdl
                   BIW_0(2 downto 0) when OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR or OP = SBCD or OP = Scc or OP = SUB or OP = SUBA else
                   BIW_0(2 downto 0) when OP = SUBI or OP = SUBQ or OP = SUBX or OP = TAS or OP = TST or OP = UNLK or OP = UNPK else "000";

    -- Always the destination.
    AR_SEL_WR_1 <= BIW_0(2 downto 0) when OP = ADDQ or OP = SUBQ else
                   BIW_0(2 downto 0) when OP = EXG and BIW_0(7 downto 3) = "10001" else -- Data and Address register.
                   BIW_1(14 downto 12) when OP = MOVEC or OP = MOVES else
                   "111" when OP = UNLK and FETCH_STATE = START_OP else
                   BIW_0(2 downto 0) when OP = LINK else
                   MOVEM_PNTR(2 downto 0) when OP = MOVEM else
                   BIW_0(2 downto 0) when OP = MOVE_USP else
                   BIW_1(7 downto 5) when OP = LEA and BIW_0(13 downto 12) = "11" else -- [PMMU3] PTEST A = 1: An.
                   BIW_0(11 downto 9); -- ADDA, EXG, LEA, MOVE, MOVEA, SUBA.
    
    AR_WR_1 <= AR_WR_I;
    AR_WR_I <= '1' when OP = LINK and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' else
               -- [T8] FETCH_DEC always leaves SWITCH_STATE for UNLK (NEXT_FETCH_STATE = CALC_AEFF), so the old term
               -- NEXT_FETCH_STATE /= SWITCH_STATE was constant '1' here; it only made STA time the MOVEM F3 decision
               -- (WR_EARLY -> F3_EARLY -> MOVEM_PVAR -> NEXT_FETCH_STATE) into AR_IN_1 (tt21 worst, -1.010 ns).
               '1' when OP = UNLK and FETCH_STATE = SWITCH_STATE else -- Write An to SP.
               '0' when EXEC_WB_STATE /= WRITEBACK else
               '1' when OP_WB_I = ADDA or OP_WB_I = SUBA else
               '1' when (OP_WB_I = ADDQ or OP_WB_I = SUBQ) and BIW_0_WB(5 downto 3) = "001" else
               '1' when OP_WB_I = EXG and BIW_0_WB(7 downto 3) = "01001" else -- Two address registers.
               '1' when OP_WB_I = EXG and BIW_0_WB(7 downto 3) = "10001" else -- Data and Address register.
               '0' when OP_WB_I = LEA and BIW_0_WB_MMU = '1' else -- [PMMU2b] MMU operation: no An.
               '1' when OP_WB_I = LEA else
               '1' when OP_WB_I = MOVE_USP and BIW_0_WB(3) = '1' else
               '1' when OP_WB_I = MOVEA else
               '1' when OP_WB_I = MOVEC and BIW_1_WB(15) = '1' and BIW_0_WB(0) = '0' else -- To general register.
               '1' when OP_WB_I = MOVES and BIW_1_WB(15) = '1' else
```

#### AR_MARK_USED: `hdl/cpu030/wf68k30L_control.vhd` lines 1481-1493
```vhdl
    AR_MARK_USED <= '1' when OP = UNLK and FETCH_STATE /= SWITCH_STATE and NEXT_FETCH_STATE = SWITCH_STATE else -- This is for An to SP.
                    '1' when OP = LINK and FETCH_STATE = SWITCH_STATE and NEXT_FETCH_STATE /= SWITCH_STATE else -- This is for SP to An.
                    '0' when FETCH_STATE /= INIT_EXEC_WB or NEXT_FETCH_STATE = INIT_EXEC_WB else -- Deactivate except in the end of INIT_EXEC_WB.
                    '1' when OP = ADDA or OP = SUBA else
                    '1' when (OP = ADDQ or OP = SUBQ) and BIW_0(5 downto 3) = "001" else
                    '1' when OP = EXG and BIW_0(7 downto 3) /= "01000" else
                    '1' when OP = LEA else
                    '1' when OP = MOVE_USP else
                    '1' when OP = MOVEM and BIW_0(10) = '1' and MOVEM_ADn_I = '1' and MOVEM_COND = true else -- Memory to register.
                    '1' when OP = MOVEA else
                    '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(15) = '1' else -- Destination is Ax.
                    '1' when OP = MOVES and BIW_1(15) = '1' and BIW_1(11) = '0' else
                    '1' when OP = UNLK else '0';
```

#### UNMARK: `hdl/cpu030/wf68k30L_control.vhd` lines 1524-1528
```vhdl
                    '1' when (OP = PACK or OP = UNPK) and BIW_0(3) = '0' else '0';

    UNMARK <= '1' when WR_FLT = '1' else -- [FLT1] The aborted write-back releases its address.
              '1' when EXEC_WB_STATE /= IDLE and NEXT_EXEC_WB_STATE = IDLE else '0'; -- Release a pending write cycle when done.

```

#### FETCH_DEC START_OP hazard checks (ADDQ An): `hdl/cpu030/wf68k30L_control.vhd` lines 1975-2030
```vhdl
    --                         ADDI | ANDI | SUBI | CMPI | EORI | ORI | MULS | MULU, '0' when others;

    FETCH_DEC: process(ADR_MODE_I, ALU_BSY, ALU_BSY_M, ALU_COND, AR_IN_USE, CMPA_DLY, BF_BYTES, BIW_0, BIW_1, BRANCH_ATN, DR_IN_USE, EW_ACK, EW_RDY, EXEC_WB_STATE, 
                       EXH_REQ, EXT_WORD, FETCH_STATE, MEM_INDIRECT, MEMADR_RDY, MOVEM_COND, MOVEM_END, MOVEM_PNTR, MOVEP_PNTR_I, NEXT_EXEC_WB_STATE, 
                       OP, OP_SIZE_I, OP_WB_I, OPD_ACK, OW_RDY, PHASE2, RD_RDY, TRACE_MODE, OD_REQ_32, OD_REQ_16, WR_RDY, MOVEM_FIRST_RD, PMMU_WR_D, PM_INFL, MMU_BUSY, MV_RW, MV_AN, PM_QUAD) -- MOVEM_FIRST_RD: sensitivity audit; [PMMU2] PMMU_WR_D, PM_INFL
    -- ADH: avoid data hazard.
    -- ASH: avoid structural hazard.
    -- ASH: avoid control hazard.
    begin
        case FETCH_STATE is
            when START_OP =>
                if OPD_ACK = '0' and OW_RDY = '0' then
                    NEXT_FETCH_STATE <= START_OP;
                elsif PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' then -- [PMMU2b] also an MMU operation (PLOAD/PTEST walk)
                    -- [PMMU2] A PMOVE to an MMU register finishes its writeback before the next instruction
                    -- starts, so the post-instruction MMU configuration exception (8.1.10) is taken before it.
                    NEXT_FETCH_STATE <= START_OP;
                -- Debugging:
                --elsif OP_TEST = '1' and ALU_BSY = '1' then
                --    NEXT_FETCH_STATE <= START_OP;
                else
                    case OP is
                        when ILLEGAL | RTE | TRAP | UNIMPLEMENTED =>
                            NEXT_FETCH_STATE <= START_OP;
                        when MOVEQ => -- [F141] Overwrite only: no hazard wait (the newer mark wins in the register file).
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        when DBcc | EXT | EXTB | SWAP =>
                            if DR_IN_USE = '1' then
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Proceed.
                            end if;
                        when ABCD | SBCD | ADDX | SUBX | PACK | UNPK =>
                            if BIW_0(3) = '0' and DR_IN_USE = '0' then -- Check for destination addressing register. ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to register.
                            elsif BIW_0(3) = '1' and AR_IN_USE = '0' then -- Check for destination addressing register. ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF; -- Memory to memory.
                            else
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            end if;
                        when ADD | ADDI | ADDQ | AND_B | ANDI | CAS | CMP | CMPI | EOR | EORI | 
                             NBCD | NEG | NEGX | NOT_B | OR_B | ORI | SUB | SUBI | SUBQ | TST | TAS =>
                            -- These instructions have to take the destination into aspect
                            -- because the destination is an ALU operand and may cause data hazards.
                             case BIW_0(5 downto 3) is
                                when "000" => -- Dn.
                                    if DR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "001" => -- An.
                                    if (OP = ADD or OP = SUB or OP = AND_B or OP = EOR or OP = OR_B or OP = CMP) and (AR_IN_USE = '1' or DR_IN_USE = '1')then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif AR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
```

#### EXEC_WB_DEC ADDQ/SUBQ An: `hdl/cpu030/wf68k30L_control.vhd` lines 3020-3032
```vhdl
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            end if;
                        when ADDA | SUBA | ANDI_TO_SR | BFEXTS | BFEXTU | BFFFO | DIVS | DIVU | EORI_TO_SR | EXG | EXT | EXTB | 
                             LEA | MOVE_TO_CCR | MOVE_TO_SR | MOVE_USP | MOVEA | MOVEC | MOVEQ | MULS | MULU | ORI_TO_SR | STOP | SWAP | UNLK =>
                            NEXT_EXEC_WB_STATE <= WRITEBACK;
                        when ADDI | ADDQ | ANDI | BCHG | BCLR | BFCHG | BFCLR | BFINS | BFSET | BSET | CLR | EOR | EORI |
                                     MOVE_FROM_CCR | MOVE_FROM_SR | NBCD | NEG | NEGX | NOT_B | ORI | Scc | SUBI | SUBQ | TAS =>
                            if BIW_0_WB(5 downto 3) = "000" then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is a data register.
                            elsif BIW_0_WB(5 downto 3) = "001" then -- Valid for ADDQ and SUBQ.
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is an address register.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
```

#### AR_PNTR_WB latch, P_IN_USE (UNMARK has priority), AR_IN_USE: `hdl/cpu030/wf68k30L_address_registers.vhd` lines 195-256
```vhdl
signal USP_REG          : std_logic_vector(31 downto 0); -- User stack pointer (refers to A7 in the user mode.).
begin
    IDX_SEL <= EXT_WORD(14 downto 12) when STORE_ADR_FORMAT = '1' else IDX_N; -- [F97]
    DBG_A5 <= AR(5); -- FalconFPGA DIAG
    DBG_SP <= ISP_REG; -- FalconFPGA DIAG STR
    DBG_AR <= AR(0) & AR(1) & AR(2) & AR(3) & AR(4) & AR(5) & AR(6) & USP_REG & ISP_REG & MSP_REG; -- [F77]
    INBUFFER: process
    begin
        wait until CLK = '1' and CLK' event;
        if AR_MARK_USED = '1' then
            AR_PNTR_WB_1 <= conv_integer(AR_SEL_WR_1);
            AR_PNTR_WB_2 <= conv_integer(AR_SEL_WR_2);
        end if;
    end process INBUFFER;

    AR_PNTR_1 <= conv_integer(AR_SEL_RD_1);
    AR_PNTR_2 <= conv_integer(AR_SEL_RD_2);

    P_IN_USE: process
    variable DELAY  : boolean;
    begin
        wait until CLK = '1' and CLK' event;
        if RESET = '1' or UNMARK = '1' then
            AR_USED_1(3) <= '0';
            AR_USED_2(3) <= '0';
            -- [COLD] 68030 reset SR is S=1 M=0.  MSBIT had no reset and
            -- only updated on AR_MARK_USED, so move.l %sp could write
            -- USP/MSP while exception stacking still used ISP.
            MSBIT <= "01";
        elsif AR_MARK_USED = '1' then
            AR_USED_1 <= '1' & AR_SEL_WR_1;
            if USE_APAIR = true then
                AR_USED_2 <= '1' & AR_SEL_WR_2;
            end if;
            MSBIT <= MBIT & SBIT;
        end if;
        --
        if RESET = '1' or UNMARK = '1' then
            ADR_WB(32) <= '0';
            DELAY := false;
        elsif ADR_MARK_USED = '1' and ADR_FAST = '1' then
            ADR_WB <= '1' & ADR_EFF_I; -- [F3] MOVEM: the next register's address is already calculated.
            DELAY := false;
        elsif ADR_MARK_USED = '1' then
            DELAY := true; -- One clock cycle address calculation delay.
        elsif DELAY = true then
            ADR_WB <= '1' & ADR_EFF_I;
            DELAY := false;
        end if;
    end process P_IN_USE; 

    -- [F116] While a full-format EA tracks a pending write-back of its index Dn (IDX_TRK, F97), report the
    -- address unit busy so the control unit holds the EA calculation (FETCH_D_LO/FETCH_MEMADR/ABS -> SWITCH_STATE
    -- for LEA/PEA, operand fetch) until INDEX holds the written value. F97 alone covered single-clock writers
    -- (lsl, add); after MULS/MULU the next PEA/LEA (bd,Dn) used Dn from before the multiply (XaAES +$3266).
    AR_IN_USE <= '1' when IDX_TRK = '1' else
                 '0' when AR_USED_1(2 downto 0) = "111" and SBIT = '1' and MSBIT(1) /= MBIT else -- Wrong stack pointer.
                 '0' when AR_USED_2(2 downto 0) = "111" and SBIT = '1' and MSBIT(1) /= MBIT else -- Wrong stack pointer.
                 '1' when AR_USED_1(3) = '1' and AR_USED_1(2 downto 0) = AR_SEL_RD_1 else
                 '1' when AR_USED_1(3) = '1' and AR_USED_1(2 downto 0) = AR_SEL_RD_2 else
                 '1' when AR_USED_2(3) = '1' and AR_USED_2(2 downto 0) = AR_SEL_RD_1 else
                 '1' when AR_USED_2(3) = '1' and AR_USED_2(2 downto 0) = AR_SEL_RD_2 else '0';
```

#### AR write: `hdl/cpu030/wf68k30L_address_registers.vhd` lines 776-784
```vhdl

        if RESET = '1' then
            AR <= (others => (Others => '0'));
        end if;
        
        if AR_WR_1 = '1' and AR_PNTR_WB_1 < 7 then
            AR(AR_PNTR_WB_1) <= AR_IN_1; -- Always written long.
        end if;
        
```

#### DR P_IN_USE after F141 (mark wins); compare with the AR side: `hdl/cpu030/wf68k30L_data_registers.vhd` lines 108-128
```vhdl
    P_IN_USE: process
    begin
        wait until CLK = '1' and CLK' event;
        -- [F141] A new mark wins over the release of the previous write-back in the same clock (MOVEQ is
        -- initialised without waiting for a pending write-back of its destination).
        if RESET = '1' then
            DR_USED_1(3) <= '0';
            DR_USED_2(3) <= '0';
        elsif DR_MARK_USED = '1' then
            DR_USED_1 <= '1' & DR_SEL_WR_1;
            if USE_DPAIR = true then
                DR_USED_2 <= '1' & DR_SEL_WR_2;
            elsif UNMARK = '1' then
                DR_USED_2(3) <= '0';
            end if;
        elsif UNMARK = '1' then
            DR_USED_1(3) <= '0';
            DR_USED_2(3) <= '0';
        end if;
    end process P_IN_USE;

```

#### ADDQ quick data: `hdl/cpu030/wf68k30L_top.vhd` lines 685-692
```vhdl
                      x"000000" & BIW_1(7 downto 0) when OP = CMPI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = EORI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = SUBI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = ORI and OP_SIZE = BYTE else
                      x"00000008" when (OP = ADDQ or OP = SUBQ) and BIW_0(11 downto 9) = "000" else
                      x"000000" & "00000" & BIW_0(11 downto 9) when OP = ADDQ or OP = SUBQ else
                      x"000000" & BIW_0(7 downto 0) when OP = MOVEQ else
                      x"00000001" when OP = DBcc else
```

#### AR_IN_1 mux: `hdl/cpu030/wf68k30L_top.vhd` lines 958-970
```vhdl
    AR_SEL_RD_1 <= "111" when BUSY_EXH = '1' else AR_SEL_RD_1_MAIN; -- ISP during exception.

    AR_WR_1_REG <= AR_WR_1 or To_Bit(MMU_AN_WR);
    AR_IN_1 <= MMU_AN_DATA when MMU_AN_WR = '1' else -- [PMMU3] PTEST A = 1 (the core is stalled by MMU_BUSY)
               DATA_TO_CORE when BUSY_EXH = '1' else
               ALU_RESULT(31 downto 0) when ALU_BSY = '1' and AR_WR_1 = '1' else
               ALU_RESULT(31 downto 0) when ALU_BSY = '1' and (DFC_WR = '1' or SFC_WR = '1' or ISP_WR = '1' or MSP_WR = '1' or USP_WR = '1') else
               -- [C3] Memory-indirect JMP/JSR: the pointer read must load MEM_ADR from the bus, not ADR_EFF.
               DATA_TO_CORE when FETCH_MEM_ADR = '1' else
               ADR_EFF when OP = JMP or OP = JSR else
               DR_OUT_1 when USE_DREG = '1' else -- CAS2: Address register from data register.
               AR_OUT_1 when OP = LINK or OP = UNLK else DATA_TO_CORE; -- Default used for RTD, RTR, RTS.

```

#### ALU latch at ALU_INIT: `hdl/cpu030/wf68k30L_alu.vhd` lines 218-228
```vhdl
begin
    PARAMETER_BUFFER: process
    begin
        wait until CLK = '1' and CLK' event;
        if ALU_INIT = '1' then
            ADR_MODE <= ADR_MODE_IN;
            CHK2CMP2_DR <= USE_DREG;
            OP_SIZE <= OP_SIZE_IN;
            OP <= OP_IN;
            BIW_0 <= BIW_0_IN;
            BIW_1 <= BIW_1_IN;
```

#### ADDQ/SUBQ An arithmetic: `hdl/cpu030/wf68k30L_alu.vhd` lines 803-815
```vhdl
            when ADDA => -- No sign extension for the destination.
                RESULT := unsigned(OP2) + unsigned(OP1_SIGNEXT);
            when ADDQ =>
                case ADR_MODE is
                    when "001" => RESULT := unsigned(OP2) + unsigned(OP1); -- No sign extension for address destination.
                    when others => RESULT := unsigned(OP2_SIGNEXT) + unsigned(OP1);
                end case;
            when SUBQ =>
                case ADR_MODE is
                    when "001" => RESULT := unsigned(OP2) - unsigned(OP1); -- No sign extension for address destination.
                    when others => RESULT := unsigned(OP2_SIGNEXT) - unsigned(OP1);
                end case;
            when ADD | ADDI =>
```

#### COF_BLK, P_BSY, PF_DEMAND (F144): `hdl/cpu030/wf68k30L_opcode_decoder.vhd` lines 245-300
```vhdl
        end if;
    end process P_BSY;

    -- [F144] BRA/BSR taken over by the control unit: its target replaces the stream, so the decoder starts
    -- no further stream read (it would be dismissed by the flush and delay the target request two clocks).
    P_COF_BLK: process
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' or BUSY_EXH = '1' then
            COF_BLK <= '0';
        elsif OW_REQ = '1' and PIPE_RDY = '1' and (OP_I = BRA or OP_I = BSR) and LOOP_BSY_I = false then
            COF_BLK <= '1';
        end if;
    end process P_COF_BLK;

    P_OPCODE_FLUSH: process
    -- If there is a pending opcode cycle during a pipe flush,
    -- an opcode mismatch will destroy scalar opcode processing.
    -- To avoid this, we have to dismiss the upcoming opcode.  
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' and OPCODE_RD_I = '1' and OPCODE_RDY = '0' then
            OPCODE_FLUSH <= '1';
        elsif OPCODE_RDY = '1' or BUSY_EXH = '1' then
            OPCODE_FLUSH <= '0';
        end if;
    end process P_OPCODE_FLUSH;

    OPCODE_RD <= OPCODE_RD_I;
    PIPE_FULL <= '1' when IPIPE_PNTR = 3 else '0'; -- [F140]
    -- [F140] OPCODE_RD_I is cleared by OPCODE_RDY, so a word could only be requested every other clock.
    -- In the clock of a ready strobe, ask the prefetch queue for the next word as well when the pipe has
    -- room for it after this one is loaded (pointer below 2), so a queue holding words (cache hits)
    -- fills the pipe at one word per clock as the 68030 pipeline. Not during flush, dismissal,
    -- exceptions or loop mode; the bus interface uses it only for queue hits, never to start a bus cycle.
    -- Only on demand (the control unit waits for an operation or extension word), so the pipe does not run
    -- further ahead of execution than before and the stream prefetch placement is unchanged.
    OPC_RD_NEXT <= '1' when OPCODE_RDY = '1' and OPCODE_FLUSH = '0' and IPIPE_FLUSH = '0' and BUSY_EXH = '0' and
                            IPIPE_PNTR < 2 and (OW_REQ = '1' or EW_REQ = '1') and LOOP_ATN = false and LOOP_BSY_I = false else '0';
    OPCODE_DISMISS <= OPCODE_FLUSH; -- [F62c]

    -- [PFCOF] The control unit executes a change of flow (COF_PEND): hold the stream fetches past it,
    -- as the 68030/CPU32 bus controller. Any wait of the control unit for an operation or extension word
    -- (PF_DEMAND) lifts the hold, as do exceptions, loop mode and the flush itself, so a wrong COF_PEND
    -- costs time only. (A decoder-side detection at the head of the pipe was tried and was slower: it
    -- also blocks words of the running instruction's look-ahead; see docs/PREFETCH_COF.md.)
    PF_DEMAND <= '1' when OW_REQ = '1' and PIPE_RDY = '0' else
                 '1' when EW_REQ = '1' and IPIPE_PNTR = 0 else '0';

    -- [PFCOF2] Predecode, as the 68030 pipeline recognises a change of flow before it executes: the
    -- instruction stream ahead of the decoder (pipe words D, C, B, then the prefetch queue) is scanned for
    -- a change-of-flow operation word whose words (at least two: the decoder takes two to deliver one) are
    -- all present. Unconditional ones (BRA, BSR, JMP/JSR (An)/d16(An)/xxx.W/d16(PC)/xxx.L, RTS, RTE, RTR,
    -- RTD), DBcc, and Bcc with a backward displacement (loops; a forward Bcc may fall through). The words
    -- are not known to be operation words (they can be extension or immediate data); a wrong guess only
    -- delays the next fetch, because any wait of the control unit for a word (PF_DEMAND) lifts the hold.
```

#### OPD_ACK / opword handshake: `hdl/cpu030/wf68k30L_opcode_decoder.vhd` lines 370-445
```vhdl
            IPIPE.D <= (others => '0');
            IPIPE.C <= (others => '0');
            IPIPE.B <= (others => '0');
            IPIPE_PNTR <= 0;
        elsif BKPT_INSERT = '1' then
            IPIPE_D_VAR := IPIPE.D;
            IPIPE.D <= BKPT_DATA; -- Insert the breakpoint data.
            BKPT_REQ <= '1';
        elsif OW_REQ = '1' and BKPT_REQ = '1' then
            IPIPE.D <= IPIPE_D_VAR; -- Restore from breakpoint.
            BKPT_REQ <= '0';
        elsif LOOP_ATN = true and OPCODE_RD_I = '1' then
            null; -- Wait for pending opcodes.
        elsif OW_REQ = '1' and PIPE_RDY = '1' and OP_I = DBcc and LOOP_OP = true and IPIPE.C = x"FFFC" then -- Initialize the loop.
            IPIPE.D <= BIW_0; -- This is the LEVEL D operation for the loop.
        elsif OW_REQ = '1' and LOOP_BSY_I = true then
            IPIPE.D <= BIW_0; -- Recycle the loop operations.
        elsif LOOP_BSY_I = true then
            null; -- Do not change the pipe during the loop.
        elsif OW_REQ = '1' and INSTR_LVL = D and PIPE_RDY = '1' and IPIPE_PNTR = 2 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= not OPCODE_VALID;
            else
                IPIPE.D <= IPIPE.C;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = D and PIPE_RDY = '1' and IPIPE_PNTR = 3 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= IPIPE.B;
                IPIPE.B <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= IPIPE_B_FAULT;
                IPIPE_B_FAULT <= not OPCODE_VALID;
            else
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= IPIPE.B;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= IPIPE_B_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = C and PIPE_RDY = '1' and IPIPE_PNTR = 2 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= OPCODE_DATA;
                IPIPE_D_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            else
                IPIPE_PNTR <= 0;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = C and PIPE_RDY = '1' and IPIPE_PNTR = 3 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.B;
                IPIPE.C <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_B_FAULT;
                IPIPE_C_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            else
                IPIPE.D <= IPIPE.B;
                IPIPE_D_FAULT <= IPIPE_B_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 2;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = B and PIPE_RDY = '1' then -- IPIPE_PNTR = 3.
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= OPCODE_DATA;
                IPIPE_D_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 2;
            else
                IPIPE_PNTR <= 0;
            end if;
        elsif EW_REQ = '1' and IPIPE_PNTR >= 1 then
            case IPIPE_PNTR is
                when 3 =>
```

#### I-cache miss lock (F144): `hdl/cpu030/wf68k30L_bus_interface.vhd` lines 930-945
```vhdl
    -- [XH1] A long is requested while the queue still holds two words (was Q_CNT <= 1), so the stream keeps the
    -- bus busy across operand cycles (W->R, R->R, MOVEM.W, stack). Exception processing keeps the old threshold.
    -- [IC] A long word the instruction cache holds is taken from the cache (P_QUEUE) and never starts a bus
    -- cycle. With nothing cached (CIIN asserted on every cycle) IC_HIT is 0 and PF_REQ is the old request.
    PF_REQ <= PF_REQ_RAW and not To_Bit(IC_HIT) and not RMC_HOLD; -- [RMC1] no prefetch between the locked read and its write
    IC_TAKE <= PF_REQ_RAW and To_Bit(IC_HIT) and not Q_MISS and not RESET_CPU_I;
    -- [F144] Stream restart (branch target, Q_MISS) with no prefetch in flight: look the requested long up in the
    -- instruction cache in the restart clock and queue it at once (IC_MTAKE), one clock earlier than the IC_TAKE
    -- of the next clock. The 68030 starts the target fetch from the cache when the branch resolves.
    IC_MISS_LK <= '1' when Q_MISS = '1' and INFL = '0' and RMC_HOLD = '0' and RESET_CPU_I = '0' else '0';
    IC_MTAKE <= IC_MISS_LK and To_Bit(IC_HIT);
    IC_LK_ADR <= OPC_ADR(31 downto 2) when IC_MISS_LK = '1' else F_ADR(31 downto 2);
    IC_LK_FC2 <= OPC_FC(2) when IC_MISS_LK = '1' else Q_FC(2); -- [F144]
    -- [IC] Fill: every bus prefetch long reports its end with, per word, "no bus error and CIIN negated on its
    -- portion" (MC68030UM 5.7.1, 6.1.3.1 single entry mode). The cache fills aligned longs whose two words are
    -- OK, assembles the longs of a misaligned stream (4n+2 start) from consecutive fetches, and checks EI, FI
```

#### IC_MTAKE queue load: `hdl/cpu030/wf68k30L_bus_interface.vhd` lines 1400-1415
```vhdl
                Q_FC <= OPC_FC;
                F_ADR <= OPC_ADR(31 downto 1);
                if (INFL = '1' and PF_DONE = '0') or PF_START = '1' then
                    INFL_STALE <= '1';
                end if;
            end if;
            -- [F144] The restart long from the instruction cache (IC_MTAKE, see above).
            if IC_MTAKE = '1' then
                if OPC_ADR(1) = '0' then
                    W(0) := IC_HIT_DATA(31 downto 16); F(0) := '0'; C(0) := '1';
                    W(1) := IC_HIT_DATA(15 downto 0); F(1) := '0'; C(1) := '1'; CNT := 2;
                    F_ADR <= OPC_ADR(31 downto 1) + "10";
                else
                    W(0) := IC_HIT_DATA(15 downto 0); F(0) := '0'; C(0) := '1'; CNT := 1;
                    F_ADR <= OPC_ADR(31 downto 1) + '1';
                end if;
```

## Questions (answer each)
1. Combinational loops or long glitch-prone combinational paths created by EARLY_OW: OW_REQ_MAIN depends on
   NEXT_FETCH_STATE (FETCH_DEC, which reads OPD_ACK/OW_RDY and AR_IN_USE), and the decoder's acknowledge feeds
   back. Is any path combinational from OW_REQ back into OW_REQ, PIPE_RDY or AR_IN_USE?
2. Glitch-sensitive combinational signals used as clock enables, async resets or latch gates (anything that
   would differ with routing while static timing still passes).
3. Async resets or set/reset flops in this path; inferred latches; read-during-write on the register-file
   inference (AR array, BRAM vs LUTRAM) when the An write-back and the next instruction's An read share a clock.
4. X/'U'/uninitialised states or integer/enum encodings that GHDL masks but synthesis resolves differently
   (FETCH_STATES/EXEC_WB_STATES encoding, AR_PNTR_WB_1 integer range, bit vs std_logic).
5. Hazard: ADDQ/SUBQ An write-back (AR_WR_1 from OP_WB_I/BIW_0_WB, AR_PNTR_WB_1 latched at AR_MARK_USED)
   against the early-issued next instruction's mark or read. Can the next AR_MARK_USED move AR_PNTR_WB_1 before
   the ADDQ write lands? Can UNMARK (priority) clear the next instruction's mark? Can MSBIT reset to "01" on
   UNMARK and steer an SP write to the wrong stack pointer?
6. The incomplete sensitivity lists above (MV_RW_WB at control 3086 in particular): any effect here?
7. Why would ADDQ/SUBQ #,An fail but ADDA/SUBA (same An write path) and Dn forms pass? Consider DATA_IMMEDIATE
   from BIW_0(11:9) and AR_SEL_RD_2 = BIW_0(2:0) read after the opword has advanced, UPDT_CC=0, and word-size
   ADDQ An still written as 32 bits.

## Deliverables
Ranked hypotheses; a minimal VHDL fix tagged `[F145]` (revision line in the file header, licence header kept;
no relaxed constraints or hacks); a GHDL test program (68k asm for tb030 at $FC0000, CIMODE=1 code at $FD0000,
results written at $5000, done marker $600DC0DE at $3300) that fails without the fix and passes with it; and a
board check (cold boot of the AUTO LOOPTEST floppy shows the LOOPTEST screen; also MiNT boot).
Never faster than MC68030UM section 11 timing.
