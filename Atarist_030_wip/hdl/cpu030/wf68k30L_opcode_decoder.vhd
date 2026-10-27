------------------------------------------------------------------------
----                                                                ----
---- WF68K30L IP Core: this is the bus controller module.           ----
----                                                                ----
---- Description:                                                   ----
---- This module is a 68030 compatible instruction word decoder.    ----
----                                                                ----
---- It is primarily controlled by the following signals:           ----
---- OW_REQ, OPD_ACK, EW_REQ and EW_ACK. The handshaking is as      ----
---- follows: if a new instruction is required, assert the signal   ----
---- OW_REQ and wait until ACK is asserted by the decoder logic.    ----
---- Deassert OW_REQ right after ACK (in the same clock cycle).     ----
---- At this point, the required instruction has already been copied----
---- from the pipe to the register BIW_0. The respective additional ----
---- instruction words are located in BIW_1, BIW_2. For more infor- ----
---- mation see the 68010 "Programmers Reference Manual" and the    ----
---- signal INSTR_LVL in this module.                               ----
---- The extension request works in the same manner by asserting    ----
---- EW_REQ. At the time of EXT_ACK one extension word has been     ----
---- copied to EXT_WORD.                                            ----
---- Be aware that it is in the scope of the logic driving          ----
---- OW_REQ and EW_REQ to hold the instruction pipe aligned.        ----
---- This means in detail, that the correct number or instruction   ----
---- and extension words must be requested. Otherwise unpredictable ----
---- processor behaviour will occur. Furthermore OW_REQ and EW_REQ  ----
---- must not be asserted the same time.                            ----
---- This operation code decoder with the handshake logic as des-   ----
---- cribed above is the first pipeline stage of the CPU architec-  ----
---- ture.                                                          ----
----                                                                ----
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
--   Removed REST_BIW_0.
--   Fixed the PW_EW_OFFSET calculation for JSR.
--   TOP, CONTROL, Exception Handler Opcode Decoder: Rearranged PC_INC and ipipe flush logic.
--   Fix for unimplemented or illegal operations: PC is increased before stacked.
--   Implemented the 68K10 loop mechanism.
--   Removed CAHR, we have no cache.
--   Rearranged address error handling.
-- FalconFPGA modifications (David Dunne, github.com/dave-1024/falconfpga), CERN OHL v1.2.
-- Changes are tagged Fnn in the code. Dates are from git history.
-- Base: WF68K30L 2K19A (this repo's import of 2026-09-24).
--   2026-09-30 F42-F54: reset and power-up values (SR $2700, no spurious traps).
--   2026-10-04 F57: explicit power-up values for set-type flops.
--   2026-10-04 F59: pipe flush sets OP to NOP (loop-mode interrupt deadlock).
--   2026-10-08 F62/F62b/F62c: opcode prefetch queue (PREFETCH_Q).
-- 

library work;
use work.WF68K30L_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity WF68K30L_OPCODE_DECODER is
    generic(NO_LOOP         : boolean); -- If true the DBcc loop mechanism is disabled.
    port (
        CLK                 : in std_logic;

        OW_REQ_MAIN         : in bit; -- Request from the execution unit.
        EW_REQ_MAIN         : in bit; -- Extension words request.

        EXH_REQ             : in bit; -- Exception request.
        BUSY_EXH            : in bit; -- Exception handler is busy.
        BUSY_MAIN           : in bit; -- Main controller busy.
        BUSY_OPD            : out bit; -- This unit is busy.
        
        BKPT_INSERT         : in bit;
        BKPT_DATA           : in std_logic_vector(15 downto 0);

        LOOP_EXIT           : in bit;
        LOOP_BSY            : out bit;

        OPD_ACK_MAIN        : out bit; -- Operation controller acknowledge.
        EW_ACK              : buffer bit; -- Extension word available.

        PC_INC              : out bit;
        PC_INC_EXH          : in bit;
        PC_ADR_OFFSET       : out std_logic_vector(7 downto 0);
        PC_EW_OFFSET        : buffer std_logic_vector(3 downto 0);
        PC_OFFSET           : out std_logic_vector(7 downto 0);

        OPCODE_RD           : out bit;
        OPCODE_RDY          : in bit;
        OPCODE_VALID        : in std_logic;
        OPCODE_DATA         : in std_logic_vector(15 downto 0);

        IPIPE_FILL          : in bit;
        IPIPE_FLUSH         : in bit; -- Abandon the instruction pipe.
        OPCODE_DISMISS      : out bit; -- [F62c] OPCODE_FLUSH: the next OPCODE_RDY is dismissed (prefetch queue uses it as is).
        COF_PEND            : in bit; -- [PFCOF] Control unit executes a taken change of flow.
        PF_HOLD             : out bit := '0'; -- [PFCOF] Start no further instruction-stream fetches.
        Q_STREAM            : in std_logic_vector(63 downto 0); -- [PFCOF2] Prefetch queue words 0-3.
        Q_COUNT             : in integer range 0 to 4; -- [PFCOF2]
        COF_ANY             : out bit; -- [XH3] A flow-change word may be among the valid words ahead (no early long prefetch).

        -- Fault logic:
        OW_VALID            : out std_logic; -- Operation words valid.
        RC                  : out std_logic; -- Rerun flag on instruction pipe stage C.
        RB                  : out std_logic; -- Rerun flag on instruction pipe stage B.
        FC                  : out std_logic; -- Fault on use of instruction pipe stage C.
        FB                  : out std_logic; -- Fault on use of instruction pipe stage B.
        -- [FRM] Bus-error frame stage images: the words at PC+2 (stage C) and PC+4 (stage B) of the
        -- instruction in execution, once they have reached the decoder pipe, with their fault flags.
        STG_C               : out std_logic_vector(15 downto 0);
        STG_B               : out std_logic_vector(15 downto 0);
        STG_CA              : out std_logic; -- Stage C word has reached the pipe.
        STG_BA              : out std_logic;
        STG_CF              : out std_logic; -- Stage C word was fetched with a bus error.
        STG_BF              : out std_logic;

        -- Trap logic:
        SBIT                : in std_logic;
        TRAP_CODE           : out TRAPTYPE_OPC := NONE;  -- [F47] no spurious trap out of reset

        -- System control signals:
        -- F42 [FIXED 2026-08-31].  OP had NO initial value and the
        -- OUTBUFFERS process that drives it has no reset branch, so on
        -- silicon it powers up as whatever the synthesiser's zero
        -- encoding lands on.  wf68k30L_control.vhd:937 reads it as
        --   TRAP_V <= '1' when OP = TRAPV and ALU_COND = true
        --             and FETCH_STATE = SLEEP
        --             and NEXT_FETCH_STATE = START_OP
        -- and SLEEP -> START_OP is the transition at the head of the
        -- FIRST instruction after reset.  If the power-up encoding
        -- aliases TRAPV, the core takes a spurious TRAPV before it has
        -- executed anything: vector 7, format 2, PC = the reset PC.
        --
        -- Observed on a Tang Console 138K: ten cold starts, byte
        -- identical, EXC v=04 fmt=0 with a nested frame underneath
        -- reading vector 7 / format 2 / PC $400 / SR $2700.  The same
        -- fault for two DIFFERENT instructions at $400, so it is not
        -- the instruction.  BSRAM was read back and verified correct.
        --
        -- GHDL defaults an uninitialised enum to OP_68K'left, which is
        -- not TRAPV, so simulation never sees this.  That is why sim
        -- and silicon disagreed DETERMINISTICALLY on identical RTL.
        --
        -- OP_68K'left is chosen deliberately over any "safe looking"
        -- opcode: it is the exact state every passing simulation of
        -- this core has run in, so the fix makes silicon match the
        -- configuration FIXREV14 was verified in, rather than
        -- introducing a new and unverified one.
        OP                  : buffer OP_68K := OP_68K'left;
        BIW_0               : buffer std_logic_vector(15 downto 0) := x"0100";  -- [F47] bits11:8=0001 => ALU_COND false out of reset
        BIW_1               : out std_logic_vector(15 downto 0);
        BIW_2               : out std_logic_vector(15 downto 0);
        EXT_WORD            : out std_logic_vector(15 downto 0)
    );
end entity WF68K30L_OPCODE_DECODER;

architecture BEHAVIOR of WF68K30L_OPCODE_DECODER is
type INSTR_LVL_TYPE is(D, C, B);
type IPIPE_TYPE is
    record
        D       : std_logic_vector(15 downto 0);
        C       : std_logic_vector(15 downto 0);
        B       : std_logic_vector(15 downto 0);
    end record;

signal REQ                  : bit;
signal EW_REQ               : bit;

signal IPIPE                : IPIPE_TYPE;
signal FIFO_RD              : bit;
signal IPIPE_B_FAULT        : std_logic;
signal STG_USED             : integer range 0 to 3; -- [FRM]
signal IPIPE_C_FAULT        : std_logic;
signal IPIPE_D_FAULT        : std_logic;
signal IPIPE_PNTR           : natural range 0 to 3;

signal INSTR_LVL            : INSTR_LVL_TYPE;
signal LOOP_ATN             : boolean;
signal LOOP_BSY_I           : boolean := false; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal LOOP_OP              : boolean;

signal BKPT_REQ             : bit := '0'; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)

