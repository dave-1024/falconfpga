------------------------------------------------------------------------
----                                                                ----
---- WF68K30L IP Core: this is the main controller to handle all    ----
---- integer instructions.                                          ----
----                                                                ----
---- Description:                                                   ----
---- This controller handles all integer instructions and provides  ----
---- all required system control signals. The instructions are      ----
---- requested from the instruction prefetch unit in the opcode     ----
---- decoder unit. The data is mostly written to the ALU and after- ----
---- wards from the ALU to the writeback logic. This pipelined      ----
---- structure requires a correct management of data in use. Any    ----
---- address or data registers or memory addresses which are in use ----
---- are marked by a flag not to be used befor written back. Any    ----
---- time data or address reegisters or the effective address are   ----
---- in the writeback pipe, the respective use flag is evaluated.   ----
---- Instructions like MOVE read unused source and the destination  ----
---- is written, when the ALU and writeback controller 'free'.      ----
---- Instructions like ADD, SUB etc. read unused source and desti-  ----
---- nations and write back the destination, when the operands are  ----
---- not used any more and the ALU and writeback controller are not ----
---- in use by another operation.                                   ----
---- The main controller is the second pipeline stage of the CPU.   ----
---- The pipelining structure also requires some special treatment  ----
---- for the system control instructions as described as follows:   ----
------------------------------------------------------------------------
---- System Control Instructions:                                   ----
---- There are several instructions which require the instruction   ----
---- pipe to be flushed as described in the following. For further  ----
---- information refer to the 68Kxx data sheets.                    ----
----                                                                ----
---- 1. TRAP generating:                                            ----
----     The following instructions result in a pipe flush when the ----
----     exception handler takes control over the system:           ----
----     BKPT, CHK, ILLEGAL, TRAP, TRAPV                            ----
----     There are some other indirect conditions flushing the pipe ----
----     such as the STOP which is invoked by an external interrupt.----
----                                                                ----
---- 2. Priviledge violations:                                      ----
----     Some instructions may result in a priviledge violation     ----
----     when executed in user space. The result will be a          ----
----     priviledge violation trap and the ipipe is flushed when    ----
----     the exception handler takes over. The instructions are:    ----
----     ANDI_TO_SR, EORI_TO_SR, ORI_TO_SR, MOVEC, MOVES, MOVE_USP, ----
----     MOVE_FROM_SR, MOVE_TO_SR, RESET, RTE and STOP              ----
----                                                                ----
---- 3. Branches and Jumps:                                         ----
----    In case of branches and jumps and the respective return     ----
----    operations it is required to flush the instruction pipe.    ---- 
----    If PC value changes due to any branch or jump, it is neces- ----
----    sary to flush the instruction pipe to invalidate already    ----
----    loaded 'old' instructions. This affects:                    ----
----    BRA, BSR, Bcc, DBcc, JMP, JSR and the returns:              ----
----    RTD, RTR, RTS, RTE and also STOP.                           ----
----                                                                ----
------------------------------------------------------------------------
---- Data hazards:                                                  ----
----    To avoid malfunction by using old data several things have  ----
----    to be taken into account:                                   ----
----    1. Operations manipulating the system registers must wait   ----
----      in the end of the operation until the ALU has updated     ----
----      the condition codes. These operations are ANDI_TO_SR,     ----
----      EORI_TO_SR, ORI_TO_SR, MOVE_TO_SR and MOVEC.              ----
----    2. Operations using the staus register must not start until ----
----      the ALU has updated the condition codes. These operations ----
----      are MOVE_FROM_CCR, MOVE_FROM_SR and MOVEC.                ----
----    3. Operations using the stack pointer must not start until  ----
----      the stack pointer is updated by the previous operation.   ----
----      Operations using the stack pointer are RTD, RTR, RTS,     ----
----      MOVEC, MOVE_USP and UNLK.                                 ----
----    4. Operations manipulating the stack pointer without using  ----
----      the ALU must not start until the stack is written by the  ----
----      previous operation. Stack pointer manipulating operations ----
----      are BSR, JSR, LINK and PEA.                               ----
------------------------------------------------------------------------
----                                                                ----
---- Remarks:                                                       ----
----                                                                ----
---- Author(s):                                                     ----
---- - Wolfgang Foerster, wf@experiment-s.de; wf@inventronik.de     ----
----                                                                ----
------------------------------------------------------------------------
----                                                                ----
---- Copyright © 2014-2019 Wolfgang Foerster Inventronik GmbH.      ----
----                                                                ----
---- This documentation describes Open Hardware and is licensed     ----
---- under the CERN OHL v. 1.2. You may redistribute and modify     ----
---- this documentation under the terms of the CERN OHL v.1.2.      ----
---- (http://ohwr.org/cernohl). This documentation is distributed   ----
---- WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING OF          ----
---- MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A        ----
---- PARTICULAR PURPOSE. Please see the CERN OHL v.1.2 for          ----
---- applicable conditions                                          ----
----                                                                ----
------------------------------------------------------------------------
-- 
-- Revision History
-- 
-- Revision 2K14B 20141201 WF
--   Initial Release.
-- Revision 2K16A 20160620 WF
--   Fixed a bug in the MOVEM operation.
-- Revision 2K18A (unreleased) WF
--   Fixed a bug in MOVE An,-(Ay). Thanks to Gary Bingham for the support.
--   Fixed wrong PEA behaviour.
--   Fixed the displacement for LINK.
--   Fixed AR_MARK_USED in LINK.
--   Fixed the operation size for MOVEQ.
--   ADDQ, SUBQ Fix: address registers are always written long.
--   ADDI, ANDI, EORI, ORI, SUBI: address is not marked used if destination is Dn.
--   ADDI, ANDI, EORI, ORI, SUBI: data register is marked used if destination is Dn.
--   EXG: rearranged logic to meet the new top level multiplexers.
--   LINK, UNLK: wait in START_OP until the ALU is ready (avoids possible data hazards).
--   LINK, UNLK: fixed the write back operation size.
--   MOVEM: Fixed predecrement mode for consecutive MOVEM -(An).
--   MOVEP: MOVEP_PNTR is now correct for consecutive MOVEP.
--   MOVEP: avoid structural hazard in SWITCH_STATE by waiting for ALU.
--   EOR: fixed a bug in the writeback mechanism.
--   BSR, JSR: EXEC_WB state machine waits now for ALU_INIT. Avoid structural / data hazard.
--   The instruction pipe is not flushed for ANDI_TO_CCR, EORI_TO_CCR, ORI_TO_CCR.
--   The instruction pipe is not flushed for MOVE_FROM_CCR, MOVE_TO_CCR, MOVE_FROM_SR, MOVE_USP, MOVEC.
--   Modifications in the FETCH state machine to avoid several data hazards for MOVEM, MOVE_FROM_CCR, MOVE_FROM_SR.
--   Modifications in the FETCH state machine to avoid several data hazards for ANDI_TO_CCR, ANDI_TO_SR, EORI_TO_CCR, EORI_TO_SR, ORI_TO_CCR, ORI_TO_SR.
--   We have to stop a pending operation in case of a pending interrupt. This is done by rejecting OW_RDY.
--   TOP, CONTROL, Exception Handler Opcode Decoder: Rearranged PC_INC and ipipe flush logic.
--   Write the undecremented Register for MOVE Ax, -(Ax).
--   LINK A7 and PEA(A7) stacks the undecremented A7.
--   Control: LINK A7 and PEA(A7) stacks the undecremented A7.
--   Bus interface: Rearranged the DATA_RDY vs. BUS_FLT logic.
--   UNMARK is now asserted in the end of the write cycle. This avoids data hazards.
--   Fixed a MOVEC writeback issue (use BIW_WB... instead of BIW_...).
--   Fixed a USP writeback issue (use BIW_WB... instead of BIW_...).
--   Introduced a switch NO_PIPELINE.
--   MOVEM-Fix: the effective address in memory to register is stored (STORE_AEFF) not to be overwritten in case the addressing register is also loaded.
--   DBcc: fixed a data hazard for DBcc_COND evaluation by waiting on the ALU result.
--   Fixed DR_WR_1 locking against AR_WR_2.
--   IPIPE is flushed, when there is a memory space change in the end of xx_TO_SR operations.
--   To handle correct addressing, ADR_OFFSET is now cleared right in the end of the respective operation.
--   Fixed a bug in EOR writing back in register direct mode.
--   ADDQ and SUBQ: fixed (An)+ mode. An increments now.
--   Fixed DIVS, DIVU in memory address modes (wrong control flow).
--   ADDQ and SUBQ: fixed condition code control UPDT_CC.
--   Fixed a data hazard bug using addressing modes with index register.
--   Implemented the 68K10 loop mechanism.
--   Fixed several pipelinig issues (hazards).
-- Revision 2K19A 20190419 WF
--   Introdeced a new state CALC_AEFF which results in no need of ADR_ATN and a twice highre fmax.
-- FalconFPGA modifications (David Dunne, github.com/dave-1024/falconfpga), CERN OHL v1.2.
-- Changes are tagged Fnn in the code. Dates are from git history.
-- Base: WF68K30L 2K19A (this repo's import of 2026-09-24).
--   2026-09-30 F11: CACR/CAAR via MOVEC.
--   2026-09-30 F21-F25: bit field byte count, register wrap, BFINS pattern, width, BFSET typo.
--   2026-09-30 COLD: MSBIT reset; single ISP write chain.
--   2026-09-30 F42-F54: reset and power-up values (SR $2700, no spurious traps).
--   2026-10-03 F56: combinational loops and BF_NZ latch removed; hazard selects.
--   2026-10-08 F62/F62b/F62c: opcode prefetch queue (PREFETCH_Q).
--   2026-10-09 F62d: JSR waits for a pending A7 writeback.
--   2026-10-15 F66: a bus-errored operand read ends the instruction, no register writeback (MC68030).
--   2026-10-16 PH2-FMAX: register-mode PACK/UNPK START_OP address select without the DR_IN_USE term (timing, same cycles).
--   2026-11-18 F166: the F165 write overlap again for a following MOVE (F166_MV_OLAP). The operation part of WR_OLAP
--     (which write-back operation, which waiting operation) is now a flip flop (WR_OLAP_Q) computed in the clock
--     before from the same registered OP/BIW_0/OP_WB_I (they cannot change while the operation waits in INIT_EXEC_WB),
--     so the acknowledge clock only ANDs WR_OLAP_Q with WR_RDY/DATA_VALID and the state flags (as the F157 REARM
--     qualifier). MOVE's INIT terms use ALU_BSY_MV (ALU_BSY or WR_OLAP; no F3_EARLY/WR_EARLY MOVEM term), and the
--     MOVE destination address mode is selected for the whole INIT_EXEC_WB stay (F166_MV_AMODE, not only once the
--     ALU is free): AR_SEL_RD_1/AMODE_SEL already point at the destination there and nothing else reads the
--     address unit while the operation waits, so the acknowledge is not in the ADR_MODE -> address chain.
--     MOVE Dn,(An)/-(An)/(An)+ 6 -> 5, Dn,d16(An) 8 -> 7, Dn,abs.L 9 -> 8 clocks (back to back).
--   2026-11-18 F165: memory-source operations with a data register destination (MOVE <ea>,Dn, ADD/SUB/AND/OR/CMP
--     <ea>,Dn, TST <ea>, CMPI/BTST #,<ea>) ask for the next operation word in INIT_EXEC_WB (F165_MEM_EI, as the
--     F141 register-only early issue): the operand read is complete and valid (RD_OK), so nothing can fault any
--     more. No address register destination (F145/F159 An early-issue race); (An)+/-(An) are updated before INIT.
--     F165_MEM_FAST: the same operations skip INIT_EXEC_WB when the ALU is idle: in the FETCH_OPERAND clock their
--     read ends (RD_RDY with DATA_VALID; DATA_TO_CORE = DBUFFER) the operand goes straight into the ALU (ALU_INIT),
--     the destination Dn is marked and the next operation word is requested, and the state goes to START_OP (as
--     the F161 RTS). Not with trace, an interrupt hot, an exception request, loop mode, an MMU operation or a
--     write fault (INT_TRIG needs INIT/SLEEP; those cases keep the INIT path). MOVE/ADD (An),Dn 9 -> 7 clocks.
--     F165_WR_OLAP: Option A (MOVEM) for single-write operations: the next operation waiting in INIT_EXEC_WB is
--     loaded in the clock the write is acknowledged without a fault (WR_RDY with DATA_VALID; data and address are
--     in the bus latches), WRITE_DEST -> EXECUTE. Old: MOVE/CLR/ADD/SUB/AND/OR/EOR/ADDQ/SUBQ/ADDI/SUBI/ANDI/ORI/
--     EORI/NEG/NOT to memory. New: those except MOVE, plus CMP/TST/CMPI, MOVEQ, EXT, SWAP (no address register
--     destination, no padded ALU operation). Not a following MOVE: making MOVE's INIT terms (ADR_MODE, PHASE2) see
--     the write acknowledge put WR_EARLY in front of the PHASE2/DR_SEL/NEXT_FETCH_STATE chain (14.2 MHz). One clock.
--     F165_EW_B2B: the next extension word is requested in the clock the previous one is acknowledged in
--     FETCH_ABS_HI, FETCH_IDATA_B2, FETCH_D_HI and FETCH_OD_HI (decoded from FETCH_STATE, not NEXT_FETCH_STATE,
--     for timing), so the low word is there on entry: abs.L, #.L and 32-bit displacements one clock shorter.
--   2026-11-18 F163: CCR_IN is forwarded from the ALU on its ALU_ACK clock, so a taken Bcc.B may decide early (BCC_EARLY)
--     while ADDQ/SUBQ/CMP/TST/ADD/SUB/AND/OR/EOR/MOVEQ (register destination) finishes (F163_CCR_FWD).
--     subq/bcc.s loop 9 -> 8 clocks (MC68030UM 8).
--   2026-11-18 F162: MOVEQ written in EXECUTE (F162_MQ, as the F157c ops), so a dependent op issues 2 clocks later
--     (straight-line register code at the MC68030UM 2 clocks per op). A taken Bcc.B that missed its OPD_ACK clock
--     (ALU still busy with the previous op) flushes in INIT_EXEC_WB from the live CCR (F162_BCC_INIT), like BRA.
--   2026-11-18 F161: RTS leaves FETCH_OPERAND for START_OP in the clock its return address is ready (RD_RDY with
--     DATA_VALID, DATA_TO_CORE = DBUFFER): PC_LOAD and the flush one clock earlier, no INIT_EXEC_WB pass (the
--     RTS ALU pass writes nothing; SP was already incremented in FETCH_OPERAND). Only with the ALU idle (AR_IN_1
--     = DATA_TO_CORE), trace off, no interrupt hot (INT_TRIG needs INIT/SLEEP), no exception request, no MMU
--     operation or write fault (F161_RTS_EARLY). Bus-errored reads keep the old path. RTS -1 clock.
--   2026-11-18 F161: taken DBcc completes in its OPD_ACK (START_OP) clock (F161_DBCC_EARLY), as the F160
--     early Bcc.B. Condition false from the live CCR (BCC_LCOND), count not expiring (Dn.W /= 0, DBCC_DNZ
--     from the unforwarded register file with no data register write this clock), ALU idle, Dn not in
--     use, no SR writer in write-back, trace off, no interrupt hot, no exception request, no loop mode
--     and d16 /= -4 (68010 loop-mode entry), no MMU operation or write fault: the pipe is flushed, PC
--     loads PC + 2 + d16 and Dn.W - 1 is written by the register file's DR_DEC port (no ALU pass).
--     DBF (cc = F, no CCR use) may also complete while the ALU finishes a simple register operation
--     (no trap possible, EXECUTE/WRITEBACK only, no memory destination); other DBcc need the ALU idle.
--     Taken DBcc 10 -> 6/7 clocks (MC68030UM 6; 7 when the target is a two-word instruction). Expired / cc
--     true keep the ALU path. Expired DBcc (count -1, not loop mode) is padded in SLEEP (F161_DBCC_XPAD;
--     unpadded it took 5, below the MC68030UM 10) so the dbf_expired harness is at or just under the UM 14
--     (leave SLEEP at DBCC_CNT = 5). Prefer slightly faster than over the manual when 10 exactly is not hit.
--   2026-11-18 F160: taken Bcc.B decided and flushed in its OPD_ACK (START_OP) clock (F160_BCC_EARLY).
--     When the condition codes are settled (ALU idle, no SR writer in write-back), trace off, no
--     interrupt hot, no exception request, no loop mode, no MMU operation and the operation word is
--     valid, a Bcc with an 8-bit displacement whose condition (live CCR, CCR_IN) is true flushes the
--     pipe and loads PC + 2 + d8 in the acknowledge clock and stays in START_OP (OW_RDY cleared), like
--     a BRA without the INIT_EXEC_WB clock and the ALU handshake. Taken Bcc.B 8 -> 6 clocks
--     (MC68030UM 6). Not taken and .W/.L keep the ALU_COND path (not taken never below the UM 4).
--   2026-11-18 F159: EARLY_ISSUE on again (stopgap): all F145 register-only
--     groups except ADDA/SUBA. Board bisect of the TOS 2.06 stacked-menu /
--     same-X icon bug (F145 first-bad) pinned it on early issue of ADDA/SUBA
--     with a Dn/An source (g2an FAIL). CMP/TST early issue is clean (g2cmp
--     PASS). ADDQ/SUBQ #,An stay excluded (F145).
--   2026-11-17 F157z: EARLY_ISSUE := false again (F143-safe). TOS 2.06 board bisect
--     2026-11-17: last-good F144 / first-bad F145; stacked menu titles and missing A: icon.
--   2026-11-04 F145: early issue on again (EARLY_ISSUE = true) except ADDQ/SUBQ #,An; EXEC_WB_DEC sensitivity list completed (MV_RW_WB).
--   2026-11-04 F143: F141 early issue disabled (EARLY_ISSUE = false) after the board AUTO failure; MOVEQ hazard change kept.
--   2026-11-04 F142: CMPA Rn,An one clock longer (4, as the manual; it was faster).
--   2026-11-04 F141: early OW_REQ in INIT_EXEC_WB for register-only instructions (2-clock issue, MC68030UM 11.6).
--   2026-11-09 F157a: keep the opcode pipe two words deep (decoder/bus) and overlap the next
--     INIT with WRITEBACK (ALU_TRIG during WRITEBACK, ALU_REQ re-arm, UNMARK, WRITEBACK->EXECUTE).
--     Constant F157_PHASE_A. Writes stay in WRITEBACK. MOVEQ/NOP target: 2 clocks.
--     [F157c] F157_PHASE_B: combo RESULT + write in EXECUTE for ADD/ADDQ/AND/NEG/NOT/CLR (reg dest).
--

use work.WF68K30L_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity WF68K30L_CONTROL is
    generic(NO_PIPELINE     : boolean := false); -- If true the controller work in scalar mode.
    port (
        CLK                 : in std_logic; -- System clock.
        RESET_CPU           : in bit; -- CPU reset.
    
        BUSY                : out bit; -- Main controller finished an execution.
        BUSY_EXH            : in bit;
        EXH_REQ             : in bit;
        INT_TRIG            : out bit;
        IRQ_HOT             : in bit; -- [F141] Interrupt may be taken after this instruction.

        OW_REQ              : out bit; -- Operation words request.
        OW_VALID            : in std_logic; -- Operation words is valid.
        EW_REQ              : out bit; -- Extension word request.
        EW_ACK              : in bit; -- Extension word available.
        OPD_ACK             : in bit; -- Opcode has new data.

        ADR_MARK_USED       : out bit;
        ADR_IN_USE          : in bit;
        ADR_OFFSET          : out std_logic_vector(5 downto 0);

        DATA_RD             : out bit;
        DATA_WR             : out bit;
        DATA_RDY            : in bit;
        DATA_VALID          : in std_logic;
        RMC                 : out bit;

        FETCH_MEM_ADR       : out bit;
        MI_HOLD             : out bit; -- [MI1] Memory indirect: hold queue prefetches for the pointer/operand reads.
        LOAD_OP1            : out bit;
        LOAD_OP2            : out bit;
        LOAD_OP3            : out bit;
        STORE_ADR_FORMAT    : out bit;
        STORE_D16           : out bit;
        STORE_D32_LO        : out bit;
        STORE_D32_HI        : out bit;
        STORE_DISPL         : out bit;
        STORE_OD_HI         : out bit;
        STORE_OD_LO         : out bit;
        STORE_ABS_HI        : out bit;
        STORE_ABS_LO        : out bit;
        STORE_IDATA_B2      : out bit;
        STORE_IDATA_B1      : out bit;
        STORE_MEM_ADR       : out bit;
        STORE_AEFF          : out bit;

        -- System control signals:
        OP                  : in OP_68K;
        OP_SIZE             : out OP_SIZETYPE;
        BIW_0               : in std_logic_vector(13 downto 0);
        BIW_1               : in std_logic_vector(15 downto 0);
        BIW_2               : in std_logic_vector(15 downto 0);
        EXT_WORD            : in std_logic_vector(15 downto 0);

        ADR_MODE            : out std_logic_vector(2 downto 0);
        AMODE_SEL           : out std_logic_vector(2 downto 0);
        USE_DREG            : out bit;
        HILOn               : out bit;
        BF_BYTES_OUT        : out integer range 0 to 5; -- F21/H29: the ALU needs the
                                                        -- SAME byte count, incl. the
                                                        -- =4 register-access case.

        OP_WB               : out OP_68K;
        OP_SIZE_WB          : out OP_SIZETYPE;
        BIW_0_WB_73         : out std_logic_vector(7 downto 3); -- Used for EXG.

        AR_MARK_USED        : out bit;
        USE_APAIR           : out boolean;
        AR_IN_USE           : in bit;
        AR_SEL_RD_1         : out std_logic_vector(2 downto 0);
        AR_SEL_RD_2         : out std_logic_vector(2 downto 0);
        AR_SEL_WR_1         : out std_logic_vector(2 downto 0);
        AR_SEL_WR_2         : out std_logic_vector(2 downto 0);
        AR_INC              : out bit;
        AR_DEC              : out bit;
        MV_SAVE             : out bit;
        MV_RESTORE          : out bit;
        AR_WR_1             : out bit;
        AR_WR_2             : out bit;

        DR_MARK_USED        : out bit;
        USE_DPAIR           : out boolean;
        DR_IN_USE           : in bit;
        DR_SEL_WR_1         : out std_logic_vector(2 downto 0);
        DR_SEL_WR_2         : out std_logic_vector(2 downto 0);
        DR_SEL_RD_1         : out std_logic_vector(2 downto 0);
        DR_SEL_RD_2         : out std_logic_vector(2 downto 0);
        DR_SEL_ADH_2        : out std_logic_vector(2 downto 0); -- F56: data hazard check selects
        DR_SEL_ADH_3        : out std_logic_vector(2 downto 0);
        DR_WR_1             : out bit;
        DR_WR_2             : out bit;

        UNMARK              : out bit;

        DISPLACEMENT        : out std_logic_vector(31 downto 0);
        PC_ADD_DISPL        : out bit;
        PC_LOAD             : out bit;
        PC_INC_EXH          : in bit;

        SP_ADD_DISPL        : out bit;

        DFC_WR              : out bit;
        DFC_RD              : out bit;
        SFC_WR              : out bit;
        SFC_RD              : out bit;

        VBR_WR              : out bit;
        VBR_RD              : out bit;

        CACR_WR             : out bit;
        PMMU_WR             : out bit; -- [PMMU1] PMOVE <ea>,MRn writeback strobe.
        PMMU_WR_SEL         : out std_logic_vector(5 downto 0); -- [PMMU1] Ext word bits 15-10 of that PMOVE.
        PMMU_FD             : out std_logic; -- [PMMU2b] FD bit (ext word bit 8) of that PMOVE.
        PMMU_OP             : out std_logic; -- [PMMU2b] PFLUSH/PLOAD/PTEST writeback strobe (EA on the ALU result).
        PMMU_EXT            : out std_logic_vector(15 downto 0); -- [PMMU2b] its extension word.
        MMU_BUSY            : in std_logic := '0'; -- [PMMU2b] MMU operation still running: no next opcode.
        PMMU_RD_SEL         : out std_logic_vector(5 downto 0); -- [PMMU1] Ext word bits 15-10 of the current PMOVE.
        PMMU_LD_HI          : out bit; -- [PMMU1] Upper long of a CRP/SRP read is on DATA_TO_CORE.
        PMMU_LO             : out bit; -- [PMMU1] Second (lower) long of a CRP/SRP transfer.
        CACR_RD             : out bit;
        CAAR_WR             : out bit;
        CAAR_RD             : out bit;

        ISP_RD              : out bit;
        ISP_WR              : out bit;
        MSP_RD              : out bit;
        MSP_WR              : out bit;
        USP_RD              : out bit;
        USP_WR              : out bit;

        IPIPE_FLUSH         : out bit; -- Abandon the instruction pipeline.
        COF_PEND            : out bit; -- [PFCOF] A taken change of flow executes: start no further stream fetches.

        ALU_INIT            : out bit;
        ALU_BSY             : in bit;
        ALU_REQ             : in bit;
        ALU_ACK             : out bit;
        WR_EARLY            : in bit; -- [F3]
        WR_TAKE             : out bit; -- [F3]
        F3_BYP              : out bit; -- [F3]
        ADR_FAST            : out bit; -- [F3]

        BKPT_CYCLE          : out bit;
        BKPT_INSERT         : out bit;

        LOOP_BSY            : in bit;
        LOOP_SPLIT          : out boolean;
        LOOP_EXIT           : out bit;

        BF_OFFSET           : in Std_Logic_Vector(2 downto 0);
        BF_WIDTH            : in Std_Logic_Vector(5 downto 0);

        SR_WR               : out bit;
        MOVEM_ADn           : out bit;
        MOVEP_PNTR          : out integer range 0 to 3;
        CC_UPDT             : out bit;
        TRACE_MODE          : in std_logic_vector(1 downto 0);
        VBIT                : in std_logic;
        ALU_COND            : in boolean;
        CCR_IN              : in std_logic_vector(4 downto 0); -- [F160] live X N Z V C for the early Bcc.
        DBCC_DNZ            : in bit; -- [F161] Dn.W /= 0 (unforwarded, no data register write this clock).
        DR_DEC              : out bit; -- [F161] Dn.W - 1 (early taken DBcc, register file port).
        DBcc_COND           : in boolean;
        BRANCH_ATN          : in bit;
        RESET_STRB          : out bit;
        BERR                : out bit;
        BERR_IBOUND         : out bit; -- [FLT2] Data write fault at an instruction boundary (format $A).
        BERR_PCSTALE        : out bit; -- [F131] ... and the next instruction is not issued yet: PC_I is still the faulted one.
        MOVEM_RA            : out bit; -- [F2] MOVEM memory to register waits for a read and more registers follow.
        STATUSn             : out bit;
        EX_TRACE            : out bit;
        TRAP_cc             : out bit;
        TRAP_ILLEGAL        : out bit; -- Used for BKPT.
        TRAP_V              : out bit
    );
end entity WF68K30L_CONTROL;

architecture BEHAVIOUR of WF68K30L_CONTROL is
-- F21/H29: BF_BYTEMATRIX and BF_BYTES_I moved to WF68K30L_PKG so the ALU
-- can derive the same byte count (see alu.vhd bit field bounds).

--
type FETCH_STATES is (START_OP, CALC_AEFF, FETCH_DISPL, FETCH_EXWORD_1, FETCH_D_LO, FETCH_D_HI, FETCH_OD_HI, FETCH_OD_LO, FETCH_ABS_HI, 
                      FETCH_ABS_LO, FETCH_IDATA_B2, FETCH_IDATA_B1, FETCH_MEMADR, FETCH_OPERAND, INIT_EXEC_WB, SLEEP, SWITCH_STATE);
type EXEC_WB_STATES is (IDLE, EXECUTE, ADR_PIPELINE, WRITEBACK, WRITE_DEST);
signal MV_RW, MV_AN, MV_RW_WB : std_logic; -- [PMMU1]
signal PM_INFL : std_logic := '0'; -- [PMMU2]
signal PMMU_WR_D : std_logic := '0';
signal BIW_0_WB_MMU : std_logic := '0'; -- [PMMU2b] the instruction in writeback is an F-line (MMU) LEA.
signal PMMU_OP_I : std_logic; -- [PMMU2] PMMU_WR one clock later (START_OP hold).
signal PM_QUAD : std_logic; -- [PMMU1] PMOVE of the 64-bit CRP or SRP: two long bus transfers (EA, EA+4).
signal FETCH_STATE          : FETCH_STATES := START_OP;  -- [F49] was
    -- uninitialised while its partner NEXT_FETCH_STATE had an init (F44a).
    -- Both are read by the TRAP_V/TRAP_cc terms; leaving one uninitialised
    -- leaves the condition evaluable from power-up garbage on a COLD boot.
    -- Cold-vs-warm silicon A/B proved the fault is power-up state.
signal NEXT_FETCH_STATE     : FETCH_STATES := START_OP;  -- [F44] init
signal EXEC_WB_STATE        : EXEC_WB_STATES := IDLE;  -- [F54] measured warm-boot value
signal NEXT_EXEC_WB_STATE   : EXEC_WB_STATES := IDLE;  -- [F54] measured warm-boot value
signal ADR_MARK_USED_I		: bit := '0';  -- [F54] measured warm-boot value
signal ADR_MODE_I           : std_logic_vector(2 downto 0) := "100";  -- [F54] measured warm-boot value
signal ALU_INIT_I           : bit := '0';  -- [F54] measured warm-boot value
signal AR_INC_S           : bit; -- [FLT2] internal copy of the AR_INC output.
signal AR_DEC_S           : bit; -- [FLT2] internal copy of the AR_DEC output.
signal SP_ADD_DISPL_S     : bit; -- [FLT2] internal copy of the SP_ADD_DISPL output.
signal MV_ACT, MV_FLT, MV_RESTORE_I, MV_SAVE_I : bit := '0'; -- [F126]
signal WR_FLT               : bit; -- [FLT1] The control unit's data write ends with a bus error (this clock).
signal WFLT                 : bit := '0'; -- [FLT1] Held from a data write fault until the exception handler runs.
signal FI_DIRTY             : boolean := false; -- [FLT2] The fetch side changed an address register in this instruction.
signal ISS_SEEN             : boolean := false; -- [F131]
signal FI_MULTI             : boolean := false; -- [F131] the fetch side changed more than one An (or SP by a displacement).
signal FI_REST              : boolean; -- [F131] the single fetch-side An change can be undone (MV snapshot, user mode).
signal WR_LAST              : boolean; -- [FLT2] The running write is its instruction's last bus cycle.
signal F3_EARLY             : bit; -- [F3] Next MOVEM register taken in the S3 clock of the running write.
signal F3_BYP_I             : bit := '0';
signal ALU_BSY_M            : bit := '0'; -- Option A: ALU busy as seen by MOVEM register-to-memory.
signal ALU_TRIG             : bit := '0';  -- [F54] measured warm-boot value
signal ALU_INIT_C2          : bit := '0';  -- [T7] ALU_INIT_I for CHK2/CMP2 without the [F3] MOVEM term
signal AR_DEC_I             : bit := '1';  -- [F54] measured warm-boot value
signal AR_WR_I              : bit := '0';  -- [F54] measured warm-boot value
signal AR_WR_II             : bit := '0';  -- [F54] measured warm-boot value
signal BF_BYTES             : integer range 0 to 5 := 0;  -- [F54] measured warm-boot value
signal BF_BYTES_FULL        : integer range 0 to 5 := 0;  -- [F54] measured warm-boot value -- F24/H31: the START_OP value, held.
signal BF_HILOn             : bit := '0';  -- [F54] measured warm-boot value
signal BF_OFFSET_I          : integer range 0 to 7 := 0;  -- [F54] measured warm-boot value
signal BF_WIDTH_I           : integer range 1 to 32 := 32;  -- [F54] measured warm-boot value
signal BIW_0_WB             : std_logic_vector(11 downto 0);
signal BIW_1_WB             : std_logic_vector(15 downto 0);
signal DATA_RD_I            : bit := '0';  -- [F54] measured warm-boot value
signal DATA_WR_I            : bit := '0';  -- [F54] measured warm-boot value
signal EW_RDY               : bit := '0';  -- [F54] measured warm-boot value
signal INIT_ENTRY           : bit := '0';  -- [F54] measured warm-boot value
signal DR_SEL_ADH_2_I       : std_logic_vector(2 downto 0); -- F56
signal IPIPE_FLUSH_I        : bit := '0';  -- [F54] measured warm-boot value
signal LOOP_EXIT_I          : bit := '0';  -- [F54] measured warm-boot value
signal MEM_INDIRECT         : bit := '0';  -- [F54] measured warm-boot value
signal MEMADR_RDY           : bit := '0';  -- [F54] measured warm-boot value
signal MOVEM_ADn_I          : bit := '1';  -- [F54] measured warm-boot value
signal MOVEM_ADn_WB         : bit := '0';  -- [F54] measured warm-boot value
signal MOVEM_COND           : boolean := false;  -- [F54] measured warm-boot value
signal MOVEM_END            : boolean := false;  -- [F1] no register-list bit set above MOVEM_PVAR
signal MOVEM_FIRST_RD       : boolean := false;  -- [F54] measured warm-boot value
signal MOVEM_INH_WR         : boolean := false;  -- [F54] measured warm-boot value
signal MOVEM_PNTR           : std_logic_vector(3 downto 0) := x"F";  -- [F54] measured warm-boot value
signal MOVEP_PNTR_I         : integer range 0 to 3 := 0;  -- [F54] measured warm-boot value
signal OD_REQ_16            : std_logic;
signal OD_REQ_32            : std_logic;
signal OP_SIZE_I            : OP_SIZETYPE := BYTE;  -- [F54] measured warm-boot value
signal OP_WB_I              : OP_68K := UNIMPLEMENTED;
signal OW_RDY               : bit := '0';  -- [F54] measured warm-boot value
signal PC_ADD_DISPL_I       : bit := '0';  -- [F54] measured warm-boot value
signal PC_LOAD_I            : bit := '0';  -- [F54] measured warm-boot value
signal PHASE2               : boolean := false;  -- [F54] measured warm-boot value
signal RD_RDY               : bit := '0';  -- [F54] measured warm-boot value
signal READ_CYCLE           : bit := '0';  -- [F54] measured warm-boot value
signal SBIT_I               : bit := '0';  -- [F54] measured warm-boot value
signal SR_WR_I              : bit := '0';  -- [F54] measured warm-boot value
signal UPDT_CC              : bit := '0';  -- [F54] measured warm-boot value
signal CAS2_WGAP            : bit := '0'; -- [C1]
signal CAS2_CCHOLD          : bit := '0'; -- [C1]
signal EARLY_OW             : bit; -- [F141]
constant EARLY_ISSUE        : boolean := true; -- [F159] on again; per-group gates EI_G1..EI_G6.
-- [F159] Per-group EARLY_OW enables (all on in this stopgap). A group set false
-- takes the F158 path (no early OW_REQ) for those ops. ADDQ/SUBQ #,An stay
-- excluded (F145 / bld_aq AUTO fail). ADDA/SUBA stay excluded (F159, below).
constant EI_G1_MOVEQ        : boolean := true; -- MOVEQ/NOP/EXG/SWAP/EXT/EXTB
constant EI_G2_ADD          : boolean := true; -- ADD..TST to Dn/An
constant EI_G3_ADDI         : boolean := true; -- ADDI..CMPI #,Dn
constant EI_G4_MOVE         : boolean := true; -- MOVE/MOVEA reg-reg
constant EI_G5_SHIFT        : boolean := true; -- ASL..ROXR register (size /= "11")
constant EI_G6_BIT          : boolean := true; -- BTST/BCHG/BCLR/BSET Dn
constant F165_MEM_EI        : boolean := true; -- [F165] early OW_REQ for memory-source ops to Dn (operand read done).
    signal RD_OK                : bit := '0'; -- [F165] this instruction's operand read(s) completed without a bus error.
    signal MEM_EI               : bit; -- [F165]
constant F165_MEM_FAST      : boolean := true; -- [F165] mem-source ops to Dn: ALU_INIT in the read-ready clock, no INIT.
    signal MEM_OPS              : bit; -- [F165] operation/mode qualifies for MEM_EI / MEM_FAST.
    signal MEM_FAST             : bit; -- [F165]
constant F165_WR_OLAP       : boolean := true; -- [F165] next op loads in the write-acknowledge clock (Option A, generalised).
    signal WR_OLAP              : bit; -- [F165]
constant F166_MV_OLAP       : boolean := true; -- [F166] WR_OLAP for a following MOVE, registered operation qualifier.
constant F166_MV_AMODE      : boolean := true; -- [F166] MOVE destination address mode for the whole INIT_EXEC_WB stay.
    signal WR_OLAP_Q            : bit := '0'; -- [F166] registered WR_OLAP operation qualifier.
    signal WR_OLAP_OPS          : bit; -- [F166] its input (operation lists).
    signal ALU_BSY_MV           : bit; -- [F166] ALU busy as seen by MOVE's INIT terms.
constant F165_EW_B2B        : boolean := true; -- [F165] back-to-back extension word requests.
constant F162_BCC_INIT      : boolean := true; -- [F162] taken Bcc.B that missed the OPD_ACK clock (ALU busy) flushes in INIT.
    signal BCC_INIT             : bit; -- [F162]
constant F162_MQ            : boolean := true; -- [F162] MOVEQ written in EXECUTE like the F157c ops.
constant F160_BCC_EARLY     : boolean := true; -- [F160] taken Bcc.B flushes in its OPD_ACK clock.
    signal BCC_EARLY            : bit; -- [F160]
constant F163_CCR_FWD       : boolean := true; -- [F163] early Bcc.B also in the ALU_ACK clock of a CC op (CCR forwarded).
    signal CCR_FWD_OK           : bit; -- [F163] CC op (register destination) ends EXECUTE this clock: CCR forwarded.
constant F161_DBCC_EARLY    : boolean := true; -- [F161] taken DBcc completes in its OPD_ACK clock.
    signal DBCC_EARLY           : bit; -- [F161]
    signal DISPL_DBCC           : std_logic_vector(31 downto 0); -- [F161]
constant F161_RTS_EARLY     : boolean := true; -- [F161] RTS: PC load in the FETCH_OPERAND ready clock.
    signal RTS_EARLY            : boolean; -- [F161]
constant F161_DBCC_XPAD     : boolean := true; -- [F161] expired DBcc padded so dbf_expired is at or under the UM 14.
    signal DBCC_CNT             : integer range 0 to 15 := 0; -- [F161] clocks since the DBcc left START_OP.
    signal DBCC_XHOLD           : boolean; -- [F161] hold an expired DBcc in SLEEP.
    signal BCC_LCOND            : boolean; -- [F160] Bcc condition from CCR_IN.
    signal DISPLACEMENT_R       : std_logic_vector(31 downto 0); -- [F160] registered displacement.
    signal DISPL_EARLY          : std_logic_vector(31 downto 0); -- [F160] PC offset of the early Bcc.B (d8 + 2).
constant F157_PHASE_A       : boolean := false; -- [F157a] pipe depth + INIT/WRITEBACK overlap. Set false to restore F156 issue timing.
-- [F157x] Phase A OFF: with it on, the EmuTOS 1.4 desktop has no icons and GEM clicks fail (board). Re-enable after the fix.
constant F157_PHASE_B       : boolean := true; -- [F157c] write ADD/ADDQ/AND/NEG/NOT/CLR (and siblings) in EXECUTE.
    -- [F157a] INIT may overlap the previous WRITEBACK: ALU_TRIG is open and the new
    -- operation is accepted this clock, so INIT must not wait on ALU_BSY (or DBcc/MOVEQ
    -- stay in INIT and re-issue themselves forever).
    signal F157_ALU_FREE        : boolean;
    signal F157_OLAP            : bit;
    signal F157_WR_EXEC         : bit;
signal CMPA_DLY             : bit := '0'; -- [F142]
signal MEMADR_IN            : bit := '0'; -- [C2] FETCH_STATE was FETCH_MEMADR last clock.
signal MEMADR_Q1, MEMADR_OK : bit := '0'; -- [F130] base/index register final for the pointer read.
signal ADR_MARK_USED_W      : bit; -- [C1]
signal WR_RDY               : bit := '0';  -- [F54] measured warm-boot value
signal WRITE_CYCLE          : bit := '0';  -- [F54] measured warm-boot value
-- Debugging:
signal OP_TEST            : bit := '0';  -- [F54] measured warm-boot value
begin
    -- Option A (see docs/OPTION_A_DESIGN.md): for MOVEM register-to-memory the ALU is
    -- released in the clock its write completes (ALU_ACK), so the next register may be
    -- loaded in that same clock instead of one clock later (as on the real 68030, which
    -- overlaps the next MOVEM transfer set-up with the current bus cycle).
    ALU_BSY_M <= '0' when ALU_BSY = '0' else
                 '0' when OP = MOVEM and OP_WB_I = MOVEM and BIW_0(10) = '0' and BIW_0_WB(10) = '0' and
                          EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and DATA_VALID = '1' else
                 '0' when F3_EARLY = '1' else
                 '0' when WR_OLAP = '1' else '1'; -- [F165]
    -- [F165] Write acknowledged without a fault (posted S3 or S5): the next operation may load now.
    -- [F166] Registered operation qualifier: OP/BIW_0 (waiting operation) and OP_WB_I (write in WRITE_DEST) are
    -- flip flops that do not change while the operation waits in INIT_EXEC_WB and its predecessor is in WRITE_DEST
    -- (OP is final before FETCH_DEC enters INIT_EXEC_WB, OP_WB_I loads with ALU_INIT), so their value of the clock
    -- before is the value of the acknowledge clock (checked by P_WO_CHK in simulation).
    WR_OLAP_OPS <= '1' when (OP_WB_I = MOVE or OP_WB_I = CLR or OP_WB_I = ADD or OP_WB_I = SUB or OP_WB_I = AND_B or OP_WB_I = OR_B or
                         OP_WB_I = EOR or OP_WB_I = ADDQ or OP_WB_I = SUBQ or OP_WB_I = ADDI or OP_WB_I = SUBI or
                         OP_WB_I = ANDI or OP_WB_I = ORI or OP_WB_I = EORI or OP_WB_I = NEG or OP_WB_I = NOT_B) and
                        ((F166_MV_OLAP and OP = MOVE) or -- [F166]
                         OP = CLR or OP = ADD or OP = SUB or OP = AND_B or OP = OR_B or OP = EOR or
                         OP = CMP or OP = TST or OP = CMPI or OP = MOVEQ or OP = EXT or OP = SWAP or
                         ((OP = ADDQ or OP = SUBQ) and BIW_0(5 downto 3) /= "001") or
                         OP = ADDI or OP = SUBI or OP = ANDI or OP = ORI or OP = EORI or OP = NEG or OP = NOT_B) else '0';
    P_WO_Q: process
    begin
        wait until CLK = '1' and CLK' event;
        WR_OLAP_Q <= WR_OLAP_OPS;
    end process P_WO_Q;
    -- synthesis translate_off
    P_WO_CHK: process
    begin
        wait until CLK = '1' and CLK' event;
        assert not (WR_OLAP = '1' and WR_OLAP_OPS = '0')
            report "F166: WR_OLAP_Q set but the operation lists are not met" severity failure;
    end process P_WO_CHK;
    -- synthesis translate_on
    WR_OLAP <= '1' when F165_WR_OLAP and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and DATA_VALID = '1' and
                        WFLT = '0' and FETCH_STATE = INIT_EXEC_WB and WR_OLAP_Q = '1' else '0';
    -- [F166] MOVE's INIT terms: no MOVEM (F3_EARLY, WR_EARLY) term.
    ALU_BSY_MV <= '0' when ALU_BSY = '0' or WR_OLAP = '1' else '1';
    -- [F3] Back-to-back MOVEM register-to-memory writes. The outcome of a posted write is final in the S3 clock
    -- of its last portion (WR_EARLY = WP_GO: DSACK, no bus error, no retry), and its data and address are in the
    -- bus latches. The next register is loaded there (the same set-up as in the DATA_RDY clock, one clock earlier,
    -- only when it is certain: register-to-memory, list continues, no write fault pending), the bus interface
    -- drops that write's DATA_RDY, and the next write is presented in the S4/S5 clock (S5 chain, GAP 1). Its
    -- data comes straight from the loaded ALU operand in that clock (F3_BYP) and its address skips the
    -- one-clock calculation delay (ADR_FAST). A bus error can only hit the next write, never the taken one.
    F3_EARLY <= '1' when WR_EARLY = '1' and EXEC_WB_STATE = WRITE_DEST and OP_WB_I = MOVEM and BIW_0_WB(10) = '0' and
                         OP = MOVEM and BIW_0(10) = '0' and FETCH_STATE = INIT_EXEC_WB and MOVEM_COND = true and
                         WRITE_CYCLE = '1' and WFLT = '0' and ALU_BSY = '1' else '0';
    WR_TAKE <= F3_EARLY and ALU_INIT_I;
    ADR_FAST <= F3_EARLY and ALU_INIT_I;
    F3_BYP <= F3_BYP_I;
    P_F3: process
    begin
        wait until CLK = '1' and CLK' event;
        F3_BYP_I <= F3_EARLY and ALU_INIT_I;
    end process P_F3;
    BUSY <= '1' when OPD_ACK = '1' else -- Early indication.
            '1' when LOOP_BSY = '1' else -- Finish the DBcc loop.
            '1' when ALU_BSY = '1' else -- Busy, wait.
            '1' when FETCH_STATE /= START_OP else '0'; -- Main controller is busy.

    -- The interrupt must not be activated when the controller is in its START_OP
    -- state and fetches new OPWORDS. so we define the trigger for the interrupt
    -- in the end of the FETCH phase. The SLEEP state is important for STOP.
    INT_TRIG <= '1' when FETCH_STATE = INIT_EXEC_WB or FETCH_STATE = SLEEP else '0';

    OW_REQ <= '0' when BUSY_EXH = '1' else
              '0' when EXH_REQ = '1' and LOOP_BSY = '0' else -- Non interrupt exception requests, loop has priority.
              '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' else -- [PMMU2] PMOVE to the MMU: no next opcode before its writeback (8.1.10).
              '0' when OPD_ACK = '1' or OW_RDY = '1' else
              '1' when NO_PIPELINE = true and FETCH_STATE = START_OP and ALU_BSY = '0' else
              '1' when NO_PIPELINE = false and FETCH_STATE = START_OP else
              '1' when NO_PIPELINE = false and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE = START_OP and EARLY_OW = '1' else -- [F141]
              '1' when NO_PIPELINE = false and MEM_FAST = '1' else '0'; -- [F165]

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
                '0' when (OP = ADDQ or OP = SUBQ) and BIW_0(5 downto 3) = "001" else -- [F145] no early issue for ADDQ/SUBQ #,An (board AUTO failure, bld_aq).
                '0' when OP = ADDA or OP = SUBA else -- [F159] no early issue for ADDA/SUBA (TOS 2.06 stacked menu, board g2an).
                '1' when EI_G1_MOVEQ and (OP = MOVEQ or OP = NOP or OP = EXG or OP = SWAP or OP = EXT or OP = EXTB) else -- [F157c] NOP: early OW_REQ
                '1' when EI_G2_ADD and (OP = ADD or OP = ADDA or OP = ADDQ or OP = SUB or OP = SUBA or OP = SUBQ or OP = AND_B or OP = OR_B or
                          OP = EOR or OP = CMP or OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST) and
                         (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") else
                '1' when EI_G3_ADDI and (OP = ADDI or OP = SUBI or OP = ANDI or OP = ORI or OP = EORI or OP = CMPI) and BIW_0(5 downto 3) = "000" else
                '1' when EI_G4_MOVE and (OP = MOVE or OP = MOVEA) and (BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001") and
                         (BIW_0(8 downto 6) = "000" or BIW_0(8 downto 6) = "001") else
                '1' when EI_G5_SHIFT and (OP = ASL or OP = ASR or OP = LSL or OP = LSR or OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and
                         BIW_0(7 downto 6) /= "11" else
                '1' when EI_G6_BIT and (OP = BTST or OP = BCHG or OP = BCLR or OP = BSET) and BIW_0(5 downto 3) = "000" else
                MEM_EI; -- [F165]

    -- [F165] Memory source, data register destination: in INIT_EXEC_WB the operand is in the ALU and its read
    -- ended without a bus error (RD_OK), so the instruction cannot fault and the next operation word may be
    -- requested now. Immediate sources (#) have no read and are always final. Never an address register
    -- destination (F145/F159 An early-issue race).
    MEM_OPS <= '0' when BIW_0(5 downto 3) = "000" or BIW_0(5 downto 3) = "001" else -- Register source: F141 groups.
               '1' when OP = MOVE and BIW_0(8 downto 6) = "000" else
               '1' when (OP = ADD or OP = SUB or OP = AND_B or OP = OR_B) and BIW_0(8) = '0' else
               '1' when OP = CMP or OP = TST else
               '1' when (OP = CMPI or OP = BTST) else '0';
    MEM_EI <= '0' when not F165_MEM_EI or LOOP_BSY = '1' else
              '0' when RD_OK = '0' and not (BIW_0(5 downto 0) = "111100") else -- Read not done / bus error.
              MEM_OPS;

    -- [F165] Read-ready clock: load the ALU from DATA_TO_CORE (DBUFFER, registered with DATA_RDY) and leave for
    -- START_OP. The Dn operand of ADD/SUB/AND/OR/CMP/BTST must be final (DR_IN_USE), as in the FETCH_OPERAND
    -- decision of the INIT path. MOVE/TST/CMPI read no data register. ALU_BSY = '0': no operation in EXECUTE,
    -- WRITEBACK or WRITE_DEST.
    MEM_FAST <= '0' when not F165_MEM_FAST or FETCH_STATE /= FETCH_OPERAND or RD_RDY = '0' or DATA_VALID /= '1' else
                '0' when MEM_OPS = '0' or ALU_BSY = '1' or LOOP_BSY = '1' or OP = BTST else -- BTST: bit number path not checked.
                '0' when TRACE_MODE /= "00" or IRQ_HOT = '1' or EXH_REQ = '1' else
                '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' or WR_FLT = '1' or WFLT = '1' else
                '0' when DR_IN_USE = '1' and OP /= MOVE and OP /= TST and OP /= CMPI else '1';

    P_RD_OK: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP then
            RD_OK <= '0';
        elsif FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
            if DATA_VALID = '1' then
                RD_OK <= '1';
            else
                RD_OK <= '0';
            end if;
        end if;
    end process P_RD_OK;

    -- [F157a] Only register-only ops (the F141 EARLY_OW set) may take INIT during the
    -- previous WRITEBACK. Multi-phase MOVE/ORI to memory would otherwise ALU_INIT and
    -- then WRITE_DEST with PHASE2 still false (wrong address; prog_mrmw).
    F157_OLAP <= '1' when F157_PHASE_A and EXEC_WB_STATE = WRITEBACK and EARLY_OW = '1' else '0';
    F157_ALU_FREE <= true when ALU_BSY = '0' else
                     true when WR_OLAP = '1' else -- [F165]
                     true when F157_OLAP = '1' else false;

    -- [F157c] Register-destination single-cycle INT/LOG ops: RESULT is valid
    -- in the ALU_REQ/EXECUTE clock (combinational P_OUT path). Write then and
    -- skip WRITEBACK so a following RAW ALU_INIT sees the new register.
    -- ADDQ/SUBQ #,An stay on WRITEBACK (F145 board).
    F157_WR_EXEC <= '1' when F157_PHASE_B and EXEC_WB_STATE = EXECUTE and ALU_REQ = '1' and
                             (((OP_WB_I = ADD or OP_WB_I = SUB or OP_WB_I = AND_B or OP_WB_I = OR_B) and BIW_0_WB(8) = '0') or
                              (F162_MQ and OP_WB_I = MOVEQ) or -- [F162]
                              ((OP_WB_I = ADDQ or OP_WB_I = SUBQ or OP_WB_I = ADDI or OP_WB_I = SUBI or
                                OP_WB_I = ANDI or OP_WB_I = ORI or OP_WB_I = EORI or OP_WB_I = EOR or
                                OP_WB_I = CLR or OP_WB_I = NEG or OP_WB_I = NEGX or OP_WB_I = NOT_B) and
                               BIW_0_WB(5 downto 3) = "000")) else '0';

    DATA_AVAILABLE: process
    -- These flip flops store the information whether the data required in the different
    -- states is available or not. This is necessary in case of delayed cycles for
    -- example if the required address register is not ready to be read.
    begin
        wait until CLK = '1' and CLK' event;
        if RESET_CPU = '1' then
            OW_RDY <= '0';
        elsif FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP then
            OW_RDY <= '0'; -- Reset.
        elsif FETCH_STATE = START_OP and (OP = ILLEGAL or OP = RTE or OP = TRAP or OP = UNIMPLEMENTED) and BUSY_EXH = '1' then
            OW_RDY <= '0'; -- Done.
        elsif BCC_EARLY = '1' or DBCC_EARLY = '1' then
            OW_RDY <= '0'; -- [F160] The early Bcc is done in its acknowledge clock. [F161] Early DBcc too.
        elsif OPD_ACK = '1' then
            OW_RDY <= '1'; -- Set.
        end if;

        if FETCH_STATE = START_OP then
            EW_RDY <= '0';
        elsif FETCH_STATE = FETCH_DISPL and NEXT_FETCH_STATE /= FETCH_DISPL then
            EW_RDY <= '0';
        elsif FETCH_STATE = FETCH_EXWORD_1 and NEXT_FETCH_STATE /= FETCH_EXWORD_1 then
            EW_RDY <= '0';
        elsif FETCH_STATE = FETCH_D_LO and NEXT_FETCH_STATE /= FETCH_D_LO then
            EW_RDY <= '0';
        elsif FETCH_STATE = FETCH_IDATA_B1 and NEXT_FETCH_STATE /= FETCH_IDATA_B1 then
            EW_RDY <= '0';
        elsif (FETCH_STATE = FETCH_DISPL or FETCH_STATE = FETCH_EXWORD_1 or FETCH_STATE = FETCH_IDATA_B1 or FETCH_STATE = FETCH_D_LO) and EW_ACK = '1' then
            EW_RDY <= '1';
        end if;
        
        if FETCH_STATE = START_OP then
            MEMADR_RDY <= '0';
        elsif FETCH_STATE = FETCH_MEMADR and NEXT_FETCH_STATE /= FETCH_MEMADR then
            MEMADR_RDY <= '0';
        elsif FETCH_STATE = FETCH_MEMADR and RD_RDY = '1' and DATA_VALID = '1' then
            -- [C3] Was DATA_RDY: the acknowledge of a previous instruction's write that finished while
            -- this one waited in FETCH_MEMADR (ADR_IN_USE) counted as the pointer read, so the pointer
            -- was never read (JMP/JSR ([bd,An]) hung or jumped to a stale MEM_ADR).
            MEMADR_RDY <= '1';
        end if;
    end process DATA_AVAILABLE;

    -- [F165] Decoded from FETCH_STATE only (not NEXT_FETCH_STATE: timing): these states always go on to the low word on EW_ACK.
    EW_REQ <= '1' when F165_EW_B2B and EW_ACK = '1' and (FETCH_STATE = FETCH_ABS_HI or FETCH_STATE = FETCH_IDATA_B2 or
                       FETCH_STATE = FETCH_D_HI or FETCH_STATE = FETCH_OD_HI) else
              '0' when EW_ACK = '1' or EW_RDY = '1' else
              '1' when FETCH_STATE = FETCH_DISPL or FETCH_STATE = FETCH_EXWORD_1 else 
              '1' when FETCH_STATE = FETCH_D_HI or FETCH_STATE = FETCH_D_LO else 
              '1' when FETCH_STATE = FETCH_OD_HI or FETCH_STATE = FETCH_OD_LO else
              '1' when FETCH_STATE = FETCH_ABS_HI or FETCH_STATE = FETCH_ABS_LO else
              '1' when FETCH_STATE = FETCH_IDATA_B2 or FETCH_STATE = FETCH_IDATA_B1 else
              '1' when FETCH_STATE /= FETCH_DISPL and NEXT_FETCH_STATE = FETCH_DISPL else
              '1' when FETCH_STATE /= FETCH_EXWORD_1 and NEXT_FETCH_STATE = FETCH_EXWORD_1 else
              '1' when FETCH_STATE /= FETCH_D_HI and NEXT_FETCH_STATE = FETCH_D_HI else
              '1' when FETCH_STATE /= FETCH_D_LO and NEXT_FETCH_STATE = FETCH_D_LO else
              '1' when FETCH_STATE /= FETCH_OD_HI and NEXT_FETCH_STATE = FETCH_OD_HI else
              '1' when FETCH_STATE /= FETCH_OD_LO and NEXT_FETCH_STATE = FETCH_OD_LO else
              '1' when FETCH_STATE /= FETCH_ABS_HI and NEXT_FETCH_STATE = FETCH_ABS_HI else
              '1' when FETCH_STATE /= FETCH_ABS_LO and NEXT_FETCH_STATE = FETCH_ABS_LO else
              '1' when FETCH_STATE /= FETCH_IDATA_B2 and NEXT_FETCH_STATE = FETCH_IDATA_B2 else
              '1' when FETCH_STATE /= FETCH_IDATA_B1 and NEXT_FETCH_STATE = FETCH_IDATA_B1 else '0';

    CYCLECONTROL: process
    -- This process contros the read and write signals, if
    -- asserted simultaneously. In this way, a read cycle is
    -- not interrupted by a write cycle and vice versa.
    begin
        wait until CLK = '1' and CLK' event;
        if DATA_RDY = '1' then
            WRITE_CYCLE <= '0';
            READ_CYCLE <= '0';
        elsif DATA_WR_I = '1' then
            WRITE_CYCLE <= '1';
            READ_CYCLE <= '0';
        elsif DATA_RD_I = '1' then
            READ_CYCLE <= '1';
            WRITE_CYCLE <= '0';
        end if;
    end process CYCLECONTROL;

    RD_RDY <= DATA_RDY when READ_CYCLE = '1' else '0';
    WR_RDY <= DATA_RDY when WRITE_CYCLE = '1' else '0';

    -- [F142] CMPA Rn,An takes 4 clocks on the 68030 (MC68030UM 11.6.7), one more than CMP: one extra START_OP clock.
    P_CMPA_DLY: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP and (OPD_ACK = '1' or OW_RDY = '1') and OP = CMPA and BIW_0(5 downto 4) = "00" then
            CMPA_DLY <= '1';
        else
            CMPA_DLY <= '0';
        end if;
    end process P_CMPA_DLY;

    INIT_ENTRY <= '1' when FETCH_STATE /= INIT_EXEC_WB and NEXT_FETCH_STATE = INIT_EXEC_WB else '0';
    
    DATA_RD <= DATA_RD_I;
    DATA_RD_I <= '0' when WFLT = '1' else -- [FLT1] No operand cycle after a data write fault (MC68030: exception straight after the faulted cycle).
                 '0' when DATA_WR_I = '1' and READ_CYCLE = '0' and WRITE_CYCLE = '0' else -- Write is prioritized.
                 '0' when WRITE_CYCLE = '1' else -- Do not read during a write cycle.
                 '0' when ADR_IN_USE = '1' else -- Avoid data hazards.
                 '0' when DATA_RDY = '1' or MEMADR_RDY = '1' else
                 -- [C2] ADR_EFF is registered: in the first FETCH_MEMADR clock it still holds the value
                 -- computed in the previous state (MEM_ADR + od of the LAST memory-indirect access).
                 -- With an idle bus the pointer read went out at that stale address. Registered gate.
                 '1' when FETCH_STATE = FETCH_MEMADR and MEMADR_IN = '1' and MEMADR_OK = '1' else
                 '1' when FETCH_STATE = FETCH_OPERAND else
                 -- Option A step 3: MOVEM memory to register, 2nd and later reads: the effective address is valid in
                 -- CALC_AEFF already (AR increment / offset update at ALU_INIT, one registered calculation clock in
                 -- SWITCH_STATE), so the read is requested there instead of one clock later in FETCH_OPERAND.
                 '1' when FETCH_STATE = CALC_AEFF and OP = MOVEM and BIW_0(10) = '1' and MOVEM_FIRST_RD = true else '0';

    -- [F2] The bus interface may start the next register's read right behind this one (MC68030UM 7.3: the next
    -- cycle starts after S5 when a request is pending; the 68030 sequencer has the next MOVEM operand queued).
    -- The control unit is waiting in FETCH_OPERAND and the register list has a further bit set (MOVEM_END), so
    -- that read is certain to be requested next, at the next address. The control unit still requests it as
    -- before; the bus interface hands it the data read ahead (or the bus error) only on a matching request.
    MOVEM_RA <= '1' when OP = MOVEM and BIW_0(10) = '1' and FETCH_STATE = FETCH_OPERAND and MOVEM_END = false else '0';

    DATA_WR <= DATA_WR_I;
    DATA_WR_I <= '0' when WFLT = '1' else -- [FLT1]
                 '0' when CAS2_WGAP = '1' else -- [C1] CAS2: ADR_EFF_WB is loaded one clock after ADR_MARK_USED.
                 '0' when READ_CYCLE = '1' else -- Do not write during a read cycle.
                 '0' when DATA_RDY = '1' else
                 '1' when EXEC_WB_STATE = WRITE_DEST else '0';

    RMC <= '1' when (OP = CAS or OP = CAS2 or OP = TAS) and FETCH_STATE /= START_OP else '0';

    -- [C1] CAS2 writes the update operands from ADR_EFF_WB (Rn1, then Rn2). The address register
    -- unit loads ADR_EFF_WB one clock after ADR_MARK_USED (DELAY), but WRITE_DEST requested the
    -- write in that same clock, so the bus interface latched the previous address: write 1 went to
    -- whatever ADR_EFF_WB still held (Rn2 of the last CAS2) and write 2 to Rn1. Hold the request for
    -- that one clock. Registered from ADR_MARK_USED: nothing new on the DSACK path.
    -- [RMC1] CAS (one operand) loads ADR_EFF_WB the same way. It was hidden while the prefetcher ran
    -- between the locked read and the write; with no cycle allowed there (cycle-correct RMC) the write
    -- request came in the load clock and went to the previous instruction's address.
    P_CAS2_WGAP: process
    begin
        wait until CLK = '1' and CLK' event;
        if (OP_WB_I = CAS2 or OP_WB_I = CAS) and ADR_MARK_USED_W = '1' then -- [RMC1] CAS has the same race
            CAS2_WGAP <= '1';
        else
            CAS2_WGAP <= '0';
        end if;
    end process P_CAS2_WGAP;

    ALU_ACK <= '1' when EXEC_WB_STATE = EXECUTE and NEXT_EXEC_WB_STATE = IDLE else
               '1' when EXEC_WB_STATE = WRITEBACK else
               '0' when (OP_WB_I = BFCHG or OP_WB_I = BFCLR) and EXEC_WB_STATE = WRITE_DEST and BF_BYTES = 5 else
               '0' when (OP_WB_I = BFINS or OP_WB_I = BFSET) and EXEC_WB_STATE = WRITE_DEST and BF_BYTES = 5 else
               '1' when EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' else
               '1' when F3_EARLY = '1' and ALU_INIT_I = '1' else '0'; -- [F3]

    FETCH_MEM_ADR <= '1' when FETCH_STATE = FETCH_MEMADR else '0';
    STORE_MEM_ADR <= '1' when FETCH_STATE = FETCH_MEMADR and RD_RDY = '1' and DATA_VALID = '1' else '0';

    -- Store the extension word right in the end due to used data and/or address registers.
    STORE_ADR_FORMAT <= '1' when FETCH_STATE = FETCH_EXWORD_1 and NEXT_FETCH_STATE /= FETCH_EXWORD_1 else '0';

    STORE_D16 <= '1' when FETCH_STATE = FETCH_DISPL and EW_ACK = '1' else '0';
    STORE_D32_LO <= '1' when FETCH_STATE = FETCH_D_LO and EW_ACK = '1' else '0';
    STORE_D32_HI <= '1' when FETCH_STATE = FETCH_D_HI and EW_ACK = '1' else '0';

	STORE_DISPL <= '1' when OP = MOVEP and FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP and BIW_0(7 downto 6) < "10" else -- Memory to register.
                   '1' when OP = MOVEP and FETCH_STATE = SWITCH_STATE else '0'; -- Register to memory.

    STORE_OD_HI <= '1' when FETCH_STATE = FETCH_OD_HI and EW_ACK = '1' else '0';
    STORE_OD_LO <= '1' when FETCH_STATE = FETCH_OD_LO and EW_ACK = '1' else '0';

    STORE_ABS_HI <= '1' when FETCH_STATE = FETCH_ABS_HI and EW_ACK = '1' else '0';
    STORE_ABS_LO <= '1' when FETCH_STATE = FETCH_ABS_LO and EW_ACK = '1' else '0';

    STORE_IDATA_B2 <= '1' when FETCH_STATE = FETCH_IDATA_B2 and EW_ACK = '1' else '0';
    STORE_IDATA_B1 <= '1' when FETCH_STATE = FETCH_IDATA_B1 and EW_ACK = '1' else '0';

    LOAD_OP1 <= '1' when OP = BFINS and INIT_ENTRY = '1' else -- Load insertion pattern.
                '1' when (OP = CHK2 or OP = CMP2) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = false else 
                '1' when OP = CMPM and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = true else
                '1' when OP = MOVE and BIW_0(8 downto 6) = "100" and BIW_0(5 downto 3) = "001" and BIW_0(11 downto 9) = BIW_0(2 downto 0) and INIT_ENTRY = '1' else -- Load early to write the undecremented Register for Ax, -(Ax).
				'1' when OP = MOVES and FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP and ADR_MODE_I = "100" and BIW_1(15) = '1' and BIW_1(11) = '1' and BIW_1(14 downto 12) = BIW_0(2 downto 0) else -- Load the adressing register before decrementing.
                '1' when OP = PEA and FETCH_STATE = SWITCH_STATE and PHASE2 = true else -- Load early not to stack the decremented value.
                '0' when OP = BFINS or OP = CHK2 or OP = CMP2 or OP = CMPM or OP = PEA else
                '0' when OP = MOVE and BIW_0(8 downto 6) = "100" and BIW_0(5 downto 3) = "001" and BIW_0(11 downto 9) = BIW_0(2 downto 0) else
                '0' when OP = MOVES and ADR_MODE_I = "100" and BIW_1(15) = '1' and BIW_1(11) = '1' and BIW_1(14 downto 12) = BIW_0(2 downto 0) else -- Do not load the decremented addressing register.
                '0' when OP = PEA and ADR_MODE_I = "001" and BIW_0(2 downto 0) = "111" else
                '1' when ALU_INIT_I = '1' else '0';

    LOAD_OP2 <= '1' when MEM_FAST = '1' else -- [F165] no INIT_ENTRY on the fast path: Dn / memory operand now.
                '1' when (OP = ABCD or OP = SBCD) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = false else
                '1' when (OP = ADDX or OP = SUBX) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = false else
                '1' when (OP = ABCD or OP = SBCD) and FETCH_STATE = INIT_EXEC_WB and BIW_0(3) = '0' else -- Register direct.
                '1' when (OP = ADDX or OP = SUBX) and FETCH_STATE = INIT_EXEC_WB and BIW_0(3) = '0' else -- Register direct.
                '1' when (OP = BFCHG or OP = BFCLR) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '0' else
                '1' when (OP = BFINS or OP = BFSET) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '0' else
                '1' when (OP = BFEXTS or OP = BFEXTU) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '0' else
                '1' when (OP = BFFFO or OP = BFTST) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '0' else
                '1' when OP = CMPM and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = false else
                '1' when OP = LINK and BIW_0(2 downto 0) = "111" and FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP else -- Load early not to stack the decremented address register.
                '0' when OP = ABCD or OP = SBCD or OP = ADDX or OP = SUBX or OP = CMPM else
                '0' when OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST else
                '0' when OP = LINK and BIW_0(2 downto 0) = "111" else
                '1' when INIT_ENTRY = '1' else '0';

    LOAD_OP3 <= '1' when (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET) and BIW_0(5 downto 3) = "000" and INIT_ENTRY = '1' else 
                '1' when (OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFTST) and BIW_0(5 downto 3) = "000" and INIT_ENTRY = '1' else 
                '1' when (OP = BFCHG or OP = BFCLR) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '1' else
                -- F25/H32: upstream typo. Every sibling line in LOAD_OP2 and
                -- LOAD_OP3 pairs BFINS with BFSET; this one alone said BSET.
                -- Consequence: BFSET never loaded its fetched memory operand
                -- into OP3 and read-modify-wrote whatever OP3 still held from
                -- the PREVIOUS instruction. Measured: V22f found OP3 = $56,
                -- left over from V22e's BFINS, so BFSET set the top nibble of
                -- the wrong byte's stale value. BSET also got a spurious OP3
                -- load it never needed.
                '1' when (OP = BFINS or OP = BFSET) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '1' else
                '1' when (OP = BFEXTS or OP = BFEXTU) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '1' else
                '1' when (OP = BFFFO or OP = BFTST) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and BF_HILOn = '1' else
                '1' when OP = CAS2 and INIT_ENTRY = '1' and PHASE2 = false else -- Memory operand 2.
                '1' when (OP = CHK2 or OP = CMP2) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and PHASE2 = true else
                '1' when (OP = DIVS or OP = DIVU) and OP_SIZE_I = LONG and BIW_1(10) = '1' and INIT_ENTRY = '1' else '0'; -- 64 bit operand.

    SR_WR <= SR_WR_I;
    SR_WR_I <= '1' when (OP_WB_I = ANDI_TO_SR or OP_WB_I = EORI_TO_SR or OP_WB_I = ORI_TO_SR) and EXEC_WB_STATE = WRITEBACK else 
               '1' when (OP_WB_I = MOVE_TO_CCR or OP_WB_I = MOVE_TO_SR) and EXEC_WB_STATE = WRITEBACK else
               '1' when OP_WB_I = STOP and EXEC_WB_STATE = WRITEBACK else '0';

    BF_BYTES_OUT <= BF_BYTES;

    HILOn <= '1' when OP_WB_I = CAS2 and FETCH_STATE = FETCH_OPERAND and PHASE2 = false else
             '1' when OP_WB_I = CAS2 and EXEC_WB_STATE = WRITEBACK and PHASE2 = false else
             '0' when OP = CAS2 else BF_HILOn; -- Select destinations.

    -- Addressing mode:
    ADR_MODE <= ADR_MODE_I;
    ADR_MODE_I <= "010" when OP = BSR or OP = CAS2 or OP = LINK or OP = UNLK else -- (An), (Dn).
                  "010" when OP = LEA and BIW_0(13 downto 12) = "11" and BIW_0(5 downto 3) = "000" else -- [PMMU2b] PFLUSHA etc.: dummy (A0).
                  "010" when OP = RTD or OP = RTR or OP = RTS else -- (An).
                  "011" when OP = CMPM else -- (An)+
                  "100" when OP = ABCD or OP = SBCD else -- -(An).
                  "100" when OP = ADDX or OP = SUBX else -- -(An).
                  "100" when OP = PACK or OP = UNPK else -- -(An).
                  "101" when OP = MOVEP else -- (d16, An).
                  -- The following two conditions change the address mode right in the end of the fetch phase. 
                  "010" when (OP = JSR or OP = PEA) and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' else -- (A7).
                  BIW_0(8 downto 6) when OP = MOVE and FETCH_STATE = INIT_EXEC_WB and (F166_MV_AMODE or ALU_BSY = '0') else -- [F166]
                  BIW_0(8 downto 6) when OP = MOVE and PHASE2 = true else
                  BIW_0(5 downto 3); 

    -- This is the selector for the address mode "111".
    AMODE_SEL <= BIW_0(11 downto 9) when OP = MOVE and (NEXT_FETCH_STATE = INIT_EXEC_WB or FETCH_STATE = INIT_EXEC_WB) else
                 BIW_0(11 downto 9) when OP = MOVE and PHASE2 = true else BIW_0(2 downto 0);
    
    -- Used for the addressing modes and as source selector.
    -- In case of the addressing modes, the selector mus be valid one clock cycle before the bus cycle
    -- starts due to the pipeline stage for ADR_REG in the address register section.
    AR_SEL_RD_1 <= BIW_0(11 downto 9) when (OP = ABCD or OP = SBCD) and FETCH_STATE = START_OP else
                   BIW_0(11 downto 9) when (OP = ABCD or OP = SBCD) and FETCH_STATE = CALC_AEFF and PHASE2 = false else
                   BIW_0(11 downto 9) when (OP = ABCD or OP = SBCD) and FETCH_STATE = FETCH_OPERAND and PHASE2 = false and RD_RDY = '0' else -- Destination first.
                   BIW_0(11 downto 9) when (OP = ABCD or OP = SBCD) and FETCH_STATE = INIT_EXEC_WB else
                   BIW_0(11 downto 9) when (OP = ADDX or OP = SUBX) and FETCH_STATE = START_OP else
                   BIW_0(11 downto 9) when (OP = ADDX or OP = SUBX) and FETCH_STATE = CALC_AEFF and PHASE2 = false else
                   BIW_0(11 downto 9) when (OP = ADDX or OP = SUBX) and FETCH_STATE = FETCH_OPERAND and PHASE2 = false and RD_RDY = '0' else -- Destination first.
                   BIW_0(11 downto 9) when (OP = ADDX or OP = SUBX) and FETCH_STATE = INIT_EXEC_WB else
                   -- [F122] CMPM: Ax (read first) must be selected in START_OP already: the address pipeline takes the
                   -- selector one clock before the bus cycle. With the opword from the I-cache and the operand cycle
                   -- starting at once, the first read used Ay, so CMPM (Ay)+,(Ax)+ compared (Ay) with itself (Linux memcmp).
                   BIW_0(11 downto 9) when OP = CMPM and FETCH_STATE = START_OP else
                   BIW_0(11 downto 9) when OP = CMPM and FETCH_STATE = FETCH_OPERAND and PHASE2 = false else -- Fetch destination.
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = FETCH_MEMADR and PHASE2 = true else
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = START_OP and BIW_0(5 downto 3) < "010" and BIW_0(8 downto 6) /= "000" else  -- Dn, An.
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = CALC_AEFF and PHASE2 = true else
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and BIW_0(8 downto 6) = "100" and BIW_0(5 downto 3) /= "011" else -- All except (An)+,-(An).
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = FETCH_IDATA_B1 and BIW_0(8 downto 6) /= "000" else
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = FETCH_ABS_LO and BIW_0(8 downto 6) /= "000" and PHASE2 = false else
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = SWITCH_STATE and BIW_0(8 downto 6) /= "000" else
                   BIW_0(11 downto 9) when OP = MOVE and FETCH_STATE = INIT_EXEC_WB and BIW_0(8 downto 6) /= "000" else
                   BIW_1(14 downto 12) when OP = MOVEC and BIW_0(0) = '1' else -- MOVEC: general register to control register.
                   "111" when OP = BSR or OP = MOVEC else -- Stack pointers.
                   -- [PH2-FMAX] No DR_IN_USE term: register-mode PACK/UNPK leaves START_OP on DR_IN_USE alone
                   -- (FETCH_DEC), AR_IN_USE is not looked at, and nothing reads the AR port in those wait
                   -- clocks. The term put the data hazard compare in front of the address hazard compare
                   -- (DR_IN_USE -> AR_SEL_RD_1 -> AR_IN_USE -> NEXT_FETCH_STATE): the clk_cpu030 critical path.
                   BIW_0(11 downto 9) when (OP = PACK or OP = UNPK) and FETCH_STATE = START_OP and BIW_0(3) = '0' else -- Destination address.
                   BIW_0(11 downto 9) when (OP = PACK or OP = UNPK) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' else -- Destination address.
                   BIW_0(11 downto 9) when (OP = PACK or OP = UNPK) and FETCH_STATE = INIT_EXEC_WB else -- Destination address.
                   BIW_1(14 downto 12) when OP = CAS2 and FETCH_STATE = START_OP else -- Address operand.
                   BIW_1(14 downto 12) when OP = CAS2 and FETCH_STATE = FETCH_OPERAND and PHASE2 = false else -- Address operand.
                   BIW_2(14 downto 12) when OP = CAS2 and FETCH_STATE = CALC_AEFF else -- Address operand.
                   BIW_2(14 downto 12) when OP = CAS2 and FETCH_STATE = FETCH_OPERAND else -- Address operand.
                   BIW_1(14 downto 12) when OP_WB_I = CAS2 and (EXEC_WB_STATE = EXECUTE or EXEC_WB_STATE = ADR_PIPELINE) else -- Address operand.
                   BIW_2(14 downto 12) when OP_WB_I = CAS2 and EXEC_WB_STATE = WRITE_DEST else -- Address operand.
                   "111" when (OP = JSR or OP = LINK) and FETCH_STATE = START_OP else -- Select the SP to decrement.
                   "111" when OP = PEA and FETCH_STATE = SWITCH_STATE and PHASE2 = true else -- Select the SP to decrement.
                   "111" when (OP = JSR or OP = LINK or OP = PEA) and FETCH_STATE = INIT_EXEC_WB else -- Writeback address is the SP.
                   "111" when OP = RTD or OP = RTR or OP = RTS else -- Stack pointer.
                   "111" when OP = UNLK and (FETCH_STATE = START_OP or FETCH_STATE = CALC_AEFF or FETCH_STATE = FETCH_OPERAND) else -- Check in START_OP to avoid dataz hazards!
                   BIW_0(2 downto 0) when OP = ABCD or OP = ADD or OP = ADDA or OP = ADDI or OP = ADDQ or OP = ADDX or OP = AND_B or OP = ANDI else
                   BIW_0(2 downto 0) when OP = ASL or OP = ASR or OP = BCHG or OP = BCLR or OP = BSET or OP = BTST or OP = BFCHG or OP = BFCLR else 
                   BIW_0(2 downto 0) when OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST else 
                   BIW_0(2 downto 0) when OP = CAS or OP = CHK or OP = CHK2 or OP = CLR or OP = CMP or OP = CMPA or OP = CMPI or OP = CMPM or OP = CMP2 else
                   BIW_0(2 downto 0) when OP = DIVS or OP = DIVU or OP = EOR or OP = EORI or OP = EXG or OP = JMP or OP = JSR or OP = LEA or OP = LINK or OP = LSL or OP = LSR else
                   BIW_0(2 downto 0) when OP = MOVE or OP = MOVEA or OP = MOVE_FROM_CCR or OP = MOVE_FROM_SR or OP = MOVE_TO_CCR or OP = MOVE_TO_SR else
                   BIW_0(2 downto 0) when OP = MOVE_USP or OP = MOVEM or OP = MOVEP or OP = MOVES or OP = PMOVE or OP = MULS or OP = MULU else
                   BIW_0(2 downto 0) when OP = NBCD or OP = NEG or OP = NEGX or OP = NOT_B or OP = OR_B or OP = ORI or OP = PACK or OP = PEA else
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
               '1' when OP_WB_I = MOVEM and MOVEM_ADn_WB = '1' else '0';

    AR_SEL_RD_2 <= BIW_1(14 downto 12) when OP = CHK2 or OP = CMP2 else
                   MOVEM_PNTR(2 downto 0) when OP = MOVEM else -- This is the non addressing output.
                   BIW_1(14 downto 12) when OP = MOVES else
                   BIW_0(2 downto 0) when OP = ADDQ or OP = MOVE or OP = SUBQ or OP = TST else
                   BIW_0(2 downto 0) when OP = EXG and BIW_0(7 downto 3) = "10001" else -- Data and address register.
                   BIW_0(11 downto 9) when OP = ADDA or OP = CMPA or OP = EXG or OP = SUBA else "000";

    AR_SEL_WR_2 <= BIW_0(2 downto 0); -- Used for EXG, UNLK.

    AR_WR_2 <= AR_WR_II;
    AR_WR_II <= '1' when OP_WB_I = UNLK and EXEC_WB_STATE = WRITEBACK else -- Write (SP) to An.
                '1' when OP_WB_I = EXG and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(7 downto 3) = "01001" else '0'; -- Two address registers.

    -- [F125] -(An) source: the predecrement was done before the read; undo it when the read ends with a bus error
    -- (the instruction restarts after RTE and decrements again).
    AR_INC_S <= '1' when AR_DEC_I = '1' and ADR_MODE_I = "100" and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '0' else
              '1' when (OP = ADD or OP = CMP or OP = SUB) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = ADDA or OP = CMPA or OP = SUBA) and ADR_MODE_I = "011" and FETCH_STATE = FETCH_OPERAND and DATA_RDY = '1' else
              '1' when (OP = ADDI or OP = CMPI or OP = SUBI) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = ADDQ or OP = SUBQ) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = AND_B or OP = EOR or OP = OR_B) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = ANDI or OP = EORI or OP = ORI) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = ASL or OP = ASR or OP = LSL or OP = LSR) and BIW_0(7 downto 3) = "11011" and ALU_INIT_I = '1' else
              '1' when (OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and BIW_0(7 downto 3) = "11011" and ALU_INIT_I = '1' else
              '1' when (OP = BCHG or OP = BCLR or OP = BSET or OP = BTST) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = CAS or OP = TAS) and ADR_MODE_I = "011" and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE /= INIT_EXEC_WB else
              '1' when (OP = CHK or OP = CLR or OP = TST or OP = Scc) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = NBCD or OP = NEG or OP = NEGX or OP = NOT_B) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when OP = CMPM and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' else
              '1' when (OP = MULS or OP = MULU or OP = DIVS or OP = DIVU) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = MOVE_FROM_CCR or OP = MOVE_FROM_SR) and ADR_MODE_I = "011" and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE /= INIT_EXEC_WB else 
              '1' when (OP = MOVE_TO_CCR or OP = MOVE_TO_SR) and ADR_MODE_I = "011" and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE /= INIT_EXEC_WB else 
              -- [F124] Not when the source read ended with a bus error (the instruction restarts after RTE).
              '1' when OP = MOVE and ADR_MODE_I = "011" and FETCH_STATE = FETCH_OPERAND and NEXT_FETCH_STATE /= FETCH_OPERAND and
                       not (RD_RDY = '1' and DATA_VALID = '0') else
              '1' when OP = MOVE and BIW_0(8 downto 6) = "011" and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE /= INIT_EXEC_WB else
              '1' when OP = MOVEA and ADR_MODE_I = "011" and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE /= INIT_EXEC_WB else
              '1' when OP = MOVEM and ADR_MODE_I = "011" and ALU_INIT_I = '1' else
              '1' when (OP = MOVES or OP = PMOVE) and ADR_MODE_I = "011" and ALU_INIT_I = '1' else 
              '1' when (OP = UNLK or OP = RTD or OP = RTR or OP = RTS) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' else '0';

    with OP select
        AR_DEC_I <= '1' when ABCD | ADD | ADDA | ADDI | ADDQ | ADDX | AND_B | ANDI | ASL | ASR | BCHG | BCLR | BSET | BTST | CHK | CMP | CMPA | CMPI | 
                             DIVS | DIVU | EOR | EORI | LSL | LSR | MOVE | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | MOVES | PMOVE | MULS | MULU | NBCD | NEG | NEGX | 
                             NOT_B | OR_B | ORI | ROTL | ROTR | ROXL | ROXR | SBCD | SUB | SUBA | SUBI | SUBQ | SUBX | TAS | TST, '0' when others;

    AR_DEC_S <= AR_DEC_I when ADR_MODE_I = "100" and FETCH_STATE /= CALC_AEFF and NEXT_FETCH_STATE = CALC_AEFF else
              '1' when (OP = BSR or OP = JSR or OP = LINK) and FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP else
              '1' when (OP = CLR or OP = Scc) and ADR_MODE_I = "100" and INIT_ENTRY = '1' else
              -- [F123] Not when the source operand read ended with a bus error: the instruction restarts after RTE and
              -- decremented again (MOVE <mem>,-(An) pushed a garbage slot; Linux busybox argc/argv shifted).
              '1' when OP = MOVE and BIW_0(8 downto 6) = "100" and BIW_0(5 downto 3) /= "011" and INIT_ENTRY = '1' and
                       not (FETCH_STATE = FETCH_OPERAND and DATA_VALID = '0') else -- (An)+, -(An)
              '1' when OP = MOVE and BIW_0(8 downto 6) = "100" and FETCH_STATE = SWITCH_STATE else -- Needed for source (An)+ mode.
              '1' when OP = MOVEM and ADR_MODE_I = "100" and INIT_ENTRY = '1' else -- Decrement before the first bus access. 
              -- [F1] After the last bus access the address register is not decremented. The last register is the one with no list bit above it
              -- (MOVEM_END); the old clock-counted MOVEM_LAST_WR came one clock too late once unused list positions take no clocks.
              '1' when OP = MOVEM and ADR_MODE_I = "100" and ALU_INIT_I = '1' and MOVEM_END = false else
              '1' when (OP = MOVE_FROM_CCR or OP = MOVE_FROM_SR) and ADR_MODE_I = "100" and INIT_ENTRY = '1' else
              '1' when OP = MOVES and ADR_MODE_I = "100" and BIW_1(11) = '1' and INIT_ENTRY = '1' else
              '1' when OP = PMOVE and ADR_MODE_I = "100" and BIW_1(9) = '1' and INIT_ENTRY = '1' else -- [PMMU1] MMU register to memory.
              '1' when (OP = PACK or OP = UNPK) and BIW_0(3) = '1' and INIT_ENTRY = '1' else
              -- PEA: decrement late in SWITCH_STATE not to decremented address register for PEA (xx,A7,yy) address modi.
              '1' when OP = PEA and FETCH_STATE = SWITCH_STATE and PHASE2 = true else '0';

    DR_SEL_RD_1 <= EXT_WORD(14 downto 12) when FETCH_STATE = FETCH_EXWORD_1 else -- Index register
                   BIW_0(11 downto 9) when (OP = ADD or OP = SUB) and BIW_0(8) = '1' else
                   BIW_0(11 downto 9) when (OP = AND_B or OP = EOR or OP = OR_B) and BIW_0(8) = '1' else
                   BIW_0(11 downto 9) when OP = BCHG or OP = BCLR or OP = BSET or OP = BTST else
                   BIW_0(11 downto 9) when OP = ASL or OP = ASR or OP = LSL or OP = LSR else
                   BIW_0(11 downto 9) when OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR else
                   BIW_0(2 downto 0) when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and FETCH_STATE = START_OP and BIW_0(5 downto 3) = "000" else
                   BIW_0(2 downto 0) when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and FETCH_STATE = START_OP and BIW_0(5 downto 3) = "001" else
                   BIW_0(2 downto 0) when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and FETCH_STATE = FETCH_ABS_LO else
                   BIW_0(2 downto 0) when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) and FETCH_STATE = START_OP and BIW_0(5 downto 3) = "000" else
                   BIW_0(2 downto 0) when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) and FETCH_STATE = START_OP and BIW_0(5 downto 3) = "001" else
                   BIW_0(2 downto 0) when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) and FETCH_STATE = FETCH_ABS_LO else
                   BIW_1(8 downto 6) when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) else -- Width value.
                   BIW_1(8 downto 6) when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) else -- Width value.
                   BIW_1(2 downto 0) when OP = CAS else -- Compare operand.
                   BIW_1(14 downto 12) when OP = CAS2 and FETCH_STATE = START_OP else -- Address operand.
                   BIW_1(14 downto 12) when OP = CAS2 and FETCH_STATE = FETCH_OPERAND and PHASE2 = false else -- Address operand.
                   BIW_2(14 downto 12) when OP = CAS2 and FETCH_STATE = CALC_AEFF else -- Address operand.
                   BIW_2(14 downto 12) when OP = CAS2 and FETCH_STATE = FETCH_OPERAND else -- Address operand.
                   BIW_1(14 downto 12) when OP_WB_I = CAS2 and BIW_1(15) = '0' and (EXEC_WB_STATE = EXECUTE or EXEC_WB_STATE = ADR_PIPELINE) else -- Address operand.
                   BIW_2(14 downto 12) when OP_WB_I = CAS2 and BIW_2(15) = '0' and EXEC_WB_STATE = WRITE_DEST else -- Address operand.
                   BIW_1(2 downto 0) when OP = CAS2 and PHASE2 = false else -- Compare operand.
                   BIW_2(2 downto 0) when OP = CAS2 else -- Compare operand.
                   BIW_1(2 downto 0) when (OP = DIVS or OP = DIVU) and FETCH_STATE /= INIT_EXEC_WB and BIW_0(8 downto 6) = "001" else -- LONG 64.
                   MOVEM_PNTR(2 downto 0) when OP = MOVEM else
                   BIW_0(11 downto 9) when OP = MOVEP else
                   BIW_1(14 downto 12) when OP = MOVEC or OP = MOVES else
                   BIW_0(2 downto 0) when OP = ADD or OP = AND_B or OP = OR_B or OP = SUB else 
                   BIW_0(2 downto 0) when OP = ABCD or OP = ADDA or OP = ADDX or OP = CHK or OP = CMP or OP = CMPA else
                   BIW_0(11 downto 9) when OP = EXG and BIW_0(7 downto 3) = "10001" else -- Data and address register.
                   BIW_0(2 downto 0) when OP = DIVS or OP = DIVU or OP = EXG else
                   BIW_0(2 downto 0) when OP = MOVE or OP = MOVEA or OP = MOVE_TO_CCR or OP = MOVE_TO_SR or OP = MULS or OP = MULU or OP= PACK else
                   BIW_0(2 downto 0) when OP = SBCD or OP = SUBA or OP = SUBX or OP = UNPK else "000";

    DR_SEL_WR_1 <= BIW_1(14 downto 12) when OP = BFEXTS or OP = BFEXTU or OP = BFFFO else 
                   BIW_1(14 downto 12) when OP = MOVEC or OP = MOVES else
                   BIW_0(11 downto 9) when OP = ABCD or OP = SBCD else
                   BIW_0(11 downto 9) when OP = ADDX or OP = SUBX else
                   BIW_0(11 downto 9) when OP = ADD or OP = SUB else
                   BIW_0(11 downto 9) when OP = AND_B or OP = OR_B else
                   BIW_0(11 downto 9) when (OP = DIVS or OP = DIVU) and OP_SIZE_I = WORD else
                   BIW_1(14 downto 12) when OP = DIVS or OP = DIVU else
                   BIW_0(11 downto 9) when (OP = MULS or OP = MULU) and OP_SIZE_I = WORD else
                   BIW_1(14 downto 12) when OP = MULS or OP = MULU else -- Low order result and operand.
                   BIW_0(11 downto 9) when OP = EXG else
                   BIW_0(11 downto 9) when OP = MOVE or OP = MOVEP or OP = MOVEQ else
                   BIW_0(11 downto 9) when OP = PACK or OP = UNPK else
                   BIW_1(2 downto 0) when OP = CAS else -- Compare operand.
                   -- [C1] Failed CAS2: the register file latches the selector at DR_MARK_USED (EXECUTE,
                   -- then WRITEBACK) and writes OP3 = (Rn2) first, OP2 = (Rn1) second. The selector named
                   -- Dc1 first, so Dc1 got operand 2 and Dc2 operand 1. Dc2 first also gives the UM result
                   -- for Dc1 = Dc2 (operand 1 wins).
                   BIW_2(2 downto 0) when OP_WB_I = CAS2 and EXEC_WB_STATE = EXECUTE else -- Compare operand 2.
                   BIW_1(2 downto 0) when OP_WB_I = CAS2 and EXEC_WB_STATE = WRITEBACK else -- Compare operand 1.
                   MOVEM_PNTR(2 downto 0) when OP = MOVEM else
                   BIW_0(2 downto 0);

    DR_WR_1 <= '1' when OP_WB_I = EXG and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(7 downto 3) = "10001" else -- Address- and data register.
               '0' when AR_WR_I = '1' else -- This is the locking AR against DR.
               '0' when AR_WR_II = '1' else -- This is the locking AR against DR.
               '0' when OP_WB_I = ANDI_TO_SR or OP_WB_I = EORI_TO_SR or OP_WB_I = ORI_TO_SR else
               '0' when OP_WB_I = MOVE_TO_CCR or OP_WB_I = MOVE_TO_SR else
               '0' when OP_WB_I = MOVE_USP else -- USP is written.
               '0' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' else -- To control register.
               '0' when OP_WB_I = PMOVE else -- [PMMU1] MMU registers only, never a data register.
               '0' when OP_WB_I = LEA and BIW_0_WB_MMU = '1' else -- [PMMU2b] PFLUSH/PLOAD/PTEST: no register at all
                                                                  -- (without this the AR lock is gone and Dn was written).
               '0' when OP_WB_I = STOP else -- SR is written but not DR.
               '1' when F157_WR_EXEC = '1' else -- [F157c] valid RESULT in EXECUTE.
               '1' when EXEC_WB_STATE = WRITEBACK else '0';

    -- F56: the BFINS insertion pattern takes read port 2 at INIT_ENTRY (see F22/F24 below).
    -- INIT_ENTRY is decoded from NEXT_FETCH_STATE, and NEXT_FETCH_STATE waits on DR_IN_USE,
    -- so the data hazard check must not see that INIT_ENTRY arm (combinational loop
    -- NEXT_FETCH_STATE -> INIT_ENTRY -> DR_SEL_RD_2 -> DR_IN_USE -> NEXT_FETCH_STATE).
    -- The hazard check uses DR_SEL_ADH_2/3 instead: for BFINS both the width register
    -- and the pattern register are checked at all times, which can only add a wait.
    DR_SEL_RD_2 <= BIW_1(14 downto 12) when OP = BFINS and INIT_ENTRY = '1' else DR_SEL_ADH_2_I;
    DR_SEL_ADH_2 <= DR_SEL_ADH_2_I;
    DR_SEL_ADH_3 <= BIW_1(14 downto 12) when OP = BFINS else DR_SEL_ADH_2_I;
    DR_SEL_ADH_2_I <= BIW_0(11 downto 9) when OP = ABCD or OP = SBCD or OP = ADDX or OP = SUBX else
                   BIW_0(2 downto 0) when (OP = ADD or OP = AND_B or OP = OR_B or OP = SUB) and BIW_0(8) = '1' else 
                   BIW_0(11 downto 9) when OP = ADD or OP = CMP or OP = SUB or OP = AND_B or OP = OR_B else
                   BIW_0(11 downto 9) when OP = CHK or OP = EXG else
                   -- F22/H29: the BFINS insertion pattern register, MC68030UM 4-19 /
                   -- Table 4-2: the extension word's Dn field is the source for EVERY
                   -- addressing mode. The three original arms enumerated only
                   -- (START_OP, mode 000), (START_OP, mode 001) and FETCH_ABS_LO, so
                   -- (An), (d16,An), (d8,An,Xn) and the PC-relative forms all fell
                   -- through the whole chain to the default "000" and inserted D0
                   -- regardless of the encoding. Port 2 has no other consumer during
                   -- BFINS, so one unconditional arm is correct and covers the three
                   -- cases the original arms already handled.
                   -- F24/H31: the WIDTH register is extension word bits 2-0; the
                   -- OFFSET register is bits 8-6, which read port 1 already
                   -- carries. Bits 2-0 were selected NOWHERE in either port, so a
                   -- register width read whichever register the OFFSET field
                   -- named -- measured, d2=16/d4=8 gave a width of 16.
                   -- Port 2 is free for every bit field op except at the instant
                   -- BFINS loads its pattern, and those instants are DISJOINT:
                   -- INIT_ENTRY asserts only while FETCH_STATE /= INIT_EXEC_WB,
                   -- whereas ALU_TRIG requires FETCH_STATE = INIT_EXEC_WB. So the
                   -- pattern takes port 2 at INIT_ENTRY and the width register
                   -- takes it at every other time, including the two instants
                   -- BITFIELD_CONTROL indexes BF_BYTES_I with offset AND width
                   -- together (START_OP, and the FETCH_OPERAND restore).
                   BIW_1(2 downto 0) when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and BIW_1(5) = '1' else
                   BIW_1(2 downto 0) when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) and BIW_1(5) = '1' else
                   BIW_1(14 downto 12) when OP = BFINS else -- F22: the insertion pattern.
                   BIW_1(8 downto 6) when OP = CAS else -- Update operand.
                   BIW_1(8 downto 6) when OP = CAS2 and PHASE2 = false else -- Update operand.
                   BIW_2(8 downto 6) when OP = CAS2 else -- Update operand.
                   BIW_1(14 downto 12) when OP = CHK2 or OP = CMP2 else
                   BIW_0(11 downto 9) when (OP = DIVS or OP = DIVU) and BIW_0(7) = '1' else -- WORD size.
                   BIW_1(14 downto 12) when (OP = DIVS or OP = DIVU) else -- Quotient low portion.
                   BIW_0(11 downto 9) when (OP = MULS or OP = MULU) and BIW_0(7) = '1' else -- WORD size.
                   BIW_1(14 downto 12) when (OP = MULS or OP = MULU) else
                   BIW_0(2 downto 0) when OP = BCHG or OP = BCLR or OP = BSET or OP = BTST else
                   BIW_0(2 downto 0) when OP = ADDI or OP = ADDQ or OP = ANDI or OP = BCHG or OP = BCLR or OP = BSET or OP = BTST or OP = CMPI else
                   BIW_0(2 downto 0) when OP = DBcc or OP = EOR or OP = EORI or OP = EXT or OP = EXTB or OP = NBCD or OP = NEG or OP = NEGX else
                   BIW_0(2 downto 0) when OP = NOT_B or OP = ORI or OP = SUBI or OP = SUBQ or OP = SWAP or OP = TAS or OP = TST else
                   BIW_0(2 downto 0) when OP = ASL or OP = ASR or OP = LSL or OP = LSR else
                   BIW_0(2 downto 0) when OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR else
                   BIW_0(2 downto 0) when OP = MOVE else -- [F157b] source Dn (not the default D0). Dest WAW is not a hazard.
                   "000";

    DR_SEL_WR_2 <= BIW_0(2 downto 0) when OP = EXG else BIW_1(2 downto 0); -- Default is for DIVS and DIVU, MULS, MULU.

    -- Normally source register. Writte in a few exceptions.
    DR_WR_2 <= '1' when OP_WB_I = EXG and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(7 downto 3) = "01000" else -- Two data registers.
               '1' when OP_WB_I = DIVS and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(8 downto 6) = "001" and BIW_1_WB(14 downto 12) /= BIW_1_WB(2 downto 0) else
               '1' when OP_WB_I = DIVU and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(8 downto 6) = "001" and BIW_1_WB(14 downto 12) /= BIW_1_WB(2 downto 0) else
               '1' when OP_WB_I = MULS and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(8 downto 6) = "000" and BIW_1_WB(10) = '1' and BIW_1_WB(14 downto 12) /= BIW_1_WB(2 downto 0) else
               '1' when OP_WB_I = MULU and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(8 downto 6) = "000" and BIW_1_WB(10) = '1' and BIW_1_WB(14 downto 12) /= BIW_1_WB(2 downto 0) else '0';

    USE_DREG <= '1' when OP = CAS2 and BIW_1(15) = '0' and PHASE2 = false else
                '1' when OP = CAS2 and BIW_2(15) = '0' else
                '1' when (OP = CHK2 or OP = CMP2) and BIW_1(15) = '0' and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and PHASE2 = true else -- Select destination register.
                '1' when (OP = CHK2 or OP = CMP2) and BIW_1(15) = '0' and ALU_INIT_C2 = '1' else '0'; -- Store compare information

    -- [T7] ALU_INIT_I as it is for CHK2/CMP2 (same function, fewer inputs). For those opcodes ALU_BSY_M equals
    -- ALU_BSY (its other arms need OP = MOVEM), the ALU_TRIG arm for CHK2/CMP2 requires PHASE2 = true, and
    -- ALU_INIT_I = ALU_TRIG. The full ALU_INIT_I carries the [F3] MOVEM term (WR_EARLY -> F3_EARLY -> ALU_BSY_M),
    -- which STA then timed through USE_DREG -> AR_IN_1 -> ADR_MUX -> two adders -> ADR_EFF_I as a half-cycle
    -- clk_cpu030_n -> clk_cpu030 path (tt20 worst, -4.887 ns), although OP cannot be MOVEM and CHK2 at once.
    ALU_INIT_C2 <= '1' when ALU_BSY = '0' and FETCH_STATE = INIT_EXEC_WB and WR_FLT = '0' and WFLT = '0' and PHASE2 = true else '0';
    -- synthesis translate_off
    P_T7_CHK: process(CLK) begin -- Sampled at the edge (no delta glitches).
        if CLK = '1' and CLK'event then
            assert not ((OP = CHK2 or OP = CMP2) and ALU_INIT_C2 /= ALU_INIT_I) report "T7: ALU_INIT_C2 /= ALU_INIT_I" severity failure;
        end if;
    end process P_T7_CHK;
    P_T8_CHK: process(CLK) begin
        if CLK = '1' and CLK'event then
            assert not (OP = UNLK and FETCH_STATE = SWITCH_STATE and NEXT_FETCH_STATE = SWITCH_STATE) report "T8: UNLK stays in SWITCH_STATE" severity failure;
        end if;
    end process P_T8_CHK;
    -- synthesis translate_on

    WB_BUFFER: process
    -- This process stores the data for the 
    -- WRITEBACK or the WRITE_DEST procedure.
    -- The MOVEM condition is foreseen to bring
    -- the ADn_WB and the PNTR_WB right in time
    -- befor the address or data registers are
    -- marked used.
    begin
        wait until CLK = '1' and CLK' event;
        if (OP_WB_I = BFCHG or OP_WB_I = BFCLR or OP_WB_I = BFINS or OP_WB_I = BFSET) and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and BF_BYTES = 5 then 
            -- This condition may not overwhelm the ALU_INIT_I sowe have to wait in INIT_EXEC_WB for the 
            -- bit field operations until the last bus cycle finishes.
            OP_SIZE_WB <= BYTE; -- Remaining Byte.
        elsif OP = LINK and FETCH_STATE = START_OP and NEXT_FETCH_STATE = SWITCH_STATE then
            OP_SIZE_WB <= OP_SIZE_I; -- Bring this information early because the registers are written early.
        elsif ALU_INIT_I = '1' then
            if OP = DIVS or OP = DIVU or OP = MULS or OP = MULU then
                OP_SIZE_WB <= LONG;
            elsif OP = MOVEM and BIW_0(10) = '1' then -- Memory to register.
                OP_SIZE_WB <= LONG; -- Registers are always written long.
            else
                OP_SIZE_WB <= OP_SIZE_I; -- Store right in the end before data processing starts.
            end if;

            MOVEM_ADn_WB <= MOVEM_ADn_I;
            OP_WB_I <= OP;
            BIW_0_WB <= BIW_0(11 downto 0);
            if BIW_0(13 downto 12) = "11" then BIW_0_WB_MMU <= '1'; else BIW_0_WB_MMU <= '0'; end if;
            BIW_1_WB <= BIW_1;
        end if;
    end process WB_BUFFER;


    OP_WB <= OP_WB_I;
    BIW_0_WB_73 <= BIW_0_WB(7 downto 3);

    OP_SIZE <= OP_SIZE_I;
    OP_SIZE_I <= LONG when FETCH_STATE = FETCH_MEMADR and RD_RDY = '0' else -- (RD_RDY: release early to provide correct OP_SIZE.
                 LONG when (OP = ADDA or OP = CMPA or OP = SUBA) and BIW_0(8 downto 7) = "11" else
                 LONG when (OP = BCHG or OP = BCLR or OP = BTST or OP = BSET) and BIW_0(5 downto 3) = "000" else
                 LONG when (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET) and BIW_0(5 downto 3) = "000" else
                 LONG when (OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFTST) and BIW_0(5 downto 3) = "000" else
                 LONG when (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET) and BF_BYTES > 2 else
                 LONG when (OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFTST) and BF_BYTES > 2 else
                 -- F21/H29 part A: OP_SIZE serves BOTH the bit field memory fetch
                 -- and the register writeback. The fetch size rightly follows
                 -- BF_BYTES, but MC68030UM places the extracted field right
                 -- justified and zero or sign extended across ALL 32 bits, so the
                 -- DESTINATION write must be LONG whatever the field span.
                 -- Qualified on the writeback stage, exactly as MOVEP does below.
                 LONG when (OP = BFEXTS or OP = BFEXTU or OP = BFFFO) and FETCH_STATE = INIT_EXEC_WB else
                 LONG when OP = EXT and BIW_0(8 downto 6) = "011" else
                 LONG when OP = BSR or OP = EXG or OP = EXTB or OP = JSR or OP = LEA or OP = LINK or OP = PEA or OP = SWAP or OP = UNLK else
                 LONG when (OP = CAS or OP = CAS2) and BIW_0(10 downto 9) = "11" else
                 LONG when OP = CHK and BIW_0(8 downto 7) = "10" else
                 LONG when (OP = CHK2 or OP = CMP2) and BIW_0(10 downto 9) = "10" else
                 LONG when OP = CMPM and BIW_0(7 downto 6) = "10" else
                 LONG when (OP = MOVE or OP = MOVEA) and BIW_0(13 downto 12) = "10" else
                 WORD when OP = PMOVE and BIW_1(15 downto 13) = "011" else -- [PMMU1] MMUSR is a word (MC68030UM 2.x / 9.7.4).
                 LONG when OP = PMOVE else -- [PMMU1] TC, TT0, TT1 are longs.
                 LONG when OP = MOVEC or OP = MOVEQ or OP = MOVE_USP or OP = RTD or OP = RTS else
                 LONG when OP = MOVEM and BIW_0(6) = '1' else
                 LONG when OP = MOVEP and FETCH_STATE = INIT_EXEC_WB and BIW_0(7 downto 6) < "10" else -- Writeback to registers is long (see top level multiplexer).
                 LONG when (OP = DIVS or OP = DIVU or OP = MULS or OP = MULU) and BIW_0(7) = '0' else
                 LONG when OP = RTR and PHASE2 = true else -- Read PC.
                 WORD when (OP = ADDA or OP = CMPA or OP = SUBA) and BIW_0(8 downto 7) = "01" else
                 WORD when (OP = ASL or OP = ASR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                 WORD when OP = ANDI_TO_SR or OP = EORI_TO_SR or OP = ORI_TO_SR else
                 WORD when (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET) and BF_BYTES = 2 else
                 WORD when (OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFTST) and BF_BYTES = 2 else
                 WORD when OP = BKPT and FETCH_STATE = FETCH_OPERAND and DATA_RD_I = '1' else
                 WORD when (OP = CAS or OP = CAS2) and BIW_0(10 downto 9) = "10" else
                 WORD when OP = CHK and BIW_0(8 downto 7) = "11" else
                 WORD when (OP = CHK2 or OP = CMP2) and BIW_0(10 downto 9) = "01" else
                 WORD when OP = CMPM and BIW_0(7 downto 6) = "01" else
                 WORD when OP = DBcc or OP = EXT else
                 WORD when (OP = LSL or OP = LSR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                 WORD when (OP = MOVE or OP = MOVEA) and BIW_0(13 downto 12) = "11" else
                 WORD when OP = MOVE_FROM_CCR or OP = MOVE_TO_CCR else
                 WORD when OP = MOVE_FROM_SR or OP = MOVE_TO_SR else
                 WORD when OP = MOVEM or OP = RTR else
                 WORD when OP = DIVS or OP = DIVU or OP = MULS or OP = MULU else
                 WORD when OP = PACK and (NEXT_FETCH_STATE = FETCH_OPERAND or FETCH_STATE = FETCH_OPERAND) and INIT_ENTRY = '0' else -- Read data is word wide.
                 WORD when (OP = ROTL or OP = ROTR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                 WORD when (OP = ROXL or OP = ROXR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                 WORD when OP = UNPK and (INIT_ENTRY = '1' or FETCH_STATE = INIT_EXEC_WB) else -- Writeback data is a word.
                 BYTE when OP = ABCD or OP = NBCD or OP = SBCD else
                 BYTE when OP = ANDI_TO_CCR or OP = EORI_TO_CCR or OP = ORI_TO_CCR else
                 BYTE when OP = BCHG or OP = BCLR or OP = BTST or OP = BSET else
                 BYTE when OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET else
                 BYTE when OP = BFEXTS or OP = BFEXTU or OP = BFFFO or OP = BFTST else
                 BYTE when OP = CAS and BIW_0(10 downto 9) = "01" else
                 BYTE when (OP = CHK2 or OP = CMP2) and BIW_0(10 downto 9) = "00" else
                 BYTE when OP = CMPM and BIW_0(7 downto 6) = "00" else
                 BYTE when OP = MOVE or OP = MOVEP else
                 BYTE when OP = PACK else -- Writeback data is a byte.
                 BYTE when OP = Scc or OP = TAS else
                 BYTE when OP = UNPK else -- Read data is byte wide.
                 BYTE when BIW_0(7 downto 6) = "00" else
                 WORD when BIW_0(7 downto 6) = "01" else LONG;

    BKPT_CYCLE <= '1' when OP = BKPT and FETCH_STATE = FETCH_OPERAND and DATA_RD_I = '1' else '0';
    BKPT_INSERT <= '1' when OP = BKPT and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' else '0';

    -- All traps must be modeled as strobes. Be aware that the TRAP_cc is released right in the end of the TRAPcc operation.
    -- This is necessary to meet the timing requirements (BUSY_EXH, IPIPE_FLUSH, PC_INC) to provide the next PC address. See
    -- the exception handler unit for more details.
    -- [F44] All three trap STROBES are additionally gated on RESET_CPU='0'.
    --
    -- SILICON FINDING.  On a Tang Console 138K the core took a spurious
    -- TRAPV (vector 7, format 2) on the FIRST instruction after reset,
    -- at the reset PC, with SR still at the reset value -- ten cold
    -- starts, byte identical, independent of the instruction at the
    -- reset PC, and confirmed by a stack dump.  There is no TRAPV in the
    -- image.  The cause: TRAP_V asserts on OP=TRAPV at the first
    -- SLEEP->START_OP transition, but OP, ALU_COND and NEXT_FETCH_STATE
    -- are all in their POWER-UP state at that instant (OP had no initial
    -- value; NEXT_FETCH_STATE was not reset -- see STATE_REGs).  If the
    -- power-up encoding of OP aliases TRAPV and ALU_COND is momentarily
    -- true, the strobe fires once, then normal fetch takes over -- which
    -- is exactly the observed "faults once at $400, handler then runs
    -- perfectly".  GHDL inits enums to 'left (not TRAPV), so simulation
    -- never saw it: a deterministic sim/silicon divergence.
    --
    -- Giving NEXT_FETCH_STATE a reset value (above) removes one leg;
    -- gating the strobes on RESET_CPU='0' removes the whole class,
    -- because no trap can be raised until the CPU is genuinely running.
    -- A real trap needs an executed TRAPV/TRAPcc/BKPT, which cannot
    -- happen during reset, so this cannot suppress a legitimate trap.
    TRAP_ILLEGAL <= '1' when RESET_CPU = '0' and OP = BKPT and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '0' else '0';

    TRAP_cc <= '1' when RESET_CPU = '0' and OP = TRAPcc and ALU_COND = true and FETCH_STATE = SLEEP and NEXT_FETCH_STATE = START_OP else '0';
    TRAP_V <= '1' when RESET_CPU = '0' and OP = TRAPV and ALU_COND = true and FETCH_STATE = SLEEP and NEXT_FETCH_STATE = START_OP else '0';

    -- [F62] A faulted operation word is reported when the controller takes it, which is at the
    -- instruction boundary (FETCH_STATE = START_OP): the idle gate below applies to data cycles only.
    -- Before, an instruction fetch fault on an operation word was dropped and the bus's $FFFF was
    -- executed as a line F opcode.
    BERR <= '0' when OP = BKPT and FETCH_STATE /= START_OP else -- No bus error during breakpoint cycle.
            '1' when OPD_ACK = '1' and OW_VALID = '0' else
            '1' when EW_ACK = '1' and OW_VALID = '0' else
            '0' when FETCH_STATE = START_OP and EXEC_WB_STATE = IDLE else -- Disable when controller is not active.
            '0' when OP = BKPT else
            '1' when DATA_RDY = '1' and DATA_VALID = '0' else '0';

    SFC_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"000" else '0';
    SFC_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1(11 downto 0) = x"000" and EXEC_WB_STATE = WRITEBACK else '0';

    DFC_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"001" else '0';
    DFC_WR <= '1' when OP_WB_I = MOVEC and BIW_0(0) = '1' and BIW_1_WB(11 downto 0) = x"001" and EXEC_WB_STATE = WRITEBACK else '0';

    VBR_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"801" else '0';
    VBR_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"801" and EXEC_WB_STATE = WRITEBACK else '0';

    -- F11: cache control registers. No caches are implemented, but MC68030UM
    -- 6.3.1/6.3.2 define both as MOVEC-accessible 32 bit registers, so the
    -- programming model presents them. Read-back masking lives in the top.
    -- [PMMU1] PMOVE: MV_RW/MV_AN map the PMOVE direction (ext bit 9: 1 = MMU register to memory) onto the
    -- MOVES flow (ext bit 11: 1 = register to memory); the PMOVE source/destination is never An/Dn.
    MV_RW <= BIW_1(9) when OP = PMOVE else BIW_1(11);
    MV_AN <= '0' when OP = PMOVE else BIW_1(15);
    MV_RW_WB <= BIW_1_WB(9) when OP_WB_I = PMOVE else BIW_1_WB(11);
    PMMU_RD_SEL <= BIW_1(15 downto 10);
    PM_QUAD <= '1' when OP = PMOVE and BIW_1(15 downto 11) = "01001" else '0';
    -- First (upper) long of a quad read: the top level keeps it until the writeback of the lower long.
    PMMU_LD_HI <= '1' when PM_QUAD = '1' and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and PHASE2 = false else '0';
    PMMU_LO <= '1' when PHASE2 = true else '0'; -- Quad write: the lower long is the second ALU load.
    PMMU_WR <= '1' when OP_WB_I = PMOVE and BIW_1_WB(9) = '0' and EXEC_WB_STATE = WRITEBACK else '0';
    -- [PMMU2] PM_INFL: a PMOVE to an MMU register is between INIT_EXEC_WB and one clock after its writeback.
    -- START_OP waits on it, so the configuration exception (8.1.10) is pending before the next instruction.
    P_PMMU_WR_D: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            if (OP_WB_I = PMOVE and BIW_1_WB(9) = '0' and EXEC_WB_STATE = WRITEBACK) or PMMU_OP_I = '1' then
                PMMU_WR_D <= '1';
            else
                PMMU_WR_D <= '0';
            end if;
            if RESET_CPU = '1' or PMMU_WR_D = '1' then
                PM_INFL <= '0';
            elsif FETCH_STATE = INIT_EXEC_WB and ((OP = PMOVE and BIW_1(9) = '0') or (OP = LEA and BIW_0(13 downto 12) = "11")) then
                PM_INFL <= '1';
            end if;
        end if;
    end process P_PMMU_WR_D;
    PMMU_WR_SEL <= BIW_1_WB(15 downto 10);
    PMMU_FD <= BIW_1_WB(8);
    PMMU_OP_I <= '1' when OP_WB_I = LEA and BIW_0_WB_MMU = '1' and EXEC_WB_STATE = WRITEBACK else '0';
    PMMU_OP <= PMMU_OP_I;
    PMMU_EXT <= BIW_1_WB;

    CACR_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"002" else '0';
    CACR_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"002" and EXEC_WB_STATE = WRITEBACK else '0';

    CAAR_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"802" else '0';
    CAAR_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"802" and EXEC_WB_STATE = WRITEBACK else '0';

    ISP_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"804" else '0';
    ISP_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"804" and EXEC_WB_STATE = WRITEBACK else '0';

    MSP_RD <= '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"803" else '0';
    MSP_WR <= '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"803" and EXEC_WB_STATE = WRITEBACK else '0';

    USP_RD <= '1' when OP = MOVE_USP and BIW_0(3) = '1' else
              '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(11 downto 0) = x"800" else '0';
    USP_WR <= '1' when OP_WB_I = MOVE_USP and EXEC_WB_STATE = WRITEBACK and BIW_0_WB(3) = '0' else
              '1' when OP_WB_I = MOVEC and BIW_0_WB(0) = '1' and BIW_1_WB(11 downto 0) = x"800" and EXEC_WB_STATE = WRITEBACK else '0';

    P_DISPLACEMENT: process
    variable DISPL_VAR : std_logic_vector(31 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        case OP is
            when Bcc | BRA | BSR =>
                case BIW_0(7 downto 0) is
                    when x"FF" =>
                        DISPL_VAR := BIW_1 & BIW_2;
                    when x"00" =>
                        for i in 16 to 31 loop
                            DISPL_VAR(i) := BIW_1(15);
                        end loop;
                        DISPL_VAR(15 downto 0) := BIW_1;
                    when others =>
                        for i in 8 to 31 loop
                            DISPL_VAR(i) := BIW_0(7);
                        end loop;
                        DISPL_VAR(7 downto 0) := BIW_0(7 downto 0);
                end case;
            when DBcc | MOVEP | RTD =>
                for i in 16 to 31 loop
                    DISPL_VAR(i) := BIW_1(15);
                end loop;
                DISPL_VAR(15 downto 0) := BIW_1;
            when others => -- Used for LINK.
                case BIW_0(11 downto 3) is
                    when "100000001" => -- Long.
                        DISPL_VAR := BIW_1 & BIW_2;
                    when others => -- Word.
                        for i in 16 to 31 loop
                            DISPL_VAR(i) := BIW_1(15);
                        end loop;
                        DISPL_VAR(15 downto 0) := BIW_1;
                end case;
        end case;
        --
        case OP is
            when LINK | MOVEP => DISPLACEMENT_R <= DISPL_VAR;
            when others => DISPLACEMENT_R <= DISPL_VAR + "10";
        end case;
    end process P_DISPLACEMENT;

    -- [F160] Early Bcc.B. In the OPD_ACK clock OP and BIW_0 are the new (registered) operation word, but the
    -- registered DISPLACEMENT still belongs to the previous one: the early branch uses d8 + 2 from BIW_0.
    -- CC_UPDT and the ALU_BSY clear happen on the same ALU_ACK edge (STATUS_REG is registered there), so with
    -- ALU_BSY = '0' CCR_IN holds the last result. The SR writers in WRITEBACK are excluded explicitly.
    BCC_LCOND <= true when BIW_0(11 downto 8) = x"0" else
                 true when BIW_0(11 downto 8) = x"2" and (CCR_IN(2) nor CCR_IN(0)) = '1' else
                 true when BIW_0(11 downto 8) = x"3" and (CCR_IN(2) or CCR_IN(0)) = '1' else
                 true when BIW_0(11 downto 8) = x"4" and CCR_IN(0) = '0' else
                 true when BIW_0(11 downto 8) = x"5" and CCR_IN(0) = '1' else
                 true when BIW_0(11 downto 8) = x"6" and CCR_IN(2) = '0' else
                 true when BIW_0(11 downto 8) = x"7" and CCR_IN(2) = '1' else
                 true when BIW_0(11 downto 8) = x"8" and CCR_IN(1) = '0' else
                 true when BIW_0(11 downto 8) = x"9" and CCR_IN(1) = '1' else
                 true when BIW_0(11 downto 8) = x"A" and CCR_IN(3) = '0' else
                 true when BIW_0(11 downto 8) = x"B" and CCR_IN(3) = '1' else
                 true when BIW_0(11 downto 8) = x"C" and (CCR_IN(3) xnor CCR_IN(1)) = '1' else
                 true when BIW_0(11 downto 8) = x"D" and (CCR_IN(3) xor CCR_IN(1)) = '1' else
                 true when BIW_0(11 downto 8) = x"E" and CCR_IN(3 downto 1) = "101" else
                 true when BIW_0(11 downto 8) = x"E" and CCR_IN(3 downto 1) = "000" else
                 true when BIW_0(11 downto 8) = x"F" and CCR_IN(2) = '1' else
                 true when BIW_0(11 downto 8) = x"F" and (CCR_IN(3) xor CCR_IN(1)) = '1' else false;
    -- [F163] Same clock as ALU_ACK (EXECUTE -> IDLE) for these ops, decoded from registers only: ALU_ACK itself goes
    -- through NEXT_EXEC_WB_STATE and the [F3] WR_EARLY term (half-cycle path WP_NEG -> EX_P_*, -1.8 ns in the first build).
    CCR_FWD_OK <= '0' when not F163_CCR_FWD or EXEC_WB_STATE /= EXECUTE or ALU_REQ = '0' else
                  '1' when OP_WB_I = MOVEQ or OP_WB_I = CMP or OP_WB_I = TST else
                  '1' when (OP_WB_I = ADD or OP_WB_I = SUB or OP_WB_I = AND_B or OP_WB_I = OR_B) and BIW_0_WB(8) = '0' else
                  '1' when (OP_WB_I = ADDQ or OP_WB_I = SUBQ or OP_WB_I = EOR) and BIW_0_WB(5 downto 3) = "000" else '0';

    BCC_EARLY <= '0' when not F160_BCC_EARLY or OP /= Bcc or FETCH_STATE /= START_OP or OPD_ACK = '0' or OW_VALID /= '1' else
                 '0' when BIW_0(7 downto 0) = x"00" or BIW_0(7 downto 0) = x"FF" else -- Byte displacement only.
                 '0' when BCC_LCOND = false else -- Not taken: ALU_COND path (UM 4, never faster).
                 '0' when ALU_BSY = '1' and CCR_FWD_OK = '0' else -- [F163] CCR forwarded.
                 '0' when TRACE_MODE /= "00" or IRQ_HOT = '1' or EXH_REQ = '1' or LOOP_BSY = '1' else
                 '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' or WR_FLT = '1' or WFLT = '1' else
                 '0' when EXEC_WB_STATE /= IDLE and (OP_WB_I = MOVE_TO_CCR or OP_WB_I = MOVE_TO_SR or OP_WB_I = ANDI_TO_SR or
                                                     OP_WB_I = EORI_TO_SR or OP_WB_I = ORI_TO_SR or OP_WB_I = STOP or
                                                     OP_WB_I = ANDI_TO_CCR or OP_WB_I = EORI_TO_CCR or OP_WB_I = ORI_TO_CCR) else '1';
    -- [F162] Taken Bcc.B whose OPD_ACK clock still had the ALU busy (typically SUBQ/CMP right before it): in its
    -- INIT_EXEC_WB clock the ALU is idle, so CCR_IN holds the result (CC_UPDT and the ALU_BSY clear share the ALU_ACK
    -- edge) and DISPLACEMENT_R is this Bcc's. Leave like BRA (flush + PC + d8 + 2) without the ALU handshake and SLEEP.
    -- Not taken keeps the ALU path (UM 4, never faster). Same exclusions as BCC_EARLY. F160a tried this and lost the
    -- clock to the stale OPCODE_RDY after the flush; F162_DQ removes that.
    BCC_INIT <= '0' when not F162_BCC_INIT or OP /= Bcc or FETCH_STATE /= INIT_EXEC_WB else
                '0' when BIW_0(7 downto 0) = x"00" or BIW_0(7 downto 0) = x"FF" else -- Byte displacement only.
                '0' when BCC_LCOND = false else
                '0' when ALU_BSY = '1' or TRACE_MODE /= "00" or IRQ_HOT = '1' or EXH_REQ = '1' or LOOP_BSY = '1' else
                '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' or WR_FLT = '1' or WFLT = '1' else
                '0' when EXEC_WB_STATE /= IDLE and (OP_WB_I = MOVE_TO_CCR or OP_WB_I = MOVE_TO_SR or OP_WB_I = ANDI_TO_SR or
                                                    OP_WB_I = EORI_TO_SR or OP_WB_I = ORI_TO_SR or OP_WB_I = STOP or
                                                    OP_WB_I = ANDI_TO_CCR or OP_WB_I = EORI_TO_CCR or OP_WB_I = ORI_TO_CCR) else '1';
    -- [F161] Early taken DBcc in its OPD_ACK clock. OP, BIW_0 and BIW_1 (d16) are the new registered words;
    -- read port 2 already selects Dn (DR_SEL_ADH_2_I = BIW_0(2 downto 0) for DBcc), PC still points at the DBcc.
    DBCC_EARLY <= '0' when not F161_DBCC_EARLY or OP /= DBcc or FETCH_STATE /= START_OP or OPD_ACK = '0' or OW_VALID /= '1' else
                  '0' when BCC_LCOND = true or DBCC_DNZ = '0' else -- cc true or the count expires: ALU path.
                  '0' when BIW_1 = x"FFFC" or LOOP_BSY = '1' else -- 68010 loop-mode entry / loop mode: unchanged.
                  '0' when DR_IN_USE = '1' or TRACE_MODE /= "00" or IRQ_HOT = '1' or EXH_REQ = '1' else
                  '0' when ALU_BSY = '1' and BIW_0(11 downto 8) /= x"1" else -- cc /= F: CCR must be settled.
                  '0' when ALU_BSY = '1' and EXEC_WB_STATE /= EXECUTE and EXEC_WB_STATE /= WRITEBACK else -- No memory destination.
                  '0' when ALU_BSY = '1' and not (OP_WB_I = ADD or OP_WB_I = ADDA or OP_WB_I = ADDI or OP_WB_I = ADDQ or OP_WB_I = ADDX or
                                                  OP_WB_I = AND_B or OP_WB_I = ANDI or OP_WB_I = ASL or OP_WB_I = ASR or OP_WB_I = BCHG or
                                                  OP_WB_I = BCLR or OP_WB_I = BSET or OP_WB_I = BTST or OP_WB_I = CLR or OP_WB_I = CMP or
                                                  OP_WB_I = CMPA or OP_WB_I = CMPI or OP_WB_I = EOR or OP_WB_I = EORI or OP_WB_I = EXG or
                                                  OP_WB_I = EXT or OP_WB_I = EXTB or OP_WB_I = LEA or OP_WB_I = LSL or OP_WB_I = LSR or
                                                  OP_WB_I = MOVE or OP_WB_I = MOVEA or OP_WB_I = MOVEQ or OP_WB_I = NEG or OP_WB_I = NEGX or
                                                  OP_WB_I = NOT_B or OP_WB_I = OR_B or OP_WB_I = ORI or OP_WB_I = ROTL or OP_WB_I = ROTR or
                                                  OP_WB_I = ROXL or OP_WB_I = ROXR or OP_WB_I = Scc or OP_WB_I = SUB or OP_WB_I = SUBA or
                                                  OP_WB_I = SUBI or OP_WB_I = SUBQ or OP_WB_I = SUBX or OP_WB_I = SWAP or OP_WB_I = TST) else
                  '0' when PM_INFL = '1' or PMMU_WR_D = '1' or MMU_BUSY = '1' or WR_FLT = '1' or WFLT = '1' else
                  '0' when EXEC_WB_STATE /= IDLE and (OP_WB_I = MOVE_TO_CCR or OP_WB_I = MOVE_TO_SR or OP_WB_I = ANDI_TO_SR or
                                                      OP_WB_I = EORI_TO_SR or OP_WB_I = ORI_TO_SR or OP_WB_I = STOP or
                                                      OP_WB_I = ANDI_TO_CCR or OP_WB_I = EORI_TO_CCR or OP_WB_I = ORI_TO_CCR) else '1';
    DR_DEC <= DBCC_EARLY; -- [F161]
    RTS_EARLY <= true when F161_RTS_EARLY and OP = RTS and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' and
                           ALU_BSY = '0' and TRACE_MODE = "00" and IRQ_HOT = '0' and EXH_REQ = '0' and PM_INFL = '0' and
                           PMMU_WR_D = '0' and MMU_BUSY = '0' and WR_FLT = '0' and WFLT = '0' else false;
    -- [F161] Expired DBcc: OA, INIT, SLEEP ... START_OP, next OA. Leaving SLEEP at DBCC_CNT = 5 puts the
    -- dbf_expired harness at the MC68030UM 14 (or just under). The unpadded instruction was 5 (UM 10);
    -- CNT < 7 gave the harness 16, 2 over the UM 14, so the hold is CNT < 5. Prefer at or below the UM.
    P_DBCC_CNT: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP or OP /= DBcc then
            DBCC_CNT <= 0;
        elsif DBCC_CNT < 15 then
            DBCC_CNT <= DBCC_CNT + 1;
        end if;
    end process P_DBCC_CNT;
    DBCC_XHOLD <= true when F161_DBCC_XPAD and OP = DBcc and FETCH_STATE = SLEEP and LOOP_BSY = '0' and ALU_COND = false and
                            DBcc_COND = true and DBCC_CNT < 5 else false;
    DISPL_DBCC(31 downto 16) <= (others => BIW_1(15));
    DISPL_DBCC(15 downto 0) <= BIW_1;
    DISPL_EARLY(31 downto 8) <= (others => '1') when BIW_0(7) = '1' else (others => '0');
    DISPL_EARLY(7 downto 0) <= BIW_0(7 downto 0);
    DISPLACEMENT <= DISPL_EARLY + "10" when F160_BCC_EARLY and OP = Bcc and FETCH_STATE = START_OP else -- [F160]
                    DISPL_DBCC + "10" when F161_DBCC_EARLY and OP = DBcc and FETCH_STATE = START_OP else DISPLACEMENT_R; -- [F161]

    PC_ADD_DISPL <= PC_ADD_DISPL_I;
    PC_ADD_DISPL_I <= '1' when BCC_EARLY = '1' else -- [F160]
                      '1' when BCC_INIT = '1' else -- [F162]
                      '1' when DBCC_EARLY = '1' else -- [F161]
                      '1' when OP = Bcc and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP and ALU_COND = true else
                      '1' when (OP = BRA or OP = BSR) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else 
                      '1' when OP = DBcc and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP and ALU_COND = false and DBcc_COND = false else '0';
    
    PC_LOAD <= PC_LOAD_I;
    PC_LOAD_I <= '1' when (OP = JMP or OP = JSR) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else
                 '1' when (OP = RTD or OP = RTR or OP = RTS) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else '0';

    -- The pipe is flushed for the system control instructions. Be aware, that the operations resulting in an exception
    -- like the CHK or TRAP operations flush the pipe via the exception handler.
    -- Context switch may occur from:
    --   changing the PC value (branches etc.)
    --   changing the RAM space (status register MSBs).
    --   changing Function codes or the active stack pointer.
    IPIPE_FLUSH <= IPIPE_FLUSH_I;

    -- [PFCOF] Change of flow pending, as the 68030/CPU32 prefetch controller: the instruction words of
    -- the executing branch/jump/return are all consumed (states after the extension words), and it will
    -- load the PC. The bus interface starts no further instruction-stream fetches while this is set.
    -- Only timing depends on it (a stale ALU_COND costs or saves one fetch, never changes results).
    -- The decoder lifts the hold whenever the control unit waits for an operation or extension word.
    COF_PEND <= '1' when FETCH_STATE /= START_OP and
                         ((OP = BRA or OP = BSR or OP = JMP or OP = JSR or OP = RTS or OP = RTD or OP = RTR) or
                          (OP = Bcc and FETCH_STATE = SLEEP and ALU_COND = true) or -- Condition valid in SLEEP only.
                          (BCC_INIT = '1') or -- [F162]
                          (OP = DBcc and FETCH_STATE = SLEEP and LOOP_BSY = '0' and ALU_COND = false and DBcc_COND = false)) else '0';
    IPIPE_FLUSH_I <= '1' when BCC_EARLY = '1' else -- [F160]
                     '1' when BCC_INIT = '1' else -- [F162]
                     '1' when DBCC_EARLY = '1' else -- [F161]
                     '1' when (OP = BRA or OP = BSR) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else
                     '1' when OP = Bcc and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP and ALU_COND = true else
                     '1' when OP = DBcc and LOOP_BSY = '0' and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP and ALU_COND = false and DBcc_COND = false else
                     '1' when OP = DBcc and LOOP_EXIT_I = '1' and (ALU_COND = true or DBcc_COND = true) else -- Flush the pipe after a finished loop.
                     '1' when (OP = ANDI_TO_SR or OP = EORI_TO_SR or OP = MOVE_TO_SR or OP = ORI_TO_SR) and FETCH_STATE = SLEEP and NEXT_FETCH_STATE = START_OP else
                     '1' when (OP = JMP or OP = JSR) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else
                     '1' when OP = MOVEC and BIW_0(0) = '1' and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else -- Writing control registers.
                     '1' when (OP = RTD or OP = RTR or OP = RTS) and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else '0';

    SP_ADD_DISPL_S <= '1' when OP = LINK and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' else 
                    '1' when OP = RTD and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and DATA_VALID = '1' else '0';

    -- [F157a] A new ALU_INIT may overlap the current WRITEBACK (ALU_BSY still set until this
    -- clock's ALU_ACK). Without this, ALU_TRIG stays low and the next op never loads.
    ALU_TRIG <= '1' when MEM_FAST = '1' else -- [F165] read-ready clock, ALU idle.
                '0' when (ALU_BSY_M = '1' and F157_OLAP = '0') or FETCH_STATE /= INIT_EXEC_WB else
                '0' when WR_FLT = '1' or WFLT = '1' else -- [FLT1] Nothing new after a data write fault.
                '0' when BCC_INIT = '1' else -- [F162] decided from the live CCR, no ALU.
                '0' when (OP = CHK2 or OP = CMP2 or OP = CMPM) and PHASE2 = false else
                '0' when OP = MOVE and PHASE2 = true else -- no ALU required after second portion of address calculation.
                '0' when OP = MOVEM and MOVEM_COND = false else
                '0' when OP = MOVEM and BIW_0(10) = '1' and MOVEM_FIRST_RD = false else -- Do not load before the first read access.
                '0' when OP = RTR and PHASE2 = true else '1'; -- RTR: not when PC is loaded.

    -- This is the signal loading the operands into the ALU registers:
    ALU_INIT <= ALU_INIT_I;
    with OP select
        ALU_INIT_I <= ALU_TRIG when ABCD | ADD | ADDA | ADDI | ADDQ | ADDX | AND_B | ANDI | ANDI_TO_CCR | ANDI_TO_SR | ASL | ASR | Bcc | BCHG |
                                    BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BSR | BTST | CAS | CAS2 | 
                                    CHK | CHK2 | CLR | CMP | CMPA | CMPI | CMPM | CMP2 | DBcc | DIVS | DIVU | EOR | EORI | EORI_TO_CCR | EORI_TO_SR |
                                    EXG | EXT | EXTB | JSR | LEA | LINK | LSL | LSR | MOVE | MOVEA | MOVE_FROM_CCR | MOVE_TO_CCR | MOVE_FROM_SR | 
                                    MOVE_TO_SR | MOVE_USP | MOVEC | MOVEM | MOVEQ | MOVEP | MOVES | PMOVE | MULS | MULU | NBCD | NEG | NEGX | NOT_B | OR_B | 
                                    ORI | ORI_TO_CCR | ORI_TO_SR | PACK | PEA | ROTL | ROTR | ROXL | ROXR | RTR | SBCD | Scc | SUB | SUBA | SUBI | 
                                    SUBQ | SUBX | SWAP | STOP | TAS | TRAPV | TRAPcc | TST | UNLK | UNPK, '0' when others;

    ADR_FORMAT: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = FETCH_EXWORD_1 and EW_ACK = '1' and EXT_WORD(8) = '1' then
            case EXT_WORD(1 downto 0) is
                when "11" =>
                    MEM_INDIRECT <= '1';
                    OD_REQ_32 <= '1';
                    OD_REQ_16 <= '0';
                when "10" =>
                    MEM_INDIRECT <= '1';
                    OD_REQ_32 <= '0';
                    OD_REQ_16 <= '1';
                when "01" =>
                    MEM_INDIRECT <= '1';
                    OD_REQ_32 <= '0';
                    OD_REQ_16 <= '0';
                when others =>
                    MEM_INDIRECT <= '0';
                    OD_REQ_32 <= '0';
                    OD_REQ_16 <= '0';
            end case;
        end if;
    end process ADR_FORMAT;

    -- [C1] CAS2 condition codes come from the compare that decides: the first one if it fails,
    -- else the second (MC68030UM CAS2). The old suppress terms tested FETCH_STATE = INIT_EXEC_WB,
    -- which the pipelined CAS2 no longer meets, so the second compare and the Dc writeback also
    -- updated the CCR. Registered hold bit: set by a failed first compare, cleared after writeback.
    UPDT_CC <= '0' when (OP_WB_I = ADDQ or OP_WB_I = SUBQ) and BIW_0_WB(5 downto 3) = "001" else -- No update for ADDQ and SUBQ when destination is an address register.
               '0' when OP_WB_I = CAS2 and (EXEC_WB_STATE /= EXECUTE or CAS2_CCHOLD = '1') else ALU_REQ;

    P_CAS2_CCHOLD: process
    begin
        wait until CLK = '1' and CLK' event;
        if OP_WB_I = CAS2 and EXEC_WB_STATE = EXECUTE and CAS2_CCHOLD = '0' and ALU_REQ = '1' and ALU_COND = false then
            CAS2_CCHOLD <= '1';
        elsif EXEC_WB_STATE = WRITEBACK or EXEC_WB_STATE = WRITE_DEST then
            CAS2_CCHOLD <= '0';
        end if;
    end process P_CAS2_CCHOLD;

    P_MEMADR_IN: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = FETCH_MEMADR then
            MEMADR_IN <= '1';
        else
            MEMADR_IN <= '0';
        end if;
    end process P_MEMADR_IN;

    -- [F130] FETCH_D_LO/FETCH_EXWORD_1/FETCH_OD_x enter FETCH_MEMADR without the AR_IN_USE (ADH) wait, and the pointer
    -- read went out with an index Dn whose write-back was still pending (F97 IDX_TRK only holds the later states).
    -- Board: 'bfextu d2{8:2},d0; jmp ([bd,pc,d0.l*4])' (Linux FPU emulator fp_decode_cond) read the table at the stale
    -- d0 -> BAD KERNEL BUSERR. The pointer read now waits until AR_IN_USE (base An pending or IDX_TRK) has been clear
    -- for two clocks, so INDEX and the registered ADR_EFF hold the written value. Sticky for the rest of FETCH_MEMADR.
    P_MEMADR_OK: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE /= FETCH_MEMADR then
            MEMADR_Q1 <= '0'; MEMADR_OK <= '0';
        else
            if AR_IN_USE = '0' then MEMADR_Q1 <= '1'; end if;
            if MEMADR_Q1 = '1' then MEMADR_OK <= '1'; end if;
        end if;
    end process P_MEMADR_OK;

    -- [MI1] Memory indirect: the pointer read (FETCH_MEMADR) and, right after it, the operand read
    -- (CALC_AEFF one clock, the address calculation) come before further queue prefetches. Before,
    -- the bus rolled the pointer read into a queue prefetch (DP_CHAIN) or started one from IDLE in
    -- the CALC_AEFF clock, and the operand read waited a whole long-word prefetch (8 clocks on the
    -- 16-bit port). Registered state decode only; the bus interface ANDs it into PF_REQ.
    MI_HOLD <= '1' when FETCH_STATE = FETCH_MEMADR else
               '1' when FETCH_STATE = CALC_AEFF and MEMADR_IN = '1' else
               -- [CS1] CAS2 is one read-modify-write sequence (RMC, the bus is locked from the first
               -- read to the last write on a 68030): no queue prefetch between the two reads and the
               -- two writes once the first operand is in. All extension words are fetched by then.
               '1' when OP = CAS2 and PHASE2 = true and FETCH_STATE /= START_OP else
               '1' when OP = CAS2 and (FETCH_STATE = INIT_EXEC_WB or FETCH_STATE = SLEEP) else '0';

    with OP_WB_I select
    CC_UPDT <= UPDT_CC when ABCD | ADD | ADDI | ADDQ | ADDX | AND_B | ANDI | ANDI_TO_CCR | ASL | ASR | BCHG | BCLR |
                            BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST |
                            CAS | CAS2 | CHK | CHK2 | CLR | CMP | CMPA | CMPI | CMPM | CMP2 | DIVS | DIVU |
                            EOR | EORI | EORI_TO_CCR | EXT | EXTB | LSL | LSR | MOVE | MOVEQ | MULS | MULU | NBCD |
                            NEG | NEGX | NOT_B | OR_B | ORI | ORI_TO_CCR | ROTL | ROTR | ROXL | ROXR | RTR | SBCD |
                            SUB | SUBI | SUBQ | SUBX | SWAP | TAS | TST, '0' when others;

    ADR_MARK_USED_I <= '1' when OP = MOVE and FETCH_STATE = INIT_EXEC_WB and PHASE2 = true else -- Destination address calculation done.
                       '0' when FETCH_STATE /= INIT_EXEC_WB or ALU_BSY_M = '1' else -- Deactivate except in the end of INIT_EXEC_WB.
                       '1' when OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET or OP = BSR  or OP = JSR or OP = LINK or OP = PEA  else
                       '1' when (OP = ADDI or OP = ANDI or OP = EOR or OP = EORI or OP = ORI or OP = SUBI) and BIW_0(5 downto 3) /= "000" else
                       '1' when (OP = ABCD or OP = SBCD or OP = ADDX or OP = SUBX) and BIW_0(3) = '1' else
                       '1' when (OP = ADD or OP = AND_B or OP = OR_B or OP = SUB) and BIW_0(8) = '1' else
                       '1' when (OP = ADDQ or OP = BCHG or OP = BCLR or OP = BSET or OP = CLR or OP = MOVE_FROM_CCR or OP = MOVE_FROM_SR) and BIW_0(5 downto 3) > "001"  else
                       '1' when (OP = NBCD or OP = NEG or OP = NEGX or OP = NOT_B or OP = Scc or OP = SUBQ or OP = TAS) and BIW_0(5 downto 3) > "001"  else
                       '1' when (OP = ASL or OP = ASR or OP = LSL or OP = LSR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                       '1' when (OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and BIW_0(7 downto 6) = "11" else -- Memory shifts.
                       '1' when OP = MOVE and PHASE2 = false and BIW_0(8 downto 6) /= "000" and BIW_0(8 downto 6) < "101" else -- We do not need destination address calculation access.
                       '1' when OP = MOVEM and BIW_0(10) = '0' and MOVEM_COND = true else -- Register to memory.
                       '1' when OP = MOVEP and BIW_0(7 downto 6) > "01" else -- Register to Memory.
                       '1' when OP = MOVES and BIW_1(11) = '1' else -- Register to memory.
                       '1' when OP = PMOVE and BIW_1(9) = '1' else -- [PMMU1] MMU register to memory.
                       '1' when (OP = PACK or OP = UNPK) and BIW_0(3) = '1' else '0';

    ADR_MARK_USED <= ADR_MARK_USED_W;
    ADR_MARK_USED_W <= '1' when (OP_WB_I = BFCHG or OP_WB_I = BFCLR) and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and BF_BYTES = 5 else
                     '1' when (OP_WB_I = BFINS or OP_WB_I = BFSET) and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and BF_BYTES = 5 else
                     '1' when OP_WB_I = CAS and EXEC_WB_STATE = EXECUTE and ALU_COND = true else
                     '1' when OP_WB_I = CAS2 and EXEC_WB_STATE = EXECUTE and FETCH_STATE = SLEEP and ALU_COND = true else
                     '1' when OP_WB_I = CAS2 and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and PHASE2 = false else ADR_MARK_USED_I;

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

    DR_MARK_USED <= '1' when OP_WB_I = CAS and EXEC_WB_STATE = EXECUTE and ALU_COND = false else
                    '1' when OP_WB_I = CAS2 and EXEC_WB_STATE = EXECUTE and ALU_COND = false else
                    '1' when OP_WB_I = CAS2 and EXEC_WB_STATE = WRITEBACK and PHASE2 = false else
                    '1' when MEM_FAST = '1' and (OP = MOVE or OP = ADD or OP = SUB or OP = AND_B or OP = OR_B) else -- [F165] Dn destination.
                    '0' when FETCH_STATE /= INIT_EXEC_WB or NEXT_FETCH_STATE = INIT_EXEC_WB else -- Deactivate except in the end of INIT_EXEC_WB.
                    '1' when (OP = ABCD or OP = SBCD) and BIW_0(3) = '0' else
                    '1' when (OP = ADDX or OP = SUBX) and BIW_0(3) = '0' else
                    '1' when (OP = ADDQ or OP = SUBQ) and BIW_0(5 downto 3) = "000" else
                    '1' when (OP = ADD or OP = SUB) and BIW_0(8) = '0' else
                    '1' when (OP = ADDI or OP = ANDI or OP = EOR or OP = EORI or OP = ORI or OP = SUBI) and BIW_0(5 downto 3) = "000" else
                    '1' when (OP = AND_B or OP = OR_B) and BIW_0(8) = '0' else
                    '1' when (OP = ASL or OP = ASR) and BIW_0(7 downto 6) /= "11" else
                    '1' when (OP = LSL or OP = LSR) and BIW_0(7 downto 6) /= "11" else
                    '1' when (OP = ROTL or OP = ROTR) and BIW_0(7 downto 6) /= "11" else
                    '1' when (OP = ROXL or OP = ROXR) and BIW_0(7 downto 6) /= "11" else
                    '1' when (OP = BCHG or OP = BCLR or OP = BSET) and BIW_0(5 downto 3) = "000" else
                    '1' when (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET) and BIW_0(5 downto 3) = "000" else
                    '1' when OP = BFEXTS or OP = BFEXTU or OP = BFFFO else
                    '1' when (OP = CLR or OP = TAS or OP = Scc) and BIW_0(5 downto 3) = "000" else
                    '1' when OP = DBcc or OP = DIVS or OP = DIVU or OP = MULS or OP = MULU else
                    '1' when OP = EXG and BIW_0(7 downto 3) /= "01001" else
                    '1' when OP = EXT or OP = EXTB or OP = SWAP else
                    '1' when OP = MOVE and BIW_0(8 downto 6) = "000" else
                    '1' when (OP = MOVE_FROM_CCR or OP = MOVE_FROM_SR) and BIW_0(5 downto 3) = "000" else
                    '1' when OP = MOVEM and BIW_0(10) = '1' and MOVEM_ADn_I = '0' and MOVEM_COND = true else -- Memory to register.
                    '1' when OP = MOVEP and BIW_0(7 downto 6) < "10" else -- Memory to register.
                    '1' when OP = MOVEC and BIW_0(0) = '0' and BIW_1(15) = '0' else -- Destination is Dx.
                    '1' when OP = MOVEQ else
                    '1' when OP = MOVES and BIW_1(15) = '0' and BIW_1(11) = '0' else
                    '1' when (OP = NBCD or OP = NEG or OP = NEGX or OP = NOT_B) and BIW_0(5 downto 3) = "000" else
                    '1' when (OP = PACK or OP = UNPK) and BIW_0(3) = '0' else '0';

    UNMARK <= '1' when WR_FLT = '1' else -- [FLT1] The aborted write-back releases its address.
              '1' when EXEC_WB_STATE /= IDLE and NEXT_EXEC_WB_STATE = IDLE else -- Release a pending write cycle when done.
              '1' when F157_PHASE_A and EXEC_WB_STATE = WRITEBACK and NEXT_EXEC_WB_STATE = EXECUTE else '0'; -- [F157a] WRITEBACK folded into the next EXECUTE.

    -- These signals indicates, that two registers are prepared to be written. In this case, the values
    -- in both of these registers are invalidated before the writeback.
    USE_APAIR <= true when OP = EXG and BIW_0(7 downto 3) = "01001" else false;
    USE_DPAIR <= true when OP = EXG and BIW_0(7 downto 3) = "01000" else
                 true when (OP = DIVS or OP = DIVU) and OP_SIZE_I = LONG and BIW_1(14 downto 12) /= BIW_1(2 downto 0) else
                 true when (OP = MULS or OP = MULU) and OP_SIZE_I = LONG and BIW_1(10) = '1' and BIW_1(14 downto 12) /= BIW_1(2 downto 0) else false;

    LOOP_EXIT <= LOOP_EXIT_I;
    LOOP_EXIT_I <= '1' when OP /= DBcc and LOOP_BSY = '1' and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP and EXH_REQ = '1' else -- Exception! break the loop.
                   '1' when OP = DBcc and LOOP_BSY = '1' and FETCH_STATE = SLEEP and NEXT_FETCH_STATE = START_OP and (ALU_COND = true or DBcc_COND = true) else '0'; -- 68010 loop mechanism.

    LOOP_CTRL: process
    -- This flip flop indicates, if a DBcc loop operation has finished if the exception handler indicates an interrupt. 
    -- If so, no action is required. If the loop is split (when not finished) the exception handler may not increment 
    -- the PC to hold the value of the loop operation.
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP then
            LOOP_SPLIT <= false;
        elsif PC_INC_EXH = '1' then
            LOOP_SPLIT <= false;
        elsif OP /= DBcc and EXH_REQ = '1' and LOOP_BSY = '1' and FETCH_STATE = SLEEP and NEXT_FETCH_STATE = START_OP then
            LOOP_SPLIT <= true;
        end if;
    end process LOOP_CTRL;
    

    BF_OFFSET_I <= To_Integer(unsigned(BF_OFFSET));
    BF_WIDTH_I <= To_Integer(unsigned(BF_WIDTH));

    RESET_STRB <= '1' when OP = RESET and INIT_ENTRY = '1' else '0';

    EX_TRACE <= '0' when OP = ILLEGAL or OP = UNIMPLEMENTED else
                '1' when TRACE_MODE = "10" and OPD_ACK = '1' and FETCH_STATE = START_OP and OP = TRAP else
                '1' when TRACE_MODE = "10" and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP else
                '1' when TRACE_MODE = "01" and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and OP = TRAP else
                '1' when TRACE_MODE = "01" and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and OP = TRAPcc and ALU_COND = true else
                '1' when TRACE_MODE = "01" and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and OP = TRAPV and VBIT = '1' else
                '1' when TRACE_MODE = "01" and SR_WR_I = '1' else -- Status register manipulations.
                '1' when TRACE_MODE = "01" and (PC_ADD_DISPL_I or PC_LOAD_I) = '1' else '0'; -- All branches and jumps.

    P_STATUSn: process
    -- This logic is registered to enhance the system performance concerning fmax.
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP and NEXT_FETCH_STATE /= START_OP then
            STATUSn <= '0';
        else
            STATUSn <= '1';
        end if;
    end process P_STATUSn;

    ADDRESS_OFFSET: process
    variable ADR_OFFS_VAR: std_logic_vector(5 downto 0) := "000000";
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP then
            ADR_OFFS_VAR := "000000";
        else
            case OP is
                when BFCHG | BFCLR | BFINS | BFSET =>
                    if FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and BF_BYTES = 5 then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100"; -- Another Byte required.
                    elsif INIT_ENTRY = '1' then
                        ADR_OFFS_VAR := "000000"; -- Restore.
                    elsif FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and BF_BYTES = 5 then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100"; -- Another Byte required.
                    end if;
                when BFEXTS | BFEXTU | BFFFO | BFTST =>
                    if FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and BF_BYTES = 5 then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100"; -- Another Byte required.
                    end if;
                when CHK2 | CMP2 =>
                    if FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and OP_SIZE_I = LONG then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100";
                    elsif FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' and OP_SIZE_I = WORD then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "10";
                    elsif FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + '1';
                    end if;
                when MOVEM =>
                    if ADR_MODE_I = "011" or ADR_MODE_I = "100" then -- (An)+, -(An).
                        null; -- Offset comes from addressing register.
                    elsif BIW_0(10) = '1' and MOVEM_FIRST_RD = false then
                        null; -- Do not increment before the first bus access.
                    elsif MOVEM_COND = true and FETCH_STATE = INIT_EXEC_WB and ALU_BSY_M = '0' and OP_SIZE_I = LONG then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100"; -- Register to memory.
                    elsif MOVEM_COND = true and FETCH_STATE = INIT_EXEC_WB and ALU_BSY_M = '0' then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "10"; -- Register to memory.
                    end if;
                when MOVEP =>
                    if FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "10";
                    end if;
                when PMOVE => -- [PMMU1] CRP/SRP: the lower long is at EA+4.
                    if PM_QUAD = '1' and PHASE2 = false and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100";
                    elsif PM_QUAD = '1' and MV_RW = '1' and PHASE2 = false and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' then
                        ADR_OFFS_VAR := ADR_OFFS_VAR + "100";
                    end if;
                when others => null;
            end case;
        end if;
        ADR_OFFSET <= ADR_OFFS_VAR;
    end process ADDRESS_OFFSET;

    BITFIELD_CONTROL: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE = START_OP then
            case OP is
                when BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST =>
                    -- F24/H31: latch the span ONCE, here, and restore from the
                    -- latch rather than recomputing. The operands cannot change
                    -- during the instruction, so the recomputation was never
                    -- adding information -- but it did add a LIVE dependency on
                    -- BF_WIDTH at FETCH_OPERAND, and for BFINS that instant is
                    -- exactly when read port 2 is carrying the insertion pattern
                    -- rather than the width register. Measured: V20m recomputed
                    -- BF_BYTES_I(0, $FF mod 32 = 31) = 4 instead of 1 and stored
                    -- through the wrong span. Latching removes the dependency.
                    if NEXT_FETCH_STATE = INIT_EXEC_WB then
                        BF_BYTES <= 4; -- Register access.
                        BF_BYTES_FULL <= 4;
                    else
                        BF_BYTES <= BF_BYTES_I(BF_OFFSET_I, BF_WIDTH_I);
                        BF_BYTES_FULL <= BF_BYTES_I(BF_OFFSET_I, BF_WIDTH_I);
                    end if;
                    BF_HILOn <= '1';
                when others => null;
            end case;
        elsif FETCH_STATE = FETCH_OPERAND then
            if RD_RDY = '1' and BF_BYTES = 5 then
                BF_BYTES <= 1;
                BF_HILOn <= '0';
            elsif RD_RDY = '1' then
                BF_BYTES <= BF_BYTES_FULL; -- F24/H31: restore from the latch.
                BF_HILOn <= '1'; -- Restore.
            end if;
        elsif EXEC_WB_STATE = WRITE_DEST then
            if WR_RDY = '1' and BF_BYTES = 5 then
                BF_BYTES <= 1;
                BF_HILOn <= '0';
            elsif WR_RDY = '1' then
                BF_HILOn <= '1'; -- Restore.
            end if;
        end if;
    end process BITFIELD_CONTROL;

    MOVEM_CONTROL: process(ADR_MODE_I, CLK, BIW_0, BIW_1, OP, RESET_CPU, FETCH_STATE, NEXT_FETCH_STATE, ALU_BSY, ALU_BSY_M, MOVEM_PNTR)
    variable INDEX      : integer range 0 to 15 := 0;
    variable MOVEM_PVAR : std_logic_vector(3 downto 0) := x"0";
    variable MOVEM_NXT  : std_logic_vector(3 downto 0); -- [F1] Next set register-list bit above MOVEM_PVAR (x"F" if none).
    variable MOVEM_1ST  : std_logic_vector(3 downto 0); -- [F1] Lowest set register-list bit (x"0" if the list is empty).
    variable PIDX       : integer range 0 to 15;
    begin
        if CLK = '1' and CLK' event then
            -- [F1] Like the real 68030 (8+4n clocks, independent of the mask), MOVEM does not spend clocks on
            -- registers that are not in the list: MOVEM_PVAR starts at the first set bit and jumps to the next
            -- set bit (priority encoder) instead of stepping through all 16 positions. The scan order (and the
            -- -(An) reversal via MOVEM_PNTR = not MOVEM_PVAR) is unchanged.
            PIDX := To_Integer(unsigned(MOVEM_PVAR));
            MOVEM_NXT := x"F";
            MOVEM_1ST := x"0";
            for i in 15 downto 0 loop
                if i > PIDX and BIW_1(i) = '1' then
                    MOVEM_NXT := std_logic_vector(to_unsigned(i, 4));
                end if;
                if BIW_1(i) = '1' then
                    MOVEM_1ST := std_logic_vector(to_unsigned(i, 4));
                end if;
            end loop;

            if FETCH_STATE = START_OP and OP = MOVEM and NEXT_FETCH_STATE /= START_OP then
                MOVEM_PVAR := MOVEM_1ST; -- [F1] Start at the first register in the list.
            elsif FETCH_STATE = START_OP then
                MOVEM_PVAR := x"0";
            elsif FETCH_STATE = INIT_EXEC_WB and MOVEM_COND = false and MOVEM_PVAR < x"F" and ALU_BSY_M = '0' then
                MOVEM_PVAR := MOVEM_NXT; -- No data to write.
            elsif BIW_0(10) = '1' and MOVEM_FIRST_RD = true and FETCH_STATE = INIT_EXEC_WB and MOVEM_PVAR < x"F" and ALU_BSY_M = '0' then
                MOVEM_PVAR := MOVEM_NXT; -- Data has not been read.
            elsif BIW_0(10) = '0' and FETCH_STATE = INIT_EXEC_WB and MOVEM_PVAR < x"F" and ALU_BSY_M = '0' then
                MOVEM_PVAR := MOVEM_NXT; -- Data has been written.
            end if;

            if OP = MOVEM and ALU_INIT_I = '1' and ADR_MODE_I = "011" and MOVEM_ADn_I = '1' and MOVEM_PNTR(2 downto 0) = BIW_0(2 downto 0) then
                MOVEM_INH_WR <= true; -- Do not write the addressing register.
            elsif ALU_INIT_I = '1' then 
                MOVEM_INH_WR <= false;
            end if;
        
            if FETCH_STATE = START_OP then
                MOVEM_FIRST_RD <= false;
            elsif OP = MOVEM and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
                MOVEM_FIRST_RD <= true;
            end if;
            
            -- During the MOVEM instruction in memory to register operation and addressing modes "010", "101","110" the effective address might be
            -- affected, if the addressing register is active in the register list mask. To deal with it, the effective address is stored until the
            -- MOVEM has read all registers from memory addressed by the initial addressing register (old value).
            -- This logic is modeled synchronously (one clock latency) due to the one clock delay of the address calculation.
            if OP /= MOVEM or BIW_0(10) /= '1' or (ADR_MODE_I /= "010" and ADR_MODE_I /= "101" and ADR_MODE_I /= "110") then
                STORE_AEFF <= '0'; 
            elsif BUSY_EXH = '1' then
                STORE_AEFF <= '0'; -- [F127] A bus error aborts the MOVEM: the exception stacks with the normal address calculation.
            elsif FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP then
                STORE_AEFF <= '0'; -- Operation completed.
            elsif FETCH_STATE = SWITCH_STATE or FETCH_STATE = CALC_AEFF or FETCH_STATE = FETCH_OPERAND or FETCH_STATE = INIT_EXEC_WB then
                STORE_AEFF <= '1';
            end if;
        end if;

        -- This signal determines whether to handle address or data registers.
        if ADR_MODE_I = "100" then -- -(An).
            MOVEM_ADn_I <= not To_Bit(MOVEM_PVAR(3));
            MOVEM_ADn <= not To_Bit(MOVEM_PVAR(3));
        else
            MOVEM_ADn_I <= To_Bit(MOVEM_PVAR(3));
            MOVEM_ADn <= To_Bit(MOVEM_PVAR(3));
        end if;

        INDEX := To_Integer(unsigned(MOVEM_PVAR));

        -- [F1] True when no register-list bit is set above the current position: the current register is the last one.
        MOVEM_END <= true;
        for i in 0 to 15 loop
            if i > INDEX and BIW_1(i) = '1' then
                MOVEM_END <= false;
            end if;
        end loop;

        -- The following signal determines if a register is affected or not, depending
        -- on the status of the register list bit. 
        if OP = MOVEM and BIW_1(INDEX) = '1' then
            MOVEM_COND <= true;
        else
            MOVEM_COND <= false;
        end if;

        -- This signal determines whether to handle address or data registers.
        if ADR_MODE_I = "100" then -- -(An).
            MOVEM_PNTR <= not MOVEM_PVAR; -- Count down.
        else
            MOVEM_PNTR <= MOVEM_PVAR;
        end if;
    end process MOVEM_CONTROL;

    MOVEP_CONTROL: process(CLK, MOVEP_PNTR_I)
    -- This logic handles the bytes to be written or read during the MOVEP
    -- operation. In LONG mode 4 bytes are affected and in WORD mode two bytes.
    begin
        if CLK = '1' and CLK' event then
          if RESET_CPU = '1' or (FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP) then
                MOVEP_PNTR_I <= 0;
            elsif FETCH_STATE = START_OP and (BIW_0(8 downto 6) = "101" or BIW_0(8 downto 6) = "111") then
                MOVEP_PNTR_I <= 3; -- LONG.
            elsif FETCH_STATE = START_OP then
                MOVEP_PNTR_I <= 1; -- WORD.
            elsif FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and MOVEP_PNTR_I /= 0 then
                MOVEP_PNTR_I <= MOVEP_PNTR_I - 1; -- Register to memory
            end if;
        end if;
        MOVEP_PNTR <= MOVEP_PNTR_I;
    end process MOVEP_CONTROL;

    PHASE2_CONTROL: process
    -- This is used for some operations which require
    -- two control sequences.
    begin
        wait until CLK = '1' and CLK' event;
        if NEXT_FETCH_STATE = START_OP then
            PHASE2 <= false;
        elsif (OP = ABCD or OP = SBCD) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
            PHASE2 <= true; -- One clock cycle delay for destination address calculation.
        elsif (OP = ADDX or OP = SUBX) and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
            PHASE2 <= true; -- One clock cycle delay for destination address calculation.
        elsif OP = CAS2 and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' and PHASE2 = false then
            PHASE2 <= true; -- Used as a control flow switch.
        elsif OP = CAS2 and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' then
            PHASE2 <= false; -- Prepare for writeback / write destination.
        elsif OP_WB_I = CAS2 and EXEC_WB_STATE = WRITEBACK then
            PHASE2 <= true; -- Used as a control flow switch.
        elsif OP_WB_I = CAS2 and EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' then
            PHASE2 <= true; -- Used as a control flow switch.
        elsif (OP = CHK2 or OP = CMP2 or OP = CMPM) and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' then
            PHASE2 <= true; -- Used as a control flow switch.
        elsif PM_QUAD = '1' and FETCH_STATE = FETCH_OPERAND and RD_RDY = '1' then
            PHASE2 <= true; -- [PMMU1] Upper long read, the lower one follows.
        elsif PM_QUAD = '1' and MV_RW = '1' and FETCH_STATE = INIT_EXEC_WB and ALU_BSY = '0' then
            PHASE2 <= true; -- [PMMU1] Upper long loaded for writing, the lower one follows.
        elsif OP = JSR and FETCH_STATE = SLEEP then
            PHASE2 <= true; -- One clock cycle delay for address calculation.
        elsif OP = PEA and FETCH_STATE = SWITCH_STATE then
            PHASE2 <= true; -- One clock cycle delay for address calculation.
        elsif OP = RTR and FETCH_STATE = INIT_EXEC_WB and NEXT_FETCH_STATE = CALC_AEFF then
            PHASE2 <= true; -- Used as a control flow switch.
        elsif OP = MOVE and FETCH_STATE = INIT_EXEC_WB and ALU_BSY_MV = '0' and BIW_0(8 downto 6) > "100" then -- [F166] _MV
            PHASE2 <= true; -- Indicate destination address calculation is in progress.
        end if;
    end process PHASE2_CONTROL;

    -- [FLT1] Data write fault: the bus interface ends the write with DATA_RDY and DATA_VALID = '0'.
    AR_INC <= AR_INC_S;
    AR_DEC <= AR_DEC_S;
    SP_ADD_DISPL <= SP_ADD_DISPL_S;
    WR_FLT <= '1' when WR_RDY = '1' and DATA_VALID = '0' else '0';

    -- [F126] MOVEM regs,-(An): An is decremented per register; a write bus error restarts the whole instruction
    -- after RTE, so An must get back its value from before the instruction (user mode, see address registers).
    -- [F127] also MOVEM (An)+,regs: snapshot at the first increment/decrement of the instruction.
    MV_SAVE <= MV_SAVE_I;
    MV_SAVE_I <= '1' when OP = MOVEM and (ADR_MODE_I = "100" or ADR_MODE_I = "011") and (AR_DEC_S = '1' or AR_INC_S = '1') and MV_ACT = '0' else
                 -- [F131] any other instruction: snapshot its first fetch-side An change, so that a write fault of the
                 -- previous instruction (taken while this one is already in its address calculation) can undo it.
                 '1' when OP /= MOVEM and (AR_DEC_S = '1' or AR_INC_S = '1') and FI_DIRTY = false and MV_ACT = '0' else '0';
    MV_RESTORE <= MV_RESTORE_I;
    P_MVFLT: process
    begin
        wait until CLK = '1' and CLK' event;
        MV_RESTORE_I <= '0';
        if RESET_CPU = '1' then
            MV_ACT <= '0'; MV_FLT <= '0';
        elsif MV_FLT = '1' and BUSY_EXH = '1' then
            MV_RESTORE_I <= '1'; MV_FLT <= '0'; MV_ACT <= '0';
        elsif MV_ACT = '1' and OP = MOVEM and (WR_FLT = '1' or (RD_RDY = '1' and DATA_VALID = '0')) then
            MV_FLT <= '1';
        elsif MV_ACT = '1' and OP /= MOVEM and WR_FLT = '1' and FI_REST then
            MV_FLT <= '1'; -- [F131]
        elsif MV_SAVE_I = '1' then
            MV_ACT <= '1'; MV_FLT <= '0';
        elsif MV_FLT = '0' and FETCH_STATE /= START_OP and NEXT_FETCH_STATE = START_OP then
            MV_ACT <= '0';
        end if;
    end process P_MVFLT;

    P_WFLT: process
    begin
        wait until CLK = '1' and CLK' event;
        if RESET_CPU = '1' or BUSY_EXH = '1' then
            WFLT <= '0';
        elsif WR_FLT = '1' then
            WFLT <= '1';
        end if;
    end process P_WFLT;

    -- [FLT2] MC68030UM 8.1.2 and table 8-6: the short bus fault frame (format $A, PC = next instruction) is used
    -- when the exception is taken with the execution unit at an instruction boundary; data read faults and faults
    -- inside an instruction use the long frame ($B). Here: a data write fault on its instruction's last bus cycle,
    -- while the fetch side has not yet changed any register for the following instruction (it is aborted by FLT1
    -- and runs again after RTE). Read-modify-write (CAS, CAS2, TAS) and multi-cycle bit field writes stay long.
    WR_LAST <= false when OP_WB_I = CAS or OP_WB_I = CAS2 or OP_WB_I = TAS else
               false when (OP_WB_I = BFCHG or OP_WB_I = BFCLR or OP_WB_I = BFINS or OP_WB_I = BFSET) and BF_BYTES = 5 else
               false when OP_WB_I = MOVEM and OP = MOVEM and FETCH_STATE /= START_OP and FETCH_STATE /= SLEEP else
               false when OP_WB_I = MOVEP and OP = MOVEP and FETCH_STATE /= START_OP else
               false when OP_WB_I = PMOVE and PM_QUAD = '1' and PHASE2 = false and FETCH_STATE /= START_OP else -- [PMMU1]
               true;

    P_FI_DIRTY: process
    begin
        wait until CLK = '1' and CLK' event;
        if AR_INC_S = '1' or AR_DEC_S = '1' or SP_ADD_DISPL_S = '1' then
            FI_DIRTY <= true;
            if FI_DIRTY = true or SP_ADD_DISPL_S = '1' or (AR_INC_S = '1' and AR_DEC_S = '1') then
                FI_MULTI <= true; -- [F131]
            end if;
        elsif FETCH_STATE = START_OP then
            FI_DIRTY <= false;
            FI_MULTI <= false;
        end if;
    end process P_FI_DIRTY;

    -- [F131] PC_I points to the last issued instruction (BIW_0). A write fault taken as format $A must stack the
    -- address of the NEXT instruction. When the fetch side is idle (START_OP/SLEEP) and has not issued the next
    -- opword (e.g. pipe still refilling after an RTE), PC_I is still the faulted instruction: the exception handler
    -- must advance it (as for interrupts). Otherwise RTE reruns the write and then executes the instruction again
    -- (user move.l a3,-(sp) after an IRQ: USP decremented twice, glibc fork() stack-protector abort on the board).
    P_ISS_SEEN: process
    begin
        wait until CLK = '1' and CLK' event;
        if FETCH_STATE /= START_OP and FETCH_STATE /= SLEEP then
            ISS_SEEN <= false;
        elsif OPD_ACK = '1' then
            ISS_SEEN <= true;
        end if;
    end process P_ISS_SEEN;
    BERR_PCSTALE <= '1' when (FETCH_STATE = START_OP or FETCH_STATE = SLEEP) and ISS_SEEN = false and
                             OPD_ACK = '0' else '0';

    -- [F131] The fetch side may already have changed one An for the next instruction (e.g. BSR after a faulting
    -- MOVE.L A3,-(SP)): in user mode that change is undone from the MV snapshot and the short frame is used, so RTE
    -- reruns the write and executes the next instruction from its start (was: long frame, next instruction ran again
    -- on top of its own predecrement -> SP 4 low).
    FI_REST <= MV_ACT = '1' and OP /= MOVEM and FI_DIRTY = true and FI_MULTI = false and SBIT_I = '0';

    BERR_IBOUND <= '1' when WR_FLT = '1' and EXEC_WB_STATE = WRITE_DEST and WR_LAST = true and (FI_DIRTY = false or FI_REST) and
                            AR_INC_S = '0' and AR_DEC_S = '0' and SP_ADD_DISPL_S = '0' else '0';

    STATE_REGs: process
    begin
        wait until CLK = '1' and CLK' event;
        if RESET_CPU = '1' then
            FETCH_STATE <= START_OP;
            EXEC_WB_STATE <= IDLE;
        elsif WR_FLT = '1' or WFLT = '1' then
            -- [FLT1] A data write fault ends the write-back and stops the fetch side at once: the next
            -- instruction (already decoded, maybe in its address calculation) does not run its operand
            -- cycles; the exception handler takes the fault right after the faulted cycle (MC68030UM 8.1.2).
            FETCH_STATE <= START_OP;
            EXEC_WB_STATE <= IDLE;
        elsif EW_ACK = '1' and OW_VALID = '0' then
            FETCH_STATE <= START_OP; -- Bus error.
            EXEC_WB_STATE <= IDLE;
        elsif OPD_ACK = '1' and OW_VALID = '0' then
            FETCH_STATE <= START_OP; -- Bus error.
            EXEC_WB_STATE <= IDLE;
        elsif RD_RDY = '1' and DATA_VALID = '0' and
              (FETCH_STATE = FETCH_OPERAND or FETCH_STATE = FETCH_MEMADR) then
            -- [F66] A faulted operand read ends the instruction here, so it never reaches
            -- INIT_EXEC_WB and its destination keeps the old value (MC68030). The branch
            -- below never fires: DATA_RD_I is forced to '0' while DATA_RDY = '1'. The
            -- write-back stage keeps running: it belongs to the previous instruction.
            FETCH_STATE <= START_OP;
        elsif DATA_RD_I = '1' and RD_RDY = '1' and DATA_VALID = '0' then
            FETCH_STATE <= START_OP; -- Bus error.
            EXEC_WB_STATE <= IDLE;
        elsif DATA_WR_I = '1' and RD_RDY = '1' and DATA_VALID = '0' then
            FETCH_STATE <= START_OP; -- Bus error.
            EXEC_WB_STATE <= IDLE;
        else
            FETCH_STATE <= NEXT_FETCH_STATE;
            EXEC_WB_STATE <= NEXT_EXEC_WB_STATE;
        end if;
    end process STATE_REGs;

    -- Debugging:
    -- Use this signal to detect instructions in use in the writeback path (OP_WB_I) or in the fetch path (OP).
    -- for these instructions you can halt the pipeline in the START_OP state to detect any problems.
    -- with OP select
    -- with OP_WB_I select
    --     OP_TEST <= '1' when ADDA | ADDQ | EXG | LEA | LINK | MOVEA | MOVE_USP | MOVEC | MOVEM | MOVES | SUBA | SUBQ | UNLK | -- Address register manipulations.
    --                         ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR | DIVS | DIVU | -- Long ALU operations. (68K10, 68K30L have no barrel shifter).
    --                         ADD | AND_B | CLR | EOR | SUB | OR_B | CMP | CMPA | CMPM | NOT_B | NBCD | NEG | NEGX | SWAP | TAS | TST
    --                         ANDI_TO_CCR | ANDI_TO_SR | EORI_TO_CCR | EORI_TO_SR | ORI_TO_CCR | ORI_TO_SR | MOVE_FROM_CCR | 
    --                         MOVE_TO_CCR | MOVE_FROM_SR | MOVE_TO_SR | MOVE | MOVEQ | MOVEP | PEA | 
    --                         ABCD | ADDX | SBCD | SUBX | BCHG | BCLR | BSET | BTST | EXT | 
    --                         Bcc | BSR | CHK | DBcc | JSR | TRAPV | RTR | Scc | STOP | 
    --                         ADDI | ANDI | SUBI | CMPI | EORI | ORI | MULS | MULU, '0' when others;

    FETCH_DEC: process(ADR_MODE_I, ALU_BSY, BCC_EARLY, BCC_INIT, DBCC_EARLY, DBCC_XHOLD, RTS_EARLY, MEM_FAST, ALU_BSY_M, ALU_COND, AR_IN_USE, CMPA_DLY, BF_BYTES, BIW_0, BIW_1, BRANCH_ATN, DR_IN_USE, EW_ACK, EW_RDY, EXEC_WB_STATE, F157_ALU_FREE, F157_OLAP, F157_WR_EXEC, 
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
                elsif BCC_EARLY = '1' or DBCC_EARLY = '1' then
                    NEXT_FETCH_STATE <= START_OP; -- [F160] Taken Bcc.B flushed in this clock. [F161] Taken DBcc.
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
                                    -- [F157o] Same-edge INIT during F157_WR_EXEC is safe for ALU operands:
                                    -- data_registers forwards DR_IN onto DR_FWD_1/2 (ALU ports only).
                                    -- Address and AU/index paths stay unforwarded (plain DR_OUT/DR_IDX_OUT).
                                    if DR_IN_USE = '0' or F157_WR_EXEC = '1' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "001" => -- An.
                                    if (OP = ADD or OP = SUB or OP = AND_B or OP = EOR or OP = OR_B or OP = CMP) and (AR_IN_USE = '1' or DR_IN_USE = '1')then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif AR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "010" | "011" => -- (An), (An)+.
                                    if AR_IN_USE = '1' then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    else
                                        NEXT_FETCH_STATE <= FETCH_OPERAND;
                                    end if;
                                when "100" => -- -(An).
                                    if AR_IN_USE = '1' then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    else
                                        NEXT_FETCH_STATE <= CALC_AEFF;
                                    end if;
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when others => -- "111" 
                                    if BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    elsif BIW_0(2 downto 0) = "001" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    elsif BIW_0(2 downto 0) = "100" and OP_SIZE_I = LONG then
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B2;
                                    elsif BIW_0(2 downto 0) = "100" then -- Word or byte.
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                                    elsif BIW_0(2 downto 0) = "010" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    end if;
                            end case;
                        when ADDA | BCHG | BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST | CHK | CHK2 | CMP2 | CMPA | 
                             DIVS | DIVU | MULS | MULU | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | SUBA =>
                             case BIW_0(5 downto 3) is
                                when "000" => -- Source is Dn.
                                    if OP = CMPA and CMPA_DLY = '0' then -- [F142] CMPA Rn,An: 4 clocks (MC68030UM 11.6.7).
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif (OP = ADDA or OP = SUBA or OP = CMPA or OP = MOVEA) and (AR_IN_USE = '1' or DR_IN_USE = '1') then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif DR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "001" => -- Valid for ADDA, CMPA, MOVEA, SUBA; source is An.
                                    if OP = CMPA and CMPA_DLY = '0' then -- [F142]
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif AR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB; -- ADH.
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "010" | "011" => -- (An), (An)+.
                                    if AR_IN_USE = '1' then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH!
                                    else
                                        NEXT_FETCH_STATE <= FETCH_OPERAND;
                                    end if;
                                when "100" => -- -(An).
                                    if AR_IN_USE = '1' then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH!
                                    else
                                        NEXT_FETCH_STATE <= CALC_AEFF;
                                    end if;
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when others => -- "111"
                                    if BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    elsif BIW_0(2 downto 0) = "001" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    elsif BIW_0(2 downto 0) = "100" and OP_SIZE_I = LONG then
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B2;
                                    elsif BIW_0(2 downto 0) = "100" then -- Word or Byte.
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                                    elsif BIW_0(2 downto 0) = "010" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    end if;
                            end case;
                        when EXG =>
                            if BIW_0(7 downto 3) = "10001" and (DR_IN_USE = '1' or AR_IN_USE = '1') then
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            elsif BIW_0(7 downto 3) = "01000" and DR_IN_USE = '1' then
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            elsif BIW_0(7 downto 3) = "01001" and AR_IN_USE = '1' then
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when MOVE_FROM_CCR | MOVE_FROM_SR =>
                            if ALU_BSY = '0' then
                                case BIW_0(5 downto 3) is
                                    when "000" => -- Destination is Dn.
                                        if DR_IN_USE = '0' then
                                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                        else
                                            NEXT_FETCH_STATE <= START_OP;
                                        end if;
                                    when "010" | "011" | "100" => -- (An), (An)+, -(An).
                                        if AR_IN_USE = '0' then
                                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                        else
                                            NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                        end if;
                                    when "101" => 
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    when "110" =>
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    when others => -- "111" 
                                        if BIW_0(2 downto 0) = "000" then
                                            NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                        else
                                            NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                        end if;
                                end case;
                            else
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                            if BIW_0(7 downto 6) /= "11" then -- Register shifts.
                                if DR_IN_USE = '0' then
                                    NEXT_FETCH_STATE <= INIT_EXEC_WB; -- ADH.
                                else
                                    NEXT_FETCH_STATE <= START_OP;
                                end if;
                            else -- Memory shifts.
                                case BIW_0(5 downto 3) is
                                    when "010" | "011" => -- (An), (An)+.
                                        if AR_IN_USE = '0' then -- ADH.
                                            NEXT_FETCH_STATE <= FETCH_OPERAND;
                                        else
                                            NEXT_FETCH_STATE <= START_OP;
                                        end if;
                                    when "100" => -- -(An).
                                        if AR_IN_USE = '0' then -- ADH.
                                            NEXT_FETCH_STATE <= CALC_AEFF;
                                        else
                                            NEXT_FETCH_STATE <= START_OP;
                                        end if;
                                    when "101" => 
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    when "110" =>
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    when others => -- "111". 
                                        if BIW_0(2 downto 0) = "000" then
                                            NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                        else
                                            NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                        end if;
                                end case;
                            end if;
                        when BKPT =>
                            -- Wait until the bus controller is free to avoid a structural
                            -- hazard due to the top level function code multiplexer which
                            -- switches on the CPU_SPACE selector.
                            if ALU_BSY = '0' then
                                NEXT_FETCH_STATE <= FETCH_OPERAND;
                            else
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when CAS2 | CMPM | RTD | RTR | RTS =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= FETCH_OPERAND;
                            else
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when CLR | JMP | JSR | LEA | PEA | Scc => -- No read access required.
                            case BIW_0(5 downto 3) is
                                when "000" => -- CLR, Scc.
                                    -- [F157c] CLR does not read Dn (overwrite-only). Scc still waits.
                                    -- No F157_WR_EXEC bypass (same-edge RAW, see START_OP Dn arm).
                                    if OP = CLR or DR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "001" | "010" | "011" | "100" =>
                                    if AR_IN_USE = '1' then
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    elsif OP = LEA or OP = PEA then
                                        NEXT_FETCH_STATE <= SWITCH_STATE;
                                    else
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    end if;
                                when others => -- "101", "110", "111"
                                    -- [F62d] JSR decrements A7 when it leaves START_OP (AR_DEC), for every
                                    -- addressing mode, and AR_SEL_RD_1 is A7 here. Wait until a pending A7
                                    -- writeback of the previous instruction is done, as BSR does. With the
                                    -- prefetch queue "ADDA.W #16,SP; JSR (d16,PC)" (TOS 2.06 AES Pexec wrapper
                                    -- at E21C0C) got here while the ADDA result was written back in the same
                                    -- clock: the write won, the decrement was lost, SP ended 4 too high and the
                                    -- wrapper's RTS took the filename pointer as return address.
                                    if OP = JSR and AR_IN_USE = '1' then
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    elsif BIW_0(5 downto 3) = "101" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    elsif BIW_0(5 downto 3) = "110" then
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    elsif BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    elsif BIW_0(2 downto 0) = "001" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    elsif BIW_0(2 downto 0) = "010" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    end if;
                            end case;
                        when LINK | UNLK =>
                            -- We have to wait for the ALU because the registers are written without pipelining
                            -- through the ALU and the stack is decremented early. 
                            if ALU_BSY = '1' then
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH, ASH (two address registers are affected).
                            else
                                NEXT_FETCH_STATE <= SWITCH_STATE; -- Stack pointer is decremented in this state.
                            end if;
                        when MOVE =>
                            case BIW_0(5 downto 3) is -- Source operand.
                                when "000" => -- Dn.
                                    -- Destination is -(An) and will be decremented here, wait.
                                    if BIW_0(8 downto 6) = "100" and (AR_IN_USE = '1' or DR_IN_USE = '1') then
                                        NEXT_FETCH_STATE <= START_OP;
                                    elsif DR_IN_USE = '1' then
                                        NEXT_FETCH_STATE <= START_OP;
                                    else
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    end if;
                                when "001" => -- An.
                                    if AR_IN_USE = '1' then
                                        NEXT_FETCH_STATE <= START_OP;
                                    else
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    end if;
                                when "010" | "011" => -- (An), (An)+.
                                    if AR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= FETCH_OPERAND;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "100" => -- -(An).
                                    if AR_IN_USE = '0' then
                                        NEXT_FETCH_STATE <= CALC_AEFF;
                                    else
                                        NEXT_FETCH_STATE <= START_OP;
                                    end if;
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when others =>
                                    if BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    elsif BIW_0(2 downto 0) = "001" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    elsif BIW_0(2 downto 0) = "100" and BIW_0(13 downto 12) = "10" then -- Long.
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B2;
                                    elsif BIW_0(2 downto 0) = "100" then -- Word or Byte.
                                        NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                                    elsif BIW_0(2 downto 0) = "010" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    end if;
                            end case;
                        when MOVEM =>
                            case BIW_0(5 downto 3) is
                                when "010" | "011" | "100" => -- (An), (An)+, -(An).
                                    if AR_IN_USE = '1' then -- ADH.
                                        NEXT_FETCH_STATE <= START_OP;
                                    else
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                    end if;
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when others => 
                                    if BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    elsif BIW_0(2 downto 0) = "001" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    elsif BIW_0(2 downto 0) = "010" then
                                        NEXT_FETCH_STATE <= FETCH_DISPL;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                    end if;
                            end case;
                        when MOVEP =>
                            if AR_IN_USE = '0' and BIW_0(7 downto 6) < "10" then
                                NEXT_FETCH_STATE <= SWITCH_STATE; -- Memory to register.
                            elsif AR_IN_USE = '0' and DR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= SWITCH_STATE; -- Register to memory.
                            else
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when BSR | MOVE_USP =>
                            -- MOVE_USP: wait until A7 has been updated to load the correct data to the ALU.
                            -- BSR: wait until A7 has been updated before decrementing.
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            else
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when MOVEC =>
                            if BIW_0(0) = '1' and BIW_1(15) = '1' and AR_IN_USE = '1' then -- Address register is source.
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            elsif BIW_0(0) = '1' and BIW_1(15) = '0' and DR_IN_USE = '1' then -- Data register is source.
                                NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when MOVES | PMOVE =>
                            case BIW_0(5 downto 3) is
                                when "010" | "011" => -- (An), (An)+.
                                    if MV_RW = '0' and AR_IN_USE = '0' then -- ADH.
                                        NEXT_FETCH_STATE <= FETCH_OPERAND; -- Memory to register.
                                    elsif MV_RW = '1' and AR_IN_USE = '0' then -- ADH.
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to memory.
                                    else
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    end if;
                                when "100" => -- -(An).
                                    if MV_RW = '0' and AR_IN_USE = '0' then -- ADH.
                                        NEXT_FETCH_STATE <= CALC_AEFF; -- Memory to register.
                                    elsif MV_RW = '1' and AR_IN_USE = '0' then -- ADH.
                                        NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to memory.
                                    else
                                        NEXT_FETCH_STATE <= START_OP; -- Wait, ADH.
                                    end if;
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when others => -- "111"
                                    if BIW_0(2 downto 0) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    end if;
                            end case;
                            -- Register to memory:
                            if MV_RW = '1' and MV_AN = '1' and AR_IN_USE = '1' then -- ADH.
                                NEXT_FETCH_STATE <= START_OP;
                            elsif MV_RW = '1' and MV_AN = '0' and DR_IN_USE = '1' then -- ADH.
                                NEXT_FETCH_STATE <= START_OP;
                            end if;
                        when ANDI_TO_CCR | ANDI_TO_SR | EORI_TO_CCR | EORI_TO_SR | ORI_TO_CCR | ORI_TO_SR | RESET =>
                            -- Wait until the status register / condition codes have been updated. Otherwise we 
                            -- possibly have a data hazard using the wrong condition codes for the operation.
                            -- Be aware: for the ANDI_TO_SR, EORI_TO_SR, MOVE_TO_SR and ORI_TOI_SR operations
                            -- the pipe flush results in automatically aligned condition codes. Nevertheless
                            -- we need this logic for the respective operations, if the pipe is not flushed,
                            -- in the case of non changing RAM space.
                            -- For the RESET: we should not reset in running writeback cycles.
                            if ALU_BSY = '1' then
                                NEXT_FETCH_STATE <= START_OP;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when others => -- Bcc, BRA, NOP, STOP, TRAPV.
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                    end case;
                end if;
            when FETCH_DISPL =>
                case OP is
                    when ADD | CMP | SUB | AND_B | EOR | OR_B =>
                        if (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;
                    when ADDA | BCHG | BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST | CHK | CHK2 | CMP2 | CMPA | DIVS | DIVU | MULS | MULU | MOVE | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | SUBA =>
                        if (EW_ACK = '1' or EW_RDY = '1') and OP = MOVE and PHASE2 = true and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        elsif (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;
                    when ADDI | ADDQ | ANDI | CAS | CMPI | EORI | NBCD | NEG | NEGX | NOT_B | ORI | SUBI | SUBQ | TST | TAS | ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                        if (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;
                    when MOVES | PMOVE =>
                        if (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' and MV_RW = '0' then
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        elsif (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;                    
                    when LEA | PEA =>
                        if (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;
                    when others => -- CLR, JMP, JSR, MOVE_FROM_CCR, MOVE_FROM_SR, MOVEM, Scc.
                        if (EW_ACK = '1' or EW_RDY = '1') and AR_IN_USE = '0' then -- ADH.
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        else
                            NEXT_FETCH_STATE <= FETCH_DISPL;
                        end if;
                end case;
            when FETCH_EXWORD_1 =>
                -- [F121] The index type (Dn/An) of the EA extension word is EXT_WORD(15), not BIW_1(15): for ORI/ANDI/EORI/ADDI/SUBI/CMPI
                -- BIW_1 is the immediate, for MULx.L/DIVx.L/BTST #/bitfield/CHK2/CAS it is the register word, for MOVE phase 2 it is the
                -- source extension. An immediate with bit 15 set skipped the DR_IN_USE wait, so (d8,An,Dn) used Dn before a MULS write-back
                -- (XaAES andi.w #-129,(8,a4,d0.l) after muls.w #24,d0: read at the stale index, write at the right one).
                -- Be aware that the An registers which will be addressed by EXWORD_1 and are used for several addressing modes
                -- are valid right after this state (because every address register manipulation requires no more than two clock cycles).
                if EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(5 downto 4) = "11" then -- 32 bit displacement.
                    NEXT_FETCH_STATE <= FETCH_D_HI;
                elsif EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(5 downto 4) = "10" then -- 16 bit displacement.
                    NEXT_FETCH_STATE <= FETCH_D_LO;
                elsif EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(5 downto 4) = "00" then -- Reserved.
                    NEXT_FETCH_STATE <= START_OP;
                elsif EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(1 downto 0) = "11" then
                    NEXT_FETCH_STATE <= FETCH_OD_HI; -- Long outer displacement.
                elsif EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(1 downto 0) = "10" then
                    NEXT_FETCH_STATE <= FETCH_OD_LO; -- Word outer displacement.
                elsif EW_ACK = '1' and EXT_WORD(8) = '1' and EXT_WORD(1 downto 0) = "01" then
                    NEXT_FETCH_STATE <= FETCH_MEMADR; -- Null outer displacement, go to intermediate address.
                elsif EW_ACK = '1' or EW_RDY = '1' then -- Null displacement, no outer displacement.
                    case OP is
                        when ADD | CMP | SUB | AND_B | EOR | OR_B =>
                            if (EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (EXT_WORD(15) = '1' and AR_IN_USE = '0') then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
                        when ADDA | BCHG | BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST | CHK | CHK2 | CMP2 | CMPA | DIVS | DIVU | MULS | MULU | MOVE | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | SUBA =>
                            if OP = MOVE and PHASE2 = true and EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            elsif OP = MOVE and PHASE2 = true and EXT_WORD(15) = '1' and AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            elsif (EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (EXT_WORD(15) = '1' and AR_IN_USE = '0') then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
                        when MOVES | PMOVE =>
                            if (MV_AN = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (MV_AN = '1' and AR_IN_USE = '0') then -- ADH.
                                if MV_RW = '0' then
                                    NEXT_FETCH_STATE <= CALC_AEFF;
                                else
                                    NEXT_FETCH_STATE <= INIT_EXEC_WB;
                                end if;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
                        when ADDI | ADDQ | ANDI | CAS | CMPI | EORI | NBCD | NEG | NEGX | NOT_B | ORI | SUBI | SUBQ | TST | TAS | ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                            if (EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (EXT_WORD(15) = '1' and AR_IN_USE = '0') then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
						when LEA | PEA =>
                            if (EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (EXT_WORD(15) = '1' and AR_IN_USE = '0') then -- ADH.
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
                        when others => -- CLR, JMP, JSR, MOVE_FROM_CCR, MOVE_FROM_SR, MOVEM, Scc.
                            if (EXT_WORD(15) = '0' and AR_IN_USE = '0' and DR_IN_USE = '0') or (EXT_WORD(15) = '1' and AR_IN_USE = '0') then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            else
                                NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                            end if;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                end if;
            when FETCH_D_HI =>
                if EW_ACK = '1' then
                    NEXT_FETCH_STATE <= FETCH_D_LO;
                else
                    NEXT_FETCH_STATE <= FETCH_D_HI;
                end if;
            when FETCH_D_LO =>
                if EW_ACK = '1' and OD_REQ_32 = '1' then
                    NEXT_FETCH_STATE <= FETCH_OD_HI;
                elsif EW_ACK = '1' and OD_REQ_16 = '1' then
                    NEXT_FETCH_STATE <= FETCH_OD_LO;
                elsif EW_ACK = '1' and MEM_INDIRECT = '1' then -- Null displacement.
                    NEXT_FETCH_STATE <= FETCH_MEMADR;
                elsif EW_ACK = '1' or EW_RDY = '1' then
                    case OP is
                        when ADD | CMP | SUB | AND_B | EOR | OR_B =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <=  FETCH_D_LO;
                            end if;
                        when ADDA | BCHG | BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST | CHK | CHK2| CMP2 | CMPA | DIVS | DIVU | MULS | MULU | MOVE | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | SUBA =>
                            if OP = MOVE and PHASE2 = true and AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            elsif AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_D_LO;
                            end if;
                        when MOVES | PMOVE =>
                            if AR_IN_USE = '1' then -- ADH.
                                NEXT_FETCH_STATE <= FETCH_D_LO; -- Wait, ADH.
                            elsif MV_RW = '0' then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when ADDI | ADDQ | ANDI | CAS | CMPI | EORI | NBCD | NEG | NEGX | NOT_B | ORI | SUBI | SUBQ | TST | TAS | ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <=  FETCH_D_LO;
                            end if;
                        when LEA | PEA =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= FETCH_D_LO;
                            end if;
                        when others => -- CLR, JMP, JSR, MOVE_FROM_CCR, MOVE_FROM_SR, MOVEM, Scc.
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            else
                                NEXT_FETCH_STATE <= FETCH_D_LO;
                            end if;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_D_LO;
                end if;
            when FETCH_OD_HI =>
                if EW_ACK = '1' then
                    NEXT_FETCH_STATE <= FETCH_OD_LO;
                else
                    NEXT_FETCH_STATE <= FETCH_OD_HI;
                end if;
            when FETCH_OD_LO =>
                if EW_ACK = '1' then
                    NEXT_FETCH_STATE <= FETCH_MEMADR;
                else
                    NEXT_FETCH_STATE <= FETCH_OD_LO;
                end if;
            when FETCH_MEMADR =>
                if RD_RDY = '1' or MEMADR_RDY = '1' then
                    case OP is
                        when ADD | CMP | SUB | AND_B | EOR | OR_B =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                        when ADDA | BCHG | BCLR | BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST | BSET | BTST | CHK | CHK2| CMP2 | CMPA | DIVS | DIVU | MULS | MULU | MOVE | MOVEA | MOVE_TO_CCR | MOVE_TO_SR | SUBA =>
                            if OP = MOVE and PHASE2 = true and AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            elsif AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                        when MOVES | PMOVE =>
                            if AR_IN_USE = '1' then -- ADH.
                                NEXT_FETCH_STATE <= FETCH_MEMADR; -- Wait, ADH.
                            elsif MV_RW = '0' then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when ADDI | ADDQ | ANDI | CAS | CMPI | EORI | NBCD | NEG | NEGX | NOT_B | ORI | SUBI | SUBQ | TST | TAS | ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                        when LEA | PEA =>
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                        when CLR | JMP | JSR | MOVE_FROM_CCR | MOVE_FROM_SR | Scc =>
                            -- [C3] ADR_EFF is registered and still holds the pointer address (bd + An) here; the
                            -- final address (pointer + od) is valid one clock later. Going straight to INIT_EXEC_WB
                            -- made JMP/JSR jump to the pointer address and CLR/Scc/MOVE from SR write there.
                            -- One calculation clock in SWITCH_STATE, like LEA.
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                        when others => -- MOVEM.
                            if AR_IN_USE = '0' then -- ADH.
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            else
                                NEXT_FETCH_STATE <= FETCH_MEMADR;
                            end if;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_MEMADR;
                end if;
            when FETCH_ABS_HI =>
                if EW_ACK = '1' then
                    NEXT_FETCH_STATE <= FETCH_ABS_LO;
                else
                    NEXT_FETCH_STATE <= FETCH_ABS_HI;
                end if;
            when FETCH_ABS_LO =>
                if EW_ACK = '1' then
                    case OP is
                        when CLR | JMP | JSR | MOVE_FROM_CCR | MOVE_FROM_SR | MOVEM | Scc =>
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        when LEA | PEA =>
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        when MOVE =>
                            if PHASE2 = false then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when MOVES | PMOVE =>
                            if MV_RW = '0' then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when others =>
                            NEXT_FETCH_STATE <= CALC_AEFF;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_ABS_LO;
                end if;
            when FETCH_IDATA_B2 =>
                if EW_ACK = '1' then
                    NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                else
                    NEXT_FETCH_STATE <= FETCH_IDATA_B2;
                end if;
            when FETCH_IDATA_B1 =>
                if EW_ACK = '1' or EW_RDY = '1' then
                    case OP is -- ADH.
                        when ADD | SUB | AND_B | OR_B | BTST | DIVS | DIVU | MULS | MULU | CHK | MOVE =>
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        when ADDA | CMPA | SUBA | MOVEA =>
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        when others =>
                            if DR_IN_USE = '1' then -- ADH.
                                NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_IDATA_B1;
                end if;
            when CALC_AEFF =>
                NEXT_FETCH_STATE <= FETCH_OPERAND; -- One CLK calculation delay.
            when FETCH_OPERAND =>
                if RTS_EARLY then
                    NEXT_FETCH_STATE <= START_OP; -- [F161] PC_LOAD from DATA_TO_CORE and flush now.
                elsif MEM_FAST = '1' then
                    NEXT_FETCH_STATE <= START_OP; -- [F165] ALU loaded from DATA_TO_CORE now, next opword requested.
                elsif RD_RDY = '1' then
                    case OP is
                        when ABCD | ADDX | SBCD | SUBX =>
                            if PHASE2 = false then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when ADD | CMP | CHK | SUB | AND_B | EOR | OR_B | BCHG | BCLR | BSET | BTST | DIVS | DIVU | MULS | MULU =>
                            if DR_IN_USE = '1' then
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when ADDA | CMPA | SUBA =>
                            if BIW_0(11 downto 9) = BIW_0(2 downto 0) and ADR_MODE_I = "011" then
                                NEXT_FETCH_STATE <= SWITCH_STATE; -- Postincrement (Ax)+, AX; wait before loading the ALU.
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST =>
                            if BF_BYTES = 5 then -- Another Byte required.
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when MOVE =>
                            if BIW_0(8 downto 6) = "100" and ADR_MODE_I = "011" then -- (An)+,-(An).
                                NEXT_FETCH_STATE <= SWITCH_STATE;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when PMOVE => -- [PMMU1] CRP/SRP: read the lower long at EA+4.
                            if PM_QUAD = '1' and PHASE2 = false then
                                NEXT_FETCH_STATE <= CALC_AEFF;
                            else
                                NEXT_FETCH_STATE <= INIT_EXEC_WB;
                            end if;
                        when others => 
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                    end case;
                else
                    NEXT_FETCH_STATE <= FETCH_OPERAND;
                end if;
            when SWITCH_STATE => -- This state is used individually by several operations.
                case OP is
                    when ADDA | CMPA | SUBA | MOVEA => -- Address register operations.
                        if AR_IN_USE = '0' then
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        else
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        end if;
                    when LEA | LINK | MOVE => 
                        -- LEA: calculate effective address (1 clock cycle) load it in INIT_EXEC_WB.
                        -- LINK: used to load the decremented stack pointer.
                        -- MOVE: Used for (An)+,-(An). address mode.
                        NEXT_FETCH_STATE <= INIT_EXEC_WB;
                    when UNLK => -- SP is updated here.
                        NEXT_FETCH_STATE <= CALC_AEFF;
                    when MOVEM => -- MOVEM requires 1 CLK cycle for address calculation.
                        if MOVEM_COND = false then
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Cancel bus access.
                        else
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        end if;
                    when MOVEP => -- Register select and displacement update.
                        if DR_IN_USE = '0' and BIW_0(7 downto 6) < "10" then
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        elsif DR_IN_USE = '0' and ALU_BSY = '0' then -- ASH.
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to memory.
                        else
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        end if;
                    when PEA =>
                        -- PEA requires two clock cycles here for effective adress calculation because it 
                        -- is loaded early. The first clock cycle the address becomes valid and after the
                        -- second the address is loaded to the ALU for writing on the stack.
                        if PHASE2 = false then 
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when others => -- Data register operations.
                        if DR_IN_USE = '0' then
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        else
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        end if;
                end case;
            when INIT_EXEC_WB =>
                case OP is
                    when ANDI_TO_SR | EORI_TO_SR | MOVE_TO_SR | ORI_TO_SR =>
                        if F157_ALU_FREE and BRANCH_ATN = '1' then
                            NEXT_FETCH_STATE <= SLEEP; -- Wait for new processor context.
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= START_OP; -- Proceed normally.
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when Bcc | CHK | DBcc | JMP | TRAPcc | TRAPV =>
                        if BCC_INIT = '1' then
                            NEXT_FETCH_STATE <= START_OP; -- [F162] taken Bcc.B from the live CCR (like BRA).
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= SLEEP; -- Check conditions.
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when CAS | JSR | MOVEC | TAS =>
                        -- CAS, TAS provide a RMC operation so have to sleep a little bit ;-)
                        if F157_ALU_FREE then
                            NEXT_FETCH_STATE <= SLEEP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when BRA | BSR | RTD | RTS =>
                        if F157_ALU_FREE then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when BFCHG | BFCLR | BFINS | BFSET =>
                        if F157_ALU_FREE and BF_BYTES < 5 then
                            NEXT_FETCH_STATE <= START_OP;
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= SLEEP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Wait, ASH.
                        end if;
                    when CAS2 => -- RMC operation.
                        if F157_ALU_FREE and PHASE2 = false then
                            NEXT_FETCH_STATE <= CALC_AEFF; -- Second compare.
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= SLEEP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when CHK2 =>
                        if F157_ALU_FREE and PHASE2 = false then
                            NEXT_FETCH_STATE <= FETCH_OPERAND; -- Second compare required?
                        elsif F157_ALU_FREE then -- ASH.
                            NEXT_FETCH_STATE <= SLEEP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when CMP2 | CMPM =>
                        if F157_ALU_FREE and PHASE2 = false then
                            NEXT_FETCH_STATE <= FETCH_OPERAND; -- Second compare required?
                        elsif F157_ALU_FREE then -- ASH.
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when MOVE_USP =>
                        if F157_ALU_FREE and BIW_0(3) = '0' then -- An to USP.
                            NEXT_FETCH_STATE <= SLEEP;
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= START_OP; -- USP to An.
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when MOVE =>
                        if F157_ALU_FREE and PHASE2 = false then -- Load the Operand into the ALU here.
                            case BIW_0(8 downto 6) is -- Destination operand.
                                when "101" => 
                                    NEXT_FETCH_STATE <= FETCH_DISPL;
                                when "110" =>
                                    NEXT_FETCH_STATE <= FETCH_EXWORD_1;
                                when "111" =>
                                    if BIW_0(11 downto 9) = "000" then
                                        NEXT_FETCH_STATE <= FETCH_ABS_LO;
                                    else
                                        NEXT_FETCH_STATE <= FETCH_ABS_HI;
                                    end if;
                                when others => -- No destination address calculation required.
                                    NEXT_FETCH_STATE <= START_OP;
                            end case;
                        elsif PHASE2 = true then -- ALU is not required at this point.
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when MOVEM =>
                        -- [F1] Finish on the last register in the list (MOVEM_END) instead of at position 15 (-(An): 0).
                        if ALU_BSY_M = '0' and BIW_0(10) = '0' and MOVEM_END = true then -- Register to memory, all modes.
                            NEXT_FETCH_STATE <= SLEEP; -- Data completely transfered to the ALU.
                        elsif ALU_BSY_M = '0' and BIW_0(10) = '1' and MOVEM_END = true and (MOVEM_FIRST_RD = true or MOVEM_COND = false) then -- Memory to register.
                            NEXT_FETCH_STATE <= SLEEP; -- Data completely transfered to the ALU (or empty list).
                        elsif ALU_BSY_M = '0' and BIW_0(10) = '1' then -- Memory to register.
                            NEXT_FETCH_STATE <= SWITCH_STATE;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to memory.
                        end if;
                    when PMOVE => -- [PMMU1] CRP/SRP to memory: a second ALU load and write for the lower long.
                        if F157_ALU_FREE and PM_QUAD = '1' and MV_RW = '1' and PHASE2 = false then
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        elsif F157_ALU_FREE then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when MOVEP =>
                        if F157_ALU_FREE and MOVEP_PNTR_I = 0 then
                            NEXT_FETCH_STATE <= START_OP; -- Ready.
                        elsif F157_ALU_FREE and BIW_0(7 downto 6) < "10" then
                            NEXT_FETCH_STATE <= CALC_AEFF; -- Memory to register.
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Register to memory.
                        end if;
                    when NOP =>
                        if not F157_ALU_FREE then -- ASH.
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- Wait for all pending bus cycles to be completed.
                        else
                            NEXT_FETCH_STATE <= START_OP;
                        end if;
                    when RTR =>
                        if F157_ALU_FREE and PHASE2 = false then
                            NEXT_FETCH_STATE <= CALC_AEFF;
                        elsif F157_ALU_FREE and PHASE2 = true then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when STOP =>
                        if F157_ALU_FREE then -- ASH.
                            NEXT_FETCH_STATE <= SLEEP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when UNLK =>
                        if F157_ALU_FREE and AR_IN_USE = '0' then -- ADH, ASH.
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB;
                        end if;
                    when others =>
                        if F157_ALU_FREE then -- ASH.
                            NEXT_FETCH_STATE <= START_OP;
                        elsif F157_OLAP = '1' then
                            -- [F157a] INIT overlapped the previous WRITEBACK. Leave so this
                            -- opcode is not re-inited forever.
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= INIT_EXEC_WB; -- ASH.
                        end if;
                end case;
            when SLEEP =>
                case OP is
                    when ANDI_TO_SR | CAS | CAS2 | EORI_TO_SR | MOVE_TO_SR | MOVEM | ORI_TO_SR | TAS =>
                        -- CAS, CAS2 and TAS are a read modify write instructions.
                        -- MOVEM: wait until last register is written to avoid data hazards
                        --        because the ADR_IN_USE, AR_IN__USE and DR_IN_USE does not
                        --        work for MOVEM (several registers in use).
                        -- TAS is a read modify write instruction.
                        -- _TO_SR instructions wait for the change of the SBIT
                        --        and so for a new processor context.
                        if NEXT_EXEC_WB_STATE = IDLE then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= SLEEP;
                        end if;
                    when BFCHG | BFCLR | BFINS | BFSET =>
                        if EXEC_WB_STATE = WRITE_DEST and WR_RDY = '1' and BF_BYTES = 1 then
                            -- Wait until second writeback access has been processed.
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= SLEEP;
                        end if;
                    when JSR =>
                        if PHASE2 = false then
                            NEXT_FETCH_STATE <= SLEEP; -- Wait for address calculation.
                        else
                            NEXT_FETCH_STATE <= START_OP;
                        end if;
                    when MOVE_USP | MOVEC =>
                        -- MOVE_USP: wait for writeback not to conflict with AR_DEC in START_OP.
                        if NEXT_EXEC_WB_STATE = IDLE then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= SLEEP; -- Wait for new processor context.
                        end if;
                    when CHK | DBcc =>
                        -- [T6b] CHK: the ALU may be padded to the 68030 time; wait for its acknowledge
                        -- (trap decision) before the next instruction starts.
                        -- DBcc: evaluate conditions. [F161] Expired: padded to the UM 14 harness (DBCC_XHOLD, CNT < 5).
                        if NEXT_EXEC_WB_STATE = IDLE and DBCC_XHOLD = false then
                            NEXT_FETCH_STATE <= START_OP;
                        else
                            NEXT_FETCH_STATE <= SLEEP;
                        end if;
                    when STOP =>
                        if TRACE_MODE /= "00" then
                            NEXT_FETCH_STATE <= START_OP; -- Do not perform a stop while tracing.
                        elsif EXH_REQ = '1' then
                            NEXT_FETCH_STATE <= START_OP; -- Wait on interrupt.
                        else
                            NEXT_FETCH_STATE <= SLEEP;
                        end if;
                    when others => -- Bcc, CHK, JMP, TRAPV.
                        -- Bcc: evaluate conditions.
                        -- CHK: use SWITCH_STATE for TRAP evaluation.
                        -- CHK2: use SWITCH_STATE for TRAP evaluation.
                        -- JMP: wait for address calculation.
                        -- TRAPV: check conditions.
                        NEXT_FETCH_STATE <= START_OP;
                end case;
        end case;
    end process FETCH_DEC;

    EXEC_WB_DEC: process(ALU_COND, ALU_INIT_I, ALU_REQ, BIW_0_WB, BIW_1_WB, BF_BYTES, EXEC_WB_STATE, FETCH_STATE, MOVEM_INH_WR, OP_WB_I, PHASE2, WR_RDY, MV_RW_WB, WR_OLAP) -- [F145] MV_RW_WB [F165] WR_OLAP
    begin
        case EXEC_WB_STATE is
            when IDLE =>
                if ALU_INIT_I = '1' then
                    NEXT_EXEC_WB_STATE <= EXECUTE;
                else
                    NEXT_EXEC_WB_STATE <= IDLE;
                end if;
            when EXECUTE =>
                if ALU_REQ = '1' then
                    case OP_WB_I is
                        when ABCD | SBCD | ADDX | SUBX | PACK | UNPK =>
                            if BIW_0_WB(3) = '0' then -- Register to register.
                                NEXT_EXEC_WB_STATE <= WRITEBACK;
                            else -- Memory to memory.
                                NEXT_EXEC_WB_STATE <= WRITE_DEST;
                            end if;
                        when ADD | SUB | AND_B | OR_B =>
                            if BIW_0_WB(8) = '0' then
                                if F157_PHASE_B then
                                    NEXT_EXEC_WB_STATE <= IDLE; -- [F157c] write in EXECUTE (RESULT already valid).
                                else
                                    NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is register.
                                end if;
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            end if;
                        when MOVEQ => -- [F162] written in EXECUTE (combinational RESULT).
                            if F162_MQ then
                                NEXT_EXEC_WB_STATE <= IDLE;
                            else
                                NEXT_EXEC_WB_STATE <= WRITEBACK;
                            end if;
                        when ADDA | SUBA | ANDI_TO_SR | BFEXTS | BFEXTU | BFFFO | DIVS | DIVU | EORI_TO_SR | EXG | EXT | EXTB | 
                             LEA | MOVE_TO_CCR | MOVE_TO_SR | MOVE_USP | MOVEA | MOVEC | MULS | MULU | ORI_TO_SR | STOP | SWAP | UNLK =>
                            NEXT_EXEC_WB_STATE <= WRITEBACK;
                        when ADDI | ADDQ | ANDI | BCHG | BCLR | BFCHG | BFCLR | BFINS | BFSET | BSET | CLR | EOR | EORI |
                                     MOVE_FROM_CCR | MOVE_FROM_SR | NBCD | NEG | NEGX | NOT_B | ORI | Scc | SUBI | SUBQ | TAS =>
                            if BIW_0_WB(5 downto 3) = "000" then
                                if F157_PHASE_B and (OP_WB_I = ADDI or OP_WB_I = ADDQ or OP_WB_I = ANDI or
                                                     OP_WB_I = CLR or OP_WB_I = EOR or OP_WB_I = EORI or
                                                     OP_WB_I = NEG or OP_WB_I = NEGX or OP_WB_I = NOT_B or
                                                     OP_WB_I = ORI or OP_WB_I = SUBI or OP_WB_I = SUBQ) then
                                    NEXT_EXEC_WB_STATE <= IDLE; -- [F157c] write in EXECUTE (RESULT already valid).
                                else
                                    NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is a data register.
                                end if;
                            elsif BIW_0_WB(5 downto 3) = "001" then -- Valid for ADDQ and SUBQ.
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is an address register.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            end if;
                        when ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                            if BIW_0_WB(7 downto 6) /= "11" then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Register shifts.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Memory shifts.
                            end if;
                        when CAS =>
                            if ALU_COND = false then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Update Dc.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Update destination.
                            end if;
                        when CAS2 =>
                            -- [C1] The first compare ends while the fetch side still reads memory operand 2
                            -- (CALC_AEFF or FETCH_OPERAND); only the second (fetch side in SLEEP) decides.
                            -- Testing FETCH_OPERAND alone let the first compare through in CALC_AEFF, where
                            -- the stale CAS2_COND of the previous CAS2 made it look final: writes started
                            -- during the operand 2 read and the core hung (back-to-back CAS2).
                            if FETCH_STATE /= SLEEP then
                                NEXT_EXEC_WB_STATE <= IDLE; -- Second read access.
                            elsif ALU_COND = false then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Update Dc.
                            else
                                NEXT_EXEC_WB_STATE <= ADR_PIPELINE; -- Update destination.
                            end if;
                        when DBcc =>
                            if ALU_COND = true then
                                NEXT_EXEC_WB_STATE <= IDLE;
                            else
                                NEXT_EXEC_WB_STATE <= WRITEBACK;
                            end if;
                        when MOVE =>
                            if BIW_0_WB(8 downto 6) = "000" then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is register.
                            elsif PHASE2 = false then
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            else
                                NEXT_EXEC_WB_STATE <= EXECUTE; -- Wait for PHASE2 address calculation.
                            end if;
                        when BSR | JSR | LINK | PEA =>
                            NEXT_EXEC_WB_STATE <= WRITE_DEST;
                        when MOVEM =>
                            if OP_WB_I = MOVEM and MOVEM_INH_WR = true then
                                NEXT_EXEC_WB_STATE <= IDLE; -- Discard the write cycle.
                            elsif BIW_0_WB(10) = '1' then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is register.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            end if;
                        when MOVEP =>
                            if BIW_0_WB(7 downto 6) < "10" then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Memory to register.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Register to memory.
                            end if;
                        when MOVES | PMOVE =>
                            if MV_RW_WB = '0' then
                                NEXT_EXEC_WB_STATE <= WRITEBACK; -- Destination is register.
                            else
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Destination is in memory.
                            end if;
                        -- Default is for:
                        -- ANDI_TO_CCR, Bcc, BFTST, BTST, CHK, CHK2, 
                        -- CMP, CMP2, CMPA, CMPI, CMPM, EORI_TO_CCR,
                        -- ORI_TO_CCR, RTR, TRAPV, TST.
                        when others =>
                            NEXT_EXEC_WB_STATE <= IDLE;
                    end case;
                else
                    NEXT_EXEC_WB_STATE <= EXECUTE;
                end if;
            when ADR_PIPELINE => -- Effective address calculation takes one clock cycle.
                NEXT_EXEC_WB_STATE <= WRITE_DEST;
            when WRITEBACK =>
                case OP_WB_I is
                    when CAS2 =>
                        if PHASE2 = false then
                            NEXT_EXEC_WB_STATE <= WRITEBACK;  -- Update Dc2
                        else
                            NEXT_EXEC_WB_STATE <= IDLE;
                        end if;
                    when others =>
                        -- [F157a] Next instruction already in INIT: go straight to its EXECUTE.
                        if F157_OLAP = '1' and ALU_INIT_I = '1' then
                            NEXT_EXEC_WB_STATE <= EXECUTE;
                        else
                            NEXT_EXEC_WB_STATE <= IDLE;
                        end if;
                    end case;
            when WRITE_DEST =>
                if WR_RDY = '1' then
                    case OP_WB_I is
                        when BFCHG | BFCLR | BFINS | BFSET =>
                            if BF_BYTES <= 4 then
                                NEXT_EXEC_WB_STATE <= IDLE;
                            else
                                NEXT_EXEC_WB_STATE <= ADR_PIPELINE;
                            end if;
                        when CAS2 =>
                            if PHASE2 = false then
                                NEXT_EXEC_WB_STATE <= WRITE_DEST; -- Update destination 2.
                            else
                                NEXT_EXEC_WB_STATE <= IDLE;
                            end if;
                        when MOVEM =>
                            if ALU_INIT_I = '1' then
                                NEXT_EXEC_WB_STATE <= EXECUTE; -- Option A: next MOVEM register overlaps this write.
                            else
                                NEXT_EXEC_WB_STATE <= IDLE;
                            end if;
                        when others =>
                            if WR_OLAP = '1' and ALU_INIT_I = '1' then
                                NEXT_EXEC_WB_STATE <= EXECUTE; -- [F165] next operation loaded in the acknowledge clock.
                            else
                                NEXT_EXEC_WB_STATE <= IDLE;
                            end if;
                    end case;
                else
                    NEXT_EXEC_WB_STATE <= WRITE_DEST;
                end if;
        end case;
    end process EXEC_WB_DEC;
end BEHAVIOUR;
