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
        RD_REQ              : in bit; -- Read data.
        WR_REQ              : in bit; -- Write data.
        DATA_RDY            : out bit; -- Indicates 'new data available' (this is a strobe).
        DATA_VALID          : out std_logic; -- The data buffer contains valid data when '1'.
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
        Q_STREAM            : out std_logic_vector(63 downto 0); -- [PFCOF2] Queued words 0-3 (registered) for the decoder's predecode.
        Q_COUNT             : out integer range 0 to 4; -- [PFCOF2]
        OP_RD               : in bit; -- [F65] Live data-read request, not masked by BUS_BSY.
        OP_WR               : in bit; -- [F65] Live data-write request, not masked by BUS_BSY.
        ADR_NXT             : in std_logic_vector(31 downto 0); -- [PH2] Address of the live operand request.
        FC_NXT              : in std_logic_vector(2 downto 0); -- [PH2] Its function code.
        ADR_LAT             : in std_logic_vector(31 downto 0); -- [PH2-FMAX] Registered address of the running cycle.
        FC_LAT              : in std_logic_vector(2 downto 0); -- [PH2-FMAX] Its registered function code.
        OP_CHAIN_LD         : out bit; -- [PH2] Strobe on an S5 edge that rolls an operand cycle in or out.
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
signal WP_GO                : bit; -- [PH2-WP] Post the write on this S3 edge.
signal WP_DONE              : bit := '0'; -- [PH2-WP] The running write was posted.
signal DOB_HOLD             : bit := '0'; -- [PH2-WP] Keep the faulted write's data for the frame.
signal WP_LAST              : bit := '0'; -- [PH2-WP] The bus is idle since a posted write ended.
signal PW_GO                : bit; -- [PH2-WP] IDLE clock after a posted write: start the operand cycle now.
signal SLICE_CNT_N          : std_logic_vector(2 downto 0) := "111";  -- [F54] measured warm-boot value
signal SLICE_CNT_P          : std_logic_vector(2 downto 0) := "111";  -- [F54] measured warm-boot value
signal STERM_In             : std_logic := '1';  -- [F54] measured warm-boot value
signal T_SLICE              : TIME_SLICES := IDLE;  -- [F54] measured warm-boot value
signal WAITSTATES           : bit := '0';  -- [F54] measured warm-boot value
signal WP_BUFFER            : std_logic_vector(31 downto 0);
signal WRITE_ACCESS         : bit := '0';  -- [F54] measured warm-boot value
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
signal CHAIN_GO             : bit; -- [PH2] PF_, OP_ or DP_CHAIN_GO: a new cycle starts on this S5 edge.
signal OPC_LEGACY           : bit; -- Opcode request handled by an ordinary opcode cycle.
signal PF_REQ_RAW           : bit; -- [IC] The queue wants the long word at F_ADR (cache or bus).
signal IC_TAKE              : bit; -- [IC] ... and takes it from the instruction cache in this clock.
signal CIIN_LAT             : std_logic := '0'; -- [IC] CIINn of the running portion (sampled at S4, P_CIIN).
signal PF_CI0               : std_logic := '0'; -- [IC] CIIN was asserted on the finished portion of word 0 / word 1
signal PF_CI1               : std_logic := '0'; -- [IC] of the running prefetch long (as PF_FLT0/PF_FLT1).
-- [IC] Cache-inhibit state of the running prefetch: keep it through synthesis (see WF68K30L_ICACHE).
attribute syn_preserve : integer;
attribute syn_preserve of CIIN_LAT : signal is 1;
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
            if READ_ACCESS = '1' or WRITE_ACCESS = '1' or OPCODE_ACCESS = '1' then
                null; -- Do not start either new cycle.
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
            READ_ACCESS <= not CH_WR;
            WRITE_ACCESS <= CH_WR;
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
        elsif DP_CHAIN_GO = '1' then -- [PH2] The operand cycle ends, the waiting prefetch starts.
            READ_ACCESS <= '0';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '1';
            PF_ACC <= '1';
        elsif AERR = '1' then -- Reject due to address error.
            READ_ACCESS <= '0';
            WRITE_ACCESS <= '0';
            OPCODE_ACCESS <= '0';
            PF_ACC <= '0';
        elsif BUS_CTRL_STATE = DATA_C1C4 and NEXT_BUS_CTRL_STATE = IDLE and SIZE_N = "000" then
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
            if BUS_CTRL_STATE = START_CYCLE and NEXT_BUS_CTRL_STATE = DATA_C1C4 then
                SSW_80 <= To_StdLogicVector('0' & RMC & not WR_REQ) & SIZEVAR & '0' & FC_IN;
            elsif DP_CHAIN_GO = '1' then -- [PH2] As START_CYCLE writes it for a prefetch.
                SSW_80 <= To_StdLogicVector('0' & RMC & '1') & SIZEVAR & '0' & FC_NXT;
            elsif OP_CHAIN_GO = '1' then -- [PH2]
                SSW_80 <= To_StdLogicVector('0' & RMC & not CH_WR) & SIZEVAR & '0' & FC_NXT;
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
            INBUFFER <= DATA_INMUX; -- Used for exception stack frame type B.
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
        elsif OP_CHAIN_GO = '1' then -- [PH2] Operand size of the waiting request.
            case OP_SIZE is
                when LONG => SIZE_N <= "100";
                when WORD => SIZE_N <= "010";
                when BYTE => SIZE_N <= "001";
            end case;
        elsif BUS_CTRL_STATE /= DATA_C1C4 and NEXT_BUS_CTRL_STATE = DATA_C1C4 then
            if RD_REQ = '1' or WR_REQ = '1' then
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
                          OPCODE_ACCESS, OPCODE_REQ, RD_REQ, READ_ACCESS, RESET_CPU_I, RMC, SIZE_N, WR_REQ, WRITE_ACCESS,
                          OPC_LEGACY, PF_REQ, CHAIN_GO, PW_GO)
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
                elsif (BR_In = '0' and RMC = '0') or ARB_STATE /= IDLE or BGACK_In = '0' then
                    NEXT_BUS_CTRL_STATE <= IDLE;  -- Arbitration, wait!
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
                elsif READ_ACCESS = '1' or WRITE_ACCESS = '1' or OPCODE_ACCESS = '1' then
                    NEXT_BUS_CTRL_STATE <= START_CYCLE; -- Pending (split) bus cycles.
                else
                    NEXT_BUS_CTRL_STATE <= IDLE;
                end if;
            when START_CYCLE =>
                if RD_REQ = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif WR_REQ = '1' then
                    NEXT_BUS_CTRL_STATE <= DATA_C1C4;
                elsif OPCODE_REQ = '1' and ADR_IN_P(0) = '1' then
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
    ADR_OUT_I <= (F_CUR & '0') + ADR_OFFSET when PF_ACC = '1' else ADR_LAT + ADR_OFFSET; -- [F62]
    ADR_OUT_P <= ADR_OUT_I;

    P_ADR_10: process
    -- This logic is registered to enhance the system performance concerning fmax.
    begin
        wait until CLK = '1' and CLK' event;
        ADR_10 <= ADR_OUT_I(1 downto 0);
    end process P_ADR_10;

    -- Address and bus errors:
    AERR_I <= '1' when BUS_CTRL_STATE = START_CYCLE and OPCODE_REQ = '1' and RD_REQ = '0' and WR_REQ = '0' and ADR_IN_P(0) = '1' else '0';

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
    OPC_LEGACY <= OPCODE_REQ when PREFETCH_Q = 0 else
                  OPCODE_REQ and To_Bit(ADR_IN_P(0));
    Q_MATCH <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and Q_ADR = OPC_ADR(31 downto 1) and Q_FC = OPC_FC else '0';
    Q_HIT <= '1' when Q_MATCH = '1' and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and Q_CNT /= 0 else '0';
    Q_MISS <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and
                       not (Q_MATCH = '1' and (Q_CNT /= 0 or (INFL = '1' and INFL_STALE = '0') or S_FAULTED = '0')) else '0';
    Q_DUMMY <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPCODE_RDY_I = '0' and Q_DISMISS = '1' else '0';
    PF_REQ_RAW <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and S_FAULTED = '0' and INFL = '0' and Q_CNT <= 1 and PF_HOLD = '0' else '0'; -- [PFCOF]
    -- [IC] A long word the instruction cache holds is taken from the cache (P_QUEUE) and never starts a bus
    -- cycle. With nothing cached (CIIN asserted on every cycle) IC_HIT is 0 and PF_REQ is the old request.
    PF_REQ <= PF_REQ_RAW and not To_Bit(IC_HIT);
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
                         RD_REQ = '0' and WR_REQ = '0' and OPC_LEGACY = '0' and PF_REQ = '1' else '0';
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
    OP_CHAIN_GO <= '1' when OP_CHAIN = '1' and PF_ACC = '1' and BUS_CYC_RDY = '1' and SIZE_N = "000"
                   and (OP_RD = '1' or OP_WR = '1') and RMC = '0'
                   and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                   and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else
                   PW_GO; -- [PH2-WP] Same start actions, from the IDLE clock after a posted write.

    -- [PH2-WP] The control unit sees a posted write's DATA_RDY in the S4/S5 clock and presents its
    -- next operand request in the clock after S5 (IDLE). That request starts here without the
    -- START_CYCLE clock: the edge out of IDLE does what the OP_CHAIN edge does (access type, SSW,
    -- WP_BUFFER, SIZE_N, RDY, queue flush for a write, DSACK/offset/OCS reset; the top loads the
    -- address/FC latches in IDLE anyway) and the slice counter goes straight to S0. Only operand
    -- requests (no RMC, no exception processing), and every IDLE hold (reset, halt, arbitration)
    -- takes precedence.
    PW_GO <= '1' when BUS_CTRL_STATE = IDLE and WP_LAST = '1' and (OP_RD = '1' or OP_WR = '1')
                      and RMC = '0' and BUSY_EXH = '0' and SIZE_N = "000"
                      and READ_ACCESS = '0' and WRITE_ACCESS = '0' and OPCODE_ACCESS = '0'
                      and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                      and RETRY = '0' and RESET_CPU_I = '0' else '0';
    CH_WR <= OP_WR and not OP_RD; -- Read has priority, as in START_CYCLE.
    DP_CHAIN_GO <= '1' when DP_CHAIN = '1' and (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_CYC_RDY = '1'
                   and SIZE_N = "000" and PF_REQ = '1' and Q_MISS = '0' and OPC_DISMISS = '0'
                   and RMC = '0' and BUSY_EXH = '0'
                   and HALT_In = '1' and BR_In = '1' and BGACK_In = '1' and ARB_STATE = IDLE
                   and RETRY = '0' and BUS_FLT = '0' and RESET_CPU_I = '0' else '0';
    CHAIN_GO <= PF_CHAIN_GO or OP_CHAIN_GO or DP_CHAIN_GO;
    OP_CHAIN_LD <= OP_CHAIN_GO or DP_CHAIN_GO; -- The top level loads its address/FC latches as in IDLE.

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

    FC_OUT <= F_FC when PF_ACC = '1' else FC_LAT; -- [F62] [PH2-FMAX] registered, as ADR_OUT_I

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
            DATA_VALID <= '1';
        elsif READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' and HALT_In = '0' then
            null; -- This is the RETRY condition, no bus error.
        elsif (READ_ACCESS = '1' or WRITE_ACCESS = '1') and BUS_CTRL_STATE = DATA_C1C4 and BUS_FLT = '1' then
            DATA_VALID <= '0'; -- [F62] Data cycles only: an opcode fetch fault must not fail the next data read.
        elsif DATA_RDY_I = '1' then
            DATA_VALID <= '1'; -- Reset after use, TRAP_BERR is asserted during DATA_RDY.
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
        if OP_CHAIN_GO = '1' or DP_CHAIN_GO = '1' then -- [PH2] [PH2-WP] First: a posted write's DATA_RDY can
            RDY_VAR := '1';                                 -- be high on the chain edge (never the case before).
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
        if WP_GO = '1' then
            DATA_RDY_I <= RDY_VAR; -- [PH2-WP] Posted: the outcome of the last portion is final here.
        elsif WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" then
            if WP_DONE = '0' then
                DATA_RDY_I <= RDY_VAR;
            end if;
        elsif READ_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' then
            case OP_SIZE is
                when LONG =>
                    if SIZE_N = "000" then
                        DBUFFER <= DATA_INMUX;
                        DATA_RDY_I <= RDY_VAR;
                    end if;
                when WORD =>
                    if SIZE_N = "000" then
                        DBUFFER <= x"0000" & DATA_INMUX(15 downto 0);
                        DATA_RDY_I <= RDY_VAR;
                    end if;
                when BYTE => -- Byte always aligned.
                    DATA_RDY_I <= RDY_VAR;
                    DBUFFER <= x"000000" & DATA_INMUX(7 downto 0);
            end case;
        end if;
    end process PREFETCH_BUFFERS;

    DATA_RDY <= DATA_RDY_I;

    -- [PH2-WP] Posted write (option b): the S3 edge of the last portion of a write decides the
    -- outcome in this core (DSACK, BERR and HALT sampled at the start of S3; a BERR seen at S5 is
    -- not used; a late retry needs SIZE_N /= 0). A clean ending reports DATA_RDY here, one clock
    -- before S5, so the control unit can present its next request for the S5 edge. Bus errors,
    -- retry, halt, RMC and STERM cycles are never posted and keep the S5 DATA_RDY.
    WP_GO <= '1' when WRITE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and T_SLICE = S3 and
                      WAITSTATES = '0' and DSACK_In /= "11" and STERM_In = '1' and
                      BUS_FLT = '0' and BUS_FLT_N = '0' and RETRY = '0' and HALT_In = '1' and
                      RMC = '0' and RESET_CPU_I = '0' and RESET_OUT_I = '0' and SIZE_DEC = "000" else '0';

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
                  '0' when PF_ACC = '0' and FC_IN = "111" and ADR_IN_P(19 downto 16) = x"F" and AVEC_In = '0' else -- F6/H12: AVEC terminates CPU-space IACK ONLY; ordinary cycles at $xFxxxx (grounded-AVECn systems, slow memory) must not be cut short.
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
    RMCn <= '0' when RMC = '1' else '1';
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
    
    ARB_DEC: process(ARB_STATE, BGACK_In, BR_In, BUS_CTRL_STATE, RETRY, RMC)
    -- This is the bus arbitration state machine's decoder. It can handle single-, two- 
    -- or three wire arbitration. The two wire arbitration is done in the GRANT state
    -- by negating BRn.
    begin
        case ARB_STATE is
            when IDLE =>
                if RMC = '1' and RETRY = '0' then
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