signal OP_I                 : OP_68K;

signal OPCODE_FLUSH         : bit := '0'; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal OPCODE_RD_I          : bit;
signal OPCODE_RDY_I         : bit;
signal OW_REQ               : bit;

signal TRAP_CODE_I          : TRAPTYPE_OPC;
signal FLUSHED              : boolean := false; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal PC_INC_I             : bit;
signal PIPE_RDY             : bit;
signal PF_DEMAND            : bit; -- [PFCOF]
signal COF_Q                : bit; -- [PFCOF2]
begin
    P_BSY: process(BUSY_EXH, CLK, IPIPE_FILL, OPCODE_RDY)
    -- This logic requires asynchronous reset. This flip flop is intended 
    -- to break combinatorial loops. If an opcode cycle in the bus controller 
    -- unit is currently running, the actual PC address is stored during this 
    -- cycle. Therefore it is not possible to flush the pipe and manipulate 
    -- the PC during a running cycle. For the exception handler reading the 
    -- opcode is inhibited during a pipe flush. For the main controller unit 
    -- and the coprocessor interface the pipe is flushed after a running 
    -- opcode cycle.
    begin
        if OPCODE_RDY = '1' then
            OPCODE_RD_I <= '0';
        elsif BUSY_EXH = '1' and IPIPE_FILL = '0' then
            OPCODE_RD_I <= '0';
        elsif CLK = '1' and CLK' event then
            if IPIPE_FLUSH = '1' then
                OPCODE_RD_I <= '1';
            elsif (LOOP_ATN = true and OPCODE_RD_I = '0') or LOOP_BSY_I = true then
                OPCODE_RD_I <= '0';
            elsif IPIPE_PNTR < 3 then
                OPCODE_RD_I <= '1';
            end if;
        end if;
    end process P_BSY;

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
    P_COF_Q: process(IPIPE, IPIPE_PNTR, Q_STREAM, Q_COUNT)
        type SW_T is array (0 to 6) of std_logic_vector(15 downto 0);
        variable S   : SW_T;
        variable N   : integer range 0 to 7;
        variable L   : integer range 0 to 3;
        variable HIT : bit;
        variable ANY : bit;
        variable W   : std_logic_vector(15 downto 0);
    begin
        S := (others => (others => '0')); -- No latch: every element assigned on every path.
        S(0) := IPIPE.D; S(1) := IPIPE.C; S(2) := IPIPE.B;
        for i in 0 to 3 loop
            if IPIPE_PNTR = 0 then S(i) := Q_STREAM(63 - 16 * i downto 48 - 16 * i);
            elsif IPIPE_PNTR = 1 then S(i + 1) := Q_STREAM(63 - 16 * i downto 48 - 16 * i);
            elsif IPIPE_PNTR = 2 then S(i + 2) := Q_STREAM(63 - 16 * i downto 48 - 16 * i);
            else S(i + 3) := Q_STREAM(63 - 16 * i downto 48 - 16 * i);
            end if;
        end loop;
        N := IPIPE_PNTR + Q_COUNT;
        HIT := '0'; ANY := '0';
        for i in 0 to 5 loop
            W := S(i); L := 0;
            -- [XH3] Broad match (no length needed): Bcc/BRA/BSR, DBcc, JMP/JSR any <ea>, RTS/RTE/RTR/RTD, TRAP, TRAPV.
            if i < N and (W(15 downto 12) = "0110" or (W(15 downto 12) = "0101" and W(7 downto 3) = "11001") or
                          W(15 downto 7) = "010011101" or W(15 downto 4) = x"4E4" or
                          W = x"4E73" or W = x"4E74" or W = x"4E75" or W = x"4E76" or W = x"4E77") then ANY := '1'; end if;
            if W = x"4E75" or W = x"4E73" or W = x"4E77" then L := 2; -- RTS, RTE, RTR (+1: decoder takes two words).
            elsif W = x"4E74" then L := 2; -- RTD #d16.
            elsif W(15 downto 7) = "010011101" then -- JMP/JSR <ea>
                case W(5 downto 0) is
                    when "010000" | "010001" | "010010" | "010011" | "010100" | "010101" | "010110" | "010111" => L := 2; -- (An)
                    when "101000" | "101001" | "101010" | "101011" | "101100" | "101101" | "101110" | "101111" => L := 2; -- d16(An)
                    when "111000" | "111010" => L := 2; -- xxx.W, d16(PC)
                    when "111001" => L := 3; -- xxx.L
                    when others => L := 0; -- indexed/indirect: length unknown here, no hold
                end case;
            elsif W(15 downto 12) = "0110" and (W(11 downto 8) = "0000" or W(11 downto 8) = "0001") then -- BRA, BSR
                if W(7 downto 0) = x"FF" then L := 3; else L := 2; end if;
            -- Bcc/DBcc: not predecoded (a real 030 does not predict branches; prog_loop bne.s not taken was held). Step 1 covers them at execution.
            -- DBcc excluded: measured slower (prog_loop +19%), see PREFETCH_COF.md
            end if;
            if L /= 0 and i + L <= N then HIT := '1'; end if;
        end loop;
        COF_Q <= HIT;
        COF_ANY <= ANY;
    end process P_COF_Q;

    P_PF_HOLD: process -- Registered: no combinational path from the control unit to the bus controller.
    begin
        wait until CLK = '1' and CLK' event;
        if (COF_PEND = '1' or COF_Q = '1') and PF_DEMAND = '0' and EXH_REQ = '0' and BUSY_EXH = '0' and IPIPE_FLUSH = '0' and LOOP_BSY_I = false then
            PF_HOLD <= '1';
        else
            PF_HOLD <= '0';
        end if;
    end process P_PF_HOLD;
    OPCODE_RDY_I <= '0' when OPCODE_FLUSH = '1' else OPCODE_RDY; -- Dismiss the current read cycle.
    BUSY_OPD <= '0' when EXH_REQ = '1' and BUSY_MAIN = '0' and IPIPE_PNTR > 0 and OPCODE_RD_I = '0' else -- Fill one opcode is sufficient here.
                '1' when IPIPE_PNTR < 3 or OPCODE_RD_I = '1' else '0';

    INSTRUCTION_PIPE: process
    -- These are the instruction pipe FIFO registers. The opcodes are stored in IPIPE.B, IPIPE.C
    -- and IPIPE.D which is copied to the instruction register or to the respective extension when
    -- read. Be aware, that the pipe is always completely refilled to determine the correct INSTR_LVL
    -- before it is copied to the execution unit.
    variable IPIPE_D_VAR    : std_logic_vector(15 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' then
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
                when 2 =>
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
                when 1 =>
                    if OPCODE_RDY_I = '1' then
                        IPIPE.D <= OPCODE_DATA;
                        IPIPE_D_FAULT <= not OPCODE_VALID;
                    else
                        IPIPE_PNTR <= 0;
                    end if;
                when others => null;
            end case;
        elsif OPCODE_RDY_I = '1' then
            case IPIPE_PNTR is
                when 2 =>
                    IPIPE.B <= OPCODE_DATA;
                    IPIPE_B_FAULT <= not OPCODE_VALID;
                    IPIPE_PNTR <= 3;
                when 1 =>
                    IPIPE.C <= OPCODE_DATA;
                    IPIPE_C_FAULT <= not OPCODE_VALID;
                    IPIPE_PNTR <= 2;
                when 0 =>
                    IPIPE.D <= OPCODE_DATA;
                    IPIPE_D_FAULT <= not OPCODE_VALID;
                    IPIPE_PNTR <= 1;
                when others => null;
            end case;
        end if;
    end process INSTRUCTION_PIPE;

    P_FAULT: process
    -- OW_VALID: the operation words of the issued instruction are valid.
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' then
            OW_VALID <= '0';
        elsif OW_REQ = '1' and LOOP_BSY_I = true then
            OW_VALID <= '1';
        elsif OW_REQ = '1' and PIPE_RDY = '1' and INSTR_LVL = D then
            OW_VALID <= not IPIPE_D_FAULT;
        elsif OW_REQ = '1' and PIPE_RDY = '1' and INSTR_LVL = C then
            OW_VALID <= not(IPIPE_D_FAULT or IPIPE_C_FAULT);
        elsif OW_REQ = '1' and PIPE_RDY = '1' and INSTR_LVL = B then
            OW_VALID <= not (IPIPE_D_FAULT or IPIPE_C_FAULT or IPIPE_B_FAULT);
        elsif EW_REQ = '1' and PIPE_RDY = '1' then
            OW_VALID <= not IPIPE_D_FAULT;
        end if;
    end process P_FAULT;

    -- [FRM] Fault on use: the instruction took the stage word and it was fetched with a bus error.
    -- Rerun flags from the pipe words; the top level adds the words still in the prefetch queue.
    FC <= STG_CF when STG_USED >= 2 else '0';
    FB <= STG_BF when STG_USED >= 3 else '0';
    RC <= STG_CF;
    RB <= STG_BF;

    P_STAGE: process
    -- [FRM] Stage C/B images and fault flags for the bus-error frame (MC68030UM 8.2: stage C is the word at
    -- PC+2, stage B the word at PC+4 of the stacked PC; FC/FB: the instruction used that stage and it was
    -- fetched with a bus error; RC/RB: the word came from a faulted fetch). Positions count words from the
    -- issued instruction (PC_INC on issue keeps PC on BIW_0): NARR is the position of the next word that
    -- enters the pipe, USED the number of words the instruction has taken (operation plus extension words).
    -- Earlier the flags were latched from IPIPE_C/B at the last request, i.e. from pipe progress, and
    -- stage B was BIW_2, a stale word for instructions shorter than three words.
    variable NARR   : integer range 0 to 3;
    variable USED   : integer range 0 to 3;
    variable ACC    : boolean;
    begin
        wait until CLK = '1' and CLK' event;
        ACC := false;
        if BUSY_EXH = '1' then
            null; -- Frozen while the exception handler stacks the frame.
        elsif IPIPE_FLUSH = '1' then
            NARR := 0; USED := 0;
            STG_CA <= '0'; STG_BA <= '0'; STG_CF <= '0'; STG_BF <= '0';
        elsif BKPT_INSERT = '1' or (OW_REQ = '1' and BKPT_REQ = '1') or (LOOP_ATN = true and OPCODE_RD_I = '1') or
              (OW_REQ = '1' and PIPE_RDY = '1' and OP_I = DBcc and LOOP_OP = true and IPIPE.C = x"FFFC") or LOOP_BSY_I = true then
            null; -- Pipe unchanged (breakpoint, loop mode): keep the images.
        elsif OW_REQ = '1' and PIPE_RDY = '1' then -- Issue: D = PC, C = PC+2, B = PC+4.
            STG_C <= IPIPE.C; STG_CF <= IPIPE_C_FAULT; STG_CA <= '1'; -- PIPE_RDY: IPIPE_PNTR >= 2.
            if IPIPE_PNTR = 3 then
                STG_B <= IPIPE.B; STG_BF <= IPIPE_B_FAULT; STG_BA <= '1';
                NARR := 3;
            elsif OPCODE_RDY_I = '1' then
                STG_B <= OPCODE_DATA; STG_BF <= not OPCODE_VALID; STG_BA <= '1';
                NARR := 3;
            else
                STG_BA <= '0'; STG_BF <= '0';
                NARR := 2;
            end if;
            case INSTR_LVL is
                when D => USED := 1;
                when C => USED := 2;
                when B => USED := 3;
            end case;
        else
            if EW_REQ = '1' and IPIPE_PNTR /= 0 and USED < 3 then
                USED := USED + 1;
            end if;
            if OPCODE_RDY_I = '1' and (IPIPE_PNTR < 3 or EW_REQ = '1') then
                ACC := true;
            end if;
            if ACC and NARR = 1 then
                STG_C <= OPCODE_DATA; STG_CF <= not OPCODE_VALID; STG_CA <= '1';
            elsif ACC and NARR = 2 then
                STG_B <= OPCODE_DATA; STG_BF <= not OPCODE_VALID; STG_BA <= '1';
            end if;
            if ACC and NARR < 3 then
                NARR := NARR + 1;
            end if;
        end if;
        STG_USED <= USED;
    end process P_STAGE;

    OUTBUFFERS: process
    variable OP_STOP    : boolean;
    begin
        wait until CLK = '1' and CLK' event;
        if OP_STOP = true and IPIPE_FLUSH = '1' then
            TRAP_CODE <= NONE;
            OP <= NOP;                     -- [F59] was OP_68K'left (ABCD, loop-capable): flush leaves OP non-trapping, not loop-capable
            BIW_0 <= x"0100";              -- [F47] bits11:8=0001 => ALU_COND false
            OP_STOP := false;
        elsif IPIPE_FLUSH = '1' then
            TRAP_CODE <= NONE;
            OP <= NOP;                     -- [F59] (was ABCD) reset/exception flush reaches here
            BIW_0 <= x"0100";              -- [F47] => no spurious conditional trap
        elsif OP_STOP = true then
            null; -- Do not update after PC is incremented.
        elsif LOOP_ATN = true and OPCODE_RD_I = '1' then
            null; -- Wait for pending opcodes.
        elsif OW_REQ = '1' and LOOP_BSY_I = true then
            OP <= OP_I;
            BIW_0 <= IPIPE.D;
            TRAP_CODE <= TRAP_CODE_I;
        elsif OW_REQ = '1' and (PIPE_RDY = '1' or BKPT_REQ = '1') then
            -- Be aware: all BIW are written unaffected 
            -- if they are all used.
            OP <= OP_I;
            BIW_0 <= IPIPE.D;
            BIW_1 <= IPIPE.C;
            BIW_2 <= IPIPE.B;
            if IPIPE_D_FAULT = '1' then
                TRAP_CODE <= NONE; -- [F62] Faulted operation word: the bus error is taken, not its decode.
            else
                TRAP_CODE <= TRAP_CODE_I;
            end if;
            --
            if OP_I = STOP then
                OP_STOP := true;
            end if;
        elsif EW_REQ = '1' and IPIPE_PNTR /= 0 then
            EXT_WORD <= IPIPE.D;
        end if;
    end process OUTBUFFERS;

    LOOP_OP <= false when NO_LOOP = true else
               true when OP = MOVE and BIW_0(8 downto 3) = "010010" else -- (Ay) to (Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "011010" else -- (Ay) to (Ax)+.
               true when OP = MOVE and BIW_0(8 downto 3) = "100010" else -- (Ay) to -(Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "010011" else -- (Ay)+ to (Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "011011" else -- (Ay)+ to (Ax)+.
               true when OP = MOVE and BIW_0(8 downto 3) = "100011" else -- (Ay)+ to -(Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "010100" else -- -(Ay) to (Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "011100" else -- -(Ay) to (Ax)+.
               true when OP = MOVE and BIW_0(8 downto 3) = "100100" else -- -(Ay) to -(Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "100100" else -- -(Ay) to -(Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "010000" else -- Dy to (Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "011000" else -- Dy to (Ax)+.
               true when OP = MOVE and BIW_0(8 downto 3) = "010001" else -- Ay to (Ax).
               true when OP = MOVE and BIW_0(8 downto 3) = "011001" else -- Ay to (Ax)+.
               true when (OP = ADD or OP = AND_B or OP = CMP or OP = EOR or OP = OR_B or OP = SUB) and BIW_0(5 downto 3) = "010" else -- (Ay) to Dx, Dx to (Ay).
               true when (OP = ADD or OP = AND_B or OP = CMP or OP = EOR or OP = OR_B or OP = SUB) and BIW_0(5 downto 3) = "011" else -- (Ay)+ to Dx, Dx to (Ay)+.
               true when (OP = ADD or OP = AND_B or OP = CMP or OP = EOR or OP = OR_B or OP = SUB) and BIW_0(5 downto 3) = "100" else -- -(Ay) to Dx, Dx to -(Ay).
               true when (OP = ADDA or OP = CMPA or OP = SUBA) and BIW_0(5 downto 3) = "010" else -- (Ay) to Ax.
               true when (OP = ADDA or OP = CMPA or OP = SUBA) and BIW_0(5 downto 3) = "011" else -- (Ay)+ to Ax.
               true when (OP = ADDA or OP = CMPA or OP = SUBA) and BIW_0(5 downto 3) = "100" else -- -(Ay) to Ax.
               true when OP = ABCD or OP = SBCD or OP = ADDX or OP = SUBX or OP = CMPM else -- -(Ay) to -(Ay), (Ay)+ to (Ay)+ for CMPM.
               true when (OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST or OP = NBCD) and BIW_0(5 downto 3) = "010" else -- (Ay).
               true when (OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST or OP = NBCD) and BIW_0(5 downto 3) = "011" else -- (Ay)+.
               true when (OP = CLR or OP = NEG or OP = NEGX or OP = NOT_B or OP = TST or OP = NBCD) and BIW_0(5 downto 3) = "100" else -- -(Ay).
               true when (OP = ASL or OP = ASR or OP = LSL or OP = LSR) and BIW_0(7 downto 3) = "11010" else -- (Ay) by #1.
               true when (OP = ASL or OP = ASR or OP = LSL or OP = LSR) and BIW_0(7 downto 3) = "11011" else -- (Ay)+ by #1.
               true when (OP = ASL or OP = ASR or OP = LSL or OP = LSR) and BIW_0(7 downto 3) = "11100" else -- -(Ay) by #1.
               true when (OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and BIW_0(7 downto 3) = "11010" else -- (Ay) by #1.
               true when (OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and BIW_0(7 downto 3) = "11011" else -- (Ay)+ by #1.
               true when (OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and BIW_0(7 downto 3) = "11100" else false; -- -(Ay) by #1.

    -- This is the loop attention signal. There are several conditions to start a loop operation. 
    -- 1. A loop capable operation is in progress indicated by LOOP_OP.
    -- 2. A DBcc operation is coming up (IPIPE.D).
    -- 3. The displacement is minus four (IPIPE.C).
    -- 4. The exception handler may not indicate a request. Otherwise the system may hang  in a self 
    --    blocking mechanism concerning OW_REQ, LOOP_ATN, ALU_BSY.
    LOOP_ATN <= false when EXH_REQ = '1' else
                true when LOOP_BSY_I = false and LOOP_OP = true and OP_I = DBcc and IPIPE.C = x"FFFC" else false; -- IPIPE.C value must be minus four.

    P_LOOP: process
    -- This flip flop controls the loop mode of the
    -- processor. Refer to the MC68000 user manual
    -- Appendix A for more information.
    begin
        wait until CLK = '1' and CLK' event;
        if LOOP_ATN = true and OW_REQ = '1' and OPCODE_RD_I = '0' then
            LOOP_BSY_I <= true;
        elsif LOOP_EXIT = '1' or BUSY_EXH = '1' then
            LOOP_BSY_I <= false;
        end if;
    end process P_LOOP;
    -- F57: the port follows the internal flip flop (one register, explicit power-up value).
    LOOP_BSY <= '1' when LOOP_BSY_I else '0';

    OW_REQ <= '0' when BUSY_EXH = '1' else OW_REQ_MAIN;
    EW_REQ <= EW_REQ_MAIN;

    PIPE_RDY <= '1' when OW_REQ = '1' and IPIPE_PNTR = 3 and INSTR_LVL = B else
                '1' when OW_REQ = '1' and IPIPE_PNTR > 1 and INSTR_LVL = C else
                '1' when OW_REQ = '1' and IPIPE_PNTR > 1 and INSTR_LVL = D else -- We need always pipe C and D to determine the INSTR_LVL.
                '1' when EW_REQ = '1' and IPIPE_PNTR > 0 else '0';
 
    HANDSHAKING: process
    -- Wee need these flip flops to ensure, that the OUTBUFFERS are
    -- written when the respecktive _ACK signal is asserted.
    -- The breakpoint cycles are valid for one word operations and
    -- therefore does never start FPU operations.
    begin
        wait until CLK = '1' and CLK' event;
        if EW_REQ = '1' and IPIPE_PNTR /= 0 then
            EW_ACK <= '1';
        else
            EW_ACK <= '0';
        end if;

        if IPIPE_FLUSH = '1' then
            OPD_ACK_MAIN <= '0';
        elsif TRAP_CODE_I = T_PRIV then -- No action when priviledged.
            OPD_ACK_MAIN <= '0';
        elsif OW_REQ = '1' and LOOP_BSY_I = true then
            OPD_ACK_MAIN <= '1';
        elsif OW_REQ = '1' and (PIPE_RDY = '1' or BKPT_REQ = '1') then
            OPD_ACK_MAIN <= '1';
        else
            OPD_ACK_MAIN <= '0';
        end if;
    end process HANDSHAKING;

    P_PC_OFFSET: process(CLK, BUSY_EXH, LOOP_BSY_I, LOOP_EXIT, OP, PC_INC_I)
    -- Be Aware: the ADR_OFFSET requires the 'old' PC_VAR.
    -- To arrange this, the ADR_OFFSET logic is located
    -- above the PC_VAR logic. Do not change this!
    -- The PC_VAR is modeled in a way, that the PC points
    -- always to the BIW_0.
    -- The PC_EW_OFFSET is also used for the calculation 
    -- of the correct PC value written to the stack pointer
    -- during BSR, JSR and exceptions.
    variable ADR_OFFSET     : std_logic_vector(6 downto 0);
    variable PC_VAR         : std_logic_vector(6 downto 0);
    variable PC_VAR_MEM     : std_logic_vector(6 downto 0);
    begin
        if CLK = '1' and CLK' event then
            if IPIPE_FLUSH = '1' then
                ADR_OFFSET := "0000000";
            elsif PC_INC_I = '1' and OPCODE_RDY_I = '1' then
                ADR_OFFSET := ADR_OFFSET + '1' - PC_VAR;
            elsif OPCODE_RDY_I = '1' then
                ADR_OFFSET := ADR_OFFSET + '1';
            elsif PC_INC_I = '1' then
                ADR_OFFSET := ADR_OFFSET - PC_VAR;
            end if;
            --
            if BUSY_EXH = '0' then
                PC_VAR_MEM := PC_VAR; -- Store the old offset to write back on the stack.
            end if;

            if BUSY_EXH = '1' then
                -- New PC is loaded by the exception handler.
                -- So PC_VAR must be initialized.
                PC_VAR := "0000000";
            elsif PC_INC_I = '1' or FLUSHED = true then
                case INSTR_LVL is
                    when D => PC_VAR := "0000001";
                    when C => PC_VAR := "0000010";
                    when B => PC_VAR := "0000011";
                end case;
            elsif EW_REQ = '1' and IPIPE_PNTR /= 0 then
                PC_VAR := PC_VAR + '1';
            end if;
            --
            if OW_REQ = '1' and BKPT_REQ = '1' then
                PC_EW_OFFSET <= "0010"; -- Always level D operations.
            elsif OW_REQ = '1' and PIPE_RDY = '1' and OP_I = JSR then -- Initialize.
                PC_EW_OFFSET <= x"0";
            elsif OW_REQ = '1' and PIPE_RDY = '1' then -- BSR.
                case INSTR_LVL is
                    when D => PC_EW_OFFSET <= "0010";
                    when C => PC_EW_OFFSET <= "0100";
                    when others => PC_EW_OFFSET <= "0110"; -- LONG displacement.
                end case;
            elsif EW_ACK = '1' and OP = JSR then -- Calculate the required extension words.
                PC_EW_OFFSET <= PC_EW_OFFSET + "010";
            end if;
        end if;
        --
        if BUSY_EXH = '1' and PC_INC_I = '1' then
            PC_OFFSET <= PC_VAR_MEM & '0';
        elsif OP = DBcc and LOOP_BSY_I = true and LOOP_EXIT = '0' then
            -- Suppress to increment after DBcc operation during the loop to
            -- handle a correct PC with displacement when looping around.
            -- In non looping mode, the PC_ING is superseeded by
            -- IPIPE_FLUSH in the PC logic. In loop mode we have no flush.
            PC_OFFSET <= x"00";
        else
            PC_OFFSET <= PC_VAR & '0';
        end if;
        PC_ADR_OFFSET <= ADR_OFFSET & '0';
    end process P_PC_OFFSET;

    P_FLUSH: process
    -- This flip flop is intended to control the incrementation
    -- of the PC: normally the PC is updated in the end of an
    -- operation (if a new opword is available) or otherwise in
    -- the START_OP phase. When the instruction pipe is flushed,
    -- it is required to increment the PC immediately to provide
    -- the correct address for the pipe refilling. In this case
    -- the PC update after the pipe refill is suppressed. 
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' then
            FLUSHED <= true;
        elsif OW_REQ = '1' and PIPE_RDY = '1' then
            FLUSHED <= false;
        end if;
    end process P_FLUSH;

    PC_INC <= PC_INC_I;
    PC_INC_I <= '0' when FLUSHED = true else -- Avoid double increment after a flushed pipe.
                '1' when IPIPE_FLUSH = '1' and BUSY_MAIN = '1' else -- If the pipe is flushed, we need the new PC value for refilling.
                '0' when BKPT_REQ = '1' else -- Do not update!
                '1' when OW_REQ = '1' and PIPE_RDY = '1' else PC_INC_EXH;


    -- This signal indicates how many pipe stages are used at a time.
    -- Be aware: all coprocessor commands are level D to meet the require-
    -- ments of the scanPC.
    INSTR_LVL <= D when TRAP_CODE_I = T_PRIV else -- Points to the first word. Required for stacking.
                 B when OP_I = ADDI and IPIPE.D(7 downto 6) = "10" else
                 B when OP_I = ANDI and IPIPE.D(7 downto 6) = "10" else
                 B when (OP_I = Bcc or OP_I = BRA or OP_I = BSR) and IPIPE.D(7 downto 0) = x"FF" else
                 B when OP_I = CAS2 or (OP_I = CMPI and IPIPE.D(7 downto 6) = "10") else
                 B when OP_I = EORI and IPIPE.D(7 downto 6) = "10" else
                 B when OP_I = LINK and IPIPE.D(11 downto 3) = "100000001" else -- LONG.
                 B when OP_I = ORI and IPIPE.D(7 downto 6) = "10" else
                 B when OP_I = SUBI and IPIPE.D(7 downto 6) = "10" else
                 B when OP_I = TRAPcc and IPIPE.D(2 downto 0) = "011" else
                 C when OP_I = ADDI or OP_I = ANDI or OP_I = ANDI_TO_SR or OP_I = ANDI_TO_CCR else
                 C when (OP_I = BCHG or OP_I = BCLR or OP_I = BSET or OP_I = BTST) and IPIPE.D(8) = '0' else
                 C when (OP_I = Bcc or OP_I = BRA or OP_I = BSR) and IPIPE.D(7 downto 0) = x"00" else
                 C when OP_I = BFCHG or OP_I = BFCLR or OP_I = BFEXTS or OP_I = BFEXTU else
                 C when OP_I = BFFFO or OP_I = BFINS or OP_I = BFSET or OP_I = BFTST else
                 C when OP_I = CAS or OP_I = CHK2 or OP_I = CMP2 or OP_I = CMPI or OP_I = DBcc else
                 C when (OP_I = DIVS or OP_I = DIVU) and IPIPE.D(8 downto 6) = "001" else
                 C when OP_I = EORI or OP_I = EORI_TO_CCR or OP_I = EORI_TO_SR else
                 C when OP_I = LINK or OP_I = MOVEC else
                 C when OP_I = MOVEM or OP_I = MOVEP or OP_I = MOVES or OP_I = PMOVE else
                 C when OP_I = LEA and IPIPE.D(15 downto 12) = x"F" else -- [PMMU2b] MMU operation: EA words after the ext word.
                 C when (OP_I = MULS or OP_I = MULU) and IPIPE.D(8 downto 6) = "000" else
                 C when OP_I = ORI_TO_CCR or OP_I = ORI_TO_SR or OP_I = ORI else
                 C when OP_I = PACK or OP_I = RTD or OP_I = SUBI or OP_I = STOP else
                 C when OP_I = TRAPcc and IPIPE.D(2 downto 0) = "010" else 
                 C when OP_I = UNPK else D;

    -- [PMMU1] MC68030UM 9.8 (p. 9-64/9-65): an F-line instruction with CpID = 0 that the 68030 does not
    -- support takes the F-line trap in supervisor mode but a privilege violation in user mode; PMOVE is privileged.
    TRAP_CODE_I <= T_PRIV when OP_I = UNIMPLEMENTED and IPIPE.D(15 downto 9) = "1111000" and SBIT = '0' else
                   T_PRIV when OP_I = PMOVE and SBIT = '0' else
                   T_PRIV when OP_I = LEA and IPIPE.D(15 downto 12) = x"F" and SBIT = '0' else -- [PMMU2b]
                   T_1010 when OP_I = UNIMPLEMENTED and IPIPE.D(15 downto 12) = x"A" else
                   T_1111 when OP_I = UNIMPLEMENTED and IPIPE.D(15 downto 12) = x"F"  else
                   T_ILLEGAL when OP_I = ILLEGAL else 
                   T_RTE when OP_I = RTE and SBIT = '1' else -- Handled like a trap simplifies the code.
                   T_TRAP when OP_I = TRAP else
                   T_PRIV when OP_I = ANDI_TO_SR and SBIT = '0' else 
                   T_PRIV when OP_I = EORI_TO_SR and SBIT = '0' else 
                   T_PRIV when (OP_I = MOVE_FROM_SR or OP_I = MOVE_TO_SR) and SBIT = '0' else 
                   T_PRIV when (OP_I = MOVE_USP or OP_I = MOVEC or OP_I = MOVES) and SBIT = '0' else 
                   T_PRIV when OP_I = ORI_TO_SR and SBIT = '0' else
                   T_PRIV when (OP_I = RESET or OP_I = RTE) and SBIT = '0' else 
                   T_PRIV when OP_I = STOP and SBIT = '0' else NONE;
            
    OP_DECODE: process(IPIPE)
    begin
        -- The default OPCODE is the ILLEGAL operation, if no of the following conditions are met.
        -- If any not used bit pattern occurs, the CPU will result in an ILLEGAL trap. An exception of
        -- this behavior is the OPCODE with the 1010 or the 1111 pattern in the four MSBs. 
        -- These lead to the respective traps.
        OP_I <= ILLEGAL;
        case IPIPE.D(15 downto 12) is -- Operation code map.
            when x"0" => -- Bit manipulation / MOVEP / Immediate.
                if IPIPE.D(11 downto 0) = x"03C" then
                    OP_I <= ORI_TO_CCR;
                elsif IPIPE.D(11 downto 0) = x"07C" then
                    OP_I <= ORI_TO_SR;
                elsif IPIPE.D(11 downto 0) = x"23C" then
                    OP_I <= ANDI_TO_CCR;
                elsif IPIPE.D(11 downto 0) = x"27C" then
                    OP_I <= ANDI_TO_SR;
                elsif IPIPE.D(11 downto 0) = x"A3C" then
                    OP_I <= EORI_TO_CCR;
                elsif IPIPE.D(11 downto 0) = x"A7C" then
                    OP_I <= EORI_TO_SR;
                elsif IPIPE.D(11 downto 0) = "110011111100" then
                    OP_I <= CAS2;
                elsif IPIPE.D(11 downto 0) = "111011111100" then
                    OP_I <= CAS2;
                elsif IPIPE.D(11 downto 8) = "1110" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) >= "010" and IPIPE.D(5 downto 3) < "111" then
                    OP_I <= MOVES;
                elsif IPIPE.D(11 downto 8) = "1110" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= MOVES;
                elsif IPIPE.D(8 downto 6) > "011" and IPIPE.D(5 downto 3) = "001" then
                    OP_I <= MOVEP;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "010" and IPIPE.C(11) = '1' then
                        OP_I <= CHK2;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) > "100" and IPIPE.D(5 downto 3) < "111" and IPIPE.C(11) = '1' then
                        OP_I <= CHK2;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" and IPIPE.C(11) = '1' then
                        OP_I <= CHK2;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "010" and IPIPE.C(11) = '0' then
                        OP_I <= CMP2;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) > "100" and IPIPE.D(5 downto 3) < "111" and IPIPE.C(11) = '0' then
                        OP_I <= CMP2;
                elsif IPIPE.D(11) = '0' and IPIPE.D(10 downto 9) /= "11" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" and IPIPE.C(11) = '0' then
                        OP_I <= CMP2;
                elsif IPIPE.D(11) = '1' and IPIPE.d(10 downto 9) /= "00" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) < "111" then
                    OP_I <= CAS;
                elsif IPIPE.D(11) = '1' and IPIPE.d(10 downto 9) /= "00" and IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= CAS;
                else
                    case IPIPE.D(5 downto 3) is -- Addressing mode.
                        when "000" | "010" | "011" | "100" | "101" | "110" =>
                            -- Bit operations with static bit number:
                            if IPIPE.D(11 downto 6) = "100000" then
                                OP_I <= BTST;
                            elsif IPIPE.D(11 downto 6) = "100001" then
                                OP_I <= BCHG;
                            elsif IPIPE.D(11 downto 6) = "100010" then
                                OP_I <= BCLR;
                            elsif IPIPE.D(11 downto 6) = "100011" then
                                OP_I <= BSET;
                            -- Logic operations:
                            elsif IPIPE.D(11 downto 8) = x"0" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= ORI;
                            elsif IPIPE.D(11 downto 8) = x"2" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= ANDI;
                            elsif IPIPE.D(11 downto 8) = x"4" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= SUBI;
                            elsif IPIPE.D(11 downto 8) = x"6" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= ADDI;
                            elsif IPIPE.D(11 downto 8) = x"A" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= EORI;
                            elsif IPIPE.D(11 downto 8) = x"C" and IPIPE.D(7 downto 6) < "11" then
                                OP_I <= CMPI;
                            -- Bit operations with dynamic bit number:
                            elsif IPIPE.D(8 downto 6) = "100" then
                                OP_I <= BTST;
                            elsif IPIPE.D(8 downto 6) = "101" then
                                OP_I <= BCHG;
                            elsif IPIPE.D(8 downto 6) = "110" then
                                OP_I <= BCLR;
                            elsif IPIPE.D(8 downto 6) = "111" then
                                OP_I <= BSET;
                            end if;
                        when "111" =>
                            -- In the addressing mode "111" not all register selections are valid.
                            -- Bit operations with static bit number:
                            if IPIPE.D(11 downto 6) = "100000" and IPIPE.D(2 downto 0) < "100" then
                                OP_I <= BTST;
                            elsif IPIPE.D(11 downto 6) = "100001" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BCHG;
                            elsif IPIPE.D(11 downto 6) = "100010" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BCLR;
                            elsif IPIPE.D(11 downto 6) = "100011" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BSET;
                            -- Logic operations:
                            elsif IPIPE.D(11 downto 8) = x"0" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= ORI;
                            elsif IPIPE.D(11 downto 8) = x"2" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= ANDI;
                            elsif IPIPE.D(11 downto 8) = x"4" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= SUBI;
                            elsif IPIPE.D(11 downto 8) = x"6" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= ADDI;
                            elsif IPIPE.D(11 downto 8) = x"A" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= EORI;
                            elsif IPIPE.D(11 downto 8) = x"C" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(2 downto 0) < "100" then
                                OP_I <= CMPI;
                            -- Bit operations with dynamic bit number:
                            elsif IPIPE.D(8 downto 6) = "100" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= BTST;
                            elsif IPIPE.D(8 downto 6) = "101" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BCHG;
                            elsif IPIPE.D(8 downto 6) = "110" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BCLR;
                            elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= BSET;
                            end if;
                        when others =>
                            null;
                    end case;
                end if;
            when x"1" => -- Move BYTE.
                if IPIPE.D(8 downto 6) = "111" and IPIPE.D(11 downto 9) < "010"
                        and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(11 downto 9) < "010" and IPIPE.D(5 downto 3) /= "001"  and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) /= "001" and IPIPE.D(8 downto 6) /= "111" 
                        and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) /= "001" and IPIPE.D(8 downto 6) /= "111" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MOVE;
                end if;
            when x"2" | x"3" => -- Move WORD or LONG.
                if IPIPE.D(8 downto 6) = "111" and IPIPE.D(11 downto 9) < "010" 
                        and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(11 downto 9) < "010" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) = "001" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MOVEA;
                elsif IPIPE.D(8 downto 6) = "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MOVEA;
                elsif IPIPE.D(8 downto 6) /= "001" and IPIPE.D(8 downto 6) /= "111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MOVE;
                elsif IPIPE.D(8 downto 6) /= "001" and IPIPE.D(8 downto 6) /= "111" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MOVE;
                end if;
            when x"4" => -- Miscellaneous.
                if IPIPE.D(11 downto 0) = x"E70" then
                    OP_I <= RESET;
                elsif IPIPE.D(11 downto 0) = x"E71" then
                    OP_I <= NOP;
                elsif IPIPE.D(11 downto 0) = x"E72" then
                    OP_I <= STOP;
                elsif IPIPE.D(11 downto 0) = x"E73" then
                    OP_I <= RTE;
                elsif IPIPE.D(11 downto 0) = x"E74" then
                    OP_I <= RTD;
                elsif IPIPE.D(11 downto 0) = x"E75" then
                    OP_I <= RTS;
                elsif IPIPE.D(11 downto 0) = x"E76" then
                    OP_I <= TRAPV;
                elsif IPIPE.D(11 downto 0) = x"E77" then
                    OP_I <= RTR;
                elsif IPIPE.D(11 downto 0) = x"AFC" then
                    OP_I <= ILLEGAL;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"000" then
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"001" then
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"002" then -- CACR.
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"800" then
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"801" then
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"802" then -- CAAR.
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"803" then -- MSP.
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" and IPIPE.C(11 downto 0) = x"804" then -- ISP.
                    OP_I <= MOVEC;
                elsif IPIPE.D(11 downto 1) = "11100111101" then
                    OP_I <= ILLEGAL; -- Not valid MOVEC patterns.
                elsif IPIPE.D(11 downto 3) = "100001001" then -- 68K20, 68K30, 68K40
                    OP_I <= BKPT;
                elsif IPIPE.D(11 downto 3) = "100000001" then -- 68K20, 68K30, 68K40
                    OP_I <= LINK; -- LONG.
                elsif IPIPE.D(11 downto 3) = "111001010" then
                    OP_I <= LINK; -- WORD.
                elsif IPIPE.D(11 downto 3) = "111001011" then
                    OP_I <= UNLK;
                elsif IPIPE.D(11 downto 3) = "100001000" then
                    OP_I <= SWAP;
                elsif IPIPE.D(11 downto 4) = x"E4" then
                    OP_I <= TRAP;
                elsif IPIPE.D(11 downto 4) = x"E6" then
                    OP_I <= MOVE_USP;
                else
                    case IPIPE.D(5 downto 3) is -- Addressing mode.
                        when "000" | "010" | "011" | "100" | "101" | "110" =>
                            if IPIPE.D(11 downto 6) = "110001" then
                                if IPIPE.C(11) = '1' then
                                    OP_I <= DIVS; -- Long.
                                else
                                    OP_I <= DIVU; -- Long.
                                end if;
                            elsif IPIPE.D(11 downto 6) = "001011" then
                                OP_I <= MOVE_FROM_CCR;
                            elsif IPIPE.D(11 downto 6) = "000011" then
                                OP_I <= MOVE_FROM_SR;
                            elsif IPIPE.D(11 downto 6) = "010011" then
                                OP_I <= MOVE_TO_CCR;                    
                            elsif IPIPE.D(11 downto 6) = "011011" then
                                OP_I <= MOVE_TO_SR;
                            elsif IPIPE.D(11 downto 6) = "110000" then
                                if IPIPE.C(11) = '1' then
                                    OP_I <= MULS; -- Long.
                                else
                                    OP_I <= MULU; -- Long.
                                end if;
                            elsif IPIPE.D(11 downto 6) = "100000" then
                                OP_I <= NBCD;
                            elsif IPIPE.D(11 downto 6) = "101011" then
                                OP_I <= TAS;
                            end if;
                        when  "111" => -- Not all registers are valid for this mode.
                            if IPIPE.D(11 downto 6) = "110001" and IPIPE.D(2 downto 0) < "101" then
                                if IPIPE.C(11) = '1' then
                                    OP_I <= DIVS; -- Long.
                                else
                                    OP_I <= DIVU; -- Long.
                                end if;
                            elsif IPIPE.D(11 downto 6) = "001011" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= MOVE_FROM_CCR;
                            elsif IPIPE.D(11 downto 6) = "000011" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= MOVE_FROM_SR;
                            elsif IPIPE.D(11 downto 6) = "010011" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= MOVE_TO_CCR;                    
                            elsif IPIPE.D(11 downto 6) = "011011" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= MOVE_TO_SR;
                            elsif IPIPE.D(11 downto 6) = "110000" and IPIPE.D(2 downto 0) < "101" then
                                if IPIPE.C(11) = '1' then
                                    OP_I <= MULS; -- Long.
                                else
                                    OP_I <= MULU; -- Long.
                                end if;
                            elsif IPIPE.D(11 downto 6) = "100000" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= NBCD;
                            elsif IPIPE.D(11 downto 6) = "101011" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= TAS;
                            end if;
                        when others =>
                            null;
                    end case;
                                
                    case IPIPE.D(5 downto 3) is -- Addressing mode.
                        when "010" | "101" | "110" =>
                            if IPIPE.D(11 downto 6) = "100001" then
                                OP_I <= PEA;
                            elsif IPIPE.D(11 downto 6) = "111010" then
                                OP_I <= JSR;
                            elsif IPIPE.D(11 downto 6) = "111011" then
                                OP_I <= JMP;
                            end if;
                        when  "111" => -- Not all registers are valid for this mode.
                            if IPIPE.D(11 downto 6) = "100001" and IPIPE.D(2 downto 0) < "100" then
                                OP_I <= PEA;
                            elsif IPIPE.D(11 downto 6) = "111010" and IPIPE.D(2 downto 0) < "100" then
                                OP_I <= JSR;
                            elsif IPIPE.D(11 downto 6) = "111011" and IPIPE.D(2 downto 0) < "100" then
                                OP_I <= JMP;
                            end if;
                        when others =>
                            null;
                    end case;

                    -- For the following operation codes a SIZE (IPIPE.D(7 downto 6)) is not valid.
                    -- For the following operation codes an addressing mode x"001" is not valid.
                    if IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                        case IPIPE.D(11 downto 8) is
                            when x"0" => OP_I <= NEGX;
                            when x"2" => OP_I <= CLR;
                            when x"4" => OP_I <= NEG;
                            when x"6" => OP_I <= NOT_B;
                            when others => null;
                        end case;
                    -- Not all registers are valid for the addressing mode "111":
                    elsif IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                        case IPIPE.D(11 downto 8) is
                            when x"0" => OP_I <= NEGX;
                            when x"2" => OP_I <= CLR;
                            when x"4" => OP_I <= NEG;
                            when x"6" => OP_I <= NOT_B;
                            when others => null;
                        end case;
                    end if;

                    -- if IPIPE.D(11 downto 8) = x"A" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and (IPIPE.D(2 downto 0) < "010" or IPIPE.D(2 downto 0) = "100") then -- 68K
                    if IPIPE.D(11 downto 8) = x"A" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                        case IPIPE.D(7 downto 6) is
                            when "01" | "10" => OP_I <= TST; -- Long or word, all addressing modes.
                            when others => -- Byte: Address register direct not allowed.
                                if IPIPE.D(2 downto 0) /= "100" then
                                    OP_I <= TST;
                                end if;
                        end case;
                    elsif IPIPE.D(11 downto 8) = x"A" and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) /= "111" then
                        case IPIPE.D(7 downto 6) is
                            when "01" | "10" => OP_I <= TST; -- Long or word, all addressing modes.
                            when others => -- Byte: Address register direct not allowed.
                                if IPIPE.D(5 downto 3) /= "001" then
                                    OP_I <= TST;
                                end if;
                        end case;
                    end if;

                    if IPIPE.D(11 downto 9) = "100" and IPIPE.D(5 downto 3) = "000" then
                        case IPIPE.D(8 downto 6) is -- Valid OPMODES for this operation code.
                            when "010" | "011" => OP_I <= EXT;
                            when "111" => OP_I <= EXTB;
                            when others => null;
                        end case;
                    end if;
                    
                    if IPIPE.D(8 downto 6) = "111" then
                        case IPIPE.D(5 downto 3) is -- OPMODES.
                            when "010" | "101" | "110" =>
                                OP_I <= LEA;
                            when "111" =>
                                if IPIPE.D(2 downto 0) < "100" then -- Not all registers are valid for this OPMODE.
                                    OP_I <= LEA;
                                end if;
                            when others => null;
                        end case;
                    end if;

                    if IPIPE.D(11) = '1' and IPIPE.D(9 downto 7) = "001" then
                        if IPIPE.D(10) = '0' then -- Register to memory transfer.
                            case IPIPE.D(5 downto 3) is -- OPMODES, no postincrement addressing.
                                when "010" | "100" | "101" | "110" =>
                                    OP_I <= MOVEM;
                                when "111" =>
                                    if IPIPE.D(2 downto 0) = "000" or IPIPE.D(2 downto 0) = "001" then
                                        OP_I <= MOVEM;
                                    end if;
                                when others => null;
                            end case;
                        else -- Memory to register transfer, no predecrement addressing.
                            case IPIPE.D(5 downto 3) is -- OPMODES.
                                when "010" | "011" | "101" | "110" =>
                                    OP_I <= MOVEM;
                                when "111" =>
                                    if IPIPE.D(2 downto 0) < "100" then
                                        OP_I <= MOVEM;
                                    end if;
                                when others => null;
                            end case;
                        end if;
                    end if;

                    -- The size must be "10" or "11" and the OPMODE may not be "001".
                    if IPIPE.D(8 downto 7) >= "10" and IPIPE.D(6 downto 3) = x"7" and IPIPE.D(2 downto 0) < "101" then
                        OP_I <= CHK;
                    elsif IPIPE.D(8 downto 7) >= "10" and IPIPE.D(6 downto 3) /= x"1" and IPIPE.D(6 downto 3) < x"7" then
                        OP_I <= CHK;
                    end if;
                end if;
            when x"5" => -- ADDQ / SUBQ / Scc / DBcc / TRAPcc.
                if IPIPE.D(7 downto 3) = "11001" then
                    OP_I <= DBcc;
                elsif IPIPE.D(7 downto 6) = "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= Scc;
                elsif IPIPE.D(7 downto 6) = "11" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= Scc;
                --
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ADDQ;
                elsif IPIPE.D(8) = '0' and (IPIPE.D(7 downto 6) = "01" or IPIPE.D(7 downto 6) = "10") and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ADDQ;
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) = "00" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ADDQ;
                --
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= SUBQ;
                elsif IPIPE.D(8) = '1' and (IPIPE.D(7 downto 6) = "01" or IPIPE.D(7 downto 6) = "10") and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= SUBQ;
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) = "00" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= SUBQ;
                --
                elsif IPIPE.D(7 downto 3) = "11111" then
                    OP_I <= TRAPcc;
                end if;
            when x"6" => -- Bcc / BSR / BRA.
                if IPIPE.D(11 downto 8) = x"0" then
                    OP_I <= BRA;
                elsif IPIPE.D(11 downto 8) = x"1" then
                    OP_I <= BSR;
                else
                    OP_I <= Bcc;
                end if;
            when x"7" => -- MOVEQ.
                if IPIPE.D(8) = '0' then
                    OP_I <= MOVEQ;
                end if;
            when x"8" => -- OR / DIV / SBCD / PACK / UNPK.
                if IPIPE.D(8 downto 4) = "10100" then
                    OP_I <= PACK;
                elsif IPIPE.D(8 downto 4) = "11000" then
                    OP_I <= UNPK;
                elsif IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= DIVU; -- WORD.
                elsif IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= DIVU; -- WORD.
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= DIVS; -- WORD.
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= DIVS; -- WORD.
                elsif IPIPE.D(8 downto 4) = "10000" then
                    OP_I <= SBCD;
                end if;
                --
                case IPIPE.D(8 downto 6) is
                    when "000" | "001" | "010" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= OR_B;
                        elsif IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= OR_B;
                        end if;
                    when "100" | "101" | "110" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                            OP_I <= OR_B;
                        elsif IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= OR_B;
                        end if;
                    when others =>
                        null;
                end case;
            when x"9" => -- SUB / SUBX.
                case IPIPE.D(8 downto 6) is
                    when "000" => -- Byte size.
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= SUB;
                        elsif IPIPE.D(5 downto 3) /= "111" and IPIPE.D(5 downto 3) /= "001" then
                            OP_I <= SUB;
                        end if;
                    when "001" | "010" => -- Word and long.
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= SUB;
                        elsif IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= SUB;
                        end if;
                    when "100" =>
                        if IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "001" then
                            OP_I <= SUBX;
                        elsif IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                            OP_I <= SUB;
                        elsif IPIPE.D(5 downto 3) /= "111" and IPIPE.D(5 downto 3) /= "001" then  -- Byte size.
                            OP_I <= SUB;
                        end if;
                    when "101" | "110"  =>
                        if IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "001" then
                            OP_I <= SUBX;
                        elsif IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                            OP_I <= SUB;
                        elsif IPIPE.D(5 downto 3) /= "111" then -- Word and long.
                            OP_I <= SUB;
                        end if;
                    when "011" | "111" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= SUBA;
                        elsif IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= SUBA;
                        end if;
                    when others => -- U, X, Z, W, H, L, -.
                        null;
                end case;
            when x"A" => -- (1010, Unassigned, Reserved).
                OP_I <= UNIMPLEMENTED;
            when x"B" => -- CMP / EOR.
                if IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(5 downto 3) = "001" then
                    OP_I <= CMPM;
                else
                    case IPIPE.D(8 downto 6) is -- OPMODE field.
                        when "000" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= CMP;
                            elsif IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= CMP;
                            end if;
                        when "001" | "010" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= CMP;
                            elsif IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= CMP;
                            end if;
                        when "011" | "111" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= CMPA;
                            elsif IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= CMPA;
                            end if;
                        when "100" | "101" | "110" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= EOR;
                            elsif IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= EOR;
                            end if;
                        when others => -- U, X, Z, W, H, L, -.
                            null;
                    end case;
                end if;
            when x"C" => -- AND / MUL / ABCD / EXG.
                if IPIPE.D(8 downto 4) = "10000" then
                    OP_I <= ABCD;
                elsif IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MULU; -- WORD.
                elsif IPIPE.D(8 downto 6) = "011" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MULU; -- WORD.
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                    OP_I <= MULS; -- WORD.
                elsif IPIPE.D(8 downto 6) = "111" and IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= MULS; -- WORD.
                elsif IPIPE.D(8 downto 3) = "101000" or IPIPE.D(8 downto 3) = "101001" or IPIPE.D(8 downto 3) = "110001" then
                    OP_I <= EXG;
                else
                    case IPIPE.D(8 downto 6) is -- OPMODE
                        when "000" | "001" | "010" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                                OP_I <= AND_B;
                            elsif IPIPE.D(5 downto 3) /= "001" and IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= AND_B;
                            end if;
                        when "100" | "101" | "110" =>
                            if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                                OP_I <= AND_B;
                            elsif IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                                OP_I <= AND_B;
                            end if;
                        when others =>
                            null;
                    end case;
                end if;
            when x"D" => -- ADD / ADDX.
                case IPIPE.D(8 downto 6) is
                    when "000" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= ADD;
                        elsif IPIPE.D(5 downto 3) /= "111" and IPIPE.D(5 downto 3) /= "001" then
                            OP_I <= ADD;
                        end if;
                    when "001" | "010" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= ADD;
                        elsif IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= ADD;
                        end if;
                    when "100"  =>
                        if IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "001" then
                            OP_I <= ADDX;
                        elsif IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                            OP_I <= ADD;
                        elsif IPIPE.D(5 downto 3) /= "111" and IPIPE.D(5 downto 3) /= "001" then
                            OP_I <= ADD;
                        end if;
                    when "101" | "110"  =>
                        if IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "001" then
                            OP_I <= ADDX;
                        elsif IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                            OP_I <= ADD;
                        elsif IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= ADD;
                        end if;
                    when "011" | "111" =>
                        if IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "101" then
                            OP_I <= ADDA;
                        elsif IPIPE.D(5 downto 3) /= "111" then
                            OP_I <= ADDA;
                        end if;
                    when others => -- U, X, Z, W, H, L, -.
                        null;
                end case;
            when x"E" => -- Shift / Rotate / Bit Field.
                if IPIPE.D(11 downto 6) = "101011" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFCHG;
                elsif IPIPE.D(11 downto 6) = "101011" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFCHG;
                elsif IPIPE.D(11 downto 6) = "101011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= BFCHG;
                elsif IPIPE.D(11 downto 6) = "110011" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFCLR;
                elsif IPIPE.D(11 downto 6) = "110011" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFCLR;
                elsif IPIPE.D(11 downto 6) = "110011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= BFCLR;
                elsif IPIPE.D(11 downto 6) = "101111" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFEXTS;
                elsif IPIPE.D(11 downto 6) = "101111" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFEXTS;
                elsif IPIPE.D(11 downto 6) = "101111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" then
                    OP_I <= BFEXTS;
                elsif IPIPE.D(11 downto 6) = "100111" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFEXTU;
                elsif IPIPE.D(11 downto 6) = "100111" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFEXTU;
                elsif IPIPE.D(11 downto 6) = "100111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" then
                    OP_I <= BFEXTU;
                elsif IPIPE.D(11 downto 6) = "110111" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFFFO;
                elsif IPIPE.D(11 downto 6) = "110111" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFFFO;
                elsif IPIPE.D(11 downto 6) = "110111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" then
                    OP_I <= BFFFO;
                elsif IPIPE.D(11 downto 6) = "111111" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFINS;
                elsif IPIPE.D(11 downto 6) = "111111" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFINS;
                elsif IPIPE.D(11 downto 6) = "111111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= BFINS;
                elsif IPIPE.D(11 downto 6) = "111011" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFSET;
                elsif IPIPE.D(11 downto 6) = "111011" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFSET;
                elsif IPIPE.D(11 downto 6) = "111011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= BFSET;
                elsif IPIPE.D(11 downto 6) = "100011" and (IPIPE.D(5 downto 3) = "000" or IPIPE.D(5 downto 3) = "010") then
                    OP_I <= BFTST;
                elsif IPIPE.D(11 downto 6) = "100011" and (IPIPE.D(5 downto 3) >= "101" or IPIPE.D(5 downto 3) <= "110") then
                    OP_I <= BFTST;
                elsif IPIPE.D(11 downto 6) = "100011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "100" then
                    OP_I <= BFTST;
                elsif IPIPE.D(11 downto 6) = "000011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ASR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "000011" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ASR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "000111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ASL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "000111" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ASL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "001011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= LSR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "001011" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= LSR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "001111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= LSL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "001111" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= LSL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "010011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ROXR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "010011" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ROXR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "010111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ROXL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "010111" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ROXL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "011011" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ROTR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "011011" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ROTR; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "011111" and IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010" then
                    OP_I <= ROTL; -- Memory shifts.
                elsif IPIPE.D(11 downto 6) = "011111" and IPIPE.D(5 downto 3) > "001" and IPIPE.D(5 downto 3) /= "111" then
                    OP_I <= ROTL; -- Memory shifts.
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "00" then
                    OP_I <= ASR; -- Register shifts.
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "00" then
                    OP_I <= ASL; -- Register shifts.
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "01" then
                    OP_I <= LSR; -- Register shifts.
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "01" then
                    OP_I <= LSL; -- Register shifts.
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "10" then
                    OP_I <= ROXR; -- Register shifts.
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "10" then
                    OP_I <= ROXL; -- Register shifts.
                elsif IPIPE.D(8) = '0' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "11" then
                    OP_I <= ROTR; -- Register shifts.
                elsif IPIPE.D(8) = '1' and IPIPE.D(7 downto 6) < "11" and IPIPE.D(4 downto 3) = "11" then
                    OP_I <= ROTL; -- Register shifts.
                end if;
            when x"F" => -- 1111, Coprocessor Interface / 68K40 Extensions.
                -- [PMMU1] PMOVE (MC68030UM 9.8, CpID 0, opword $F000 + EA, one extension word).
                -- Memory alterable EA only: (An), (An)+, -(An), (d16,An), (d8,An,Xn)/full, (xxx).W, (xxx).L.
                -- Extension word: 000 P-REG R/W FD 00000000 (TT0 = 010, TT1 = 011),
                --                 010 P-REG R/W FD 00000000 (TC = 000, SRP = 010, CRP = 011; the 64-bit SRP/CRP
                --                 not yet with (An)+ / -(An): those two still take the F-line trap),
                --                 011 000   R/W 0  00000000 (MMUSR, word).
                -- [PMMU2b] PFLUSHA, PFLUSH, PLOAD, PTEST (MC68030UM 9.8, pp. A-? / 9-64): decoded as an LEA that computes
                -- the control EA (no operand access) and hands EA + extension word to the MMU at writeback instead of
                -- writing An. Forms with no EA (PFLUSHA, PFLUSH FC,#MASK) use (A0) as a dummy EA.
                -- FC field: 10XXX immediate, 00000 SFC, 00001 DFC 01RRR Dn [PMMU3]. PTEST with A = 1: not yet.
                if IPIPE.D(11 downto 6) = "000000" and
                   (IPIPE.C(4 downto 3) = "10" or IPIPE.C(4 downto 3) = "01" or IPIPE.C(4 downto 1) = "0000" or IPIPE.C(12 downto 10) = "001") and
                   ((IPIPE.D(5 downto 0) = "000000" and IPIPE.C = x"2400") or -- PFLUSHA
                    (IPIPE.D(5 downto 0) = "000000" and IPIPE.C(15 downto 8) = x"30") or -- PFLUSH FC,#MASK
                    (((IPIPE.D(5 downto 3) = "010" or IPIPE.D(5 downto 3) = "101" or IPIPE.D(5 downto 3) = "110") or
                      (IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010")) and
                     ((IPIPE.C(15 downto 8) = x"38") or -- PFLUSH FC,#MASK,<ea>
                      (IPIPE.C(15 downto 10) = "001000" and IPIPE.C(8 downto 5) = "0000") or -- PLOAD
                      (IPIPE.C(15 downto 13) = "100" and IPIPE.C(8 downto 5) = "0000")))) then -- PTEST, A = 0
                    OP_I <= LEA;
                elsif IPIPE.D(11 downto 6) = "000000" and ((IPIPE.D(5 downto 3) >= "010" and IPIPE.D(5 downto 3) < "111") or
                   (IPIPE.D(5 downto 3) = "111" and IPIPE.D(2 downto 0) < "010")) and IPIPE.C(7 downto 0) = x"00" and
                   ((IPIPE.C(15 downto 13) = "000" and IPIPE.C(12 downto 11) = "01") or
                    (IPIPE.C(15 downto 10) = "010000") or
                    (IPIPE.C(15 downto 11) = "01001" and IPIPE.D(5 downto 3) /= "011" and IPIPE.D(5 downto 3) /= "100") or
                    (IPIPE.C(15 downto 10) = "011000" and IPIPE.C(8) = '0')) then
                    OP_I <= PMOVE;
                else
                    OP_I <= UNIMPLEMENTED;
                end if;
            when others => -- U, X, Z, W, H, L, -.
                null;
            end case;
    end process OP_DECODE;
end BEHAVIOR;
