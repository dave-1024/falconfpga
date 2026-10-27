------------------------------------------------------------------------
----                                                                ----
---- WF68K30L IP Core: this is the bus interface.                   ----
----                                                                ----
---- Description:                                                   ----
---- This module is a 68030 compatible bus controller featuring     ----
---- all of the 68030 bus interface functionality.                  ----
----                                                                ----
---- Bus cycle operation:                                           ----
---- A bus cycle is invoked by either asserting RD_REQ, WR_REQ or   ----
---- OPCODE_REQ. Data is provided immediately or after the          ----
---- respective bus cycle has finished. The RD_REQ, WR_REQ or       ----
---- OPCODE_REQ signals should stay asserted until the respective   ----
---- _RDY signal from the bus controller indicates, that the data   ----
---- is available. These _RDY signals are strobes. If more than one ----
---- read or write request are asserted the same time, RD_REQ is    ----
---- prioritized over WR_REQ and OPCODE_REQ has lowest priority.    ----
---- For more information of the signal functionality of the bus    ----
---- controller entity see also the comments below.                 ----
----                                                                ----
---- Remarks:                                                       ----
----                                                                ----
---- Bus arbitration topics:                                        ----
---- Additionally to the single wire and the three wire bus arbi-   ----
---- tration as described in the 68030 hardware manual, the bus     ----
---- controller  also features the two wire arbitration as des-     ----
---- cribed in the documentation of the 68020 processor.            ----
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
-- Revision 2K18A 20180620 WF
--   Suppress bus faults during RESET instruction.
--   Optimized ASn and DSn timing for synchronous RAM.
--   DATA_PORT_EN timing optimization.
--   BUS_EN is now active except during arbitration.
--   Rearanged the DATA_RDY vs. BUS_FLT logic.
--   Opted out START_READ and CHK_RD.
--   Fixed the faulty bus arbitration logic.
--   Rearranged address error handling.
-- [F65] FalconFPGA (dave-1024, 2026-10-09): optional prefetch-to-prefetch
--   handoff. With generic FAST_HANDOFF = 1 a completing queue prefetch whose
--   stream is still valid rolls S5 straight into S0 of the next long, the
--   way a 68030 starts the next cycle when a request is pending. Default 0
--   keeps the IDLE -> START_CYCLE path. Operand cycles are not chained here.
-- [PH2] FalconFPGA (dave-1024, 2026-10-16): CPU rework phase 2. A completing
--   queue prefetch with an operand request already waiting rolls S5 straight
--   into S0 of that operand cycle (MC68030UM 7.3: the next cycle starts after
--   S5 when a request is pending). Unconditional: a 68030 bus behaviour fix.
--   Likewise an operand cycle rolls into a waiting queue prefetch (DP_CHAIN).
-- FalconFPGA modifications (David Dunne, github.com/dave-1024/falconfpga), CERN OHL v1.2.
-- Changes are tagged Fnn in the code. Dates are from git history.
-- Base: WF68K30L 2K19A (this repo's import of 2026-09-24).
--   2026-09-30 F1/F13/F14/F15: bus fault SSW and address latched at the faulting cycle.
--   2026-09-30 F2: SSW SIZE field uses the MC68030 Table 7-4 encoding.
--   2026-09-30 F5/F6: bus-errored IACK is spurious; AVEC ends CPU-space IACK only.
--   2026-09-30 F42-F54: reset and power-up values (SR $2700, no spurious traps).
--   2026-10-04 F58: falling-edge flops on CLK_F for the synchronous ST bridge.
--   2026-10-08 F62/F62b/F62c: opcode prefetch queue (PREFETCH_Q).
--   2026-10-09 F65: FAST_HANDOFF generic, prefetch S5-to-S0 chain (off by default).
--   2026-10-16 PH2: prefetch S5 to operand S0 (OP_CHAIN), operand S5 to prefetch S0 (DP_CHAIN), unconditional.
--   2026-10-16 PH2-FMAX: operand address and FC pins from ADR_LAT/FC_LAT (registered; differ only in IDLE).
--   2026-10-16 PH2-WP: posted writes: DATA_RDY of a write on the S3 edge of its last portion (option b).
--   2026-10-16 PH2-WP: a faulted write's data is held in OUTBUFFER (frame DOB) until the exception.
--   2026-10-16 PH2-WP: PW_GO: the operand request in the IDLE clock after a posted write starts without START_CYCLE.
--   2026-10-18 F2: MOVEM memory-to-register read-ahead: the S5 edge of a MOVEM read with more registers to come
--     rolls into the next register's read (RA_GO); its data or bus error is handed over on the matching request.
--   2026-10-17 IC: 68030 instruction cache on the prefetch queue: a queue long that hits is taken from the cache
--     without a bus cycle; a bus prefetch long with CIIN negated on every portion and no bus error is filled
--     (docs/ICACHE_DESIGN.md). Unconditional; with CIIN asserted on every cycle nothing is stored.
-- 

library work;
use work.WF68K30L_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity WF68K30L_BUS_INTERFACE is
    generic (
        -- [F62] 1: opcode prefetch queue. Instruction words are fetched as long words
        -- (SIZE = 00, two word cycles with dynamic bus sizing on a 16-bit port, as a
        -- 68030 with the cache off does) into a queue, ahead of the decoder and back to
        -- back on the bus. Decoder requests that hit the queue are served in one clock. 0: the
        -- original one-word-per-request opcode cycles (used with the caches).
        PREFETCH_Q          : integer := 0;
        -- [F65] 1: a completing prefetch long rolls into the next prefetch long
        -- on the S5 edge when the stream is still valid and no operand is
        -- waiting. 0 (default): DATA_C1C4 -> IDLE -> START_CYCLE.
        FAST_HANDOFF        : integer := 0);
    port (
        -- System control:
        CLK                 : in std_logic; -- System clock.
        CLK_F               : in std_logic; -- [F58] falling-edge registers: rising edge of a 180 degree clock

        -- Adress bus:
        ADR_IN_P            : in std_logic_vector(31 downto 0); -- Logical address line inputs.
        ADR_OUT_P           : out std_logic_vector(31 downto 0); -- Address line outputs.

        -- Function code relevant stuff:
        FC_IN               : in std_logic_vector(2 downto 0); -- Function codes.
        FC_OUT              : out std_logic_vector(2 downto 0); -- Physical function codes (top level entity).

        -- Data bus:
        DATA_PORT_IN        : in std_logic_vector(31 downto 0); -- Data bus input lines (top level entity).
        DATA_PORT_OUT       : out std_logic_vector(31 downto 0); -- Data bus output lines (top level entity).
        DATA_FROM_CORE      : in std_logic_vector(31 downto 0); -- Internal bus input lines.
        DATA_TO_CORE        : out std_logic_vector(31 downto 0); -- Internal data bus output lines.
        OPCODE_TO_CORE      : out std_logic_vector(15 downto 0); -- Internal instruction bus output lines.

        -- Tri state controls:
        DATA_PORT_EN        : out std_logic; -- For the data bus.
        BUS_EN              : out std_logic; -- For all other bus control signals.

        -- Transfer and operation size:
        SIZE                : out std_logic_vector(1 downto 0); -- This is the size information (top level entity).
        OP_SIZE             : in OP_SIZETYPE; -- Used for bus access control.

        -- Control signals:
        RD_REQ_IN           : in bit; -- Read data.
        WR_REQ_IN           : in bit; -- Write data.
        DATA_RDY            : out bit; -- Indicates 'new data available' (this is a strobe).
        DATA_VALID          : out std_logic; -- The data buffer contains valid data when '1'.
        WR_EARLY            : out bit; -- [F3] S3 of a posted write's last portion: its outcome is final (WP_GO).
        WR_TAKE             : in bit; -- [F3] The control unit took WR_EARLY for the next MOVEM register: no DATA_RDY.
        OPCODE_REQ          : in bit; -- Read opcode.
        OPCODE_RDY          : out bit; -- Indicates 'new opcode available' (this is a strobe).
        OPCODE_VALID        : out std_logic; -- The opcode buffer contains valid data when '1'.
        RMC                 : in bit; -- Indicates a read modify write operation.
        BUSY_EXH            : in bit;
        OPC_RD              : in bit; -- [F62] Raw decoder opcode request (not masked while the bus is busy).
        OPC_ADR             : in std_logic_vector(31 downto 0); -- [F62] Address of the requested opcode word (PC_L).
        OPC_FC              : in std_logic_vector(2 downto 0); -- [F62] Program space function code.
        OPC_DISMISS         : in bit; -- [F62c] The decoder's OPCODE_FLUSH: its next opcode ready is dismissed.
        PF_HOLD             : in bit; -- [PFCOF] Change of flow pending (decoder): start no further stream fetches.
        EXH_STK             : in bit; -- [XT2] Exception handler in BUILD_STACK (ISP stack writes): operand-write chains allowed.
        PF_NOEARLY          : in bit; -- [XH3] A change of flow is ahead or executing: no early long at Q_CNT = 2.
        Q_STREAM            : out std_logic_vector(63 downto 0); -- [PFCOF2] Queued words 0-3 (registered) for the decoder's predecode.
        Q_COUNT             : out integer range 0 to 4; -- [PFCOF2]
        DBG_IC              : out std_logic_vector(15 downto 0); -- FalconFPGA DIAG STR {lookup F_ADR7:1, fill F_CUR7:2, IC_HIT, IC_FILL, FILL_MIS}
        DBG_QF              : out std_logic_vector(3 downto 0); -- FalconFPGA DIAG STR {Q_HIT, IC_TAKE, PF_DONE, Q_MISS}
        Q_HEAD              : out std_logic_vector(31 downto 1); -- [FRM] Address of queued word 0.
        Q_FAULT             : out bit_vector(0 to 3); -- [FRM] Queued words fetched with a bus error.
        OP_RD               : in bit; -- [F65] Live data-read request, not masked by BUS_BSY.
        OP_WR               : in bit; -- [F65] Live data-write request, not masked by BUS_BSY.
        ADR_NXT             : in std_logic_vector(31 downto 0); -- [PH2] Address of the live operand request.
        FC_NXT              : in std_logic_vector(2 downto 0); -- [PH2] Its function code.
        ADR_LAT             : in std_logic_vector(31 downto 0); -- [PH2-FMAX] Registered address of the running cycle.
        FC_LAT              : in std_logic_vector(2 downto 0); -- [PH2-FMAX] Its registered function code.
        OP_CHAIN_LD         : out bit; -- [PH2] Strobe on an S5 edge that rolls an operand cycle in or out.
        RA_MORE             : in bit; -- [F2] MOVEM memory to register: the running read is not the last register.
        RA_LD               : out bit; -- [F2] S5 edge of a MOVEM read-ahead: the address latch steps to the next operand.
        IC_LK_ADR           : out std_logic_vector(31 downto 2); -- [IC] Long word the queue fetches next (F_ADR).
        IC_LK_FC2           : out std_logic; -- [IC]
        IC_HIT              : in std_logic; -- [IC] The instruction cache holds it.
        IC_HIT_DATA         : in std_logic_vector(31 downto 0); -- [IC]
        IC_FILL             : out std_logic; -- [IC] Strobe: a bus prefetch long ended (last portion).
        IC_FILL_MIS         : out std_logic; -- [IC] ... it started at 4n+2 (stream start at a misaligned word).
        IC_FILL_OK          : out std_logic_vector(1 downto 0); -- [IC] Per word (1 = first): no bus error, CIIN negated.
        IC_BREAK            : out std_logic; -- [IC] The stream restarts (Q_MISS).
        IC_FILL_ADR         : out std_logic_vector(31 downto 2); -- [IC]
        IC_FILL_FC2         : out std_logic; -- [IC]
        IC_FILL_DATA        : out std_logic_vector(31 downto 0); -- [IC]
        CIINn               : in std_logic; -- [IC] Cache inhibit in (MC68030UM 5.7.1).
        DC_FILL_EN          : in std_logic; -- [DC] ED set, FD clear, CDIS negated: a cachable read miss fills.
        DC_ON               : in std_logic; -- [DC] ED set, CDIS negated: reads are looked up.
        DC_LK_ADR           : out std_logic_vector(31 downto 0); -- [DC] Lookup of the read request in START_CYCLE.
        DC_LK_FC            : out std_logic_vector(2 downto 0);
        DC_LK_SZ            : out std_logic_vector(2 downto 0);
        DC_HIT              : in std_logic;
        DC_HIT_DATA         : in std_logic_vector(31 downto 0);
        DC_WR_GO            : out std_logic; -- [DC] A write started (registered, the clock after).
        DC_WR_ADR           : out std_logic_vector(31 downto 0);
        DC_WR_FC            : out std_logic_vector(2 downto 0);
        DC_WR_SZ            : out std_logic_vector(2 downto 0);
        DC_WR_DATA          : out std_logic_vector(31 downto 0);
        DC_FL_GO            : out std_logic; -- [DC] A read and its fill cycles ended.
        DC_FL_A0            : out std_logic_vector(31 downto 2);
        DC_FL_FC            : out std_logic_vector(2 downto 0);
        DC_FL_U1            : out std_logic;
        DC_FL_D0            : out std_logic_vector(31 downto 0);
        DC_FL_D1            : out std_logic_vector(31 downto 0);
        DC_FL_OK0           : out std_logic_vector(1 downto 0);
        DC_FL_OK1           : out std_logic_vector(1 downto 0);
        DC_FL_BE0           : out std_logic;
        DC_FL_BE1           : out std_logic;
        INBUFFER            : out std_logic_vector(31 downto 0); -- Used by the exception handler for stack frame type B.
        OUTBUFFER           : out std_logic_vector(31 downto 0); -- Used by the exception handler for stack frame types A and B.
        SSW_80              : out std_logic_vector(8 downto 0);
        BFLT_SSW            : out std_logic_vector(8 downto 0); -- F1/H7: SSW snapshot latched AT the data fault.
        BFLT_ADR            : out std_logic_vector(31 downto 0); -- F1/H4: faulting bus address, latched with it.
        BFLT_VALID          : out bit; -- F1: snapshot armed; cleared when exception processing completes.

        -- Asynchronous bus control signals:
        DSACKn              : in std_logic_vector(1 downto 0); -- Asynchronous bus cycle termination (top level entity).
        ASn                 : out std_logic; -- Adress select (top level entity).
        DSn                 : out std_logic; -- Data select (top level entity).
        RWn                 : out std_logic; -- Hi is read, low = write (top level entity).
        RMCn                : out std_logic; -- Read modify write indicator (top level entity).
        RMC_LKn             : out std_logic; -- [F67] RMCn without the T_SLICE term (equal while AS is low), for the MMU/TT match.
        ECSn                : out std_logic; -- External cycle start (top level entity).
        OCSn                : out std_logic; -- Operand cycle start (top level entity).
        DBENn               : out std_logic; -- Data buffer enable (top level entity).

        -- Synchronous bus control:
        STERMn              : in std_logic; -- Synchronous bus cycle termination (top level entity).

        -- Bus arbitration:
        BRn                 : in std_logic; -- Bus request (top level entity).
        BGACKn              : in std_logic; -- Bus grant acknowledge (top level entity).
        BGn                 : out std_logic; -- Bus grant (top level entity).

        -- Exception signals:
        RESET_IN            : in std_logic; -- System's reset input (top level entity).
        RESET_STRB          : in bit; -- From Core: force external reset.
        RESET_OUT           : out std_logic; -- System's reset output open drain enable.
        RESET_CPU           : out bit; -- Internal reset used for CPU initialization.
        AVECn               : in std_logic; -- Auto interrupt vector input (top level entity).
        HALTn               : in std_logic; -- Halt (top level entity).
        BERRn               : in std_logic; -- Bus error (top level entity).
        AERR                : buffer bit; -- Core internal address error.

        BUS_BSY             : out bit -- Bus is busy when '1'.
    );
end entity WF68K30L_BUS_INTERFACE;
    
architecture BEHAVIOR of WF68K30L_BUS_INTERFACE is
type BUS_CTRL_STATES is (IDLE, START_CYCLE, DATA_C1C4);
type ARB_STATES is(IDLE, GRANT, WAIT_RELEASE_3WIRE);
type BUS_WIDTH_TYPE is(LONG_32, WORD, BYTE);
type TIME_SLICES is (IDLE, S0, S1, S2, S3, S4, S5);
signal ADR_10               : std_logic_vector(1 downto 0);
signal ADR_OFFSET           : std_logic_vector(5 downto 0);
signal ADR_OUT_I            : std_logic_vector(31 downto 0);
signal BFLT_SSW_I           : std_logic_vector(8 downto 0) := (others => '0'); -- F1
signal BFLT_ADR_I           : std_logic_vector(31 downto 0) := (others => '0'); -- F1
signal BFLT_VALID_I         : bit := '0'; -- F1
signal BUSY_EXH_D           : bit := '0'; -- F1: for the completion edge.
signal BUSY_EXH_D2          : bit := '0'; -- F13/H20: debounce the abort glitch.
signal AERR_I               : bit := '0';  -- [F54] measured warm-boot value
signal ARB_STATE            : ARB_STATES := IDLE;
signal AVEC_In              : std_logic := '1';  -- [F54] measured warm-boot value
signal BGACK_In             : std_logic := '1';  -- [F54] measured warm-boot value
signal BR_In                : std_logic := '1';  -- [F54] measured warm-boot value
signal BUS_CTRL_STATE       : BUS_CTRL_STATES := IDLE;  -- [F54] measured warm-boot value
signal BUS_CYC_RDY          : bit := '0';  -- [F54] measured warm-boot value
signal BUS_FLT_N            : std_logic; -- [F58] was the variable BUS_FLT_VAR of P_SYNC
signal BUS_FLT              : std_logic := '0';  -- [F54] measured warm-boot value
signal BUS_WIDTH            : BUS_WIDTH_TYPE := LONG_32;  -- [F54] measured warm-boot value
signal DATA_INMUX           : std_logic_vector(31 downto 0);
signal DATA_RDY_I           : bit := '0';  -- [F54] measured warm-boot value
signal DBUFFER              : std_logic_vector(31 downto 0);
signal DSACK_In             : std_logic_vector(1 downto 0) := "11";  -- [F54] measured warm-boot value
signal DSACK_MEM            : bit_vector(1 downto 0) := "11";  -- [F54] measured warm-boot value
signal OCS_INH              : bit := '0';  -- [F54] measured warm-boot value
signal HALT_In              : bit := '0';  -- [F54] measured warm-boot value
signal HALTED               : bit := '0';  -- [F54] measured warm-boot value
signal NEXT_ARB_STATE       : ARB_STATES := IDLE;  -- [F54] measured warm-boot value
signal NEXT_BUS_CTRL_STATE  : BUS_CTRL_STATES := IDLE;  -- [F54] measured warm-boot value
signal OBUFFER              : std_logic_vector(15 downto 0);
signal OPCODE_ACCESS        : bit := '0';  -- [F54] measured warm-boot value
signal OPCODE_RDY_I         : bit := '0';  -- [F54] measured warm-boot value
signal READ_ACCESS          : bit := '0';  -- [F54] measured warm-boot value
signal RESET_CPU_I          : bit := '1';  -- [F54] measured warm-boot value
signal RESET_OUT_I          : std_logic := '0';  -- [F54] measured warm-boot value
signal RETRY                : bit := '0';  -- [F54] measured warm-boot value
signal SIZE_D               : std_logic_vector(1 downto 0) := "00";  -- [F54] measured warm-boot value
signal SIZE_I               : std_logic_vector(1 downto 0) := "00";  -- [F54] measured warm-boot value
signal SIZE_N               : std_logic_vector(2 downto 0) := "000";
signal SIZE_DEC             : std_logic_vector(2 downto 0); -- [PH2-WP] SIZE_N after this portion.
signal WP_NEG               : bit := '0'; -- [T9] CLK_F part of WP_GO.
signal WP_GO                : bit; -- [PH2-WP] Post the write on this S3 edge.
signal WP_DONE              : bit := '0'; -- [PH2-WP] The running write was posted.
signal DOB_HOLD             : bit := '0'; -- [PH2-WP] Keep the faulted write's data for the frame.
signal WP_LAST              : bit := '0'; -- [PH2-WP] The bus is idle since a posted write ended.
signal WW_GO                : bit; -- [F3] Write-to-write chain on the S5 edge.
signal PW_GO                : bit; -- [PH2-WP] IDLE clock after a posted write: start the operand cycle now.
signal SLICE_CNT_N          : std_logic_vector(2 downto 0) := "111";  -- [F54] measured warm-boot value
signal SLICE_CNT_P          : std_logic_vector(2 downto 0) := "111";  -- [F54] measured warm-boot value
signal STERM_In             : std_logic := '1';  -- [F54] measured warm-boot value
signal T_SLICE              : TIME_SLICES := IDLE;  -- [F54] measured warm-boot value
signal WAITSTATES           : bit := '0';  -- [F54] measured warm-boot value
signal WP_BUFFER            : std_logic_vector(31 downto 0);
signal WRITE_ACCESS         : bit := '0';  -- [F54] measured warm-boot value
signal RMC_LK               : bit := '0'; -- [RMC1] Locked read of the RMC sequence has started.
signal RMC_PIN              : bit; -- [RMC1] Bus-visible RMC: S0 of the first locked read .. end of the last write.
signal RMC_HOLD             : bit; -- [RMC1] Lock held and the write(s) still owed: no opcode cycle may start.
signal RMC_DONE             : bit := '0'; -- [RMC1] As many write cycles as locked reads have completed.
signal RMC_NR, RMC_NW       : integer range 0 to 7 := 0; -- [RMC1] Locked read / write cycles completed.
-- [F62] Opcode prefetch queue.
type QWORDS_T is array (0 to 3) of std_logic_vector(15 downto 0);
signal Q_W                  : QWORDS_T;
signal Q_F                  : bit_vector(0 to 3) := "0000";  -- Word fetched with a bus error.
signal Q_CNT                : integer range 0 to 4 := 0;
signal Q_ADR                : std_logic_vector(31 downto 1) := (others => '0'); -- Address of Q_W(0).
signal Q_FC                 : std_logic_vector(2 downto 0) := "110";
signal S_VALID              : bit := '0'; -- The queue holds the stream starting at Q_ADR.
signal S_FAULTED            : bit := '0'; -- A fetch of this stream faulted: no further eager fetches.
signal F_ADR                : std_logic_vector(31 downto 1) := (others => '0'); -- Next long word to fetch (word address).
signal INFL                 : bit := '0'; -- A prefetch is in flight.
signal INFL_STALE           : bit := '0'; -- ... and its data is to be discarded.
signal F_CUR                : std_logic_vector(31 downto 1) := (others => '0');
signal F_FC                 : std_logic_vector(2 downto 0) := "110";
signal PF_ACC               : bit := '0'; -- The current opcode access is a queue prefetch.
signal PF_FLT0              : bit := '0';
signal PF_FLT1              : bit := '0';
signal Q_DISMISS            : bit := '0';
signal Q_HIT                : bit;
signal Q_MISS               : bit;
signal Q_DUMMY              : bit;
signal Q_MATCH              : bit;
signal PF_REQ               : bit;
signal PF_START             : bit;
signal PF_DONE              : bit;
signal PF_CHAIN             : bit := '0'; -- [F65] Armed at S3. Not the S5 decision.
signal PF_CHAIN_GO          : bit; -- [F65] S5 decision: PF_CHAIN and every cancel the FSM uses.
signal OP_CHAIN             : bit := '0'; -- [PH2] Armed at S3 of a prefetch while an operand request waits.
signal OP_CHAIN_GO          : bit; -- [PH2] S5 decision: the prefetch rolls into the operand cycle.
signal DP_CHAIN             : bit := '0'; -- [PH2] Armed at S3 of an operand cycle while a queue prefetch waits.
signal DP_CHAIN_GO          : bit; -- [PH2] S5 decision: the operand cycle rolls into the prefetch.
signal CH_WR                : bit; -- [PH2] The chained operand cycle is a write.
signal CHAIN_GO             : bit; -- [PH2] PF_, OP_, DP_CHAIN_GO or RA_GO: a new cycle starts on this S5 edge.
signal DP_CHAIN_RAW         : bit; -- [F2] DP_CHAIN_GO before the read-ahead takes precedence.
signal RA_ARM               : bit := '0'; -- [F2] Armed at S3 of a MOVEM read with more registers to come.
signal DATA_VALID_I         : std_logic := '1'; -- [F2] DATA_VALID, readable.
signal RA_FLT_P             : std_logic := '0'; -- [F2] A read-ahead bus-errored on the last edge.
signal RA_DIB_HOLD          : std_logic := '0'; -- [F2] INBUFFER (DIB) keeps the faulted read-ahead's data.
signal RA_GO                : bit; -- [F2] S5 decision: the read rolls into the next register's read.
signal RA_GO_D              : bit := '0'; -- [F2] The clock after RA_GO.
signal RA_ACC               : bit := '0'; -- [F2] The running read is a read-ahead.
signal RA_HELD              : bit := '0'; -- [F2] A finished read-ahead waits for its request (data in DBUFFER, fault in DATA_VALID).
signal RA_HADR              : std_logic_vector(31 downto 0) := (others => '0'); -- [F2] Its address.
signal RA_END               : bit; -- [F2] The read-ahead cycle ends on this edge.
signal RA_MATCH             : bit; -- [F2] The live request is the read-ahead's operand (running cycle).
signal RA_TAKE              : bit; -- [F2] The held read-ahead is handed over on this edge.
signal RA_DROP              : bit; -- [F2] Not requested as expected: dropped, the request runs its own cycle.
signal OPC_LEGACY           : bit; -- Opcode request handled by an ordinary opcode cycle.
signal PF_REQ_RAW           : bit; -- [IC] The queue wants the long word at F_ADR (cache or bus).
signal IC_TAKE              : bit; -- [IC] ... and takes it from the instruction cache in this clock.
signal CIIN_LAT             : std_logic := '0'; -- [IC] CIINn of the running portion (sampled at S4, P_CIIN).
signal PF_CI0               : std_logic := '0'; -- [IC] CIIN was asserted on the finished portion of word 0 / word 1
signal PF_CI1               : std_logic := '0'; -- [IC] of the running prefetch long (as PF_FLT0/PF_FLT1).
-- [IC] Cache-inhibit state of the running prefetch: keep it through synthesis (see WF68K30L_ICACHE).
signal RD_REQ               : bit; -- [DC] RD_REQ_IN without a read the data cache serves.
signal WR_REQ               : bit; -- [DC] WR_REQ_IN, held while a fill cycle starts.
signal DC_RHIT              : bit; -- [DC] START_CYCLE of a read the data cache holds: no bus cycle.
signal FILL_ACC             : bit := '0'; -- [DC] The running cycle is a data cache fill cycle (6.1.3.1).
signal FILL_REQ             : bit; -- [DC] A fill cycle is wanted.
signal FILL_START           : bit; -- [DC] START_CYCLE of a fill cycle.
signal FILL_WADR            : std_logic_vector(31 downto 1); -- [DC] Its word address.
signal DC_PORT              : std_logic_vector(31 downto 0); -- [DC] The data bus, sampled with IN_MUX.
signal DC_TRK               : bit := '0'; -- [DC] The running read is tracked for the fill.
signal DC_OA                : std_logic_vector(31 downto 0) := (others => '0'); -- [DC] Its address, FC, size, RMC.
signal DC_OA1               : std_logic_vector(31 downto 2) := (others => '0'); -- [F65] DC_OA(31 downto 2) + 1, registered with DC_OA.
signal DC_OFC               : std_logic_vector(2 downto 0) := "000";
signal DC_OSZ               : std_logic_vector(2 downto 0) := "000";
signal DC_ORMC              : bit := '0';
signal DC_OX                : std_logic; -- [DC] It touches two entries.
signal FB_D0, FB_D1         : std_logic_vector(31 downto 0) := (others => '0'); -- [DC] Words read, entry E0/E1.
signal FB_OK0, FB_OK1       : std_logic_vector(1 downto 0) := "00"; -- [DC] ... with CIIN negated, no bus error.
signal FB_BE0, FB_BE1       : std_logic := '0'; -- [DC] A bus error on the entry.
signal FB_AB0, FB_AB1       : std_logic := '0'; -- [DC] No fill for the entry (bus error, CIIN, 8-bit port).
signal FB_CA                : std_logic := '0'; -- [DC] Every operand portion so far was cachable.
signal FB_PF                : std_logic := '0'; -- [DC] Bus error seen in the running portion.
signal DC_DECIDE            : bit := '0'; -- [DC] The clock after a tracked read's last portion.
signal DC_NEED              : std_logic; -- [DC] ... and its entries are to be completed by fill cycles.
signal DC_MISS              : std_logic_vector(3 downto 0); -- [DC] Words still to fill: E0 w0, E0 w1, E1 w0, E1 w1.
signal FILL_PEND            : bit := '0'; -- [DC] Fill cycles of the last read are pending.
signal DC_DPBLK             : bit; -- [DC] The read may need fill cycles: no chain into a prefetch.
signal DC_WSTB              : bit; -- [DC] A write starts on this edge.
signal DC_WR_GO_I           : std_logic := '0';
signal DCW_ADR              : std_logic_vector(31 downto 0) := (others => '0');
signal DCW_FC               : std_logic_vector(2 downto 0) := "000";
signal DCW_SZ               : std_logic_vector(2 downto 0) := "001";
signal DC_FL_GO_I           : std_logic;
signal DC_FIN               : std_logic; -- [DC] The read (and its fill cycles) is complete.
signal DC_PH                : std_logic := '0'; -- [DC] Registered lookup of the request of the last clock: hit,
signal DC_PD                : std_logic_vector(31 downto 0) := (others => '0'); -- its operand,
signal DC_PV                : std_logic := '0'; -- a read request was pending (no DATA_RDY).
signal DC_CHIT              : bit; -- [DC] S5 of a prefetch: the waiting read hits instead of chaining.
signal OP_CHAIN_RAW         : bit; -- [DC] The chain decision before the hit.
attribute syn_preserve : integer;
attribute syn_preserve of CIIN_LAT : signal is 1;
attribute syn_preserve of FB_D0 : signal is 1;
attribute syn_preserve of FB_D1 : signal is 1;
attribute syn_preserve of FB_OK0 : signal is 1;
attribute syn_preserve of FB_OK1 : signal is 1;
attribute syn_preserve of FILL_ACC : signal is 1;
attribute syn_preserve of PF_CI0 : signal is 1;
attribute syn_preserve of PF_CI1 : signal is 1;
begin

    P_SYNC_N: process(CLK_F)
    -- [F58] The negative-edge half of P_SYNC, clocked by CLK_F (rising edge = falling edge
    -- of CLK). BUS_FLT_VAR is now the signal BUS_FLT_N (written here, read in P_SYNC).
    -- These flip flops synchronize the bus termination signal on the negative clock edge. 
    -- This meets the requirement of sampling these signals in the end of S2 for asynchronous 
    -- bus access. Be aware, that we have to buffer the RETRY signal to prevent the bus 
    -- controller of spurious or timing critical BERRn and/or HALTn signals.
    -- Note: there is no need to synchronize the already synchronous bus control signals 
    -- STERMn. But the logic needs delayed signals.
    -- Remark: launching BUS_FLT on the positive clock edge significantly enhances the 
    -- system performance concerning the maximum clock frequency.
    begin
        if CLK_F = '1' and CLK_F' event then
            DSACK_In <= DSACKn;
            HALT_In <= To_Bit(HALTn);
            BUS_FLT_N <= not BERRn;
            STERM_In <= STERMn; -- Delayed.
            BR_In <= BRn;
            BGACK_In <= BGACKn;
            AVEC_In <= AVECn;
            -- [T9] S3 and the pin terms of WP_GO, one flip flop (see WP_GO).
            if SLICE_CNT_P = "001" and DSACKn /= "11" and STERMn = '1' and (not BERRn) = '0' and To_Bit(HALTn) = '1' then
                WP_NEG <= '1';
            else
                WP_NEG <= '0';
            end if;
            --
            if BERRn = '0' and HALTn = '0' and BUS_CTRL_STATE = DATA_C1C4 and SIZE_N /= "000" then
                RETRY <= '1';
            elsif T_SLICE = IDLE and (BERRn = '1' or HALTn = '1') then
                RETRY <= '0';
            end if;
        end if;
    end process P_SYNC_N;

    P_SYNC: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            if BUS_CTRL_STATE = START_CYCLE then        
                AERR <= AERR_I;
            elsif BUS_CTRL_STATE = DATA_C1C4 then        
                BUS_FLT <= BUS_FLT_N;
            else
                BUS_FLT <= '0';
                AERR <= '0';
            end if;
        end if;
    end process P_SYNC;

    ACCESSTYPE: process
    -- This logic stores the execution unit control
    -- signals during the current bus access. This is
    -- important for the bus control signals to be
    -- stable during the complete bus access.
    begin
        wait until CLK = '1' and CLK' event;
        if BUS_CTRL_STATE = START_CYCLE then
            if READ_ACCESS = '1' or WRITE_ACCESS = '1' or OPCODE_ACCESS = '1' or FILL_ACC = '1' then
                null; -- Do not start either new cycle.
            elsif FILL_START = '1' then
                FILL_ACC <= '1'; -- [DC]
            elsif RD_REQ = '1' then
                READ_ACCESS <= '1';
            elsif WR_REQ = '1' then
                WRITE_ACCESS <= '1';
            elsif OPC_LEGACY = '1' then
                OPCODE_ACCESS <= '1';
            elsif PF_START = '1' then
                OPCODE_ACCESS <= '1';
                PF_ACC <= '1';
            end if;
        elsif OP_CHAIN_GO = '1' then -- [PH2] The prefetch ends, the waiting operand cycle starts.
            FILL_ACC <= '0';
            READ_ACCESS <= not CH_WR;
            WRITE_ACCESS <= CH_WR;
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
        elsif RA_GO = '1' then -- [F2] The MOVEM read rolls into the next register's read.
            READ_ACCESS <= '1';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
            FILL_ACC <= '0';
        elsif DP_CHAIN_GO = '1' then -- [PH2] The operand cycle ends, the waiting prefetch starts.
            READ_ACCESS <= '0';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '1';
            PF_ACC <= '1';
        elsif AERR = '1' then -- Reject due to address error.
            FILL_ACC <= '0';
            READ_ACCESS <= '0';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
        elsif BUS_CTRL_STATE = DATA_C1C4 and NEXT_BUS_CTRL_STATE = IDLE and SIZE_N = "000" then
            FILL_ACC <= '0';
            READ_ACCESS <= '0';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
        end if;
    end process ACCESSTYPE;

    P_DF: process
    -- This is the logic which provides the fault flags for data cycles and
    -- input and output buffer information.
    variable SIZEVAR : std_logic_vector(1 downto 0) := "00";
    begin
        wait until CLK = '1' and CLK' event;
        -- F14/H21: this freeze was the SECOND BUSY_EXH gate hiding fault data
        -- for faults taken DURING exception processing (RTE frame validation,
        -- stack building, double fault). SSW_80 kept the last pre-exception
        -- cycle's attributes, so F1's latch faithfully snapshotted a stale
        -- staging: wrong FC, with RW/SIZE right only by coincidence when the
        -- stale cycle happened to match. The freeze predates F1; the staged
        -- SSW is no longer what the frame reads -- BFLT_SSW is, latched AT the
        -- fault -- so freezing it protects nothing the fault path relies on.
        if true then
            case OP_SIZE is -- F2/H1: MC68030UM Table 7-4 encoding.
                when LONG => SIZEVAR := "00";
                when WORD => SIZEVAR := "10";
                when BYTE => SIZEVAR := "01";
            end case;
            --
            if BUS_CTRL_STATE = START_CYCLE and NEXT_BUS_CTRL_STATE = DATA_C1C4 and FILL_START = '0' then
                SSW_80 <= To_StdLogicVector('0' & RMC & not WR_REQ) & SIZEVAR & '0' & FC_IN;
            elsif DP_CHAIN_GO = '1' then -- [PH2] As START_CYCLE writes it for a prefetch.
                SSW_80 <= To_StdLogicVector('0' & RMC & '1') & SIZEVAR & '0' & FC_NXT;
            elsif OP_CHAIN_GO = '1' then -- [PH2]
                SSW_80 <= To_StdLogicVector('0' & RMC & not CH_WR) & SIZEVAR & '0' & FC_NXT;
            elsif RA_GO = '1' then -- [F2] Read, same function code.
                SSW_80 <= To_StdLogicVector('0' & RMC & '1') & SIZEVAR & '0' & FC_LAT;
            elsif BUS_CTRL_STATE = DATA_C1C4 and (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_FLT = '1' then
                SSW_80(8) <= '1';
            end if;
            
        end if;
        -- F14/H21: the buffers KEEP the freeze. They carry the faulting write's
        -- data for the frame ($18/$1A) so software can rerun the store, and the
        -- frame-build cycles would otherwise overwrite them -- measured as
        -- T1 0055, T2 1234, T3 89AB/CDEF all going to zero. Only the SSW
        -- staging above is un-frozen.
        -- [PH2-WP] A faulted write's data stays in OUTBUFFER (DOB, frame $18) until the exception
        -- handler runs: before, the cycles the core still ran before taking the exception (the next
        -- instruction's operand read) reloaded WP_BUFFER, so the frame showed an older write's data.
        if BUS_CTRL_STATE = DATA_C1C4 and WRITE_ACCESS = '1' and BUS_FLT = '1' and HALT_In = '1' then
            DOB_HOLD <= '1';
        elsif BUSY_EXH = '1' then
            DOB_HOLD <= '0';
        end if;
        if BUSY_EXH = '0' and DOB_HOLD = '0' then
            OUTBUFFER <= WP_BUFFER; -- Used for exception stack frame type A and B.
            if RA_DIB_HOLD = '0' then -- [F2] A faulted read-ahead keeps its data (DIB) while prefetches run.
                INBUFFER <= DATA_INMUX; -- Used for exception stack frame type B.
            end if;
        end if;
        -- [F2] A read-ahead that bus-errors runs before the control unit asked for that register, so the
        -- prefetches that used to precede the faulted read now follow it before BUSY_EXH freezes INBUFFER.
        -- Keep the faulted read's data in the DIB as before: freeze from the clock after it was loaded.
        RA_FLT_P <= '0';
        if RA_ACC = '1' and READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' and HALT_In = '1' then
            RA_FLT_P <= '1';
        end if;
        if RESET_CPU_I = '1' or BUSY_EXH = '1' or RA_DROP = '1' then
            RA_DIB_HOLD <= '0';
        elsif RA_FLT_P = '1' then
            RA_DIB_HOLD <= '1';
        end if;
    end process P_DF;

    P_BFLT: process
    -- F1/H7+H4: latch the fault snapshot AT the faulting data cycle, before
    -- post-fault prefetches re-arm the staging SSW_80. DF forced; address
    -- taken live from ADR_OUT_I. Read-retry (BERR+HALT) mirrors the
    -- VALIDATION carve-out and does not arm. Cleared when the exception
    -- handler releases BUSY_EXH, so a fault during exception processing
    -- (double bus fault path) re-latches the second fault's data.
    begin
        wait until CLK = '1' and CLK' event;
        BUSY_EXH_D <= BUSY_EXH;
        BUSY_EXH_D2 <= BUSY_EXH_D;
        if RESET_CPU_I = '1' then
            BFLT_VALID_I <= '0';
        -- F13/H20: the clear was BUSY_EXH's falling edge, but BUSY_EXH drops
        -- for ONE cycle in the EXAMINE_VERSION -> IDLE -> INIT gap when an RTE
        -- unwind aborts, wiping the snapshot before the bus-error frame that
        -- needs it is built. Clear instead when the CPU has genuinely resumed
        -- fetching instructions: any later exception is then a new event, and
        -- address-error / prefetch-fault frames still see legacy values.
        -- F13/H20: the clear was BUSY_EXH's falling edge alone. BUSY_EXH drops
        -- for exactly ONE cycle in the EXAMINE_VERSION -> IDLE -> INIT gap when
        -- an RTE unwind is abandoned by a fault, and that glitch wiped the
        -- snapshot before the bus-error frame that needs it was built. A
        -- single-cycle deassertion is a state-machine transition, not a return
        -- to normal execution, so require BUSY_EXH to STAY low. Everything else
        -- is unchanged: address-error and prefetch-fault frames still fall back
        -- to legacy values, and a fresh fault still overwrites the snapshot.
        elsif BUSY_EXH = '0' and BUSY_EXH_D = '0' and BUSY_EXH_D2 = '1' then
            BFLT_VALID_I <= '0';
        -- F13/H20: arming was gated on BUSY_EXH = '0', so a fault taken WHILE
        -- the exception handler was running (RTE frame validation, stack
        -- building, double-fault) never armed and the frame fell back to the
        -- legacy prefetch-derived SSW and ADR_CPY -- wrong DF, wrong FC, wrong
        -- address. The gate contradicted this process's own stated intent.
        elsif BUS_CTRL_STATE = DATA_C1C4 and
              (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_FLT = '1' and
              not (READ_ACCESS = '1' and HALT_In = '0') then
            -- F15/H1b: take the SSW SIZE field from SIZE_N, the byte counter
            -- that drives the SIZ pins, instead of inheriting the staged
            -- SIZEVAR (derived from OP_SIZE, the INSTRUCTION's operand size).
            -- SIZE_N's low two bits ARE MC68030UM Table 7-4 by construction:
            -- 4 => "00" long, 3 => "11" three byte, 2 => "10" word,
            -- 1 => "01" byte. NOT SIZE_N itself: measured, that is already
            -- decremented at the fault edge and reads "00" for every cycle.
            -- SIZE_I is the PIN value, held valid across the cycle by P_DELAY,
            -- and is the same signal the bench samples and reports correctly.
            -- Misaligned transfers make 3-byte cycles routine on a 16-bit
            -- port, so this stops being a corner case on the real ST-RAM.
            BFLT_SSW_I   <= '1' & SSW_80(7 downto 6) & SIZE_I & SSW_80(3 downto 0);
            BFLT_ADR_I   <= ADR_OUT_I;
            BFLT_VALID_I <= '1';
        end if;
    end process P_BFLT;

    BFLT_SSW <= BFLT_SSW_I;
    BFLT_ADR <= BFLT_ADR_I;
    BFLT_VALID <= BFLT_VALID_I;
    
    WRITEBACK_INFO: process
    -- This registers stor writeback relevant information.
    begin
        wait until CLK = '1' and CLK' event;
        if BUS_CTRL_STATE = IDLE and NEXT_BUS_CTRL_STATE = START_CYCLE then -- Freeze during a bus cycle.
            WP_BUFFER <= DATA_FROM_CORE;
        elsif OP_CHAIN_GO = '1' then -- [PH2] Chained operand cycle: data of the waiting request.
            WP_BUFFER <= DATA_FROM_CORE;
        end if;
    end process WRITEBACK_INFO;

    P_BUSWIDTH: process
    -- These flip flops store the bus width information
    -- during the current bus access.
    begin
        wait until CLK = '1' and CLK' event;
        -- [PH2] The chain edge comes first: DSACK_In still holds the ending
        -- cycle's DSACK there (sampled on the S4 half), and a kept "01" made the
        -- next cycle a word port (measured: a chained long read that bus-errored
        -- filled only half of the data input buffer). Same as the IDLE reset.
        if CHAIN_GO = '1' then
            DSACK_MEM <= "11"; -- [F65] [PH2] New cycle samples the port width again.
        elsif DSACK_In = "01" then
            DSACK_MEM <= "01";
        elsif DSACK_In = "10" then
            DSACK_MEM <= "10";
        elsif BUS_CTRL_STATE = IDLE then
            DSACK_MEM <= "11";
        end if;
    end process P_BUSWIDTH;
    
    BUS_WIDTH <= WORD when DSACKn = "01" or DSACK_MEM = "01" else
                 BYTE when DSACKn = "10" or DSACK_MEM = "10" else 
                 LONG_32; -- Also used during synchronous cycles.
    
    BUS_BSY <= '1' when BUS_CTRL_STATE /= IDLE else '0';

    PARTITIONING: process
    -- This logic gives information about the remaining bus cycles The initial 
    -- size is sampled right before the bus acces. This requires the RD_REQ
    -- and WR_REQ signals to work on the positive clock edge.
    variable RESTORE_VAR : std_logic_vector(2 downto 0) := "000";
    begin
        wait until CLK = '1' and CLK' event;

        if BUS_CTRL_STATE = DATA_C1C4 and T_SLICE = S1 then -- On positive clock edge.
            RESTORE_VAR := SIZE_N; -- We need this initial value for early RETRY.
        elsif BUS_CTRL_STATE = DATA_C1C4 and ((T_SLICE = S1 and STERMn = '0') or (T_SLICE = S3 and WAITSTATES = '0')) then
            RESTORE_VAR := SIZE_N; -- This is for late RETRY.
        end if;
        --
        if RESET_CPU_I = '1' then
            SIZE_N <= "000";
        elsif PF_CHAIN_GO = '1' or DP_CHAIN_GO = '1' then
            SIZE_N <= "100"; -- [F65] [PH2] Next prefetch long, loaded on the S5 edge.
        elsif OP_CHAIN_GO = '1' or RA_GO = '1' then -- [PH2] Operand size of the waiting request. [F2] Same size.
            case OP_SIZE is
                when LONG => SIZE_N <= "100";
                when WORD => SIZE_N <= "010";
                when BYTE => SIZE_N <= "001";
            end case;
        elsif BUS_CTRL_STATE /= DATA_C1C4 and NEXT_BUS_CTRL_STATE = DATA_C1C4 then
            if FILL_START = '1' then
                SIZE_N <= "010"; -- [DC] Fill cycle: one word.
            elsif RD_REQ = '1' or WR_REQ = '1' then
                case OP_SIZE is
                    when LONG => SIZE_N <= "100";
                    when WORD => SIZE_N <= "010";
                    when BYTE => SIZE_N <= "001";
                end case;
            elsif PREFETCH_Q /= 0 and OPC_LEGACY = '0' then -- [F62] Queue prefetch.
                SIZE_N <= "100"; -- LONG.
            else -- OPCODE_ACCESS.
                SIZE_N <= "010"; -- WORD.
            end if;
        end if;
        
        -- Decrementing the size information:
        -- In this logic all permutations are considered. This allows a dynamically changing bus size.
        if RETRY = '1' then
            SIZE_N <= RESTORE_VAR;
        elsif BUS_CTRL_STATE = DATA_C1C4 and ((T_SLICE = S1 and STERMn = '0') or (T_SLICE = S3 and WAITSTATES = '0')) then -- On positive clock edge.
            SIZE_N <= SIZE_DEC; -- [PH2-WP] Same decrement, also used for the write post.
        end if;
        --
        if (BUS_FLT = '1' and HALT_In = '1') then -- Abort bus cycle.
            SIZE_N <= "000";
            RESTORE_VAR := "000";
        end if;        
    end process PARTITIONING;

    -- [PH2-WP] SIZE_N after the running portion (the decrement of PARTITIONING, unchanged).
    SIZE_DEC <= SIZE_N - "11" when BUS_WIDTH = LONG_32 and SIZE_N > x"3" and ADR_OUT_I(1 downto 0) = "01" else
                SIZE_N - "10" when BUS_WIDTH = LONG_32 and SIZE_N > x"2" and ADR_OUT_I(1 downto 0) = "10" else
                SIZE_N - '1' when BUS_WIDTH = LONG_32 and SIZE_N > x"1" and ADR_OUT_I(1 downto 0) = "11" else
                "000" when BUS_WIDTH = LONG_32 else
                SIZE_N - '1' when BUS_WIDTH = WORD and ADR_OUT_I(1 downto 0) = "11" else
                SIZE_N - '1' when BUS_WIDTH = WORD and ADR_OUT_I(1 downto 0) = "01" else
                SIZE_N - '1' when BUS_WIDTH = WORD and SIZE_N = "001" else
                SIZE_N - "10" when BUS_WIDTH = WORD else
                SIZE_N - '1' when BUS_WIDTH = BYTE else
                SIZE_N;

    SIZE_I <= SIZE_N(1 downto 0) when T_SLICE = S0 or T_SLICE = S1 else SIZE_D;
    SIZE <= SIZE_I;
    
    P_DELAY: process
    -- This delay is responsible for a correct SIZE_I information. Use this, if the
    -- process PARTITIONING works on the positive clock edge. The SIZE_I information
    -- is delayed by half a clock cycle to be valid just in time of sampling the INMUX.
    begin
        wait until CLK = '1' and CLK' event;
        SIZE_D <= SIZE_N(1 downto 0);
    end process P_DELAY;

    BUS_STATE_REG: process
    -- This is the bus controller's state register.
    begin
        wait until CLK = '1' and CLK' event;
        BUS_CTRL_STATE <= NEXT_BUS_CTRL_STATE;
    end process BUS_STATE_REG;

    BUS_CTRL_DEC: process(ADR_IN_P, ADR_OUT_I, ARB_STATE, BGACK_In, BR_In, BUS_CTRL_STATE, BUS_CYC_RDY, BUS_FLT, HALT_In, 
                          OPCODE_ACCESS, OPCODE_REQ, RD_REQ, READ_ACCESS, RESET_CPU_I, RMC_PIN, SIZE_N, WR_REQ, WRITE_ACCESS,
                          OPC_LEGACY, PF_REQ, CHAIN_GO, PW_GO, FILL_REQ, FILL_START, FILL_ACC, DC_FL_GO_I, OPC_ADR) -- OPC_ADR: sensitivity audit
    -- This is the bus controller's state machine decoder.  A SIZE_N count of "000" means that all bytes
    -- to be transfered. After a bus transfer a value of x"0" indicates that no further bytes are required
    -- for a bus transfer.
    begin
        case BUS_CTRL_STATE is
            when IDLE =>
                if RESET_CPU_I = '1' then
                    NEXT_BUS_CTRL_STATE <= IDLE;  -- Reset condition (bus cycle terminated).
                elsif HALT_In = '0' then
                    NEXT_BUS_CTRL_STATE <= IDLE;  -- This is the 'HALT' condition.
                elsif (BR_In = '0' and RMC_PIN = '0') or ARB_STATE /= IDLE or BGACK_In = '0' then
                    NEXT_BUS_CTRL_STATE <= IDLE;  -- Arbitration, wait!
                elsif FILL_REQ = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- [DC] Data cache fill cycle.
                elsif DC_FL_GO_I = '1' then
                    NEXT_BUS_CTRL_STATE <= IDLE; -- [DC] The cache is updated: look the next read up after it.
                elsif PW_GO = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4; -- [PH2-WP] Operand cycle after a posted write, S0 next.
                elsif RD_REQ = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- New read cycle.
                elsif WR_REQ = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- New write cycle.
                elsif OPC_LEGACY = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- New read cycle.
                elsif PF_REQ = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- [F62] New prefetch cycle.
                elsif READ_ACCESS = '1' or WRITE_ACCESS = '1' or OPCODE_ACCESS = '1' or FILL_ACC = '1' then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- Pending (split) bus cycles.
                else
                    NEXT_BUS_CTRL_STATE <= IDLE;
                end if;
            when START_CYCLE =>
                if FILL_START = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4; -- [DC]
                elsif RD_REQ = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif WR_REQ = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif OPCODE_REQ = '1' and OPC_ADR(0) = '1' then -- [C3] the opcode address, not ADR_IN_P (a data address while a D-cache hit drops RD_REQ)
                    NEXT_BUS_CTRL_STATE <= IDLE; -- Abort due to address error.
                elsif OPC_LEGACY = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif PF_REQ = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4; -- [F62]
                else
                    NEXT_BUS_CTRL_STATE <= IDLE;
                end if;
            when DATA_C1C4 =>
                -- [F65] PF_CHAIN_GO is the only chain decision. S5 rolls to S0
                -- when it is set. Every cancel takes IDLE, and the queue re-arm
                -- and the SIZE/offset/width/OCS updates use the same signal.
                if CHAIN_GO = '1' then -- [PH2] or a waiting operand cycle.
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif BUS_CYC_RDY = '1' and SIZE_N = "000" then
                    NEXT_BUS_CTRL_STATE <= IDLE;
                else
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                end if;
        end case;
    end process BUS_CTRL_DEC;

    P_ADR_OFFS: process
    -- This process provides a temporary address offset during
    -- bus access.
    variable OFFSET_VAR     : std_logic_vector(2 downto 0) := "000";
    begin
        wait until CLK = '1' and CLK' event;
        if RESET_CPU_I = '1' then
            OFFSET_VAR := "000";
        elsif (T_SLICE = S2 and STERMn = '0') or T_SLICE = S3 then
            case BUS_WIDTH is
                when LONG_32 =>
                    case ADR_OUT_I(1 downto 0) is
                        when "11" => OFFSET_VAR := "001";
                        when "10" => OFFSET_VAR := "010";
                        when "01" => OFFSET_VAR := "011";
                        when others => OFFSET_VAR := "100";
                    end case;
                when WORD =>
                    case ADR_OUT_I(1 downto 0) is
                        when "01" | "11" => OFFSET_VAR := "001";
                        when others => OFFSET_VAR := "010";
                    end case;
                when BYTE =>
                    OFFSET_VAR := "001";
            end case;
        end if;
        --
        if RESET_CPU_I = '1' then
            ADR_OFFSET <= (others => '0');
        elsif RETRY = '1' then
            null; -- Do not update if there is a retry cycle.
        elsif CHAIN_GO = '1' then
            ADR_OFFSET <= (others => '0'); -- [F65] [PH2] New cycle starts at its base address.
        elsif BUS_CTRL_STATE /= IDLE and NEXT_BUS_CTRL_STATE = IDLE then
            ADR_OFFSET <= (others => '0');
        elsif BUS_CYC_RDY = '1' then
            ADR_OFFSET <= ADR_OFFSET + OFFSET_VAR; 
        end if;
    end process P_ADR_OFFS;

    -- [PH2-FMAX] The bus address comes from the address register (ADR_LATCH) instead of ADR_IN_P:
    -- they differ only in IDLE, where AS is negated and ADR_OUT_I is not used, so the
    -- control unit's address logic no longer reaches the address pins (and the ST bridge).
    ADR_OUT_I <= (F_CUR & '0') + ADR_OFFSET when PF_ACC = '1' else
                 (FILL_WADR & '0') + ADR_OFFSET when FILL_ACC = '1' else ADR_LAT + ADR_OFFSET; -- [F62] [DC]
    ADR_OUT_P <= ADR_OUT_I;

    P_ADR_10: process
    -- This logic is registered to enhance the system performance concerning fmax.
    begin
        wait until CLK = '1' and CLK' event;
        ADR_10 <= ADR_OUT_I(1 downto 0);
    end process P_ADR_10;

    -- Address and bus errors:
    -- [C3] Odd opcode address: OPC_ADR (PC_L), not ADR_IN_P. ADR_IN_P is the data address while the control
    -- unit requests data (DATA_RD/DATA_WR); a cachable read that hits in the data cache drops RD_REQ, so an odd
    -- byte read hit (e.g. move.b (a0,d5.w),d4 on TT-RAM) with an opcode request pending raised a false address
    -- error (vector 3, fault address = the data address). Seen only with caches on and cachable (TT-RAM) data.
    AERR_I <= '1' when BUS_CTRL_STATE = START_CYCLE and FILL_START = '0' and OPCODE_REQ = '1' and RD_REQ = '0' and WR_REQ = '0' and OPC_ADR(0) = '1' else '0';

    -- [F62] Opcode prefetch queue. The decoder requests one word at a time (OPC_RD, address
    -- OPC_ADR = PC_L). The queue fetches the instruction stream as long words in its own
    -- cycles while the bus is otherwise free (data requests keep priority), so up to three
    -- words wait ahead of the decoder and the fetches follow each other back to back.
    -- A request that is not the head of the stream restarts it (branch, exception) with a
    -- long-word fetch at the requested word: a branch target at 4n+2 costs two useful word
    -- cycles (4n+2, 4n+4) on the 16-bit port, like a misaligned long operand, instead of an
    -- aligned long whose first word is thrown away (that made the TOS 2.06 vblank sync loop
    -- at E013F6 too slow to finish in the 60 Hz blank: black screen at boot). A bus error is kept
    -- per word and only reported (OPCODE_VALID = 0) when the decoder takes that word, as on
    -- a 68030 where a prefetch fault is signalled only if the word is used. Odd addresses
    -- still take the ordinary opcode cycle path to raise the address error. A write that
    -- touches the queued or in-flight long words flushes the queue.
    OPC_LEGACY <= OPCODE_REQ and not RMC_HOLD when PREFETCH_Q = 0 else -- [RMC1] no opcode cycle inside the RMC sequence
                  OPCODE_REQ and To_Bit(OPC_ADR(0)) and not RMC_HOLD; -- [C3]
    Q_MATCH <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and Q_ADR = OPC_ADR(31 downto 1) and Q_FC = OPC_FC else '0';
    Q_HIT <= '1' when Q_MATCH = '1' and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and Q_CNT /= 0 else '0';
    Q_MISS <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and
                       not (Q_MATCH = '1' and (Q_CNT /= 0 or (INFL = '1' and INFL_STALE = '0') or S_FAULTED = '0')) else '0';
    Q_DUMMY <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPCODE_RDY_I = '0' and Q_DISMISS = '1' else '0';
    PF_REQ_RAW <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and S_FAULTED = '0' and INFL = '0' and (Q_CNT <= 1 or (Q_CNT = 2 and BUSY_EXH = '0' and PF_NOEARLY = '0')) and PF_HOLD = '0' else '0'; -- [PFCOF]
    -- [XH1] A long is requested while the queue still holds two words (was Q_CNT <= 1), so the stream keeps the
    -- bus busy across operand cycles (W->R, R->R, MOVEM.W, stack). Exception processing keeps the old threshold.
    -- [IC] A long word the instruction cache holds is taken from the cache (P_QUEUE) and never starts a bus
    -- cycle. With nothing cached (CIIN asserted on every cycle) IC_HIT is 0 and PF_REQ is the old request.
    PF_REQ <= PF_REQ_RAW and not To_Bit(IC_HIT) and not RMC_HOLD; -- [RMC1] no prefetch between the locked read and its write
    IC_TAKE <= PF_REQ_RAW and To_Bit(IC_HIT) and not Q_MISS and not RESET_CPU_I;
    IC_LK_ADR <= F_ADR(31 downto 2);
    IC_LK_FC2 <= Q_FC(2);
    -- [IC] Fill: every bus prefetch long reports its end with, per word, "no bus error and CIIN negated on its
    -- portion" (MC68030UM 5.7.1, 6.1.3.1 single entry mode). The cache fills aligned longs whose two words are
    -- OK, assembles the longs of a misaligned stream (4n+2 start) from consecutive fetches, and checks EI, FI
    -- and CDIS. Word 0 is the portion at offset 0 (ADR_OFFSET(1) = 0); the last portion always carries word 1.
    IC_FILL <= '1' when PF_DONE = '1' and RESET_CPU_I = '0' else '0';
    IC_FILL_MIS <= F_CUR(1);
    IC_FILL_OK(1) <= '1' when PF_FLT0 = '0' and PF_FLT1 = '0' and BUS_FLT = '0' and PF_CI0 = '0'
                             and PF_CI1 = '0' and CIIN_LAT = '1' else '0';
    IC_FILL_OK(0) <= '1' when PF_FLT0 = '0' and not (BUS_FLT = '1' and ADR_OFFSET(1) = '0') and PF_CI0 = '0'
                             and not (CIIN_LAT = '0' and ADR_OFFSET(1) = '0') else '0';
    IC_BREAK <= To_StdULogic(Q_MISS);
    IC_FILL_ADR <= F_CUR(31 downto 2);
    IC_FILL_FC2 <= F_FC(2);
    IC_FILL_DATA <= DATA_INMUX;
    PF_START <= '1' when BUS_CTRL_STATE = START_CYCLE and READ_ACCESS = '0' and WRITE_ACCESS = '0' and OPCODE_ACCESS = '0' and
                         RD_REQ = '0' and WR_REQ = '0' and OPC_LEGACY = '0' and PF_REQ = '1' and FILL_START = '0' else '0';
    PF_DONE <= '1' when PF_ACC = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" else '0';

    -- [F65] Arm the direct handoff one clock before the S5 edge. PF_REQ cannot
    -- be used here: it is held off while INFL = 1, and INFL clears on this
    -- cycle's completion edge. Q_CNT does not yet include this long's two
    -- words. The queue is words 0 to 3 (Q_CNT 0 to 4). Arming at Q_CNT <= 2
    -- overflowed: A then brought the count to 4 and the chained long wrote
    -- W(4)/W(5). Arm only at Q_CNT = 0, so A + the chained long is at most 4.
    -- The re-arm below also refuses to start that long unless the count after
    -- A is queued is <= 2. Registered, so the decoder does not combinationally
    -- depend on a signal that depends on BUS_BSY.
    P_PF_CHAIN: process
        variable NXT : std_logic_vector(2 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        NXT := SIZE_N;
        if BUS_WIDTH = LONG_32 and SIZE_N > x"3" and ADR_OUT_I(1 downto 0) = "01" then
            NXT := SIZE_N - "11";
        elsif BUS_WIDTH = LONG_32 and SIZE_N > x"2" and ADR_OUT_I(1 downto 0) = "10" then
            NXT := SIZE_N - "10";
        elsif BUS_WIDTH = LONG_32 and SIZE_N > x"1" and ADR_OUT_I(1 downto 0) = "11" then
            NXT := SIZE_N - '1';
        elsif BUS_WIDTH = LONG_32 then
            NXT := "000";
        elsif BUS_WIDTH = WORD and ADR_OUT_I(1 downto 0) = "11" then
            NXT := SIZE_N - '1';
        elsif BUS_WIDTH = WORD and ADR_OUT_I(1 downto 0) = "01" then
            NXT := SIZE_N - '1';
        elsif BUS_WIDTH = WORD and SIZE_N = "001" then
            NXT := SIZE_N - '1';
        elsif BUS_WIDTH = WORD then
            NXT := SIZE_N - "10";
        elsif BUS_WIDTH = BYTE then
            NXT := SIZE_N - '1';
        end if;
        if FAST_HANDOFF /= 0 and PF_ACC = '1' and BUS_CTRL_STATE = DATA_C1C4
           and T_SLICE = S3 and WAITSTATES = '0' and NXT = "000"
           and PREFETCH_Q /= 0 and S_VALID = '1' and S_FAULTED = '0' and INFL_STALE = '0'
           and Q_MISS = '0' and OPC_DISMISS = '0' and RMC = '0' and PF_HOLD = '0' -- [PFCOF]
           and OP_RD = '0' and OP_WR = '0'
           and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
           and BUS_FLT = '0' and RETRY = '0' and Q_CNT = 0 then
            PF_CHAIN <= '1';
        else
            PF_CHAIN <= '0';
        end if;
        -- [PH2] Same arm for a prefetch that ends while an operand request waits.
        -- No Q_CNT or stream condition: the operand cycle does not touch the queue.
        if PF_ACC = '1' and BUS_CTRL_STATE = DATA_C1C4
           and T_SLICE = S3 and WAITSTATES = '0' and NXT = "000"
           and RMC = '0' and (OP_RD = '1' or OP_WR = '1')
           and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
           and BUS_FLT = '0' and RETRY = '0' then
            OP_CHAIN <= '1';
        else
            OP_CHAIN <= '0';
        end if;
        -- [PH2] An operand cycle that ends while a queue prefetch waits. The IDLE
        -- clock after it would start that prefetch anyway (the control unit drops
        -- its request in the DATA_RDY clock), so only the two idle clocks go.
        -- Not during exception processing, where the handler's requests are not
        -- dropped in that clock and would come first.
        if (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_CTRL_STATE = DATA_C1C4
           and T_SLICE = S3 and WAITSTATES = '0' and NXT = "000"
           and RMC = '0' and BUSY_EXH = '0' and PF_REQ = '1'
           and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
           and BUS_FLT = '0' and RETRY = '0' then
            DP_CHAIN <= '1';
        else
            DP_CHAIN <= '0';
        end if;
        -- [F2] MOVEM read-ahead: a MOVEM read's last portion with more registers to come (RA_MORE).
        if READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and T_SLICE = S3 and WAITSTATES = '0' and NXT = "000"
           and RA_MORE = '1' and RMC = '0' and BUSY_EXH = '0'
           and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
           and BUS_FLT = '0' and RETRY = '0' then
            RA_ARM <= '1';
        else
            RA_ARM <= '0';
        end if;
    end process P_PF_CHAIN;

    -- [F65] One S5 decision for the FSM, the queue re-arm, and the SIZE,
    -- offset, width and OCS updates. RMC and a bus fault can appear after
    -- the S3 arm; without this, the FSM goes IDLE and the re-arm still sets
    -- INFL, so PF_REQ never fires again.
    PF_CHAIN_GO <= '1' when FAST_HANDOFF /= 0 and PF_CHAIN = '1' and BUS_CYC_RDY = '1' and SIZE_N = "000" and IC_HIT = '0' -- [IC]
                   and Q_MISS = '0' and OPC_DISMISS = '0' and RMC = '0' -- [PFCOF vchain] hold not applied at the S5 decision
                   and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                   and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';

    -- [PH2] S5 decision for the operand handoff. The request must still be
    -- there on the S5 edge (it is registered in the control unit, so this is
    -- not a loop through BUS_BSY), and every cancel takes the old IDLE path.
    OP_CHAIN_RAW <= '1' when OP_CHAIN = '1' and PF_ACC = '1' and BUS_CYC_RDY = '1' and SIZE_N = "000"
                   and (OP_RD = '1' or OP_WR = '1') and RMC = '0' and RA_HELD = '0' -- [F2] a held read-ahead is handed over instead and FILL_PEND = '0' and DC_DECIDE = '0' -- [DC]
                   and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                   and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';
    OP_CHAIN_GO <= (OP_CHAIN_RAW and not DC_CHIT) or
                   PW_GO or -- [PH2-WP] Same start actions, from the IDLE clock after a posted write.
                   WW_GO; -- [F3] Same start actions, on the S5 edge of the posted write before it.

    -- [F3] MOVEM register-to-memory, back-to-back writes (MC68030UM 11.6: the sequencer has the next MOVEM
    -- operand ready while the current one is on the bus). The control unit took the outcome of a posted
    -- write in its S3 clock (WR_EARLY/WR_TAKE: final there, no fault can follow) and presents the next
    -- register's write in the S4/S5 clock. The S5 edge rolls into it like the second portion of a long
    -- word (GAP 1) under the conditions of every other chain. Operand before a waiting prefetch.
    WW_GO <= '1' when WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000"
                      and WP_DONE = '1' and OP_WR = '1' and OP_RD = '0'
                      and RMC = '0' and BUSY_EXH = '0'
                      and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                      and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';
    WR_EARLY <= WP_GO;

    -- [PH2-WP] The control unit sees a posted write's DATA_RDY in the S4/S5 clock and presents its
    -- next operand request in the clock after S5 (IDLE). That request starts here without the
    -- START_CYCLE clock: the edge out of IDLE does what the OP_CHAIN edge does (access type, SSW,
    -- WP_BUFFER, SIZE_N, RDY, queue flush for a write, DSACK/offset/OCS reset; the top loads the
    -- address/FC latches in IDLE anyway) and the slice counter goes straight to S0. Only operand
    -- requests (no RMC, no exception processing), and every IDLE hold (reset, halt, arbitration)
    -- takes precedence.
    PW_GO <= '1' when BUS_CTRL_STATE = IDLE and WP_LAST = '1' and ((OP_RD = '0' and OP_WR = '1') or (OP_RD = '1' and DC_ON = '0')) -- [DC]
                      and RA_HELD = '0' -- [F2]
                      and RMC = '0' and (BUSY_EXH = '0' or EXH_STK = '1') and SIZE_N = "000" -- [XT2]
                      and READ_ACCESS = '0' and WRITE_ACCESS = '0' and OPCODE_ACCESS = '0'
                      and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                      and RETRY = '0' and RESET_CPU_I = '0' else '0';
    CH_WR <= OP_WR and not OP_RD; -- Read has priority, as in START_CYCLE.
    DP_CHAIN_RAW <= '1' when DP_CHAIN = '1' and (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_CYC_RDY = '1'
                   and SIZE_N = "000" and PF_REQ = '1' and Q_MISS = '0' and OPC_DISMISS = '0'
                   and RMC = '0' and BUSY_EXH = '0' and DC_DPBLK = '0' -- [DC]
                   and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                   and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';
    DP_CHAIN_GO <= DP_CHAIN_RAW and not RA_GO and not WW_GO; -- [F2] [F3] The next MOVEM operand comes before the queue (operand priority).

    -- [F2] MOVEM read-ahead. S3 of the last portion of a MOVEM read while the control unit waits for it and the
    -- register list has a further register (RA_MORE): arm; the S5 edge rolls into the read of the next operand
    -- (address latch + operand size, same FC and size; RA_LD) under the conditions of every other chain.
    -- No RMC, no exception processing. With the data cache on only behind a cache-inhibited read (CIIN asserted, as
    -- the ST bridge does on every cycle): nothing of that memory is cached, so the read the 68030 would run is a bus
    -- read too, and no fill is pending (a read-ahead is never looked up or filled, like the other chained reads).
    RA_GO <= '1' when RA_ARM = '1' and READ_ACCESS = '1' and BUS_CYC_RDY = '1' and SIZE_N = "000" and RA_MORE = '1'
                      and RMC = '0' and BUSY_EXH = '0' and (DC_ON = '0' or CIIN_LAT = '0') and FILL_PEND = '0' and DC_DECIDE = '0'
                      and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                      and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';
    RA_LD <= RA_GO;
    -- The read-ahead ends (data or bus error). The control unit asked for it (OP_RD at the matching address):
    -- DATA_RDY as for any read. Not asked yet: held. Asked for something else: dropped (never expected).
    RA_END <= '1' when RA_ACC = '1' and READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" else '0';
    RA_MATCH <= '1' when OP_RD = '1' and ADR_NXT = ADR_LAT else '0';
    RA_TAKE <= '1' when RA_HELD = '1' and OP_RD = '1' and ADR_NXT = RA_HADR and DATA_RDY_I = '0' and RESET_CPU_I = '0' else '0';
    RA_DROP <= '1' when (RA_HELD = '1' and ((OP_RD = '1' and ADR_NXT /= RA_HADR) or BUSY_EXH = '1')) or
                        (RA_END = '1' and OP_RD = '1' and ADR_NXT /= ADR_LAT) else '0';

    P_RA: process
    begin
        wait until CLK = '1' and CLK' event;
        RA_GO_D <= RA_GO;
        if RESET_CPU_I = '1' then
            RA_ACC <= '0';
        elsif RA_GO = '1' then
            RA_ACC <= '1';
        elsif RA_END = '1' or BUS_CTRL_STATE = IDLE then
            RA_ACC <= '0';
        end if;
        if RESET_CPU_I = '1' or RA_TAKE = '1' or RA_DROP = '1' then
            RA_HELD <= '0';
        elsif RA_END = '1' and OP_RD = '0' then
            RA_HELD <= '1';
            RA_HADR <= ADR_LAT;
        end if;
        -- pragma translate_off
        assert RA_DROP = '0' report "F2: MOVEM read-ahead dropped (request did not match)" severity warning;
        -- pragma translate_on
    end process P_RA;

    CHAIN_GO <= PF_CHAIN_GO or OP_CHAIN_GO or DP_CHAIN_GO or RA_GO;
    OP_CHAIN_LD <= OP_CHAIN_GO or DP_CHAIN_GO; -- The top level loads its address/FC latches as in IDLE.

    -- [DC] Data cache (MC68030UM 6.1.2, docs/DCACHE_DESIGN.md). A read request is looked up in its
    -- START_CYCLE clock (address and FC latched, as on the pins): a hit delivers the operand from the
    -- cache with DATA_RDY on that edge and starts no bus cycle; the bus is free for the queue. RMC reads
    -- always miss (6.1.2.2). Chained reads (OP_CHAIN, PW_GO) are not looked up and use the bus.
    DC_RHIT <= '1' when BUS_CTRL_STATE = START_CYCLE and RD_REQ_IN = '1' and DC_PH = '1' and DC_PV = '1' and RMC = '0' and RA_HELD = '0' and -- [F2]
                        READ_ACCESS = '0' and WRITE_ACCESS = '0' and OPCODE_ACCESS = '0' and FILL_ACC = '0' and
                        FILL_REQ = '0' and RESET_CPU_I = '0' else '0';
    FILL_START <= '1' when BUS_CTRL_STATE = START_CYCLE and FILL_REQ = '1' and READ_ACCESS = '0' and
                           WRITE_ACCESS = '0' and OPCODE_ACCESS = '0' and FILL_ACC = '0' else '0';
    RD_REQ <= RD_REQ_IN and not DC_RHIT and not FILL_START and not RA_HELD; -- [F2] a held read-ahead is handed over instead
    WR_REQ <= WR_REQ_IN and not FILL_START;
    -- The lookup is registered: the request's address, FC and size of each clock (ADR_NXT, the value the
    -- address latch takes in IDLE) are looked up and the result kept for the next clock (DC_PH, DC_PD), so
    -- START_CYCLE and the S5 chain decision use a flip-flop. A cache update in that clock cancels it.
    DC_LK_ADR <= ADR_NXT;
    DC_LK_FC <= FC_NXT;
    P_DCP: process
    begin
        wait until CLK = '1' and CLK' event;
        DC_PH <= DC_HIT and not DC_WR_GO_I and not DC_FL_GO_I;
        DC_PD <= DC_HIT_DATA;
        DC_PV <= To_StdULogic(OP_RD and not DATA_RDY_I);
    end process P_DCP;
    -- A read waiting for the end of a prefetch: a hit is delivered on the S5 edge instead of the chained cycle.
    DC_CHIT <= '1' when OP_CHAIN_RAW = '1' and CH_WR = '0' and DC_PH = '1' and DC_PV = '1' and DATA_RDY_I = '0' else '0';
    DC_LK_SZ <= "100" when OP_SIZE = LONG else "010" when OP_SIZE = WORD else "001";

    -- [DC] Writes: the cache is updated from the write's data (WP_BUFFER) in the clock after its first bus
    -- cycle started, before the external write ends (6.1.2: "the cache contains the new value even if the
    -- external write terminates in a bus error"). The bus write runs as without the cache.
    DC_WSTB <= '1' when (BUS_CTRL_STATE = START_CYCLE and NEXT_BUS_CTRL_STATE = DATA_C1C4 and WR_REQ = '1' and
                         RD_REQ = '0' and FILL_START = '0') or (OP_CHAIN_GO = '1' and CH_WR = '1') else '0';
    P_DCW: process
    begin
        wait until CLK = '1' and CLK' event;
        DC_WR_GO_I <= To_StdULogic(DC_WSTB and not RESET_CPU_I);
        if DC_WSTB = '1' then
            if OP_CHAIN_GO = '1' then
                DCW_ADR <= ADR_NXT; DCW_FC <= FC_NXT;
            else
                DCW_ADR <= ADR_LAT; DCW_FC <= FC_LAT;
            end if;
            case OP_SIZE is
                when LONG => DCW_SZ <= "100";
                when WORD => DCW_SZ <= "010";
                when BYTE => DCW_SZ <= "001";
            end case;
        end if;
    end process P_DCW;
    DC_WR_DATA <= WP_BUFFER;
    DC_WR_GO <= DC_WR_GO_I;
    DC_WR_ADR <= DCW_ADR;
    DC_WR_FC <= DCW_FC;
    DC_WR_SZ <= DCW_SZ;

    -- [DC] Reads: every 16-bit port portion delivers a whole aligned word, a 32-bit port a whole long word
    -- (6.1.3.1). Each word is kept for the entry it belongs to (E0 = operand A31:2, E1 = the next long word)
    -- with "CIIN negated and no bus error". When every operand portion was cachable, the cache enabled and
    -- not frozen, not RMC and not CPU space, fill cycles (one word each, FILL_ACC) read the words of the
    -- touched entries the operand did not read: a byte at $03 is followed by a word at $00, as Figure 6-6.
    -- They run after the operand's DATA_RDY. A fill cycle with a bus error, CIIN asserted or an 8-bit port
    -- ends the fill of its entry: no exception, the entry is not validated. The cache is updated in the
    -- clock after the last cycle (DC_FL_GO). With CIIN asserted (every ST cycle) no fill cycle runs.
    P_DC_CAP: process
    begin
        wait until CLK_F = '1' and CLK_F' event;
        if ((T_SLICE = S2 or T_SLICE = S3) and STERMn = '0') or T_SLICE = S4 then
            DC_PORT <= DATA_PORT_IN; -- Same sample as IN_MUX.
        end if;
    end process P_DC_CAP;

    DC_OX <= '1' when (DC_OSZ = "100" and DC_OA(1 downto 0) /= "00") or (DC_OSZ = "010" and DC_OA(1 downto 0) = "11") else '0';
    DC_NEED <= '1' when DC_FILL_EN = '1' and FB_CA = '1' and FB_BE0 = '0' and FB_BE1 = '0' and DC_ORMC = '0' and
                        DC_OFC /= "111" else '0';
    DC_MISS(3) <= not FB_OK0(1) and not FB_AB0;
    DC_MISS(2) <= not FB_OK0(0) and not FB_AB0;
    DC_MISS(1) <= DC_OX and not FB_OK1(1) and not FB_AB1;
    DC_MISS(0) <= DC_OX and not FB_OK1(0) and not FB_AB1;
    FILL_REQ <= '1' when (FILL_PEND = '1' or (DC_DECIDE = '1' and DC_NEED = '1')) and DC_MISS /= "0000" and
                         RESET_CPU_I = '0' else '0';
    FILL_WADR <= DC_OA(31 downto 2) & '0' when DC_MISS(3) = '1' else
                 DC_OA(31 downto 2) & '1' when DC_MISS(2) = '1' else
                 DC_OA1 & '0' when DC_MISS(1) = '1' else
                 DC_OA1 & '1'; -- [F65] incrementer moved before the register (bus address -> MMU -> AS -> bridge path)
    DC_FIN <= '1' when (DC_DECIDE = '1' and (DC_NEED = '0' or DC_MISS = "0000")) or
                       (FILL_PEND = '1' and DC_MISS = "0000" and FILL_ACC = '0') else '0';
    -- Only when the cache can change: something was read cachable, or a bus error hit an entry.
    DC_FL_GO_I <= '1' when RESET_CPU_I = '0' and DC_FIN = '1' and DC_ON = '1' and
                           (FB_OK0 /= "00" or FB_OK1 /= "00" or FB_BE0 = '1' or FB_BE1 = '1') else '0';
    DC_DPBLK <= '1' when READ_ACCESS = '1' and DC_TRK = '1' and DC_FILL_EN = '1' and FB_CA = '1' and CIIN_LAT = '1' and
                         DC_ORMC = '0' and DC_OFC /= "111" else '0';
    DC_FL_GO <= DC_FL_GO_I;
    DC_FL_A0 <= DC_OA(31 downto 2);
    DC_FL_FC <= DC_OFC;
    DC_FL_U1 <= DC_OX;
    DC_FL_D0 <= FB_D0;
    DC_FL_D1 <= FB_D1;
    DC_FL_OK0 <= FB_OK0;
    DC_FL_OK1 <= FB_OK1;
    DC_FL_BE0 <= FB_BE0;
    DC_FL_BE1 <= FB_BE1;

    P_DCF: process
        variable E1 : boolean;
        variable OK : std_logic_vector(1 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        DC_DECIDE <= '0';
        if DC_FIN = '1' then
            FILL_PEND <= '0';
        elsif DC_DECIDE = '1' and DC_NEED = '1' and DC_MISS /= "0000" then
            FILL_PEND <= '1';
        end if;
        if (BUS_CTRL_STATE = START_CYCLE and NEXT_BUS_CTRL_STATE = DATA_C1C4 and RD_REQ = '1' and FILL_START = '0' and
            READ_ACCESS = '0' and WRITE_ACCESS = '0' and OPCODE_ACCESS = '0' and FILL_ACC = '0') or
           (OP_CHAIN_GO = '1' and CH_WR = '0') then
            DC_TRK <= '1'; -- A new read.
            if OP_CHAIN_GO = '1' then
                DC_OA <= ADR_NXT; DC_OFC <= FC_NXT; DC_OA1 <= ADR_NXT(31 downto 2) + '1';
            else
                DC_OA <= ADR_LAT; DC_OFC <= FC_LAT; DC_OA1 <= ADR_LAT(31 downto 2) + '1';
            end if;
            case OP_SIZE is
                when LONG => DC_OSZ <= "100";
                when WORD => DC_OSZ <= "010";
                when BYTE => DC_OSZ <= "001";
            end case;
            DC_ORMC <= RMC;
            FB_OK0 <= "00"; FB_OK1 <= "00"; FB_BE0 <= '0'; FB_BE1 <= '0'; FB_AB0 <= '0'; FB_AB1 <= '0';
            FB_CA <= '1'; FB_PF <= '0';
        elsif BUS_CTRL_STATE = DATA_C1C4 and ((READ_ACCESS = '1' and DC_TRK = '1') or FILL_ACC = '1') then
            E1 := ADR_OUT_I(31 downto 2) /= DC_OA(31 downto 2);
            if BUS_FLT = '1' then
                FB_PF <= '1';
                if HALT_In = '1' then -- A bus error (BERR with HALT is a retry).
                    if E1 then FB_BE1 <= '1'; FB_AB1 <= '1'; else FB_BE0 <= '1'; FB_AB0 <= '1'; end if;
                    if READ_ACCESS = '1' then FB_CA <= '0'; end if;
                end if;
            end if;
            if BUS_CYC_RDY = '1' then
                FB_PF <= '0';
                if BUS_FLT = '0' and FB_PF = '0' then
                    if BUS_WIDTH = LONG_32 then
                        OK := "11";
                        if E1 then FB_D1 <= DC_PORT; else FB_D0 <= DC_PORT; end if;
                    elsif BUS_WIDTH = WORD and ADR_OUT_I(1) = '0' then
                        OK := "10";
                        if E1 then FB_D1(31 downto 16) <= DC_PORT(31 downto 16); else FB_D0(31 downto 16) <= DC_PORT(31 downto 16); end if;
                    elsif BUS_WIDTH = WORD then
                        OK := "01";
                        if E1 then FB_D1(15 downto 0) <= DC_PORT(31 downto 16); else FB_D0(15 downto 0) <= DC_PORT(31 downto 16); end if;
                    else
                        OK := "00"; -- 8-bit port: not filled.
                    end if;
                    if CIIN_LAT = '1' and OK /= "00" then
                        if E1 then FB_OK1 <= FB_OK1 or OK; else FB_OK0 <= FB_OK0 or OK; end if;
                    else
                        if READ_ACCESS = '1' then FB_CA <= '0'; end if;
                        if FILL_ACC = '1' then
                            if E1 then FB_AB1 <= '1'; else FB_AB0 <= '1'; end if;
                        end if;
                    end if;
                end if;
                if READ_ACCESS = '1' and SIZE_N = "000" then
                    DC_TRK <= '0';
                    DC_DECIDE <= '1'; -- The operand is complete (or faulted).
                end if;
            end if;
        end if;
        if RESET_CPU_I = '1' then
            DC_TRK <= '0';
            DC_DECIDE <= '0';
            FILL_PEND <= '0';
        end if;
    end process P_DCF;

    P_QUEUE: process
    variable W      : QWORDS_T;
    variable F      : bit_vector(0 to 3);
    variable CNT    : integer range 0 to 4;
    variable F0, F1 : bit;
    variable WDIST  : std_logic_vector(31 downto 2);
    variable WDIST2 : std_logic_vector(31 downto 2);
    begin
        wait until CLK = '1' and CLK' event;
        if PREFETCH_Q /= 0 then
            W := Q_W; F := Q_F; CNT := Q_CNT;
            if Q_HIT = '1' then
                W(0 to 2) := W(1 to 3); F(0 to 2) := F(1 to 3);
                CNT := CNT - 1;
                Q_ADR <= Q_ADR + '1';
            end if;
            -- Bus errors of the running prefetch, per word.
            if PF_ACC = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' then
                if ADR_OFFSET(1) = '0' then PF_FLT0 <= '1'; else PF_FLT1 <= '1'; end if;
            end if;
            if PF_START = '1' or DP_CHAIN_GO = '1' then -- [PH2]
                INFL <= '1';
                INFL_STALE <= '0';
                F_CUR <= F_ADR;
                F_FC <= Q_FC;
                F_ADR <= F_ADR + "10";
                PF_FLT0 <= '0';
                PF_FLT1 <= '0';
            end if;
            -- [IC] CIIN of every finished portion of the running prefetch long.
            if PF_ACC = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and CIIN_LAT = '0' then
                if ADR_OFFSET(1) = '0' then PF_CI0 <= '1'; else PF_CI1 <= '1'; end if;
            end if;
            if PF_START = '1' or DP_CHAIN_GO = '1' then
                PF_CI0 <= '0';
                PF_CI1 <= '0';
            end if;
            -- [IC] Instruction cache hit: the long word (or, for a stream start at 4n+2, its second word) goes
            -- into the queue in this clock without a bus cycle. PF_REQ_RAW needs Q_CNT <= 1, so at most 3 words.
            if IC_TAKE = '1' then
                if F_ADR(1) = '0' then
                    W(CNT) := IC_HIT_DATA(31 downto 16); F(CNT) := '0'; CNT := CNT + 1;
                    W(CNT) := IC_HIT_DATA(15 downto 0); F(CNT) := '0'; CNT := CNT + 1;
                    F_ADR <= F_ADR + "10";
                else
                    W(CNT) := IC_HIT_DATA(15 downto 0); F(CNT) := '0'; CNT := CNT + 1;
                    F_ADR <= F_ADR + '1';
                end if;
            end if;
            if PF_DONE = '1' then
                F0 := PF_FLT0 or (To_Bit(BUS_FLT) and not To_Bit(ADR_OFFSET(1)));
                F1 := F0 or PF_FLT1 or (To_Bit(BUS_FLT) and To_Bit(ADR_OFFSET(1)));
                if INFL_STALE = '0' then
                    W(CNT) := DATA_INMUX(31 downto 16); F(CNT) := F0; CNT := CNT + 1;
                    W(CNT) := DATA_INMUX(15 downto 0); F(CNT) := F1; CNT := CNT + 1;
                    if F1 = '1' then
                        S_FAULTED <= '1'; -- Words up to the fault are queued; refetch on demand only.
                    end if;
                end if;
                INFL <= '0';
                INFL_STALE <= '0';
            end if;
            -- A write into the queued or in-flight long words flushes the queue.
            WDIST := ADR_IN_P(31 downto 2) - Q_ADR(31 downto 2) + '1'; -- From the long word below the head (misaligned writes).
            if BUS_CTRL_STATE = START_CYCLE and RD_REQ = '0' and WR_REQ = '1' and READ_ACCESS = '0' and
               WRITE_ACCESS = '0' and OPCODE_ACCESS = '0' and WDIST(31 downto 4) = x"000000" & "0000" then
                S_VALID <= '0';
                CNT := 0;
                if INFL = '1' then
                    INFL_STALE <= '1';
                end if;
            end if;
            -- [PH2] The same flush for a write chained on the S5 edge. The finishing
            -- prefetch long is queued above first, so it is dropped with the rest.
            WDIST2 := ADR_NXT(31 downto 2) - Q_ADR(31 downto 2) + '1';
            if OP_CHAIN_GO = '1' and CH_WR = '1' and WDIST2(31 downto 4) = x"000000" & "0000" then
                S_VALID <= '0';
                CNT := 0;
            end if;
            -- Restart the stream at the requested word.
            if Q_MISS = '1' then
                CNT := 0;
                S_VALID <= '1';
                S_FAULTED <= '0';
                Q_ADR <= OPC_ADR(31 downto 1);
                Q_FC <= OPC_FC;
                F_ADR <= OPC_ADR(31 downto 1);
                if (INFL = '1' and PF_DONE = '0') or PF_START = '1' then
                    INFL_STALE <= '1';
                end if;
            end if;
            -- [F65] Same decision as the FSM. A cancel that sends the bus to
            -- IDLE must not leave INFL set, or PF_REQ never fires again.
            if PF_CHAIN_GO = '1' and PF_DONE = '1' and CNT <= 2 then
                INFL <= '1';
                INFL_STALE <= '0';
                F_CUR <= F_ADR;
                F_ADR <= F_ADR + "10";
                PF_FLT0 <= '0';
                PF_FLT1 <= '0';
                PF_CI0 <= '0'; -- [IC]
                PF_CI1 <= '0';
            end if;
            if RESET_CPU_I = '1' then
                S_VALID <= '0';
                CNT := 0;
                INFL <= '0';
                INFL_STALE <= '0';
            end if;
            Q_W <= W; Q_F <= F; Q_CNT <= CNT;
        end if;
    end process P_QUEUE;

    -- [F62c] The decoder's own dismissal flag, not a registered copy of its logic: one flip-flop decides
    -- whether the next opcode ready is a dummy, so the decoder and the queue cannot disagree.
    Q_DISMISS <= OPC_DISMISS;
    Q_STREAM <= Q_W(0) & Q_W(1) & Q_W(2) & Q_W(3); -- [PFCOF2]
    Q_COUNT <= Q_CNT;
    Q_HEAD <= Q_ADR; -- [FRM]
    DBG_IC <= F_ADR(7 downto 1) & F_CUR(7 downto 2) & IC_HIT & To_StdULogic(PF_DONE) & F_CUR(1); -- FalconFPGA DIAG STR
    DBG_QF <= To_StdULogic(Q_HIT) & To_StdULogic(IC_TAKE) & To_StdULogic(PF_DONE) & To_StdULogic(Q_MISS); -- FalconFPGA DIAG STR
    Q_FAULT <= Q_F; -- [FRM]

    FC_OUT <= F_FC when PF_ACC = '1' else DC_OFC when FILL_ACC = '1' else FC_LAT; -- [F62] [PH2-FMAX] [DC] registered, as ADR_OUT_I

    -- The output multiplexer is as follows:
    -- SIZE    ADR    Bytes (L = long word port, W = word port, B = Byte port, x = not used by either port)
    --  00      00    3 (L, W, B)    2 (L, W   )    1 (L      )    0 (L      )
    --  00      01    3 (      B)    3 (L, W   )    2 (L      )    1 (L      )
    --  00      10    3 (   W, B)    2 (   W   )    3 (L      )    2 (L      )
    --  00      11    3 (      B)    2 (   W   )    -----x-----    0 (L      )
    --  11      00    2 (L, W, B)    1 (L, W   )    0 (L      )    -----x-----     
    --  11      01    2 (      B)    2 (L, W   )    1 (L      )    0 (L      )
    --  11      10    1 (   W, B)    0 (   W   )    1 (L      )    0 (L      )
    --  11      11    1 (      B)    1 (   W   )    -----x-----    1 (L      )
    --  10      00    1 (L, W, B)    0 (L, W   )    -----x-----    -----x-----
    --  10      01    1 (      B)    1 (L, W   )    0 (L      )    -----x-----
    --  10      10    1 (   W, B)    0 (   W   )    1 (L      )    0 (L      )
    --  10      11    1 (      B)    1 (   W   )    -----x-----    1 (L      )
    --  01      00    0 (L, W, B)    -----x-----    -----x-----    -----x-----
    --  01      01    0 (      B)    0 (L, W   )    -----x-----    -----x-----
    --  01      10    0 (   W, B)    -----x-----    0 (L      )    -----x-----
    --  01      11    0 (      B)    0 (   W   )    -----x-----    0 (L      )

    DATA_PORT_OUT <= -- Data output multiplexer.
        -- LONG:
        WP_BUFFER(31 downto 0) when SIZE_I = "00" and ADR_OUT_I(1 downto 0) = "00" else
        WP_BUFFER(31 downto 24) & WP_BUFFER(31 downto 8) when SIZE_I = "00" and ADR_OUT_I(1 downto 0) = "01" else
        WP_BUFFER(31 downto 16) & WP_BUFFER(31 downto 16) when SIZE_I = "00" and ADR_OUT_I(1 downto 0) = "10" else
        WP_BUFFER(31 downto 24) & WP_BUFFER(31 downto 16) & WP_BUFFER(31 downto 24) when SIZE_I = "00" and ADR_OUT_I(1 downto 0) = "11" else
        -- 3 bytes:
        WP_BUFFER(23 downto 0) & WP_BUFFER(23 downto 16) when SIZE_I = "11" and ADR_OUT_I(1 downto 0) = "00" else
        WP_BUFFER(23 downto 16) & WP_BUFFER(23 downto 0) when SIZE_I = "11" and ADR_OUT_I(1 downto 0) = "01" else
        WP_BUFFER(23 downto 8) & WP_BUFFER(23 downto 8) when SIZE_I = "11" and ADR_OUT_I(1 downto 0) = "10" else
        WP_BUFFER(23 downto 16) & WP_BUFFER(23 downto 8) & WP_BUFFER(23 downto 16) when SIZE_I = "11" and ADR_OUT_I(1 downto 0) = "11" else
        -- Word:
        WP_BUFFER(15 downto 0) & WP_BUFFER(15 downto 0) when SIZE_I = "10" and ADR_OUT_I(1 downto 0) = "00" else
        WP_BUFFER(15 downto 8) & WP_BUFFER(15 downto 0) & WP_BUFFER(15 downto 8) when SIZE_I = "10" and ADR_OUT_I(1 downto 0) = "01" else
        WP_BUFFER(15 downto 0) & WP_BUFFER(15 downto 0) when SIZE_I = "10" and ADR_OUT_I(1 downto 0) = "10" else
        WP_BUFFER(15 downto 8) & WP_BUFFER(15 downto 0) & WP_BUFFER(15 downto 8) when SIZE_I = "10" and ADR_OUT_I(1 downto 0) = "11" else
        -- Byte: 
        WP_BUFFER(7 downto 0) & WP_BUFFER(7 downto 0) & WP_BUFFER(7 downto 0) & WP_BUFFER(7 downto 0); -- SIZE = "01".

    -- [IC] CIIN sampling as MC68030UM 7.2.8/7.2.9/7.2.10: "For asynchronous read cycles, the value of CIIN
    -- is internally latched on the rising edge of bus cycle state 4" (here the rising edge that ends S3,
    -- the last one with wait states) and for STERM cycles on the rising edge at which STERM is recognized.
    -- The value is held until the same edge of the next cycle, past the data latch and the fill.
    P_CIIN: process
    begin
        wait until CLK = '1' and CLK' event;
        if T_SLICE = S3 or (T_SLICE = S1 and STERMn = '0') then
            CIIN_LAT <= CIINn;
        end if;
    end process P_CIIN;

    IN_MUX: process
    -- This is the input multiplexer which can handle up to four bytes.
    begin
    wait until CLK_F = '1' and CLK_F' event; -- [F58] was the falling edge of CLK
        --
        if ((T_SLICE = S2 or T_SLICE = S3) and STERMn = '0') or T_SLICE = S4 then
            case BUS_WIDTH is
                when BYTE =>
                    case SIZE_I is
                        when "00" => DATA_INMUX(31 downto 24) <= DATA_PORT_IN(31 downto 24); -- LONG.
                        when "11" => DATA_INMUX(23 downto 16) <= DATA_PORT_IN(31 downto 24); -- Three bytes.
                        when "10" => DATA_INMUX(15 downto 8) <= DATA_PORT_IN(31 downto 24); -- Word.
                        when others => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(31 downto 24); -- Byte.
                    end case;
                when WORD =>
                    case SIZE_I is
                        when "01" => -- Byte.
                            case ADR_10 is
                                when "00" | "10" => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(31 downto 24);
                                when others => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(23 downto 16); -- "01", "11".
                            end case;
                        when "10" => -- Word.
                            case ADR_10 is
                                when "00" => DATA_INMUX(15 downto 0) <= DATA_PORT_IN(31 downto 16);
                                when "01" => DATA_INMUX(15 downto 8) <= DATA_PORT_IN(23 downto 16);
                                when "10" => DATA_INMUX(15 downto 0) <= DATA_PORT_IN(31 downto 16);
                                when others => DATA_INMUX(15 downto 8) <= DATA_PORT_IN(23 downto 16); -- "11".
                            end case;
                        when "11" => -- Three bytes.
                            case ADR_10 is
                                when "00" => DATA_INMUX(23 downto 8) <= DATA_PORT_IN(31 downto 16);
                                when "01" => DATA_INMUX(23 downto 16) <= DATA_PORT_IN(23 downto 16);
                                when "10" => DATA_INMUX(23 downto 8) <= DATA_PORT_IN(31 downto 16);
                                when others => DATA_INMUX(23 downto 16) <= DATA_PORT_IN(23 downto 16); -- "11".
                            end case;
                        when others => -- "00" = LONG.
                            case ADR_10 is
                                when "00" => DATA_INMUX(31 downto 16) <= DATA_PORT_IN(31 downto 16);
                                when "01" => DATA_INMUX(31 downto 24) <= DATA_PORT_IN(23 downto 16);
                                when "10" => DATA_INMUX(31 downto 16) <= DATA_PORT_IN(31 downto 16);
                                when others => DATA_INMUX(31 downto 24) <= DATA_PORT_IN(23 downto 16); -- "11".
                            end case;
                    end case;
                when LONG_32 =>
                    case SIZE_I is
                        when "01" => -- Byte.
                            case ADR_10 is
                                when "00" => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(31 downto 24);
                                when "01" => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(23 downto 16);
                                when "10" => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(15 downto 8);
                                when others => DATA_INMUX(7 downto 0) <= DATA_PORT_IN(7 downto 0); -- "11".
                            end case;
                        when "10" => -- Word.
                            case ADR_10 is
                                when "00" => DATA_INMUX(15 downto 0) <= DATA_PORT_IN(31 downto 16);
                                when "01" => DATA_INMUX(15 downto 0) <= DATA_PORT_IN(23 downto 8);
                                when "10" => DATA_INMUX(15 downto 0) <= DATA_PORT_IN(15 downto 0);
                                when others => DATA_INMUX(15 downto 8) <= DATA_PORT_IN(7 downto 0); -- "11".
                            end case;
                        when "11" => -- Three bytes.
                            case ADR_10 is
                                when "00" => DATA_INMUX(23 downto 0) <= DATA_PORT_IN(31 downto 8);
                                when "01" => DATA_INMUX(23 downto 0) <= DATA_PORT_IN(23 downto 0);
                                when "10" => DATA_INMUX(23 downto 8) <= DATA_PORT_IN(15 downto 0);
                                when others => DATA_INMUX(23 downto 16) <= DATA_PORT_IN(7 downto 0); -- "11".
                            end case;
                        when others => -- "00" = LONG.
                            case ADR_10 is
                                when "00" => DATA_INMUX(31 downto 0) <= DATA_PORT_IN(31 downto 0);
                                when "01" => DATA_INMUX(31 downto 8) <= DATA_PORT_IN(23 downto 0);
                                when "10" => DATA_INMUX(31 downto 16) <= DATA_PORT_IN(15 downto 0);
                                when others => DATA_INMUX(31 downto 24) <= DATA_PORT_IN(7 downto 0); -- "11".
                            end case;
                    end case;
            end case;
        end if;
    end process IN_MUX;

    VALIDATION: process
    -- These flip flops detect a fault during the read operation over one or
    -- several bytes or during the write operation.
    begin
        wait until CLK = '1' and CLK' event;
        --
        if RESET_CPU_I = '1' then
            OPCODE_VALID <= '1';
        elsif PREFETCH_Q /= 0 and Q_HIT = '1' then -- [F62] Fault flag of the served word.
            if Q_F(0) = '1' then OPCODE_VALID <= '0'; else OPCODE_VALID <= '1'; end if;
        elsif PREFETCH_Q = 0 and OPCODE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' then
            OPCODE_VALID <= '0';
        elsif OPCODE_RDY_I = '1' then
            OPCODE_VALID <= '1'; -- Reset after use, TRAP_BERR is asserted during DATA_RDY.
        end if;
        --
        if RESET_CPU_I = '1' then
            DATA_VALID_I <= '1';
        elsif READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' and HALT_In = '0' then
            null; -- This is the RETRY condition, no bus error.
        elsif (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' then
            DATA_VALID_I <= '0'; -- [F62] Data cycles only: an opcode fetch fault must not fail the next data read.
        elsif DATA_RDY_I = '1' or RA_DROP = '1' then
            DATA_VALID_I <= '1'; -- Reset after use, TRAP_BERR is asserted during DATA_RDY. [F2] A dropped read-ahead's fault is void.
        end if;
    end process VALIDATION;

    PREFETCH_BUFFERS: process
    -- These are the data and the operation code input registers. After a last read to the registered
    -- input multiplexer, the respective data is copied from the input multiplexer to these buffers.
    -- The opcode buffer is always written with 32 bit data. The data buffers may contain invalid bytes
    -- in case of word or byte data size.
    variable DBUFFER_MEM    : std_logic_vector(31 downto 8) := x"000000";
    variable RDY_VAR        : bit := '0';
    begin
        wait until CLK = '1' and CLK' event;
        --
        OPCODE_RDY_I <= '0'; -- This is a strobe.
        DATA_RDY_I <= '0'; -- This is a strobe.
        --
        -- The following variable is responsible, that the _RDY signals are
        -- always strobes.
        if OP_CHAIN_GO = '1' or DP_CHAIN_GO = '1' or RA_GO = '1' then -- [PH2] [PH2-WP] First: a posted write's DATA_RDY can
            RDY_VAR := '1';                                 -- be high on the chain edge (never the case before).
        elsif DATA_RDY_I = '1' and RA_GO_D = '1' then
            null; -- [F2] DATA_RDY of the read that rolled into the read-ahead: the read-ahead keeps its ready.
        elsif DATA_RDY_I = '1' or (PREFETCH_Q = 0 and OPCODE_RDY_I = '1') then -- [F62] Queue hits do not end a bus cycle.
            RDY_VAR := '0';
        elsif BUS_CTRL_STATE = START_CYCLE then
            RDY_VAR := '1';
        end if;
        -- Opcode cycle:
        if AERR_I = '1' then
            OPCODE_RDY_I <= '1';
        elsif PREFETCH_Q /= 0 then -- [F62] Served from the prefetch queue (P_QUEUE).
            if Q_DUMMY = '1' then
                OPCODE_RDY_I <= '1'; -- Dismissed by the decoder (pipe flush with a pending request).
            elsif Q_HIT = '1' then
                OBUFFER <= Q_W(0);
                OPCODE_RDY_I <= '1';
            end if;
        elsif OPCODE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" then
            -- Instruction prefetches are always long and on word boundaries.
            -- The word is available after the first word read.
            OBUFFER <= DATA_INMUX(15 downto 0);
            OPCODE_RDY_I <= RDY_VAR;
        end if;
        -- Data cycle:
        if RA_TAKE = '1' then
            DATA_RDY_I <= '1'; -- [F2] Held read-ahead: data (or the bus error) is already in DBUFFER/DATA_VALID.
        elsif DC_RHIT = '1' or DC_CHIT = '1' then
            DBUFFER <= DC_PD; -- [DC] Served by the data cache: no bus cycle.
            DATA_RDY_I <= '1';
        elsif WP_GO = '1' then
            DATA_RDY_I <= RDY_VAR and not WR_TAKE; -- [PH2-WP] Posted: the outcome of the last portion is final here. [F3] Taken early.
        elsif WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" then
            if WP_DONE = '0' then
                DATA_RDY_I <= RDY_VAR;
            end if;
        elsif READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' then
            case OP_SIZE is
                when LONG =>
                    if SIZE_N = "000" then
                        DBUFFER <= DATA_INMUX;
                        if RA_ACC = '0' or RA_MATCH = '1' then -- [F2] A read-ahead nobody asked for yet is held.
                            DATA_RDY_I <= RDY_VAR;
                        end if;
                    end if;
                when WORD =>
                    if SIZE_N = "000" then
                        DBUFFER <= x"0000" & DATA_INMUX(15 downto 0);
                        if RA_ACC = '0' or RA_MATCH = '1' then -- [F2]
                            DATA_RDY_I <= RDY_VAR;
                        end if;
                    end if;
                when BYTE => -- Byte always aligned.
                    DATA_RDY_I <= RDY_VAR;
                    DBUFFER <= x"000000" & DATA_INMUX(7 downto 0);
            end case;
        end if;
    end process PREFETCH_BUFFERS;

    DATA_RDY <= DATA_RDY_I;
    DATA_VALID <= DATA_VALID_I; -- [F2]

    -- [PH2-WP] Posted write (option b): the S3 edge of the last portion of a write decides the
    -- outcome in this core (DSACK, BERR and HALT sampled at the start of S3; a BERR seen at S5 is
    -- not used; a late retry needs SIZE_N /= 0). A clean ending reports DATA_RDY here, one clock
    -- before S5, so the control unit can present its next request for the S5 edge. Bus errors,
    -- retry, halt, RMC and STERM cycles are never posted and keep the S5 DATA_RDY.
    -- [T9] The CLK_F-sampled terms of the S3 post decision (S3 = SLICE_CNT_P "001" with SLICE_CNT_N
    -- "001", DSACK_In, STERM_In, BUS_FLT_N, HALT_In) are folded into one CLK_F flip flop WP_NEG, computed
    -- from the same pins on the same edge (SLICE_CNT_N <= SLICE_CNT_P there, SLICE_CNT_P only changes on CLK).
    -- WAITSTATES = '0' is implied (T_SLICE = S3, RESET_OUT_I = '0', DSACK_In /= "11"). Same function in
    -- every clock; it removes HALT_In/DSACK_In/SLICE_CNT_N -> WP_GO logic levels from the half-cycle
    -- WR_EARLY -> F3_EARLY -> NEXT_FETCH_STATE -> PC_I path (tt23 worst -1.203 ns).
    WP_GO <= '1' when WP_NEG = '1' and WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and SLICE_CNT_P = "001" and
                      BUS_FLT = '0' and RETRY = '0' and
                      RMC = '0' and RESET_CPU_I = '0' and RESET_OUT_I = '0' and SIZE_DEC = "000" else '0';
    -- synthesis translate_off
    P_T9_CHK: process
    begin
        wait until CLK = '1' and CLK' event;
        assert (WP_GO = '1') = (WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and T_SLICE = S3 and
                      WAITSTATES = '0' and DSACK_In /= "11" and STERM_In = '1' and
                      BUS_FLT = '0' and BUS_FLT_N = '0' and RETRY = '0' and HALT_In = '1' and
                      RMC = '0' and RESET_CPU_I = '0' and RESET_OUT_I = '0' and SIZE_DEC = "000")
            report "T9: WP_GO differs from the original decode" severity failure;
    end process P_T9_CHK;
    -- synthesis translate_on

    P_WP_DONE: process
    begin
        wait until CLK = '1' and CLK' event;
        if WP_DONE = '1' and BUS_CYC_RDY = '1' and BUS_CTRL_STATE = DATA_C1C4 and NEXT_BUS_CTRL_STATE = IDLE then
            WP_LAST <= '1'; -- Held through the IDLE clocks until the next cycle starts.
        elsif BUS_CTRL_STATE /= IDLE or NEXT_BUS_CTRL_STATE /= IDLE then
            WP_LAST <= '0';
        end if;
        if WP_GO = '1' then
            WP_DONE <= '1';
        elsif BUS_CYC_RDY = '1' or BUS_CTRL_STATE /= DATA_C1C4 then
            WP_DONE <= '0'; -- Cleared on the S5 edge (also when it chains).
        end if;
    end process P_WP_DONE;
    OPCODE_RDY <= OPCODE_RDY_I;

    DATA_TO_CORE <= DBUFFER;
    OPCODE_TO_CORE <= OBUFFER;

    WAITSTATES <= '0' when T_SLICE /= S3 else
                  '1' when RESET_OUT_I = '1' else -- No bus fault during RESET instruction.
                  '0' when DSACK_In /= "11" else -- For asynchronous bus cycles.
                  '0' when STERM_In = '0' else -- For synchronous bus cycles.
                  '0' when PF_ACC = '0' and FILL_ACC = '0' and FC_IN = "111" and ADR_IN_P(19 downto 16) = x"F" and AVEC_In = '0' else -- F6/H12: AVEC terminates CPU-space IACK ONLY; ordinary cycles at $xFxxxx (grounded-AVECn systems, slow memory) must not be cut short.
                  '0' when BUS_FLT = '1' else -- In case of a bus error;
                  '0' when RESET_CPU_I = '1' else '1'; -- A CPU reset terminates the current bus cycle.

    SLICES: process(CLK)
    -- This process provides the central timing for the read, write and read modify write cycle as also
    -- for the bus arbitration procedure. Be aware, that the bus controller state machine changes it's
    -- state on the positive clock edge. The BUS_CYC_RDY signal is asserted during S3 or S5. So the 
    -- slice counter working on the positive clock edge may change it's state.
    begin
        if CLK = '1' and CLK' event then
            if BUS_CTRL_STATE = IDLE and PW_GO = '1' then
                SLICE_CNT_P <= "000"; -- [PH2-WP] S0 in the next clock.
            elsif BUS_CTRL_STATE = IDLE then
                SLICE_CNT_P <= "111"; -- Init.
            elsif RETRY = '1' then
                SLICE_CNT_P <= "111"; -- Stay in IDLE, go to IDLE.
            elsif BUS_CTRL_STATE /= IDLE and NEXT_BUS_CTRL_STATE = IDLE then
                SLICE_CNT_P <= "111"; -- Init.
            elsif SLICE_CNT_P = "001" and STERM_In = '0' then -- Synchronous cycle.
                SLICE_CNT_P <= "111"; -- Ready.
            elsif SLICE_CNT_P = "010" then
                if RETRY = '1' then
                    SLICE_CNT_P <= "111"; -- Go IDLE.
                elsif BUS_CTRL_STATE = DATA_C1C4 and NEXT_BUS_CTRL_STATE = IDLE then
                    SLICE_CNT_P <= "111"; -- Ready.
                else
                    SLICE_CNT_P <= "000"; -- Go on.
                end if;
            elsif WAITSTATES = '0' then
                SLICE_CNT_P <= SLICE_CNT_P + '1'; -- Cycle active.
            end if;
        end if;
    end process SLICES;

    SLICES_N: process(CLK_F)
    begin
        if CLK_F = '1' and CLK_F' event then -- [F58] was the falling edge of CLK (in SLICES)
            SLICE_CNT_N <= SLICE_CNT_P; -- Follow the P counter.
        end if;
    end process SLICES_N;

    T_SLICE <=  S0 when SLICE_CNT_P = "000" and SLICE_CNT_N = "111" else
                S1 when SLICE_CNT_P = "000" and SLICE_CNT_N = "000" else
                S2 when SLICE_CNT_P = "001" and SLICE_CNT_N = "000" else
                S3 when SLICE_CNT_P = "001" and SLICE_CNT_N = "001" else
                S4 when SLICE_CNT_P = "010" and SLICE_CNT_N = "001" else
                S5 when SLICE_CNT_P = "010" and SLICE_CNT_N = "010" else
                S0 when SLICE_CNT_P = "000" and SLICE_CNT_N = "010" else IDLE; -- Rollover from state S5 to S0.

    P_OCS: process
    -- This flip flop enables the output of the OCSn signal for
    -- the first bus cycle and locks OCSn for all other bus cycles.
    -- ECSn is locked only during cache burst access.
    begin
        wait until CLK = '1' and CLK' event;
        --
        if CHAIN_GO = '1' then
            OCS_INH <= '0'; -- [F65] [PH2] OCSn pulses again on the chained S0.
        elsif BUS_CTRL_STATE = START_CYCLE and NEXT_BUS_CTRL_STATE /= IDLE then
            OCS_INH <= '0';
        elsif BUS_CYC_RDY = '1' and RETRY = '0' then -- No inhibit if first portion results in a retry cycle.
            OCS_INH <= '1';
        end if;
    end process P_OCS;

    -- Bus control signals:
    RWn <= '0' when WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 else '1';
    -- [RMC1] Cycle-correct RMCn (MC68030 UM 7.6 read-modify-write). The control unit holds RMC for the whole
    -- TAS/CAS/CAS2 instruction (it also keeps the prefetcher off, so no cycle can come between the locked
    -- read and the write). The pin and the bus lock follow the bus instead: RMCn goes low with S0 (AS) of the
    -- first operand read while RMC is set, and stays low through the write(s) until RMC drops. Before that
    -- read the bus is not locked, so a pending BR is granted as on a real 030.
    RMC_PIN <= '1' when RMC = '1' and RMC_DONE = '0' and
                        (RMC_LK = '1' or (READ_ACCESS = '1' and T_SLICE /= IDLE)) else '0';
    RMC_HOLD <= '1' when RMC = '1' and RMC_LK = '1' and RMC_DONE = '0' else '0';
    P_RMC_LK: process
    begin
        wait until CLK = '1' and CLK' event;
        if RMC = '0' then
            RMC_LK <= '0'; RMC_DONE <= '0'; RMC_NR <= 0; RMC_NW <= 0;
        else
            if READ_ACCESS = '1' and T_SLICE /= IDLE and T_SLICE /= S0 and RMC_DONE = '0' then
                RMC_LK <= '1';
            end if;
            if BUS_CYC_RDY = '1' and BUS_CTRL_STATE = DATA_C1C4 and RMC_LK = '1' and RMC_DONE = '0' then
                if READ_ACCESS = '1' and RMC_NR < 7 then
                    RMC_NR <= RMC_NR + 1;
                elsif WRITE_ACCESS = '1' then
                    RMC_NW <= RMC_NW + 1;
                    if RMC_NW + 1 >= RMC_NR then
                        RMC_DONE <= '1'; -- Last write of the sequence ends with this S5: release the lock.
                    end if;
                end if;
            end if;
        end if;
    end process P_RMC_LK;
    RMCn <= '0' when RMC_PIN = '1' else '1';
    -- [F67] For the ATC WP check and the TT RWM match only: while AS is low T_SLICE /= IDLE, so this equals RMCn.
    -- Without the falling-edge T_SLICE term the clk_cpu_n -> MMU -> core half-cycle path is gone (f66b: -5.2 ns).
    RMC_LKn <= '0' when RMC = '1' and RMC_DONE = '0' and (RMC_LK = '1' or READ_ACCESS = '1') else '1';
    ECSn <= '0' when T_SLICE = S0 else '1';
    OCSn <= '0' when T_SLICE = S0 and OCS_INH = '0' else '1';
    ASn <= '0' when T_SLICE = S0 or T_SLICE = S1 or T_SLICE = S2 or T_SLICE = S3 or T_SLICE = S4 else '1';
    DSn <= '0' when (T_SLICE = S3 or T_SLICE = S4 or T_SLICE = S5) and WRITE_ACCESS = '1' else -- Write.
           '0' when T_SLICE = S0 or T_SLICE = S1 or T_SLICE = S2 or T_SLICE = S3 or T_SLICE = S4 else '1'; -- Read.

    DBENn <= '0' when (T_SLICE = S1 or T_SLICE = S2 or T_SLICE = S3 or T_SLICE = S4 or T_SLICE = S5) and WRITE_ACCESS = '1' else -- Write.
             '0' when T_SLICE = S2 or T_SLICE = S3 or T_SLICE = S4 else '1'; -- Read.

    -- Bus tri state controls:
    BUS_EN <= '1' when ARB_STATE = IDLE and RESET_CPU_I = '0' else '0';
    DATA_PORT_EN <= '1' when WRITE_ACCESS = '1' and ARB_STATE = IDLE and RESET_CPU_I = '0' else '0';

    -- Progress controls:
    BUS_CYC_RDY <=  '0' when RETRY = '1' else
                    '1' when T_SLICE = S3 and STERM_In = '0' else -- Synchronous cycles.
                    '1' when T_SLICE = S5 else '0'; -- Asynchronous cycles.

    -- Bus arbitration:
    ARB_REG: process
    -- This is the arbiters state register.
    begin
        wait until CLK = '1' and CLK' event;
        --
        if RESET_CPU_I = '1' then
            ARB_STATE <= IDLE;
        else
            ARB_STATE <= NEXT_ARB_STATE;
        end if;
    end process ARB_REG;
    
    ARB_DEC: process(ARB_STATE, BGACK_In, BR_In, BUS_CTRL_STATE, RETRY, RMC_PIN)
    -- This is the bus arbitration state machine's decoder. It can handle single-, two- 
    -- or three wire arbitration. The two wire arbitration is done in the GRANT state
    -- by negating BRn.
    begin
        case ARB_STATE is
            when IDLE =>
                if RMC_PIN = '1' and RETRY = '0' then -- [RMC1]
                    NEXT_ARB_STATE <= IDLE; -- Arbitration in RETRY operation is possible.
                elsif BGACK_In = '0' and BUS_CTRL_STATE = IDLE then -- This is the single wire arbitration.
                    NEXT_ARB_STATE <= WAIT_RELEASE_3WIRE;
                elsif BR_In = '0' and BUS_CTRL_STATE = IDLE then -- Wait until the bus is free.
                    NEXT_ARB_STATE <= GRANT;
                else
                    NEXT_ARB_STATE <= IDLE;
                end if;
            when GRANT =>
                if BGACK_In = '0' then
                    NEXT_ARB_STATE <= WAIT_RELEASE_3WIRE;
                elsif BR_In = '1' then
                    NEXT_ARB_STATE <= IDLE; -- Resume normal operation.
                else
                    NEXT_ARB_STATE <= GRANT;
                end if;
            when WAIT_RELEASE_3WIRE =>
                if BGACK_In = '1' and BR_In = '0' then
                    NEXT_ARB_STATE <= GRANT; -- Re-enter new arbitration.
                elsif BGACK_In = '1' then
                    NEXT_ARB_STATE <= IDLE;
                else
                    NEXT_ARB_STATE <= WAIT_RELEASE_3WIRE;
                end if;
        end case;
    end process ARB_DEC;

    BGn <=  '0' when ARB_STATE = GRANT else '1';

    -- RESET logic:
    RESET_FILTER: process
    -- This process filters the incoming reset pin.
    -- If RESET_IN and HALT_In are asserted together for longer
    -- than 10 clock cycles over the execution of a CPU reset
    -- command, the CPU reset is released.
    variable STARTUP    : boolean := false;
    variable TMP        : std_logic_vector(3 downto 0) := x"0";
    begin
        wait until CLK = '1' and CLK' event;
        --
        if RESET_IN = '1' and HALT_In = '0' and RESET_OUT_I = '0' and TMP < x"F" then
            TMP := TMP + '1';
        elsif RESET_IN = '0' or HALT_In = '1' or RESET_OUT_I = '1' then
            TMP := x"0";
        end if;
        if TMP > x"A" then
            RESET_CPU_I <= '1'; -- Release internal reset.
            STARTUP := true;
        elsif STARTUP = false then
            RESET_CPU_I <= '1';
        else
            RESET_CPU_I <= '0';
        end if;
    end process RESET_FILTER;

    RESET_TIMER: process
    -- This logic is responsible for the assertion of the
    -- reset output for 512 clock cycles, during the reset
    -- command. The LOCK variable avoids re-initialisation
    -- of the counter in the case that the RESET_EN is no
    -- strobe.
    variable TMP : std_logic_vector(8 downto 0) := "000000000";
    begin
        wait until CLK = '1' and CLK' event;
        --
        if RESET_STRB = '1' or TMP > "000000000" then
            RESET_OUT_I <= '1';
        else
            RESET_OUT_I <= '0';
        end if;
        --
        if RESET_STRB = '1' then
            TMP := "111111111"; -- 512 initial value.
        elsif TMP > "000000000" then
            TMP := TMP - '1';
        end if;
    end process RESET_TIMER;

    RESET_CPU <= RESET_CPU_I;
    RESET_OUT <= RESET_OUT_I;
end BEHAVIOR;
