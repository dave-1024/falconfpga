------------------------------------------------------------------------
----                                                                ----
---- WF68K30L IP Core.                                              ----
----                                                                ----
---- This is the top level structural design unit of the 68K30L     ----
---- complex instruction set (CISC) microcontroller. It's program-  ----
---- ming model is (hopefully) fully compatible with Motorola's     ----
---- MC68030. This core features a pipelined architecture. In com-  ----
---- parision to the fully featured 68K30 the core has no MMU, no   ----
---- data and instruction cache and no coprocessor interface. This  ----
---- results in missing burstmodes which are not required due to    ----
---- lack of cache. Missing coprocessor operations are:             ----
---- cpBcc, cpDBcc, cpGEN, cpRESTORE, cpSAVE, cpScc, cpTRAPcc.      ----
---- Missing MMU operations are: PFLUSH, PLOAD, PMOVE and PTEST.    ----
---- The trap handler does not process the following exceptions     ----
---- which lack due to the missing MMU and coprocessor interface:   ----
---- PRE_EXC_CP, MID_EXC_CP , POST_EXC_CP, EXC_VECT_CP, MMU_CFG_ERR ----
---- The shifter in the 68K30 is a barrel shifter and in this core  ----
---- it is a conventional shift register controlled logic.          ----
---- This core features the loop operation mode of the 68010 to     ----
---- deal with DBcc loops. This feature is a predecessor to the     ----
---- MC68020/30/40 caches.                                          ----
---- The exception handler works for the RTE but without taking the ----
---- SSW into account which is intended to restore from a defectice ----
---- bus error stack frame.                                         ----
----                                                                ----
---- Enjoy.                                                         ----
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
--   Control section: fixed a bug in the MOVEM operation. Thanks to Raymond Mounissamy.
--   Address section: minor optimizations.
-- Revision 2K18A 20180620 WF
--   Control: Fixed a bug in MOVE An,-(Ay). Thanks to Gary Bingham for the support.
--   Top: changed ALU_OP1_IN multiplexer due to MOVE An,-(Ay) bug.
--   Address registers: Changed ADR_ATN logic to be valid one clock cycle earlier.
-- Revision 2K18A (unreleased) WF
--   Top / Opdecoder / Exhandler: Removed REST_BIW_0.
--   Exhandler: Removed PC_OFFSET.
--   ALU: Bug fix: MOVEM sign extension.
--   Address registers: Removed PC_REG.
--   Control: Fixed wrong PEA behaviour.
--   Control: Fixed the displacement for LINK.
--   ALU: Fix for restoring correct values during the DIVS and DIVU in word format.
--   Control: Fixed the operation size for MOVEQ.
--   Control: ADDQ, SUBQ Fix: address registers are always written long.
--   Top, exception handler, address registers: Fixed PC restoring during exception processing.
--   Control: ADDI, ANDI, EORI, ORI, SUBI: address is not marked used if destination is Dn.
--   Control: ADDI, ANDI, EORI, ORI, SUBI: data register is marked used if destination is Dn.
--   Bus interface: Suppress bus faults during RESET instruction.
--   Bus interface: Optimized ASn and DSn timing for synchronous RAM.
--   ALU: Fixed the SUBQ calculation.
--   Opcode decoder: Fixed the PW_EW_OFFSET calculation for JSR.
--   Top: fixed the value of DATA_IMMEDIATE for ADDQ and SUBQ in case of #8.
--   ALU: Rearanged the Offset for the JSR instruction.
--   Control: Fixed AR_MARK_USED in LINK.
--   ALU: EXT instruction uses now RESULT(63 downto 0).
--   Top: Introduced OP_WB form the control unit.
--   Top: Rearanged the AR_IN_1 multiplexer to avoid data hazards.
--   Top: Rearanged the AR_IN_2 multiplexer to avoid data hazards.
--   Top: Rearanged the DR_IN_1 multiplexer to avoid data hazards.
--   Top: Rearanged the DR_IN_2 multiplexer to avoid data hazards.
--   EXG: rearanged logic to meet the new top level multiplexers.
--   Control: LINK, UNLK: wait in START_OP until the ALU is ready (avoids possible data hazards).
--   Top: ALU_OP1_IN to meet the new EXG multiplexers.
--   Top: ALU_OP2_IN to meet the new EXG multiplexers.
--   Address registers: Fixed the writing of ISP_REG during EXG instruction with two address registers.
--   Control: MOVEM: Fixed predecrement mode for consecutive MOVEM -(An).
--   Control: MOVEP: MOVEP_PNTR is now correct for consecutive MOVEP.
--   Control: MOVEP: avoid structural hazard in SWITCH_STATE by waiting for ALU.
--   Control: LINK, UNLK: fixed the write back operation size.
--   Exception handler: Fixed the vector calculation of INT vectors.
--   Exception handler: Fixed faulty modelling in IRQ_FILTER.
--   Exception handler: Implemented the AVEC_FILTER to better meet bus timings.
--   Control: EOR: fixed a bug in the writeback mechanism.
--   Control: BSR, JSR: EXEC_WB state machine waits now for ALU_INIT. Avoid structural / data hazard.
--   Control: the instruction pipe is not flushed for MOVE_FROM_CCR, MOVE_FROM_SR, MOVE_USP, MOVEC.
--   Control: Modifications in the FETCH state machine to avoid several data hazards for MOVEM, MOVE_FROM_CCR, MOVE_FROM_SR.
--   Control: Modifications in the FETCH state machine to avoid several data hazards for ANDI_TO_CCR, ANDI_TO_SR, EORI_TO_CCR, EORI_TO_SR, ORI_TO_CCR, ORI_TO_SR.
--   Exception handler: The RTE exception has now highest priority (avoids mismatch).
--   Control: Bugfix: the condition codes were not updated if there was a pending interrupt.
--   Control: We have to stop a pending operation in case of a pending interrupt. This is done by rejecting OW_RDY.
--   TOP, Control, Exception handler Opcode Decoder: Rearanged PC_INC and ipipe flush logic.
--   Bus interface: BUS_EN is now active except during arbitration.
--   Control: Write the undecremented Register for MOVE Ax, -(Ax).
--   ALU: Fixed wrong condition codes for AND_B, ANDI, EOR, EORI, OR_B, ORI and NOT_B.
--   Exception handler: Update the IRQ mask only for RESET and interrupts.
--   Bus interface: Opted out START_READ and CHK_RD.
--   Control: UNMARK is now asserted in the end of the write cycle. This avoids data hazards.
--   Exception handler: external interrupts are postponed if any system controllers are in initialize operation status.
--   ALU: Fixed writeback issues in the status register logic.
--   ALU: Fixed writing the stack pointer registers (MSBIT is used now).
--   Control: Fixed a MOVEC writeback issue (use BIW_WB... instead of BIW_...).
--   Control: Fixed a USP writeback issue (use BIW_WB... instead of BIW_...).
--   ALU: the address registers are always written long.
--   Top: opted out SBIT_AREG and MBIT_AREG.
--   Address register bugfix: exception handler do not increment and decrement the USP any more.
--   Control: Introduced a switch NO_PIPELINE.
--   Address registers, Control: MOVEM-Fix see STORE_AEFF.
--   Control: DBcc: fixed a data hazard for DBcc_COND evaluation by waiting on the ALU result.
--   Control: Fixed DR_WR_1 locking against AR_WR_2.
--   Control: IPIPE is flushed, when there is a memory space change in the end of xx_TO_SR operations.
--   Control: To handle correct addressing, ADR_OFFSET is now cleared right in the end of the respective operation.
--   Control: Fixed a bug in EOR writing back in register direct mode.
--   ALU: Fixed a bug in MULU.W (input operands are now 16 bit wide).
--   Control: ADDQ and SUBQ: fixed (An)+ mode. An increments now.
--   Control: Fixed DIVS, DIVU in memory address modes (wrong control flow).
--   Control: ADDQ and SUBQ: fixed condition code control UPDT_CC.
--   Control: fixed a data hazard bug using addressing modes with index register.
--   Opcode decoder: Fix for unimplemented or illegal operations: PC is increased before stacked.
--   Exception handler: RTE now loads the address offset correctly when entering the handler.
--   Control: Implemented the 68K10 loop mechanism.
--   Opcode decoder Implemented the 68K10 loop mechanism.
--   Bus interface: Fixed the faulty bus arbitration logic.
--   Opcode decoder: Removed CAHR, we have no cache.
--   Top: Removed a data hazard in the DR_IN_1 multiplexer (EXG operation).
-- Revision 2K19A 20190419 WF
--   Control: Fixed several pipelinig issues (hazards).
--   New feature: Branch prediction for the status register manipulation operations (BRANCH_ATN).
--   Exception handler, Opcode decoder, Top: Rearranged address error handling.
--   Bus interface, Exception handler, Opcode decoder, Top: Rearranged address error handling.
--   Top, Address registers: Removed ADR_ATN. Not required any more.
--   Control: Introdeced a new state CALC_AEFF which results in no need of ADR_ATN and a twice highre fmax.
-- FalconFPGA modifications (David Dunne, github.com/dave-1024/falconfpga), CERN OHL v1.2.
-- Changes are tagged Fnn in the code. Dates are from git history.
-- Base: WF68K30L 2K19A (this repo's import of 2026-09-24).
--   2026-09-30 F1/F13/F14/F15: bus fault SSW and address latched at the faulting cycle.
--   2026-09-30 F11: CACR/CAAR via MOVEC.
--   2026-09-30 F18: MOVES read uses SFC.
--   2026-09-30 F21-F25: bit field byte count, register wrap, BFINS pattern, width, BFSET typo.
--   2026-09-30 F28: SSW RB bit for address errors (checked on MC68030).
--   2026-10-03 F56: combinational loops and BF_NZ latch removed; hazard selects.
--   2026-10-04 F58: falling-edge flops on CLK_F for the synchronous ST bridge.
--   2026-10-07 F59: CACHES generic (default 0) around icache/dcache.
--   2026-10-07 F60: CHK compares Dn, not A0.
--   2026-10-08 F62/F62b/F62c: opcode prefetch queue (PREFETCH_Q).
--   2026-10-09 F65: FAST_HANDOFF generic, prefetch S5-to-S0 chain (off by default).
--   2026-10-14 DIAG: DBG_EXC/DBG_ADR/DBG_A5 debug ports (unused ports are removed).
--   2026-10-16 PH2: address/FC latches also load on OP_CHAIN_LD (prefetch S5 to operand S0).
--   2026-10-16 PH2-FMAX: ADR_LATCH/FC_LATCH drive the bus interface's ADR_LAT/FC_LAT (address pins).
--   2026-10-17 IC: 68030 instruction cache (WF68K30L_ICACHE) on the prefetch queue, unconditional; cache pins
--     CIINn, CDISn, CBACKn (in), CBREQn, CIOUTn (out); CACR CI/CEI with CAAR. The F59 experimental I/D modules
--     and G_CACHES are gone, the prefetch queue is always on; CACHES is ignored (docs/ICACHE_DESIGN.md).
--

library work;
use work.WF68K30L_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity WF68K30L_TOP is
    generic(VERSION     : std_logic_vector(15 downto 0) := x"1904"; -- CPU version number.
        -- The following two switches are for debugging purposes. Default for both is false.
        NO_PIPELINE     : boolean := false;  -- If true the main controller work in scalar mode.
        NO_LOOP         : boolean := false; -- If true the DBcc loop mechanism is disabled.
        -- [F58] 1: the falling-edge registers are clocked by CLK_N (a 180 degree copy of CLK,
        -- e.g. a second PLL output on a global clock) instead of an inverted CLK.
        CLK_N_EXT       : integer := 0;
        -- [F59] Was: 1 = the experimental 4 Oct I/D cache modules. [IC] Ignored since
        -- 2026-10-17: the 68030 instruction cache is always built (CIINn decides what
        -- is cacheable); kept so old build scripts and bridge parameters still elaborate.
        CACHES          : integer := 0;
        -- [F65] 1: prefetch-to-prefetch S5-to-S0 handoff in the bus interface.
        -- 0 (default): the IDLE -> START_CYCLE gap stays. Operand cycles are
        -- unchanged either way.
        FAST_HANDOFF    : integer := 0);

    port (
        CLK             : in std_logic;
        CLK_N           : in std_logic := '0'; -- [F58] only used with CLK_N_EXT = 1
        
        -- Address and data:
        ADR_OUT         : out std_logic_vector(31 downto 0);
        DBG_EXC         : out std_logic_vector(104 downto 0); -- FalconFPGA DIAG: exception taken {strobe, vector, SR, PC, A5, BIW_0}
        DBG_ADR         : out std_logic_vector(31 downto 0); -- FalconFPGA DIAG: ADR_LATCH, ADR_P, PC_L, ADR_L bits 23:16
        DATA_IN         : in std_logic_vector(31 downto 0);
        DATA_OUT        : out std_logic_vector(31 downto 0);
        DATA_EN         : out std_logic; -- Enables the data port.

        -- System control:
        BERRn           : in std_logic;
        RESET_INn       : in std_logic;
        RESET_OUT       : out std_logic; -- Open drain.
        HALT_INn        : in std_logic;
        HALT_OUTn       : out std_logic; -- Open drain.
        
        -- Processor status:
        FC_OUT          : out std_logic_vector(2 downto 0);
        
        -- Interrupt control:
        AVECn           : in std_logic;
        IPLn            : in std_logic_vector(2 downto 0);
        IPENDn          : out std_logic;

        -- Aynchronous bus control:
        DSACKn          : in std_logic_vector(1 downto 0);
        SIZE            : out std_logic_vector(1 downto 0);
        ASn             : out std_logic;
        RWn             : out std_logic;
        RMCn            : out std_logic;
        DSn             : out std_logic;
        ECSn            : out std_logic;
        OCSn            : out std_logic;
        DBENn           : out std_logic; -- Data buffer enable.
        BUS_EN          : out std_logic; -- Enables ADR, ASn, DSn, RWn, RMCn, FC and SIZE.

        -- Synchronous bus control:
        STERMn          : in std_logic;

        -- [IC] Cache control (MC68030UM 5.7, 5.11.1). The defaults keep a bench that
        -- does not drive them uncached: CIINn asserted, CDISn negated, no burst.
        CIINn           : in std_logic := '0'; -- Cache inhibit in, sampled with the data.
        CDISn           : in std_logic := '1'; -- Cache disable (emulator / jumper).
        CBACKn          : in std_logic := '1'; -- Cache burst acknowledge (no burst yet: unused).
        CBREQn          : out std_logic; -- Cache burst request (no burst yet: always negated).
        CIOUTn          : out std_logic; -- Cache inhibit out (no PMMU: always negated).

        -- Status controls:
        STATUSn         : out std_logic;
        REFILLn         : out std_logic;

        -- Bus arbitration control:
        BRn             : in std_logic;
        BGn             : out std_logic;
        BGACKn          : in std_logic
    );
end entity WF68K30L_TOP;
    
architecture STRUCTURE of WF68K30L_TOP is
signal CLK_F                : std_logic; -- [F58] clock of the falling-edge registers (rising edge used)
signal ADn                      : bit;
signal ADR_CPY_EXH              : std_logic_vector(31 downto 0);
signal ADR_EFF                  : std_logic_vector(31 downto 0);
signal ADR_EFF_WB               : std_logic_vector(31 downto 0);
signal ADR_L                    : std_logic_vector(31 downto 0);
signal ADR_LATCH                : std_logic_vector(31 downto 0);
signal ADR_MODE                 : std_logic_vector(2 downto 0);
signal ADR_MODE_MAIN            : std_logic_vector(2 downto 0);
signal ADR_IN_USE               : bit;
signal ADR_OFFSET               : std_logic_vector(31 downto 0);
signal ADR_OFFSET_EXH           : std_logic_vector(31 downto 0);
signal ADR_OFFSET_MAIN          : std_logic_vector(5 downto 0);
signal ADR_P                    : std_logic_vector(31 downto 0);
signal ADR_MARK_UNUSED_MAIN     : bit;
signal ADR_MARK_USED            : bit;
signal AERR                     : bit;
signal ALU_ACK                  : bit;
signal WR_EARLY                 : bit; -- [F3]
signal WR_TAKE                  : bit;
signal F3_BYP                   : bit;
signal ADR_FAST                 : bit;
signal ALU_RESULT_MV            : std_logic_vector(31 downto 0);
signal ALU_BSY                  : bit;
signal ALU_COND                 : boolean;
signal ALU_INIT                 : bit;
signal ALU_LOAD_OP1             : bit;
signal ALU_LOAD_OP2             : bit;
signal ALU_LOAD_OP3             : bit;
signal ALU_OP1_IN               : std_logic_vector(31 downto 0);
signal ALU_OP2_IN               : std_logic_vector(31 downto 0);
signal ALU_OP3_IN               : std_logic_vector(31 downto 0);
signal ALU_REQ                  : bit;
signal ALU_RESULT               : std_logic_vector(63 downto 0);
signal AMODE_SEL                : std_logic_vector(2 downto 0);
signal AR_DEC                   : bit;
signal AR_IN_1                  : std_logic_vector(31 downto 0);
signal AR_IN_2                  : std_logic_vector(31 downto 0);
signal AR_IN_USE                : bit;
signal AR_INC                   : bit;
signal AR_MARK_USED             : bit;
signal AR_OUT_1                 : std_logic_vector(31 downto 0);
signal AR_OUT_2                 : std_logic_vector(31 downto 0);
signal AR_SEL_RD_1              : std_logic_vector(2 downto 0);
signal AR_SEL_RD_1_MAIN         : std_logic_vector(2 downto 0);
signal AR_SEL_RD_2              : std_logic_vector(2 downto 0);
signal AR_SEL_WR_1              : std_logic_vector(2 downto 0);
signal AR_SEL_WR_2              : std_logic_vector(2 downto 0);
signal AR_WR_1                  : bit;
signal AR_WR_2                  : bit;
signal AVECn_BUSIF              : std_logic;
signal BERR_MAIN                : bit;
signal BERR_IBOUND              : bit; -- [FLT2]
signal BITPOS                   : std_logic_vector(4 downto 0);
signal BF_BYTES_CTL             : integer range 0 to 5; -- F21/H29.
signal BIW_0                    : std_logic_vector(15 downto 0);
signal BIW_0_WB_73              : std_logic_vector(7 downto 3);
signal BIW_1                    : std_logic_vector(15 downto 0);
signal BIW_2                    : std_logic_vector(15 downto 0);
signal BF_OFFSET                : std_logic_vector(31 downto 0);
signal BF_WIDTH                 : std_logic_vector(5 downto 0) := "100000"; -- Default needed for simulation!
signal BKPT_CYCLE               : bit;
signal BKPT_INSERT              : bit;
signal BRANCH_ATN               : bit;
signal BUS_BSY                  : bit;
signal BUSY_EXH                 : bit;
signal BUSY_MAIN                : bit;
signal BUSY_OPD                 : bit;
signal CC_UPDT                  : bit;
signal CPU_SPACE                : bit;
signal CPU_SPACE_EXH            : bit;
signal DFC                      : std_logic_vector(2 downto 0);
signal DFC_RD                   : bit;
signal DFC_WR                   : bit;
signal DR_WR_1                  : bit;
signal DR_WR_2                  : bit;
signal DR_MARK_USED             : bit;
signal DATA_FROM_CORE           : std_logic_vector(31 downto 0);
signal DATA                     : std_logic_vector(31 downto 0);
signal DATA_IN_EXH              : std_logic_vector(31 downto 0);
signal DATA_IMMEDIATE           : std_logic_vector(31 downto 0);
signal DATA_EXH                 : std_logic_vector(31 downto 0);
signal DATA_RD                  : bit;
signal DATA_WR                  : bit;
signal DATA_RD_EXH              : bit;
signal DATA_WR_EXH              : bit;
signal DATA_RD_MAIN             : bit;
signal DATA_WR_MAIN             : bit;
signal DATA_RDY                 : bit;
signal DATA_TO_CORE             : std_logic_vector(31 downto 0);
signal DATA_VALID               : std_logic;
signal DISPLACEMENT             : std_logic_vector(31 downto 0);
signal DISPLACEMENT_MAIN        : std_logic_vector(31 downto 0);
signal DISPLACEMENT_EXH         : std_logic_vector(7 downto 0);
signal DATA_BUFFER              : std_logic_vector(31 downto 0);
signal DBcc_COND                : boolean;
signal DR_IN_1                  : std_logic_vector(31 downto 0);
signal DR_IN_2                  : std_logic_vector(31 downto 0);
signal DR_OUT_2                 : std_logic_vector(31 downto 0);
signal DR_OUT_1                 : std_logic_vector(31 downto 0);
signal DR_SEL_WR_1              : std_logic_vector(2 downto 0);
signal DR_SEL_WR_2              : std_logic_vector(2 downto 0);
signal DR_SEL_RD_1              : std_logic_vector(2 downto 0);
signal DR_SEL_RD_2              : std_logic_vector(2 downto 0);
signal DR_SEL_ADH_2             : std_logic_vector(2 downto 0);
signal DR_SEL_ADH_3             : std_logic_vector(2 downto 0);
signal DR_IN_USE                : bit;
signal EW_ACK                   : bit;
signal EW_REQ_MAIN              : bit;
signal EX_TRACE                 : bit;
signal EXEC_RDY                 : bit;
signal EXH_REQ                  : bit;
signal EXT_WORD                 : std_logic_vector(15 downto 0);
signal FAULT_ADR                : std_logic_vector(31 downto 0);
signal FB                       : std_logic;
signal FC                       : std_logic;
signal FETCH_MEM_ADR            : bit;
signal FC_I                     : std_logic_vector(2 downto 0);
signal FC_LATCH                 : std_logic_vector(2 downto 0);
signal HILOn                    : bit;
signal IBUFFER                  : std_logic_vector(31 downto 0);
signal INBUFFER                 : std_logic_vector(31 downto 0);
signal INT_TRIG                 : bit;
signal IPL                      : std_logic_vector(2 downto 0);
signal ISP_DEC                  : bit;
signal ISP_RD                   : bit;
signal ISP_LOAD_EXH             : bit;
signal ISP_WR_MAIN              : bit;
signal ISP_WR                   : bit;
signal IVECT_OFFS               : std_logic_vector(9 downto 0);
signal IPEND_In                 : bit;
signal IRQ_PEND                 : std_logic_vector(2 downto 0);
signal IPIPE_FILL               : bit;
signal IPIPE_FLUSH              : bit;
signal OPC_DISMISS              : bit; -- [F62c]
signal COF_PEND                 : bit; -- [PFCOF]
signal PF_HOLD                  : bit; -- [PFCOF]
signal MI_HOLD                  : bit; -- [MI1]
signal PF_HOLD_BI               : bit; -- [MI1]
signal Q_STREAM                 : std_logic_vector(63 downto 0); -- [PFCOF2]
signal Q_COUNT                  : integer range 0 to 4; -- [PFCOF2]
signal IPIPE_FLUSH_EXH          : bit;
signal IPIPE_FLUSH_MAIN         : bit;
signal IPIPE_OFFESET            : std_logic_vector(2 downto 0);
signal LOOP_BSY                 : bit;
signal LOOP_SPLIT               : boolean;
signal LOOP_EXIT                : bit;
signal MOVEP_PNTR               : integer range 0 to 3;
signal MSP_RD                   : bit;
signal MSP_WR                   : bit;
signal OPCODE_RD                : bit;
signal OPCODE_RDY               : bit;
signal OPCODE_VALID             : std_logic;
signal OPCODE_TO_CORE           : std_logic_vector(15 downto 0);
signal OP_SIZE                  : OP_SIZETYPE;
signal OP_SIZE_BUS              : OP_SIZETYPE;
signal OP_SIZE_EXH              : OP_SIZETYPE;
signal OP_SIZE_MAIN             : OP_SIZETYPE;
signal OP_SIZE_WB               : OP_SIZETYPE; -- Writeback.
signal OPCODE_REQ               : bit;
signal OPCODE_REQ_I             : bit;
signal BUS_OPCODE_RDY           : bit;
signal BUS_OPCODE_WORD          : std_logic_vector(15 downto 0);
signal IC_BUS_REQ               : bit;
signal IC_CI                    : std_logic;
signal BUS_DATA_RDY             : bit;
signal BUS_DATA_WORD            : std_logic_vector(31 downto 0);
signal DC_BUS_REQ               : bit;
signal IC_CEI                   : std_logic; -- [IC]
signal DC_CD                    : std_logic; -- [DC]
signal DC_CED                   : std_logic;
signal DC_FILL_EN               : std_logic;
signal DC_ON                    : std_logic;
signal DC_LK_ADR                : std_logic_vector(31 downto 0);
signal DC_LK_FC                 : std_logic_vector(2 downto 0);
signal DC_LK_SZ                 : std_logic_vector(2 downto 0);
signal DC_HIT                   : std_logic;
signal DC_HIT_DATA              : std_logic_vector(31 downto 0);
signal DC_WR_GO                 : std_logic;
signal DC_WR_ADR                : std_logic_vector(31 downto 0);
signal DC_WR_FC                 : std_logic_vector(2 downto 0);
signal DC_WR_SZ                 : std_logic_vector(2 downto 0);
signal DC_WR_DATA               : std_logic_vector(31 downto 0);
signal DC_FL_GO                 : std_logic;
signal DC_FL_A0                 : std_logic_vector(31 downto 2);
signal DC_FL_FC                 : std_logic_vector(2 downto 0);
signal DC_FL_U1                 : std_logic;
signal DC_FL_D0                 : std_logic_vector(31 downto 0);
signal DC_FL_D1                 : std_logic_vector(31 downto 0);
signal DC_FL_OK0                : std_logic_vector(1 downto 0);
signal DC_FL_OK1                : std_logic_vector(1 downto 0);
signal DC_FL_BE0                : std_logic;
signal DC_FL_BE1                : std_logic;
signal CDIS_R                   : std_logic := '0'; -- [IC] Registered CDIS (asserted = '1').
signal IC_LK_ADR                : std_logic_vector(31 downto 2); -- [IC]
signal IC_LK_FC2                : std_logic;
signal IC_HIT                   : std_logic;
signal IC_HIT_DATA              : std_logic_vector(31 downto 0);
signal IC_FILL                  : std_logic;
signal IC_FILL_MIS              : std_logic;
signal IC_FILL_OK               : std_logic_vector(1 downto 0);
signal IC_BREAK                 : std_logic;
signal IC_FILL_ADR              : std_logic_vector(31 downto 2);
signal IC_FILL_FC2              : std_logic;
signal IC_FILL_DATA             : std_logic_vector(31 downto 0);
signal OW_VALID                 : std_logic;
signal OPD_ACK_MAIN             : bit;
signal OP                       : OP_68K;
signal OP_WB                    : OP_68K;
signal OW_REQ_MAIN              : bit;
signal OUTBUFFER                : std_logic_vector(31 downto 0);
signal PC                       : std_logic_vector(31 downto 0);
signal PC_ADD_DISPL             : bit;
signal PC_ADR_OFFSET            : std_logic_vector(7 downto 0);
signal PC_EW_OFFSET             : std_logic_vector(3 downto 0);
signal PC_INC                   : bit;
signal PC_INC_EXH               : bit;
signal PC_INC_EXH_I             : bit;
signal PC_L                     : std_logic_vector(31 downto 0);
signal PC_LOAD                  : bit;
signal PC_LOAD_EXH              : bit;
signal PC_LOAD_MAIN             : bit;
signal PC_OFFSET                : std_logic_vector(7 downto 0);
signal DBG_A5_I                 : std_logic_vector(31 downto 0);
signal DBG_EXC_STB              : std_logic;
signal PC_OFFSET_OPD            : std_logic_vector(7 downto 0);
signal PC_RESTORE_EXH           : bit;
signal RB                       : std_logic;
signal RC                       : std_logic;
signal EX_IS_AERR               : std_logic; -- F28/H22.
signal RD_REQ                   : bit;
signal RD_REQ_I                 : bit;
signal RMC                      : bit;
signal REFILLn_EXH              : std_logic;
signal RESTORE_ISP_PC           : bit;
signal RESET_CPU                : bit;
signal RESET_IN                 : std_logic;
signal RESET_STRB               : bit;
signal SP_ADD_DISPL             : bit;
signal SP_ADD_DISPL_EXH         : bit;
signal SP_ADD_DISPL_MAIN        : bit;
signal SBIT                     : std_logic;
signal OPC_FC                   : std_logic_vector(2 downto 0); -- [F62]
constant PREFETCH_Q_EN          : integer := 1; -- [F62] Opcode prefetch queue. [IC] Always on: the instruction cache sits on it.
signal SSW_80                   : std_logic_vector(8 downto 0);
signal BFLT_SSW                 : std_logic_vector(8 downto 0); -- F1
signal BFLT_ADR                 : std_logic_vector(31 downto 0); -- F1
signal BFLT_VALID               : bit; -- F1
signal SSW_80_F                 : std_logic_vector(8 downto 0); -- F1 frame view
signal FLTADR_F                 : std_logic_vector(31 downto 0); -- F1 frame view
signal SFC                      : std_logic_vector(2 downto 0);
signal SFC_RD                   : bit;
signal SFC_WR                   : bit;
signal SR_CPY                   : std_logic_vector(15 downto 0);
signal SR_RD                    : bit;
signal SR_INIT                  : bit;
signal SR_CLR_MBIT              : bit;
signal SR_WR                    : bit;
signal SR_WR_EXH                : bit;
signal SR_WR_MAIN               : bit;
signal STACK_FORMAT             : std_logic_vector(3 downto 0);
signal STACK_POS                : integer range 0 to 46;
signal STATUS_REG               : std_logic_vector(15 downto 0);
signal STATUSn_MAIN             : bit;
signal STATUSn_EXH              : bit;
signal STORE_ADR_FORMAT         : bit;
signal STORE_ABS_HI             : bit;
signal STORE_ABS_LO             : bit;
signal STORE_AEFF               : bit;
signal STORE_D16                : bit;
signal STORE_D32_LO             : bit;
signal STORE_D32_HI             : bit;
signal STORE_DISPL              : bit;
signal STORE_MEM_ADR            : bit;
signal STORE_OD_HI              : bit;
signal STORE_OD_LO              : bit;
signal STORE_IDATA_B1           : bit;
signal STORE_IDATA_B2           : bit;
signal TRAP_AERR                : bit;
signal TRAP_ILLEGAL             : bit;
signal TRAP_CODE_OPC            : TRAPTYPE_OPC;
signal TRAP_cc                  : bit;
signal TRAP_CHK                 : bit;
signal TRAP_DIVZERO             : bit;
signal TRAP_V                   : bit;
signal UNMARK                   : bit;
signal USE_APAIR                : boolean;
signal USE_DFC                  : bit;
signal USE_SFC                  : bit;
signal USE_DPAIR                : boolean;
signal USE_DREG                 : bit;
signal USP_RD                   : bit;
signal USP_WR                   : bit;
signal VBR                      : std_logic_vector(31 downto 0);
signal VBR_WR                   : bit;
signal VBR_RD                   : bit;
signal CACR                     : std_logic_vector(31 downto 0);
signal CACR_WR                  : bit;
signal CACR_RD                  : bit;
signal CAAR                     : std_logic_vector(31 downto 0);
signal CAAR_WR                  : bit;
signal CAAR_RD                  : bit;
signal WR_REQ                   : bit;
signal WR_REQ_I                 : bit;
signal ADR_NXT                  : std_logic_vector(31 downto 0); -- [PH2] Address of the request, as when the bus is free.
signal FC_NXT                   : std_logic_vector(2 downto 0); -- [PH2]
signal OP_CHAIN_LD              : bit; -- [PH2]
signal MOVEM_RA                 : bit; -- [F2] MOVEM read-ahead allowed (control unit).
signal RA_LD                    : bit; -- [F2] A MOVEM read-ahead starts on this S5 edge.
-- [IC] The cache control is part of the CPU: keep it through synthesis (see WF68K30L_ICACHE).
attribute syn_preserve : integer;
attribute syn_preserve of CACR : signal is 1;
attribute syn_preserve of CAAR : signal is 1;
attribute syn_preserve of CDIS_R : signal is 1;
begin
    IDATA_BUFFER : process
    -- This register stores the immediate data.
    begin
        wait until CLK = '1' and CLK' event;
        if STORE_IDATA_B2 = '1' then
            IBUFFER(31 downto 16) <= EXT_WORD;
        elsif STORE_IDATA_B1 = '1' then
            IBUFFER(15 downto 0) <= EXT_WORD;
        end if;
    end process IDATA_BUFFER;

    DATA_IMMEDIATE <= BIW_1 & BIW_2 when OP = ADDI and OP_SIZE = LONG else
                      BIW_1 & BIW_2 when OP = ANDI and OP_SIZE = LONG else
                      BIW_1 & BIW_2 when OP = CMPI and OP_SIZE = LONG else
                      BIW_1 & BIW_2 when OP = EORI and OP_SIZE = LONG else
                      BIW_1 & BIW_2 when OP = SUBI and OP_SIZE = LONG else
                      BIW_1 & BIW_2 when OP = ORI and OP_SIZE = LONG else
                      x"0000" & BIW_1 when OP = ANDI_TO_SR else
                      x"0000" & BIW_1 when OP = EORI_TO_SR else
                      x"0000" & BIW_1 when OP = ORI_TO_SR else
                      x"0000" & BIW_1 when OP = STOP else
                      x"0000" & BIW_1 when OP = ADDI and OP_SIZE = WORD else
                      x"0000" & BIW_1 when OP = ANDI and OP_SIZE = WORD else
                      x"0000" & BIW_1 when OP = CMPI and OP_SIZE = WORD else
                      x"0000" & BIW_1 when OP = EORI and OP_SIZE = WORD else
                      x"0000" & BIW_1 when OP = SUBI and OP_SIZE = WORD else
                      x"0000" & BIW_1 when OP = ORI and OP_SIZE = WORD else
                      x"000000" & BIW_1(7 downto 0) when OP = ANDI_TO_CCR else
                      x"000000" & BIW_1(7 downto 0) when OP = EORI_TO_CCR else
                      x"000000" & BIW_1(7 downto 0) when OP = ORI_TO_CCR else
                      x"000000" & BIW_1(7 downto 0) when OP = ADDI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = ANDI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = CMPI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = EORI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = SUBI and OP_SIZE = BYTE else
                      x"000000" & BIW_1(7 downto 0) when OP = ORI and OP_SIZE = BYTE else
                      x"00000008" when (OP = ADDQ or OP = SUBQ) and BIW_0(11 downto 9) = "000" else
                      x"000000" & "00000" & BIW_0(11 downto 9) when OP = ADDQ or OP = SUBQ else
                      x"000000" & BIW_0(7 downto 0) when OP = MOVEQ else
                      x"00000001" when OP = DBcc else
                      x"0000" & BIW_1(15 downto 0) when OP = PACK or OP = UNPK else
                      IBUFFER when OP_SIZE = LONG else x"0000" & IBUFFER(15 downto 0);

    -- Internal registers are place holders written as zeros.
    -- F1: on a latched data fault the frame takes the snapshot; every other
    -- path (address error, prefetch fault) falls back to legacy behaviour.
    SSW_80_F <= BFLT_SSW when BFLT_VALID = '1' else SSW_80;
    FLTADR_F <= BFLT_ADR when BFLT_VALID = '1' else ADR_CPY_EXH;

    DATA_EXH <= -- Exception handler multiplexing:
                SR_CPY & PC(31 downto 16) when STACK_POS = 2 else
                PC(15 downto 0) & STACK_FORMAT & "00" & IVECT_OFFS when STACK_POS = 4 else
                PC when STACK_FORMAT = x"2" and STACK_POS = 6 else
                PC when STACK_FORMAT = x"9" and STACK_POS = 6 else
                -- F28/H22: MC68030UM p8-29 -- "If an address error exception
                -- occurs ... the rerun bits alone show the cause of the
                -- exception. Depending on the state of the pipeline, either RB
                -- and RC are both set, or RC alone is set."
                -- ADJUDICATED ON REAL MC68030 SILICON, 2026-08-24. A1200 +
                -- ACA1233n, MC68030RC50C mask 1F91C lot D22881-021. An odd JMP
                -- pushed SSW $264D with caches on and $2649 with caches off:
                -- RC SET, RB CLEAR, in BOTH cache configurations. WinUAE pushes
                -- $0066 and this core pushed $0005 -- both wrong, agreeing with
                -- each other and not with the hardware. Two independent
                -- implementations agreeing is not evidence.
                -- RC alone, never RB: that is what the silicon did in both
                -- runs, and the manual explicitly permits it.
                BIW_0 & FC & FB & (RC or EX_IS_AERR) & RB & "000" & SSW_80_F when STACK_POS = 6 else -- Format A and B. (F1)
                BIW_1 & BIW_2 when STACK_POS = 8 else -- Format A and B.
                FAULT_ADR when STACK_FORMAT = x"9" and STACK_POS = 10 else -- ADR_EFF_cp.
                FLTADR_F when STACK_POS = 10 else -- F1: latched fault address.
                OUTBUFFER when STACK_POS = 14 else
                PC + "100" when STACK_POS = 20 else --STAGE B address.
                INBUFFER when STACK_POS = 24 else
                x"0000" & VERSION when STACK_POS = 28 else x"00000000";

    DATA_IN_EXH <= ALU_RESULT(31 downto 0) when BUSY_MAIN = '1' else DATA_TO_CORE; -- MOVEC handles the VBR.

    -- F11: cache control registers (MC68030UM 6.3.1, 6.3.2).
    -- No caches are implemented, but both registers are part of the 68030
    -- programming model and must be MOVEC accessible. CACR read-back mask
    -- 0x00003313: bits 31-14 and 7-5 are reserved and read as zero, and the
    -- four clear strobes CD(11), CED(10), CI(3), CEI(2) are defined by the
    -- manual as ALWAYS read as zero. The remaining bits WA(13), DBE(12),
    -- FD(9), ED(8), IBE(4), FI(1), EI(0) hold what was written. CAAR has all
    -- 32 bits implemented, so it is a plain read/write register. Reset clears
    -- CACR (manual 6.2); CAAR is not specified as reset and is left alone.
    P_CACHE_REGS: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            if RESET_CPU = '1' then
                CACR <= x"00000000";
            elsif CACR_WR = '1' then
                CACR <= DATA_IN_EXH and x"00003313";
            end if;
            --
            if CAAR_WR = '1' then
                CAAR <= DATA_IN_EXH;
            end if;
        end if;
    end process P_CACHE_REGS;

    DATA_FROM_CORE <= DATA_EXH when BUSY_EXH = '1' else
                      DR_OUT_2 when OP_WB = CAS or OP_WB = CAS2 else -- Update operands.
                      ALU_RESULT_MV when F3_BYP = '1' else -- [F3] Next MOVEM register, in the clock its write is presented.
                      ALU_RESULT(31 downto 0);

    SP_ADD_DISPL <= SP_ADD_DISPL_MAIN or SP_ADD_DISPL_EXH;

    AR_SEL_RD_1 <= "111" when BUSY_EXH = '1' else AR_SEL_RD_1_MAIN; -- ISP during exception.

    AR_IN_1 <= DATA_TO_CORE when BUSY_EXH = '1' else
               ALU_RESULT(31 downto 0) when ALU_BSY = '1' and AR_WR_1 = '1' else
               ALU_RESULT(31 downto 0) when ALU_BSY = '1' and (DFC_WR = '1' or SFC_WR = '1' or ISP_WR = '1' or MSP_WR = '1' or USP_WR = '1') else
               -- [C3] Memory-indirect JMP/JSR: the pointer read must load MEM_ADR from the bus, not ADR_EFF.
               DATA_TO_CORE when FETCH_MEM_ADR = '1' else
               ADR_EFF when OP = JMP or OP = JSR else
               DR_OUT_1 when USE_DREG = '1' else -- CAS2: Address register from data register.
               AR_OUT_1 when OP = LINK or OP = UNLK else DATA_TO_CORE; -- Default used for RTD, RTR, RTS.

    AR_IN_2 <= ALU_RESULT(63 downto 32) when OP_WB = EXG else ALU_RESULT(31 downto 0); -- Default is for UNLK.

    DR_IN_1 <= ALU_RESULT(63 downto 32) when OP_WB = EXG and ALU_BSY = '1' and DR_WR_1 = '1' and BIW_0_WB_73 = "10001" else -- Address and data registers.
               ALU_RESULT(31 downto 0);

    DR_IN_2 <= ALU_RESULT(63 downto 32);

    ALU_OP1_IN <= DATA_TO_CORE when SR_WR_EXH = '1' else
                  DATA_IMMEDIATE when OP = DBcc or OP = PACK or OP = UNPK else
                  DR_OUT_1 when (OP = ABCD or OP = SBCD) and BIW_0(3) = '0' else
                  DATA_TO_CORE when OP = ABCD or OP = SBCD else
                  DR_OUT_1 when (OP = ADD or OP = SUB) and BIW_0(8) = '1' else
                  DR_OUT_1 when (OP = AND_B or OP = EOR or  OP = OR_B) and BIW_0(8) = '1' else
                  DR_OUT_1 when (OP = ADDX or OP = SUBX) and BIW_0(3) = '0' else
                  DATA_TO_CORE when OP = ADDX or OP = SUBX else
                  DR_OUT_1 when OP = ASL or OP = ASR or OP = LSL or OP = LSR else
                  DR_OUT_1 when OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR else
                  DR_OUT_2 when OP = BFINS else -- The pattern.                  
                  DR_OUT_1 when OP = CAS or OP = CAS2 else -- Compare operand.
                  DATA_TO_CORE when OP = CMPM else
                  PC + PC_EW_OFFSET when OP = BSR or OP = JSR else
                  ADR_EFF when OP = LEA or OP = PEA else
                  AR_OUT_2 when OP = MOVE and BIW_0(5 downto 3) = "001" else -- An to any location.
                  AR_OUT_1 when OP = MOVE_USP else
                  AR_OUT_1 when OP = EXG and BIW_0(7 downto 3) = "01001" else -- Two address registers.
                  DR_OUT_1 when OP = EXG else -- Two data registers.
                  VBR when OP = MOVEC and VBR_RD = '1' else
                  CACR when OP = MOVEC and CACR_RD = '1' else
                  CAAR when OP = MOVEC and CAAR_RD = '1' else
                  x"0000000" & '0' & SFC when OP = MOVEC and SFC_RD = '1' else
                  x"0000000" & '0' & DFC when OP = MOVEC and DFC_RD = '1' else
                  AR_OUT_1 when OP = MOVEC and (ISP_RD = '1' or MSP_RD = '1' or USP_RD = '1') else
                  AR_OUT_1 when OP = MOVEC and BIW_1(15) = '1' else
                  DR_OUT_1 when OP = MOVEC else
                  DR_OUT_1 when OP = MOVEM and BIW_0(10) = '0' and ADn = '0' else -- Register to memory.
                  AR_OUT_2 when OP = MOVEM and BIW_0(10) = '0' else -- Register to memory.
                  DR_OUT_1 when OP = MOVES and BIW_1(11) = '1' and BIW_1(15) = '0' else -- Register to memory.
                  AR_OUT_2 when OP = MOVES and BIW_1(11) = '1' else -- Register to memory.
                  x"000000" & DR_OUT_1(31 downto 24) when OP = MOVEP and MOVEP_PNTR = 3 and BIW_0(7 downto 6) > "01" else
                  x"000000" & DR_OUT_1(23 downto 16) when OP = MOVEP and MOVEP_PNTR = 2 and BIW_0(7 downto 6) > "01"  else
                  x"000000" & DR_OUT_1(15 downto 8) when OP = MOVEP and MOVEP_PNTR = 1 and BIW_0(7 downto 6) > "01"  else
                  x"000000" & DR_OUT_1(7 downto 0) when OP = MOVEP and BIW_0(7 downto 6) > "01"  else
                  DATA_TO_CORE(7 downto 0) & DR_OUT_1(23 downto 0) when OP = MOVEP and MOVEP_PNTR = 3 else
                  DR_OUT_1(31 downto 24) & DATA_TO_CORE(7 downto 0) & DR_OUT_1(15 downto 0)  when OP = MOVEP and MOVEP_PNTR = 2 else
                  DR_OUT_1(31 downto 16) & DATA_TO_CORE(7 downto 0) & DR_OUT_1(7 downto 0)  when OP = MOVEP and MOVEP_PNTR = 1 else
                  DR_OUT_1(31 downto 8) & DATA_TO_CORE(7 downto 0) when OP = MOVEP else
                  x"0000" & STATUS_REG(15 downto 8) & DR_OUT_1(7 downto 0) when OP = MOVE_TO_CCR and BIW_0(5 downto 3) = "000" else
                  x"0000" & STATUS_REG(15 downto 8) & DATA_IMMEDIATE(7 downto 0) when OP = MOVE_TO_CCR and BIW_0(5 downto 0) = "111100" else
                  x"0000" & STATUS_REG(15 downto 8) & DATA_TO_CORE(7 downto 0) when OP = MOVE_TO_CCR else
                  x"0000" & DR_OUT_1(15 downto 0) when OP = MOVE_TO_SR and BIW_0(5 downto 3) = "000" else
                  x"0000" & DATA_IMMEDIATE(15 downto 0) when OP = MOVE_TO_SR and BIW_0(5 downto 0) = "111100" else
                  x"0000" & DATA_TO_CORE(15 downto 0) when OP = MOVE_TO_SR else
                  x"000000" & "000" & STATUS_REG(4 downto 0) when OP = MOVE_FROM_CCR else
                  x"0000" & STATUS_REG when OP = MOVE_FROM_SR else
                  DATA_IMMEDIATE when OP = STOP else -- Status register information.
                  DATA_IMMEDIATE when OP = MOVEQ else
                  x"00000000" when OP = NEG or OP = NEGX or OP = NBCD else
                  DATA_IMMEDIATE when OP = ADDI or OP = CMPI or OP = SUBI or OP = ANDI or OP = EORI or OP = ORI else
                  DATA_IMMEDIATE when OP = ADDQ or OP = SUBQ else
                  DATA_IMMEDIATE when OP = ANDI_TO_CCR or OP = ANDI_TO_SR else
                  DATA_IMMEDIATE when OP = EORI_TO_CCR or OP = EORI_TO_SR else 
                  DATA_IMMEDIATE when OP = ORI_TO_CCR or OP = ORI_TO_SR else 
                  DR_OUT_1 when BIW_0(5 downto 3) = "000" else
                  AR_OUT_1 when BIW_0(5 downto 3) = "001" else
                  DATA_IMMEDIATE when BIW_0(5 downto 0) = "111100" else DATA_TO_CORE;

    ALU_OP2_IN <= DR_OUT_2 when (OP = ABCD or OP = SBCD) and BIW_0(3) = '0' else
                  DATA_TO_CORE when OP = ABCD or OP = SBCD else
                  DR_OUT_2 when (OP = ADDX or OP = SUBX) and BIW_0(3) = '0' else
                  DATA_TO_CORE when OP = ADDX or OP = SUBX else
                  DR_OUT_2 when (OP = ADD or OP = CMP or OP = SUB) and BIW_0(8) = '0' else
                  DR_OUT_2 when (OP = AND_B or OP = OR_B) and BIW_0(8) = '0' else
                  AR_OUT_2 when (OP = ADDA or OP = CMPA or OP = SUBA) else
                  DR_OUT_2 when OP = EXG and  BIW_0(7 downto 3) = "01000" else -- Two data registers.
                  AR_OUT_2 when OP = EXG else
                  DR_OUT_2 when (OP = ASL or OP = ASR) and BIW_0(7 downto 6) /= "11" else -- Register shifts.
                  DR_OUT_2 when (OP = LSL or OP = LSR) and BIW_0(7 downto 6) /= "11" else -- Register shifts.
                  DR_OUT_2 when (OP = ROTL or OP = ROTR) and BIW_0(7 downto 6) /= "11" else -- Register shifts.
                  DR_OUT_2 when (OP = ROXL or OP = ROXR) and BIW_0(7 downto 6) /= "11" else -- Register shifts.
                  x"0000" & STATUS_REG when(OP = ANDI_TO_CCR or OP = ANDI_TO_SR) else
                  x"0000" & STATUS_REG when(OP = EORI_TO_CCR or OP = EORI_TO_SR) else
                  x"0000" & STATUS_REG when(OP = ORI_TO_CCR or OP = ORI_TO_SR) else 
                  DATA_TO_CORE when OP = CAS or OP = CAS2 else -- Destination operand.
                  DR_OUT_2 when (OP = CHK2 or OP = CMP2) and USE_DREG = '1' else
                  -- F60: CHK compares the DATA register Dn (BIW_0(11:9), DR port 2 per
                  -- DR_SEL_ADH_2_I) against the <ea> bound (M68000PM CHK). The original
                  -- arm fed CHK from AR port 2, whose select defaults to "000" for CHK,
                  -- so every CHK tested A0.W: no trap for a bad index when A0.W was in
                  -- range, and a spurious trap ("Subscript out of range" in HiSoft
                  -- BASIC / GEMBENCH 6) when A0.W was negative or above the bound.
                  DR_OUT_2 when OP = CHK else
                  AR_OUT_2 when OP = CHK2 or OP = CMP2 else
                  DATA_TO_CORE when OP = CMPM else
                  DR_OUT_2 when OP = DBcc or OP = SWAP else
                  DR_OUT_2 when OP = DIVS or OP = DIVU else
                  DR_OUT_2 when OP = MULS or OP = MULU else
                  DR_OUT_1 when (OP = PACK or OP = UNPK) and BIW_0(3) = '0' else -- Register direct.
                  DATA_TO_CORE when OP = PACK or OP = UNPK else
                  AR_OUT_1 when OP = LINK else
                  DR_OUT_2 when BIW_0(5 downto 3) = "000" else
                  AR_OUT_2 when BIW_0(5 downto 3) = "001" else DATA_TO_CORE;

    ALU_OP3_IN <= DATA_TO_CORE when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and BIW_0(5 downto 3) /= "000" else 
                  DATA_TO_CORE when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST) and BIW_0(5 downto 3) /= "000" else 
                  DATA_TO_CORE when OP = CAS2 or OP = CHK2 or OP = CMP2 else DR_OUT_1;

    OP_SIZE <= OP_SIZE_EXH when BUSY_EXH = '1' else OP_SIZE_MAIN;
    OP_SIZE_BUS <= OP_SIZE_WB when DATA_WR_MAIN = '1' else OP_SIZE;


    PC_OFFSET <= PC_OFFSET_OPD;
    PC_L <= PC + PC_ADR_OFFSET;

    PC_INC_EXH_I <= PC_INC_EXH when LOOP_SPLIT = false else '0'; -- Suppress for a split loop.

    ADR_MODE <= "010" when BUSY_EXH = '1' else ADR_MODE_MAIN; --(ISP)

    -- The bit field offset is byte aligned
    ADR_OFFSET <= x"00000000" when FETCH_MEM_ADR = '1' else
                  ADR_OFFSET_EXH when BUSY_EXH = '1' else
                  "000" & BF_OFFSET(31 downto 3) + ADR_OFFSET_MAIN when (OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU) and BF_OFFSET(31) = '0' else
                  "111" & BF_OFFSET(31 downto 3) + ADR_OFFSET_MAIN when OP = BFCHG or OP = BFCLR or OP = BFEXTS or OP = BFEXTU else
                  "000" & BF_OFFSET(31 downto 3) + ADR_OFFSET_MAIN when (OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST ) and BF_OFFSET(31) = '0' else
                  "111" & BF_OFFSET(31 downto 3) + ADR_OFFSET_MAIN when OP = BFFFO or OP = BFINS or OP = BFSET or OP = BFTST else
                  x"000000" & "00" & ADR_OFFSET_MAIN;

    DBcc_COND <= true when OP_WB = DBcc and ALU_RESULT(15 downto 0) = x"FFFF" else false;

    -- Take a branch if the CPU space will change:
    -- F56: the immediate S/M bits are taken straight from their sources
    -- (BIW_1 for ANDI/EORI/ORI to SR, IBUFFER for MOVE #imm,SR) instead of
    -- via DATA_IMMEDIATE. Bits 13..12 are identical either way, but the
    -- DATA_IMMEDIATE path depends on OP_SIZE, which depends on
    -- NEXT_FETCH_STATE, and BRANCH_ATN feeds NEXT_FETCH_STATE: a
    -- combinational loop (Gowin AG0100).
    BRANCH_ATN <= '1' when OP = ANDI_TO_SR and BIW_1(13) = '0' and STATUS_REG(13) = '1' else
                  '1' when OP = ANDI_TO_SR and BIW_1(12) = '0' and STATUS_REG(12) = '1' else
                  '1' when OP = EORI_TO_SR and BIW_1(13) = '1' else
                  '1' when OP = EORI_TO_SR and BIW_1(12) = '1' else
                  '1' when OP = ORI_TO_SR and BIW_1(13) = '1' and STATUS_REG(13) = '0' else
                  '1' when OP = ORI_TO_SR and BIW_1(12) = '1' and STATUS_REG(12) = '0' else
                  '1' when OP = MOVE_TO_SR and BIW_0(5 downto 3) = "000" and DR_OUT_1(13 downto 12) /= STATUS_REG(13 downto 12) else
                  '1' when OP = MOVE_TO_SR and BIW_0(5 downto 0) = "111100" and IBUFFER(13 downto 12) /= STATUS_REG(13 downto 12) else
                  '1' when OP = MOVE_TO_SR and DATA_TO_CORE(13 downto 12) /= STATUS_REG(13 downto 12) else '0';

    PF_HOLD_BI <= PF_HOLD or (MI_HOLD and not BUSY_EXH); -- [MI1] Not during exception processing.

    DATA_RD <= DATA_RD_EXH or DATA_RD_MAIN;
    DATA_WR <= DATA_WR_EXH or DATA_WR_MAIN;

    P_BUSREQ: process
    begin
        wait until CLK = '1' and CLK' event;
        -- We need these flip flops to avoid combinatorial loops:
        -- The requests are valid until the bus controller enters
        -- its START_CYCLE bus phase and asserts there the BUS_BSY.
        -- After the bus controller enters the bus access state,
        -- the requests are withdrawn.
        if BUS_BSY = '0' then
            RD_REQ_I <= DATA_RD;
            WR_REQ_I <= DATA_WR;
            OPCODE_REQ_I <= OPCODE_RD;
        elsif BUS_BSY = '1' then
            RD_REQ_I <= '0';
            WR_REQ_I <= '0';
            OPCODE_REQ_I <= '0';
        end if;
    end process P_BUSREQ;

    RD_REQ <= DATA_RD when BUS_BSY = '0' else RD_REQ_I;
    WR_REQ <= DATA_WR when BUS_BSY = '0' else WR_REQ_I;
    OPCODE_REQ <= OPCODE_RD when BUS_BSY = '0' else OPCODE_REQ_I;

    DISPLACEMENT <= DISPLACEMENT_MAIN when BUSY_MAIN = '1' else x"000000" & DISPLACEMENT_EXH;

    SR_WR <= SR_WR_EXH or SR_WR_MAIN;

    IPIPE_FLUSH <= IPIPE_FLUSH_EXH or IPIPE_FLUSH_MAIN;

    ISP_WR <= ISP_WR_MAIN or ISP_LOAD_EXH;

    AVECn_BUSIF <= AVECn when BUSY_EXH = '1' else '1';

    CPU_SPACE <= '1' when OP = BKPT and DATA_RD_MAIN = '1' else
                 CPU_SPACE_EXH when BUSY_EXH = '1' else '0';

    -- The bit field offset is bit wise.
    BF_OFFSET <= (x"000000" & "000" & BIW_1(10 downto 6)) when BIW_1(11) = '0' else DR_OUT_1;
    -- F24/H31: a register-specified width comes from read port 2 (selected by
    -- extension bits 2-0), not port 1 -- port 1 carries the offset register.
    BF_WIDTH <= '0' & BIW_1(4 downto 0) when BIW_1(4 downto 0) /= "00000" and BIW_1(5) = '0' else 
                '0' & DR_OUT_2(4 downto 0) when DR_OUT_2(4 downto 0) /= "00000" and BIW_1(5) = '1' else "100000";

    -- The BITPOS is valid for bit operations and bit field operations. For BCHG, BCLR, BSET and BTST
    -- the BITPOS spans 0 to 31 bytes, when it is in register direct mode. It is modulo 8 in memory
    -- manipulation mode. For the bit field operations in register direct mode it also in the 
    -- range 0 to 31. For bit fields in memory the value is byte wide (0 to 7) because the bit
    -- field from a memory location are loaded from byte boundaries.
    BITPOS <= BIW_1(4 downto 0) when (OP = BCHG or OP = BCLR or OP = BSET or OP = BTST) and BIW_0(8) = '0' and ADR_MODE = "000" else
              "00" & BIW_1(2 downto 0) when (OP = BCHG or OP = BCLR or OP = BSET or OP = BTST) and BIW_0(8) = '0' else
              DR_OUT_1(4 downto 0) when (OP = BCHG or OP = BCLR or OP = BSET or OP = BTST) and ADR_MODE = "000" else
              "00" & DR_OUT_1(2 downto 0) when OP = BCHG or OP = BCLR or OP = BSET or OP = BTST else
              BIW_1(10 downto 6) when BIW_1(11) = '0' and ADR_MODE = "000" else
              "00" & BIW_1(8 downto 6) when BIW_1(11) = '0' else
              DR_OUT_1(4 downto 0) when ADR_MODE = "000" else "00" & DR_OUT_1(2 downto 0);

    TRAP_AERR <= AERR when BUSY_EXH = '0' else '0'; -- No address error from the system during exception processing.

    USE_DFC <= '1' when OP_WB = MOVES and DATA_WR_MAIN = '1' else '0';
    -- F18/H25: a MOVES READ takes its data cycle in the EXECUTE phase,
    -- before writeback, so OP_WB still names the PREVIOUS instruction and
    -- USE_SFC never asserted -- the read ran with the default supervisor
    -- code instead of SFC. Measured: SFC=1 (read back), MOVES read faulted
    -- with FC=5. The write direction is correct because a MOVES WRITE does
    -- happen at writeback, which is why USE_DFC works. This mirrors the
    -- core's own MOVEC convention: reads qualify on OP, writes on OP_WB_I.
    -- MiNT reads user space with MOVES, so a supervisor FC here bypasses
    -- user-space translation entirely under memory protection.
    USE_SFC <= '1' when OP = MOVES and DATA_RD_MAIN = '1' else '0';

    PC_LOAD <= PC_LOAD_EXH or PC_LOAD_MAIN;

    RESET_IN <= not RESET_INn;
    IPL <= not IPLn;

    CLK_F <= CLK_N when CLK_N_EXT /= 0 else not CLK; -- [F58]
    
    REFILL_STATUS: process
    -- This tiny logic provides signal transition on the negative
    -- clock edge.
    begin
        wait until CLK_F = '1' and CLK_F' event; -- [F58] was the falling edge of CLK
        if (STATUSn_EXH and STATUSn_MAIN) = '1' then
            STATUSn <= '1';
        else
            STATUSn <= '0';
        end if;
        REFILLn <= REFILLn_EXH;
    end process REFILL_STATUS;

    SBIT <= STATUS_REG(13);
    OPC_FC <= "110" when SBIT = '1' else "010"; -- [F62]

    ADR_L <= x"000000" & "000" & BIW_0(2 downto 0) & "00" when BKPT_CYCLE = '1' else
             x"FFFFFFF" & IRQ_PEND & '1' when CPU_SPACE_EXH = '1' else
             ADR_EFF_WB when DATA_WR_MAIN = '1' else ADR_EFF; -- Exception handler uses ADR_EFF for read and write access.

    -- FalconFPGA DIAG: PC_LOAD_EXH loads the handler address from the vector: IVECT_OFFS, the stacked SR
    -- copy and the PC (not yet reloaded) describe the exception being taken; A5 at that moment.
    DBG_EXC_STB <= '1' when PC_LOAD_EXH = '1' else '0';
    DBG_EXC <= DBG_EXC_STB & IVECT_OFFS(9 downto 2) & SR_CPY & PC & DBG_A5_I & BIW_0; -- BIW_0 = opcode word (IRD) at handler load
    DBG_ADR <= ADR_LATCH(23 downto 16) & ADR_P(23 downto 16) & PC_L(23 downto 16) & ADR_L(23 downto 16); -- FalconFPGA DIAG
    ADR_NXT <= ADR_L when DATA_RD = '1' or DATA_WR = '1' else PC_L; -- [PH2]
    ADR_P <= ADR_LATCH when BUS_BSY = '1' else ADR_NXT;

    P_ADR_LATCHES: process
    -- This register stores the address during a running bus cycle.
    -- The signals RD_DATA, WR_DATA and RD_OPCODE may change during
    -- the cycle. Opcode read is lower prioritized.
    -- FAULT_ADR latches the faulty address for stacking it via
    -- the exception handler.
    -- The FC_LATCH register stores the function code during a running
    -- bus cycle. 
    begin
        wait until CLK = '1' and CLK' event;
        if BUS_BSY = '0' or OP_CHAIN_LD = '1' then -- [PH2] also on the S5 edge of a chained operand cycle
            ADR_LATCH <= ADR_NXT;
            FC_LATCH <= FC_NXT;
        elsif RA_LD = '1' then -- [F2] MOVEM read-ahead: the next register's operand follows this one (same FC).
            case OP_SIZE_BUS is
                when LONG => ADR_LATCH <= ADR_LATCH + x"4";
                when WORD => ADR_LATCH <= ADR_LATCH + x"2";
                when others => ADR_LATCH <= ADR_LATCH + x"1";
            end case;
        elsif BERRn = '0' then
            FAULT_ADR <= ADR_LATCH;
        end if;
    end process P_ADR_LATCHES;

    FC_I <= FC_LATCH when BUS_BSY = '1' else FC_NXT;
    FC_NXT <= SFC when USE_SFC = '1' else
            DFC when USE_DFC = '1' else
            "111" when (DATA_RD = '1' or DATA_WR = '1') and CPU_SPACE = '1' else
            "101" when (DATA_RD = '1' or DATA_WR = '1') and SBIT = '1' else
            "001" when DATA_RD = '1' or DATA_WR = '1' else
            "110" when OPCODE_RD = '1' and SBIT = '1' else "010"; -- Default is OPCODE_RD and SBIT = '0'.

    -- [IC] 68030 instruction cache (MC68030UM ch. 6, docs/ICACHE_DESIGN.md). The prefetch queue in the bus
    -- interface looks up and fills it. CACR CI (bit 3) clears every entry, CEI (bit 2) the long word at
    -- CAAR 7:2; both are MOVEC write strobes and read as zero (P_CACHE_REGS mask).
    IC_CI <= '1' when CACR_WR = '1' and DATA_IN_EXH(3) = '1' else '0';
    IC_CEI <= '1' when CACR_WR = '1' and DATA_IN_EXH(2) = '1' else '0';

    P_CDIS: process(CLK) -- [IC] CDIS is an asynchronous pin.
    begin
        if CLK = '1' and CLK' event then
            CDIS_R <= not CDISn;
        end if;
    end process P_CDIS;

    I_ICACHE: WF68K30L_ICACHE
        port map(
            CLK       => CLK,
            RESET     => RESET_CPU,
            EI        => CACR(0),
            FI        => CACR(1),
            CDIS      => CDIS_R,
            CLR_ALL   => IC_CI,
            CLR_ENT   => IC_CEI,
            CLR_IDX   => CAAR(7 downto 2),
            LK_ADR    => IC_LK_ADR,
            LK_FC2    => IC_LK_FC2,
            HIT       => IC_HIT,
            HIT_DATA  => IC_HIT_DATA,
            FILL      => IC_FILL,
            FILL_MIS  => IC_FILL_MIS,
            FILL_OK   => IC_FILL_OK,
            BREAK     => IC_BREAK,
            FILL_ADR  => IC_FILL_ADR,
            FILL_FC2  => IC_FILL_FC2,
            FILL_DATA => IC_FILL_DATA
        );

    -- [DC] 68030 data cache (MC68030UM 6.1.2, docs/DCACHE_DESIGN.md). CACR ED (8) enables, FD (9) freezes,
    -- WA (13) selects write allocation; CD (11) clears every entry, CED (10) the long word at CAAR 7:2 (MOVEC
    -- write strobes, read as zero). DBE (12) is stored but has no effect (no burst). CDIS disables both caches.
    DC_CD <= '1' when CACR_WR = '1' and DATA_IN_EXH(11) = '1' else '0';
    DC_CED <= '1' when CACR_WR = '1' and DATA_IN_EXH(10) = '1' else '0';
    DC_FILL_EN <= CACR(8) and not CACR(9) and not CDIS_R;
    DC_ON <= CACR(8) and not CDIS_R;

    I_DCACHE: WF68K30L_DCACHE
        port map(
            CLK       => CLK,
            RESET     => RESET_CPU,
            ED        => CACR(8),
            FD        => CACR(9),
            WA        => CACR(13),
            CDIS      => CDIS_R,
            CLR_ALL   => DC_CD,
            CLR_ENT   => DC_CED,
            CLR_IDX   => CAAR(7 downto 2),
            LK_ADR    => DC_LK_ADR,
            LK_FC     => DC_LK_FC,
            LK_SZ     => DC_LK_SZ,
            LK_HIT    => DC_HIT,
            LK_DATA   => DC_HIT_DATA,
            WR_GO     => DC_WR_GO,
            WR_ADR    => DC_WR_ADR,
            WR_FC     => DC_WR_FC,
            WR_SZ     => DC_WR_SZ,
            WR_DATA   => DC_WR_DATA,
            FL_GO     => DC_FL_GO,
            FL_A0     => DC_FL_A0,
            FL_FC     => DC_FL_FC,
            FL_U1     => DC_FL_U1,
            FL_D0     => DC_FL_D0,
            FL_D1     => DC_FL_D1,
            FL_OK0    => DC_FL_OK0,
            FL_OK1    => DC_FL_OK1,
            FL_BE0    => DC_FL_BE0,
            FL_BE1    => DC_FL_BE1
        );

    CBREQn <= '1'; -- [IC] No burst fill until a burst-capable fast RAM exists (CACR IBE has no effect).
    CIOUTn <= '1'; -- [IC] No PMMU, so no page or TT register can ask for cache inhibit.

    -- The core talks to the bus interface for data; the bus interface serves read hits from the data cache.
    -- Instruction words come from the prefetch queue, which the instruction cache feeds.
    IC_BUS_REQ     <= OPCODE_REQ;
    OPCODE_RDY     <= BUS_OPCODE_RDY;
    OPCODE_TO_CORE <= BUS_OPCODE_WORD;
    DC_BUS_REQ     <= RD_REQ;
    DATA_RDY       <= BUS_DATA_RDY;
    DATA_TO_CORE   <= BUS_DATA_WORD;


    I_ADDRESSREGISTERS: WF68K30L_ADDRESS_REGISTERS
        port map(
            CLK                     => CLK,
            RESET                   => RESET_CPU,
            AR_IN_1                 => AR_IN_1,
            AR_IN_2                 => AR_IN_2,
            AR_OUT_1                => AR_OUT_1,
            AR_OUT_2                => AR_OUT_2,
            INDEX_IN                => DR_OUT_1, -- From data register section.
            PC                      => PC,
            FETCH_MEM_ADR           => FETCH_MEM_ADR,
            STORE_ADR_FORMAT        => STORE_ADR_FORMAT,
            STORE_ABS_HI            => STORE_ABS_HI,
            STORE_ABS_LO            => STORE_ABS_LO,
            STORE_D16               => STORE_D16,
            STORE_D32_LO            => STORE_D32_LO,
            STORE_D32_HI            => STORE_D32_HI,
            STORE_DISPL             => STORE_DISPL,
            STORE_MEM_ADR           => STORE_MEM_ADR,
            STORE_OD_HI             => STORE_OD_HI,
            STORE_OD_LO             => STORE_OD_LO,
            STORE_AEFF              => STORE_AEFF,
            OP_SIZE                 => OP_SIZE,
            AR_MARK_USED            => AR_MARK_USED,
            USE_APAIR               => USE_APAIR,
            AR_IN_USE               => AR_IN_USE,
            AR_SEL_RD_1             => AR_SEL_RD_1,
            AR_SEL_RD_2             => AR_SEL_RD_2,
            AR_SEL_WR_1             => AR_SEL_WR_1,
            AR_SEL_WR_2             => AR_SEL_WR_2,
            ADR_OFFSET              => ADR_OFFSET, -- Byte aligned.
            ADR_MARK_USED           => ADR_MARK_USED,
            ADR_FAST                => ADR_FAST,
            ADR_IN_USE              => ADR_IN_USE,
            ADR_MODE                => ADR_MODE,
            AMODE_SEL               => AMODE_SEL,
            USE_DREG                => USE_DREG,
            ADR_EFF                 => ADR_EFF,
            ADR_EFF_WB              => ADR_EFF_WB,
            DFC                     => DFC,
            DFC_WR                  => DFC_WR,
            SFC                     => SFC,
            SFC_WR                  => SFC_WR,
            ISP_DEC                 => ISP_DEC,
            ISP_RD                  => ISP_RD,
            ISP_WR                  => ISP_WR,
            MSP_RD                  => MSP_RD,
            MSP_WR                  => MSP_WR,
            USP_RD                  => USP_RD,
            USP_WR                  => USP_WR,
            AR_DEC                  => AR_DEC,
            AR_INC                  => AR_INC,
            AR_WR_1                 => AR_WR_1,
            AR_WR_2                 => AR_WR_2,
            UNMARK                  => UNMARK,
            EXT_WORD                => EXT_WORD,
            MBIT                    => STATUS_REG(12),
            SBIT                    => SBIT,
            SP_ADD_DISPL            => SP_ADD_DISPL,
            RESTORE_ISP_PC          => RESTORE_ISP_PC,
            DISPLACEMENT            => DISPLACEMENT,
            PC_ADD_DISPL            => PC_ADD_DISPL,
            PC_EW_OFFSET            => PC_EW_OFFSET,
            PC_INC                  => PC_INC,
            PC_LOAD                 => PC_LOAD,
            PC_RESTORE              => PC_RESTORE_EXH,
            PC_OFFSET               => PC_OFFSET,
            DBG_A5                  => DBG_A5_I
        );

    I_ALU: WF68K30L_ALU
        port map(
            CLK                     => CLK,
            RESET                   => RESET_CPU,
            LOAD_OP2                => ALU_LOAD_OP2,
            LOAD_OP3                => ALU_LOAD_OP3,
            LOAD_OP1                => ALU_LOAD_OP1,
            OP1_IN                  => ALU_OP1_IN,
            OP2_IN                  => ALU_OP2_IN,
            OP3_IN                  => ALU_OP3_IN,
            BF_OFFSET_IN            => BF_OFFSET,
            BF_WIDTH_IN             => BF_WIDTH,
            BITPOS_IN               => BITPOS,
            BF_BYTES_IN             => BF_BYTES_CTL,
            RESULT                  => ALU_RESULT,
            RESULT_MV               => ALU_RESULT_MV,
            ADR_MODE_IN             => ADR_MODE,
            USE_DREG                => USE_DREG,
            HILOn                   => HILOn,
            OP_SIZE_IN              => OP_SIZE,
            OP_IN                   => OP,
            OP_WB                   => OP_WB,
            BIW_0_IN                => BIW_0(11 downto 0),
            BIW_1_IN                => BIW_1,
            SR_WR                   => SR_WR,
            SR_INIT                 => SR_INIT,
            SR_CLR_MBIT             => SR_CLR_MBIT,
            CC_UPDT                 => CC_UPDT,
            STATUS_REG_OUT	        => STATUS_REG,
            ALU_COND                => ALU_COND,
            ALU_INIT                => ALU_INIT,
            ALU_BSY                 => ALU_BSY,
            ALU_REQ                 => ALU_REQ,
            ALU_ACK                 => ALU_ACK,
            IRQ_PEND                => IRQ_PEND,
            TRAP_CHK                => TRAP_CHK,
            TRAP_DIVZERO            => TRAP_DIVZERO
        );

    I_BUS_IF: WF68K30L_BUS_INTERFACE
        generic map(PREFETCH_Q => PREFETCH_Q_EN, FAST_HANDOFF => FAST_HANDOFF) -- [F62] [F65]
        port map(
            CLK                 => CLK,
            CLK_F               => CLK_F, -- [F58]

            ADR_IN_P            => ADR_P,
            ADR_OUT_P           => ADR_OUT,

            FC_IN               => FC_I,
            FC_OUT              => FC_OUT,

            DATA_PORT_IN        => DATA_IN,
            DATA_PORT_OUT       => DATA_OUT,
            DATA_FROM_CORE      => DATA_FROM_CORE,
            DATA_TO_CORE        => BUS_DATA_WORD,
            OPCODE_TO_CORE      => BUS_OPCODE_WORD,

            DATA_PORT_EN        => DATA_EN,
            BUS_EN              => BUS_EN,

            SIZE                => SIZE,
            OP_SIZE             => OP_SIZE_BUS,

            RD_REQ_IN           => DC_BUS_REQ,
            WR_REQ_IN           => WR_REQ,
            DATA_RDY            => BUS_DATA_RDY,
            DATA_VALID          => DATA_VALID,
            WR_EARLY            => WR_EARLY,
            WR_TAKE             => WR_TAKE,
            OPCODE_REQ          => IC_BUS_REQ,
            OPCODE_RDY          => BUS_OPCODE_RDY,
            OPCODE_VALID        => OPCODE_VALID,
            RMC                 => RMC,
            BUSY_EXH            => BUSY_EXH,
            OPC_RD              => OPCODE_RD, -- [F62]
            OPC_ADR             => PC_L,
            OPC_FC              => OPC_FC,
            OPC_DISMISS         => OPC_DISMISS, -- [F62c]
            PF_HOLD             => PF_HOLD_BI, -- [PFCOF] [MI1]
            Q_STREAM            => Q_STREAM, -- [PFCOF2]
            Q_COUNT             => Q_COUNT,
            OP_RD               => DATA_RD, -- [F65] not masked by BUS_BSY
            OP_WR               => DATA_WR, -- [F65]
            ADR_NXT             => ADR_NXT, -- [PH2]
            FC_NXT              => FC_NXT, -- [PH2]
            ADR_LAT             => ADR_LATCH, -- [PH2-FMAX]
            FC_LAT              => FC_LATCH, -- [PH2-FMAX]
            OP_CHAIN_LD         => OP_CHAIN_LD, -- [PH2]
            RA_MORE             => MOVEM_RA, -- [F2]
            RA_LD               => RA_LD, -- [F2]
            IC_LK_ADR           => IC_LK_ADR, -- [IC]
            IC_LK_FC2           => IC_LK_FC2,
            IC_HIT              => IC_HIT,
            IC_HIT_DATA         => IC_HIT_DATA,
            IC_FILL             => IC_FILL,
            IC_FILL_MIS         => IC_FILL_MIS,
            IC_FILL_OK          => IC_FILL_OK,
            IC_BREAK            => IC_BREAK,
            IC_FILL_ADR         => IC_FILL_ADR,
            IC_FILL_FC2         => IC_FILL_FC2,
            IC_FILL_DATA        => IC_FILL_DATA,
            CIINn               => CIINn,
            DC_FILL_EN          => DC_FILL_EN, -- [DC]
            DC_ON               => DC_ON,
            DC_LK_ADR           => DC_LK_ADR,
            DC_LK_FC            => DC_LK_FC,
            DC_LK_SZ            => DC_LK_SZ,
            DC_HIT              => DC_HIT,
            DC_HIT_DATA         => DC_HIT_DATA,
            DC_WR_GO            => DC_WR_GO,
            DC_WR_ADR           => DC_WR_ADR,
            DC_WR_FC            => DC_WR_FC,
            DC_WR_SZ            => DC_WR_SZ,
            DC_WR_DATA          => DC_WR_DATA,
            DC_FL_GO            => DC_FL_GO,
            DC_FL_A0            => DC_FL_A0,
            DC_FL_FC            => DC_FL_FC,
            DC_FL_U1            => DC_FL_U1,
            DC_FL_D0            => DC_FL_D0,
            DC_FL_D1            => DC_FL_D1,
            DC_FL_OK0           => DC_FL_OK0,
            DC_FL_OK1           => DC_FL_OK1,
            DC_FL_BE0           => DC_FL_BE0,
            DC_FL_BE1           => DC_FL_BE1,
            SSW_80              => SSW_80,
            BFLT_SSW            => BFLT_SSW,
            BFLT_ADR            => BFLT_ADR,
            BFLT_VALID          => BFLT_VALID,
            INBUFFER            => INBUFFER,
            OUTBUFFER           => OUTBUFFER,

            DSACKn              => DSACKn,
            ASn                 => ASn,
            DSn                 => DSn,
            RWn                 => RWn,
            RMCn                => RMCn,
            ECSn                => ECSn,
            OCSn                => OCSn,
            DBENn               => DBENn,

            STERMn              => STERMn,

            BRn                 => BRn,
            BGACKn              => BGACKn,
            BGn                 => BGn,

            RESET_STRB          => RESET_STRB,
            RESET_IN            => RESET_IN,
            RESET_OUT           => RESET_OUT,
            RESET_CPU           => RESET_CPU,

            AVECn               => AVECn_BUSIF,
            HALTn               => HALT_INn,
            BERRn               => BERRn,
            AERR                => AERR,

            BUS_BSY             => BUS_BSY
        );

    I_CONTROL: WF68K30L_CONTROL
        generic map(NO_PIPELINE     => NO_PIPELINE)
        port map(
            CLK                     => CLK,
            RESET_CPU               => RESET_CPU,
            BUSY                    => BUSY_MAIN,
            BUSY_EXH                => BUSY_EXH,
            EXH_REQ                 => EXH_REQ,
            INT_TRIG                => INT_TRIG,
            OW_REQ                  => OW_REQ_MAIN,
            OW_VALID                => OW_VALID,
            EW_REQ                  => EW_REQ_MAIN,
            EW_ACK                  => EW_ACK,
            OPD_ACK                 => OPD_ACK_MAIN,
            ADR_MARK_USED           => ADR_MARK_USED,
            ADR_IN_USE              => ADR_IN_USE,
            ADR_OFFSET              => ADR_OFFSET_MAIN,
            DATA_RD                 => DATA_RD_MAIN,
            DATA_WR                 => DATA_WR_MAIN,
            DATA_RDY                => DATA_RDY,
            DATA_VALID              => DATA_VALID,
            RMC                     => RMC,
            MI_HOLD                 => MI_HOLD,
            FETCH_MEM_ADR           => FETCH_MEM_ADR,
            LOAD_OP1                => ALU_LOAD_OP1,
            LOAD_OP2                => ALU_LOAD_OP2,
            LOAD_OP3                => ALU_LOAD_OP3,
            STORE_ADR_FORMAT        => STORE_ADR_FORMAT,
            STORE_ABS_HI            => STORE_ABS_HI,
            STORE_ABS_LO            => STORE_ABS_LO,
            STORE_D16               => STORE_D16,
            STORE_D32_LO            => STORE_D32_LO,
            STORE_D32_HI            => STORE_D32_HI,
            STORE_DISPL             => STORE_DISPL,
            STORE_MEM_ADR           => STORE_MEM_ADR,
            STORE_OD_HI             => STORE_OD_HI,
            STORE_OD_LO             => STORE_OD_LO,
            STORE_AEFF              => STORE_AEFF,
            STORE_IDATA_B1          => STORE_IDATA_B1,
            STORE_IDATA_B2          => STORE_IDATA_B2,
            OP                      => OP,
            OP_SIZE                 => OP_SIZE_MAIN,
            BIW_0                   => BIW_0(13 downto 0),
            BIW_1                   => BIW_1,
            BIW_2                   => BIW_2,
            EXT_WORD                => EXT_WORD,
            ADR_MODE                => ADR_MODE_MAIN,
            AMODE_SEL               => AMODE_SEL,
            USE_DREG                => USE_DREG,
            HILOn                   => HILOn,
            BF_BYTES_OUT            => BF_BYTES_CTL,
            OP_WB					=> OP_WB,
            OP_SIZE_WB              => OP_SIZE_WB,
            BIW_0_WB_73             => BIW_0_WB_73,
            AR_MARK_USED            => AR_MARK_USED,
            AR_IN_USE               => AR_IN_USE,
            AR_SEL_RD_1             => AR_SEL_RD_1_MAIN,
            AR_SEL_RD_2             => AR_SEL_RD_2,
            AR_SEL_WR_1             => AR_SEL_WR_1,
            AR_SEL_WR_2             => AR_SEL_WR_2,
            AR_INC                  => AR_INC,
            AR_DEC                  => AR_DEC,
            AR_WR_1                 => AR_WR_1,
            AR_WR_2                 => AR_WR_2,
            DR_MARK_USED            => DR_MARK_USED,
            USE_APAIR               => USE_APAIR,
            USE_DPAIR               => USE_DPAIR,
            DR_IN_USE               => DR_IN_USE,
            DR_SEL_WR_1             => DR_SEL_WR_1,
            DR_SEL_WR_2             => DR_SEL_WR_2,
            DR_SEL_RD_1             => DR_SEL_RD_1,
            DR_SEL_RD_2             => DR_SEL_RD_2,
            DR_SEL_ADH_2            => DR_SEL_ADH_2,
            DR_SEL_ADH_3            => DR_SEL_ADH_3,
            DR_WR_1                 => DR_WR_1,
            DR_WR_2                 => DR_WR_2,
            UNMARK                  => UNMARK,
            DISPLACEMENT            => DISPLACEMENT_MAIN,
            PC_ADD_DISPL            => PC_ADD_DISPL,
            PC_LOAD                 => PC_LOAD_MAIN,
            PC_INC_EXH              => PC_INC_EXH,
            SP_ADD_DISPL            => SP_ADD_DISPL_MAIN,
            DFC_RD                  => DFC_RD,
            DFC_WR                  => DFC_WR,
            SFC_RD                  => SFC_RD,
            SFC_WR                  => SFC_WR,
            VBR_RD                  => VBR_RD,
            VBR_WR                  => VBR_WR,
            CACR_RD                 => CACR_RD,
            CACR_WR                 => CACR_WR,
            CAAR_RD                 => CAAR_RD,
            CAAR_WR                 => CAAR_WR,
            ISP_RD                  => ISP_RD,
            ISP_WR                  => ISP_WR_MAIN,
            MSP_RD                  => MSP_RD,
            MSP_WR                  => MSP_WR,
            USP_RD                  => USP_RD,
            USP_WR                  => USP_WR,
            IPIPE_FLUSH             => IPIPE_FLUSH_MAIN,
            COF_PEND                => COF_PEND, -- [PFCOF]
            ALU_INIT                => ALU_INIT,
            ALU_BSY                 => ALU_BSY,
            ALU_REQ                 => ALU_REQ,
            ALU_ACK                 => ALU_ACK,
            WR_EARLY                => WR_EARLY,
            WR_TAKE                 => WR_TAKE,
            F3_BYP                  => F3_BYP,
            ADR_FAST                => ADR_FAST,
            BKPT_CYCLE              => BKPT_CYCLE,
            BKPT_INSERT             => BKPT_INSERT,
            LOOP_BSY                => LOOP_BSY,
            LOOP_SPLIT              => LOOP_SPLIT,
            LOOP_EXIT               => LOOP_EXIT,
            BF_OFFSET               => BF_OFFSET(2 downto 0),
            BF_WIDTH                => BF_WIDTH,
            SR_WR                   => SR_WR_MAIN,
            MOVEM_ADn               => ADn,
            MOVEP_PNTR              => MOVEP_PNTR,
            CC_UPDT                 => CC_UPDT,
            TRACE_MODE              => STATUS_REG(15 downto 14),
            VBIT                    => STATUS_REG(1),
            ALU_COND                => ALU_COND,
            DBcc_COND               => DBcc_COND,
            BRANCH_ATN              => BRANCH_ATN,
            RESET_STRB              => RESET_STRB,
            BERR                    => BERR_MAIN,
            BERR_IBOUND             => BERR_IBOUND,
            MOVEM_RA                => MOVEM_RA, -- [F2]
            STATUSn                 => STATUSn_MAIN,
            EX_TRACE                => EX_TRACE,
            TRAP_cc                 => TRAP_cc,
            TRAP_V                  => TRAP_V,
            TRAP_ILLEGAL            => TRAP_ILLEGAL
        );

    I_DATA_REGISTERS: WF68K30L_DATA_REGISTERS
        port map(
            CLK                     => CLK,
            RESET                   => RESET_CPU,
            DR_IN_1                 => DR_IN_1,
            DR_IN_2                 => DR_IN_2,
            DR_OUT_2                => DR_OUT_2,
            DR_OUT_1                => DR_OUT_1,
            DR_SEL_WR_1             => DR_SEL_WR_1,
            DR_SEL_WR_2             => DR_SEL_WR_2,
            DR_SEL_RD_1             => DR_SEL_RD_1,
            DR_SEL_RD_2             => DR_SEL_RD_2,
            DR_SEL_ADH_2            => DR_SEL_ADH_2,
            DR_SEL_ADH_3            => DR_SEL_ADH_3,
            DR_WR_1                 => DR_WR_1,
            DR_WR_2                 => DR_WR_2,
            DR_MARK_USED            => DR_MARK_USED,
            USE_DPAIR               => USE_DPAIR,
            DR_IN_USE               => DR_IN_USE,
            UNMARK                  => UNMARK,
            OP_SIZE                 => OP_SIZE_WB
        );

    I_EXC_HANDLER: WF68K30L_EXCEPTION_HANDLER
        generic map(VERSION         => VERSION)
        port map(   
            CLK                     => CLK,
            CLK_F                   => CLK_F, -- [F58]

            RESET                   => RESET_CPU,
            BUSY_MAIN               => BUSY_MAIN,
            BUSY_OPD                => BUSY_OPD,
    
            EXH_REQ                 => EXH_REQ,
            BUSY_EXH                => BUSY_EXH,

            ADR_IN                  => ADR_EFF,
            ADR_CPY                 => ADR_CPY_EXH,
            ADR_OFFSET              => ADR_OFFSET_EXH,
            CPU_SPACE               => CPU_SPACE_EXH,
    
            DATA_0                  => DATA_TO_CORE(0),
            DATA_RD                 => DATA_RD_EXH,
            DATA_WR                 => DATA_WR_EXH,
            DATA_IN                 => DATA_IN_EXH,
    
            OP_SIZE                 => OP_SIZE_EXH,
            DATA_RDY                => DATA_RDY,
            DATA_VALID              => DATA_VALID,
    
            OPCODE_RDY              => OPCODE_RDY,
            OPD_ACK                 => OPD_ACK_MAIN,
            OW_VALID                => OW_VALID,
    
            STATUS_REG_IN           => STATUS_REG,
            SR_CPY                  => SR_CPY,
            SR_INIT                 => SR_INIT,
            SR_CLR_MBIT             => SR_CLR_MBIT,
    
            SR_WR                   => SR_WR_EXH,
            ISP_DEC                 => ISP_DEC,
            ISP_LOAD                => ISP_LOAD_EXH,
            PC_LOAD                 => PC_LOAD_EXH,
            PC_INC                  => PC_INC_EXH,
            PC_RESTORE              => PC_RESTORE_EXH,
    
            STACK_FORMAT            => STACK_FORMAT,
            STACK_POS               => STACK_POS,
                
            SP_ADD_DISPL            => SP_ADD_DISPL_EXH,
            DISPLACEMENT            => DISPLACEMENT_EXH,
            IPIPE_FILL              => IPIPE_FILL,
            IPIPE_FLUSH             => IPIPE_FLUSH_EXH,
            REFILLn                 => REFILLn_EXH,
            RESTORE_ISP_PC          => RESTORE_ISP_PC,
    
            HALT_OUTn               => HALT_OUTn,
            STATUSn                 => STATUSn_EXH,
    
            INT_TRIG                => INT_TRIG,
            IRQ_IN                  => IPL,
            IRQ_PEND                => IRQ_PEND,
            AVECn                   => AVECn,
            IPENDn                  => IPENDn,
            IVECT_OFFS              => IVECT_OFFS,

            TRAP_AERR               => TRAP_AERR,
            TRAP_BERR               => BERR_MAIN,
            BERR_IBOUND             => BERR_IBOUND,
            TRAP_CHK                => TRAP_CHK,
            TRAP_DIVZERO            => TRAP_DIVZERO,
            TRAP_ILLEGAL            => TRAP_ILLEGAL,
            TRAP_CODE_OPC           => TRAP_CODE_OPC,
            TRAP_VECTOR             => BIW_0(3 downto 0),
            TRAP_cc                 => TRAP_cc,
            TRAP_V                  => TRAP_V,
            EX_TRACE_IN             => EX_TRACE,
            VBR_WR                  => VBR_WR,
            VBR                     => VBR,
            EX_IS_AERR              => EX_IS_AERR
        );

    I_OPCODE_DECODER: WF68K30L_OPCODE_DECODER
        generic map(NO_LOOP         => NO_LOOP)
        port map(
            CLK                     => CLK,

            OW_REQ_MAIN             => OW_REQ_MAIN,
            EW_REQ_MAIN             => EW_REQ_MAIN,

            EXH_REQ                 => EXH_REQ,
            BUSY_EXH                => BUSY_EXH,
            BUSY_MAIN               => BUSY_MAIN,
            BUSY_OPD                => BUSY_OPD,

            BKPT_INSERT             => BKPT_INSERT,
            BKPT_DATA               => DATA_TO_CORE(15 downto 0),

            LOOP_EXIT               => LOOP_EXIT,
            LOOP_BSY                => LOOP_BSY,

            OPD_ACK_MAIN            => OPD_ACK_MAIN,
            EW_ACK                  => EW_ACK,

            PC_INC                  => PC_INC,
            PC_INC_EXH              => PC_INC_EXH_I,
            PC_ADR_OFFSET           => PC_ADR_OFFSET,
            PC_EW_OFFSET            => PC_EW_OFFSET,
            PC_OFFSET               => PC_OFFSET_OPD,

            OPCODE_RD               => OPCODE_RD,
            OPCODE_RDY              => OPCODE_RDY,
            OPCODE_VALID            => OPCODE_VALID,
            OPCODE_DATA             => OPCODE_TO_CORE,

            IPIPE_FILL              => IPIPE_FILL,
            IPIPE_FLUSH             => IPIPE_FLUSH,
            OPCODE_DISMISS          => OPC_DISMISS, -- [F62c]
            COF_PEND                => COF_PEND, -- [PFCOF]
            PF_HOLD                 => PF_HOLD, -- [PFCOF]
            Q_STREAM                => Q_STREAM, -- [PFCOF2]
            Q_COUNT                 => Q_COUNT,

            -- Fault logic:
            OW_VALID                => OW_VALID,
            RC                      => RC,
            RB                      => RB,
            FC                      => FC,
            FB                      => FB,

            -- Trap logic:
            SBIT                    => SBIT,
            TRAP_CODE               => TRAP_CODE_OPC,

            -- System control:
            OP                      => OP,
            BIW_0                   => BIW_0,
            BIW_1                   => BIW_1,
            BIW_2                   => BIW_2,
            EXT_WORD                => EXT_WORD
        );
end STRUCTURE;
