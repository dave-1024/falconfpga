------------------------------------------------------------------------
----                                                                ----
---- WF68K30L IP Core: Address register logic.                      ----
----                                                                ----
---- Description:                                                   ----
---- This arithmetical logical unit handles all integer operations. ----
---- The shift operations are computed by a standard shifter within ----
---- up to 32 clock cycles depending on the shift width. This unit  ----
---- also handles the bit field operations within one clock cycle.  ----
---- The multiplication is modeled as a hardware multiplier which   ----
---- calculates the result in one clock cycle. The division requi-  ----
---- res 32 clock cycles for 32 bit wide operands. The date which   ----
---- is required for the respective operation is stored in regis-   ----
---- ters. The ALU works together with the writeback of the oper-   ----
---- ands as third stage in the pipelined architecture. The hand-   ----
---- shaking is provided by ALU_REQ, ALU_ACK and ALU_BUSY. For more ----
---- information refer to the MC68010 User' Manual.                 ----
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
-- Revision 2K14B 20141201 WF
--   Fixed the CAS and CAS2 conditional testing. Thanks to Raymond Mounissamy for the correct code.
-- Revision 2K18A 20180620 WF
--   Bug fix: MOVEM sign extension.
--   Fix for restoring correct values during the DIVS and DIVU in word format.
--   Fixed the SUBQ calculation.
--   Rearranged the Offset for the JSR instruction.
--   EXT instruction uses now RESULT(63 downto 0).
--   Shifter signals now ready if shift width is zero.
--   Fixed wrong condition codes for AND_B, ANDI, EOR, EORI, OR_B, ORI and NOT_B.
--   Fixed writeback issues in the status register logic.
--   Fixed the condition code calculation for NEG and NEGX.
-- Revision 2K19A 20190620 WF
--   Fixed a bug in MULU.W (input operands are now 16 bit wide).
-- FalconFPGA modifications (David Dunne, github.com/dave-1024/falconfpga), CERN OHL v1.2.
-- Changes are tagged Fnn in the code. Dates are from git history.
-- Base: WF68K30L 2K19A (this repo's import of 2026-09-24).
--   2026-09-30 F21-F25: bit field byte count, register wrap, BFINS pattern, width, BFSET typo.
--   2026-09-30 F26: VHDL-93 IMAX/IMIN instead of VHDL-2008 MINIMUM/MAXIMUM.
--   2026-09-30 F27: DIVS remainder takes the sign of the dividend.
--   2026-09-30 F29: CHK2/CMP2 signed bounds, full 32-bit An compare.
--   2026-09-30 F42-F54: reset and power-up values (SR $2700, no spurious traps).
--   2026-10-03 F56: combinational loops and BF_NZ latch removed; hazard selects.
--   2026-10-04 F57: explicit power-up values for set-type flops.
-- 

library work;
use work.WF68K30L_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity WF68K30L_ALU is
    port (
        CLK                 : in std_logic;
        RESET               : in bit;

        LOAD_OP1            : in bit;
        LOAD_OP2            : in bit;
        LOAD_OP3            : in bit;

        OP1_IN              : in Std_Logic_Vector(31 downto 0);
        OP2_IN              : in Std_Logic_Vector(31 downto 0);
        OP3_IN              : in Std_Logic_Vector(31 downto 0);

        BF_OFFSET_IN        : in Std_Logic_Vector(31 downto 0);
        BF_WIDTH_IN         : in Std_Logic_Vector(5 downto 0);
        BITPOS_IN           : in Std_Logic_Vector(4 downto 0);
        BF_BYTES_IN         : in integer range 0 to 5; -- F21/H29: from the control unit.

        RESULT              : out Std_Logic_Vector(63 downto 0);
        RESULT_MV           : out Std_Logic_Vector(31 downto 0); -- [F3] MOVEM operand, unregistered.

        ADR_MODE_IN         : in Std_Logic_Vector(2 downto 0);
        OP_SIZE_IN          : in OP_SIZETYPE;
        OP_IN               : in OP_68K;
        OP_WB               : in OP_68K;
        BIW_0_IN            : in Std_Logic_Vector(11 downto 0);
        BIW_1_IN            : in Std_Logic_Vector(15 downto 0);

        -- The Flags:
        SR_WR               : in bit;
        SR_INIT             : in bit;
        SR_CLR_MBIT         : in bit;
        CC_UPDT             : in bit;

        STATUS_REG_OUT      : out std_logic_vector(15 downto 0);
        ALU_COND            : out boolean;
        
        -- Status and Control:
        ALU_INIT            : in bit; -- Strobe.
        ALU_BSY             : out bit;
        ALU_REQ             : buffer bit;
        ALU_ACK             : in bit;
        USE_DREG            : in bit; -- Used for CAS2, CHK2, CMP2.
        HILOn               : in bit;
        IRQ_PEND            : in std_logic_vector(2 downto 0);
        TRAP_CHK            : out bit; -- Trap due to the CHK, CHK2 instructions.
        TRAP_DIVZERO        : out bit -- Trap due to divide by zero.
    );
end entity WF68K30L_ALU;
    
architecture BEHAVIOUR of WF68K30L_ALU is
type DIV_STATES is (IDLE, INIT, CALC);
type SHIFT_STATES is (IDLE, RUN);
signal ALU_COND_I           : boolean;
signal ADR_MODE             : Std_Logic_Vector(2 downto 0) := "000"; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal BITPOS               : integer range 0 to 31;
signal BF_DATA_IN           : Std_Logic_Vector(39 downto 0);
signal BF_REG               : std_logic; -- F23/H29-C: register operand.
signal BF_ROT               : integer range 0 to 31; -- F23/H29-C: rotate amount.
signal BF_ROT_DATA          : Std_Logic_Vector(31 downto 0);
signal BF_RESULT            : Std_Logic_Vector(31 downto 0);
signal BF_LOWER_BND         : integer range 0 to 39;
signal BF_OFFSET            : Std_Logic_Vector(31 downto 0);
signal BF_UPPER_BND         : integer range 0 to 39 := 0; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal BF_WIDTH             : integer range 1 to 32;
signal BIW_0                : Std_Logic_Vector(11 downto 0);
signal BIW_1                : Std_Logic_Vector(15 downto 0);
signal CAS2_COND            : boolean := false; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
-- [T6] Exact MC68030 timing: registered padding of ALU_REQ (see P_PAD).
signal PAD_PEND             : bit := '0';
signal PAD_LD               : bit := '0';
signal PAD_ZERO             : bit := '1';
signal PAD_CNT              : unsigned(7 downto 0) := (others => '0');
signal PAD_TGT              : unsigned(7 downto 0);
signal BF_BYTES_R           : integer range 0 to 5 := 0;
signal PAD_OP_IN            : bit;
signal PAD_OP_A             : bit;
signal PAD_OP_R             : bit;
constant PAD_EN             : bit := '1'; -- [T6] '0' restores the old (faster) timing.
signal ALU_BSY_I            : bit := '0'; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal CB_BCD               : std_logic;
signal CHK_CMP_COND         : boolean;
signal CHK2CMP2_DR          : bit := '0'; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal CHK2_RN              : std_logic_vector(31 downto 0); -- F29/H35+H37.
signal DIV_RDY              : bit;
signal DIV_STATE            : DIV_STATES := IDLE;
signal MSB                  : integer range 0 to 31;
signal OP                   : OP_68K := UNIMPLEMENTED;
signal OP1                  : Std_Logic_Vector(31 downto 0);
signal OP2                  : Std_Logic_Vector(31 downto 0);
signal OP3                  : Std_Logic_Vector(31 downto 0);
signal OP1_SIGNEXT          : Std_Logic_Vector(31 downto 0);
signal OP2_SIGNEXT          : Std_Logic_Vector(31 downto 0);
signal OP3_SIGNEXT          : Std_Logic_Vector(31 downto 0);
signal OP_SIZE              : OP_SIZETYPE := LONG;
signal QUOTIENT             : unsigned(31 downto 0);
signal REMAINDER            : unsigned(31 downto 0);
signal RESULT_BCDOP         : Std_Logic_Vector(7 downto 0);
signal RESULT_BITFIELD      : Std_Logic_Vector(39 downto 0);
signal RESULT_BITOP         : Std_Logic_Vector(31 downto 0);
signal RESULT_INTOP         : Std_Logic_Vector(31 downto 0);
signal RESULT_LOGOP         : Std_Logic_Vector(31 downto 0);
signal RESULT_MUL           : Std_Logic_Vector(63 downto 0);
signal RESULT_SHIFTOP       : Std_Logic_Vector(31 downto 0);
signal RESULT_OTHERS        : Std_Logic_Vector(31 downto 0);
signal SHIFT_STATE          : SHIFT_STATES;
signal SHIFT_WIDTH          : Std_Logic_Vector(5 downto 0) := "000000"; -- F57: explicit power-up value (Gowin drops the implicit one on set-type flops)
signal SHIFT_WIDTH_IN       : Std_Logic_Vector(5 downto 0);
signal SHFT_LOAD            : bit;
signal SHFT_RDY             : bit;
signal SHFT_EN              : bit;
signal STATUS_REG           : Std_Logic_Vector(15 downto 0) := x"2700";  -- [F49]
-- F46 forces the SREG_MEM VARIABLE to $2700 on RESET, but STATUS_REG is the
-- SIGNAL driven from it at the end of P_STATUS_REG -- so until the first
-- clock edge after reset it still holds power-up garbage.  ALU_COND is
-- COMBINATIONAL off STATUS_REG (not off SREG_MEM), and ALU_COND for TRAPV is
-- "true when OP = TRAPV and STATUS_REG(1) = '1'".  So the V bit could read as
-- '1' out of cold reset regardless of F46.  $2700 = reset SR with V clear.
signal VFLAG_DIV            : std_logic;
signal XFLAG_SHFT           : std_logic;
-- [SH1] One-clock barrel shifter (result and C/V/X for the whole count), replaces the 1 bit/clock loop.
constant FAST_SHIFT         : boolean := true;
signal FS_R                 : std_logic_vector(31 downto 0);
signal FS_C, FS_V, FS_X     : std_logic;
signal XNZVC                : Std_Logic_Vector(4 downto 0);

-- F26: MINIMUM and MAXIMUM are VHDL-2008 built-ins. GHDL was being run with
-- --std=08 and accepted them; the Gowin VHDL frontend is 93/2002 and rejected
-- them outright (EX4759, 'minimum' is not declared). The sim path and the
-- synthesis path were using DIFFERENT LANGUAGE STANDARDS, so the simulator
-- could never have caught this. These two locals are VHDL-93 clean and behave
-- identically. The whole tree now analyses under --std=93, which is what GHDL
-- is run with from here on so the two paths agree.
function IMAX(L, R : integer) return integer is
begin
    if L > R then return L; else return R; end if;
end function IMAX;

function IMIN(L, R : integer) return integer is
begin
    if L < R then return L; else return R; end if;
end function IMIN;
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
            BF_OFFSET <= BF_OFFSET_IN;
            BITPOS <= To_Integer(unsigned(BITPOS_IN));
            BF_BYTES_R <= BF_BYTES_IN; -- [T6]
            BF_WIDTH <= To_Integer(unsigned(BF_WIDTH_IN));
            -- F21/H29: BF_DATA_IN is OP3 & OP2(7 downto 0), and OP3 holds the
            -- fetched bytes RIGHT justified -- a 1 byte fetch puts the data at
            -- bits 15..8, not 39..32. These bounds anchored to 39/40, i.e. they
            -- assumed MSB alignment, so a narrow field read the empty top of
            -- the window and extracted ZERO. Measured: {0:8} gave lo=32 hi=39
            -- over DATA_IN=0000001232 -- the $12 was at bits 15..8 all along.
            -- Shift both bounds down by 8*(4 - bytes fetched). BF_BYTES_I is
            -- the same table the control unit sizes the fetch with, indexed by
            -- [bit position in byte, width], now shared via the package.
            -- BF_BYTES = 4 gives shift 0, preserving the wide-field case that
            -- already worked; BF_BYTES = 5 is the split access and is clamped
            -- to shift 0 so the BF_HILOn machinery is left untouched.
            -- IMAX(0,..): PARAMETER_BUFFER latches for EVERY instruction and
            -- BF_BYTES_IN is 0 for non bit field ops, which would drive these
            -- negative and break the 0..39 range. The values are meaningless
            -- for those ops; they only have to stay legal.
            SHIFT_WIDTH <= SHIFT_WIDTH_IN;
            --
            -- F23/H29-C: MC68030UM 2.2.1, Fig 2-3. For a REGISTER operand the
            -- offset is taken modulo 32, offset 0 is bit 31, and if
            -- offset + width exceeds 32 the field WRAPS AROUND WITHIN THE
            -- REGISTER. The operand model below is a LINEAR 40 bit window
            -- addressed by BF_LOWER_BND/BF_UPPER_BND, and a linear window
            -- cannot express a wrap. Measured: %d3{28:8} on $A000000B returned
            -- $B3, whose low nibble was PREFETCH data out of OP2 rather than
            -- the wrapped register bits -- the read ran off the end of the
            -- register into the pipeline.
            -- Rather than teach seven currently-correct arms modular indexing,
            -- on the I_OPCODE_DECODER -> I_ALU path that already owns the
            -- critical region, the register operand is ROTATED LEFT by the
            -- offset so the field becomes CONTIGUOUS at the top of the window.
            -- Every arm then sees the geometry it already handles, the bounds
            -- become the trivial 39 / 40-width, and the modified result is
            -- rotated back on the way out. Memory operands are untouched: the
            -- else branch is the F21 code verbatim.
            if BIW_0_IN(5 downto 3) = "000" then -- Register direct.
                BF_REG <= '1';
                BF_ROT <= To_Integer(unsigned(BITPOS_IN));
                BF_UPPER_BND <= 39;
                BF_LOWER_BND <= 40 - IMIN(IMAX(To_Integer(unsigned(BF_WIDTH_IN)), 1), 32);
            else
                BF_REG <= '0';
                BF_ROT <= 0;
                BF_UPPER_BND <= IMAX(0, 39 - To_Integer(unsigned(BITPOS_IN))
                                - 8 * (4 - IMIN(IMAX(BF_BYTES_IN, 1), 4)));
                if To_Integer(unsigned(BITPOS_IN)) + To_Integer(unsigned(BF_WIDTH_IN)) > 40 then
                    BF_LOWER_BND <= 0;
                else 
                    BF_LOWER_BND <= IMAX(0, 40 - (To_Integer(unsigned(BITPOS_IN)) + To_Integer(unsigned(BF_WIDTH_IN)))
                                    - 8 * (4 - IMIN(IMAX(BF_BYTES_IN, 1), 4)));
                end if;
            end if;
        end if;
    end process PARAMETER_BUFFER;

    OPERANDS: process
    -- During instruction execution, the buffers are written
    -- before or during ALU_INIT and copied to the operands
    -- during ALU_INIT.
    variable OP1_BUFFER     : Std_Logic_Vector(31 downto 0);
    variable OP2_BUFFER     : Std_Logic_Vector(31 downto 0);
    variable OP3_BUFFER     : Std_Logic_Vector(31 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        if LOAD_OP1 = '1' then
            OP1_BUFFER := OP1_IN;
        end if;

        if LOAD_OP2 = '1' then
            OP2_BUFFER := OP2_IN;
        end if;

        if LOAD_OP3 = '1' then
            OP3_BUFFER := OP3_IN;
        end if;
        
        if ALU_INIT = '1' then
            OP1 <= OP1_BUFFER;
            OP2 <= OP2_BUFFER;
            OP3 <= OP3_BUFFER;
        end if;
    end process OPERANDS;

    -- [T6] Padding to the MC68030UM chapter 11 worst-case (no-cache) clocks. Ops that this core
    -- finishes faster than a real 68030 hold ALU_REQ until a down counter, loaded one clock after
    -- ALU_INIT from the registered operation (OP, OP_SIZE, ADR_MODE, BIW, shift count, bit field
    -- bytes), runs out. Everything is registered: nothing on the bus/DSACK path. PAD_TGT is the
    -- table figure minus K (clocks the instruction needs around the ALU anyway), calibrated per
    -- class with the ISA suite at 0 wait states. Prefetches run on during the padding as on a real 68030.
    -- Read-modify-write memory forms are not padded (already slower than the table).
    PAD_TABLE: process(OP, OP_SIZE, ADR_MODE, BIW_0, BIW_1, SHIFT_WIDTH, BF_BYTES_R)
    -- T: MC68030UM table clocks (no-cache column, without the EA part); K: clocks the instruction
    -- spends outside the padded window (decode, operand load, write back), measured per class.
    variable T : integer range 0 to 255;
    variable K : integer range 0 to 15;
    variable SZ : integer range 8 to 32;
    variable REG : boolean;
    begin
        case OP_SIZE is
            when BYTE => SZ := 8;
            when WORD => SZ := 16;
            when others => SZ := 32;
        end case;
        REG := ADR_MODE = "000";
        T := 0; K := 0;
        case OP is
            when MULS | MULU =>
                if REG then K := 3; else K := 0; end if;
                if OP_SIZE = LONG then T := 44; else T := 28; end if;
            when DIVU =>
                K := 3; if OP_SIZE = LONG then T := 78; else T := 44; end if;
            when DIVS =>
                K := 3; if OP_SIZE = LONG then T := 90; else T := 56; end if;
            when BCHG | BCLR | BSET => K := 4; if REG then T := 6; end if;
            when NBCD => K := 4; if REG then T := 6; end if;
            when CHK => K := 4; if REG then T := 8; end if; -- Memory CHK is already at the table.
            when ANDI_TO_SR | EORI_TO_SR | ORI_TO_SR => K := 3; T := 14;
            when ANDI_TO_CCR | EORI_TO_CCR | ORI_TO_CCR => K := 2; T := 14;
            when LSL | LSR | ASR =>
                K := 4; -- [SH1] barrel: shift done one clock earlier.
                if BIW_0(7 downto 6) = "11" then T := 0; -- Memory, not padded.
                elsif BIW_0(5) = '0' then T := 4; -- Immediate count.
                elsif To_Integer(unsigned(SHIFT_WIDTH)) < SZ then T := 6; -- Dx, count below the size.
                elsif OP = ASR then T := 10;
                else T := 8;
                end if;
            when ASL =>
                K := 4; if BIW_0(7 downto 6) = "11" then T := 0; elsif BIW_0(5) = '0' then T := 6; else T := 8; end if;
            when ROTL | ROTR =>
                K := 4; if BIW_0(7 downto 6) = "11" then T := 0; elsif BIW_0(5) = '0' then T := 6; else T := 8; end if; -- [SH1] K 3 -> 4 for the barrel shifter.
            when ROXL | ROXR =>
                K := 4; if BIW_0(7 downto 6) = "11" then T := 0; else T := 12; end if;
            when BFTST =>
                K := 3; if REG then T := 8; elsif BF_BYTES_R = 5 then T := 14; else T := 10; end if;
            when BFCHG | BFCLR | BFSET => K := 3; if REG then T := 14; end if;
            when BFEXTS | BFEXTU =>
                if REG then K := 2; T := 10; elsif BF_BYTES_R = 5 then K := 0; T := 19; else K := 0; T := 13; end if; -- Memory: +1 (K = -1).
            when BFINS => K := 3; if REG then T := 12; end if;
            when BFFFO =>
                if REG then K := 2; T := 20; elsif BF_BYTES_R = 5 then K := 0; T := 29; else K := 0; T := 23; end if; -- Memory: +1 (K = -1).
            when others => T := 0;
        end case;
        if T > K then
            PAD_TGT <= to_unsigned(T - K, 8);
        else
            PAD_TGT <= (others => '0');
        end if;
    end process PAD_TABLE;

    P_PAD: process
    begin
        wait until CLK = '1' and CLK' event;
        PAD_LD <= ALU_INIT;
        if ALU_INIT = '1' then
            PAD_ZERO <= '0'; -- Decided in the next clock (PAD_LD).
        elsif PAD_LD = '1' then
            PAD_CNT <= PAD_TGT;
            if PAD_TGT <= 1 then PAD_ZERO <= '1'; else PAD_ZERO <= '0'; end if;
        elsif PAD_CNT /= x"00" then
            PAD_CNT <= PAD_CNT - 1;
            if PAD_CNT <= 2 then PAD_ZERO <= '1'; end if;
        else
            PAD_ZERO <= '1';
        end if;
    end process P_PAD;

    P_BUSY: process
    variable REQ_SET : boolean;
    begin
        wait until CLK = '1' and CLK' event;
        if ALU_INIT = '1' then
            ALU_BSY_I <= '1';
        elsif ALU_ACK = '1' or RESET = '1' then
            ALU_BSY_I <= '0';
        end if;
        -- This signal requests the control state machine to proceed when the ALU is ready.
        REQ_SET := false;
        if ALU_ACK = '1' and ALU_INIT = '1' and OP_IN = MOVEM then
            ALU_REQ <= '1'; -- Option A: MOVEM overlap, re-armed in the clock of the acknowledge.
        elsif ALU_ACK = '1' then
            ALU_REQ <= '0';
        elsif (OP = ASL or OP = ASR or OP = LSL or OP = LSR or OP = ROTL or OP = ROTR or OP = ROXL or OP = ROXR) and SHFT_RDY = '1' then
            REQ_SET := true;
        elsif (OP = DIVS or OP = DIVU) and DIV_RDY = '1' then
            REQ_SET := true;
        elsif OP_IN = DIVS or OP_IN = DIVU then
            null;
        elsif OP_IN = ASL or OP_IN = ASR or OP_IN = LSL or OP_IN = LSR then
            null;
        elsif OP_IN = ROTL or OP_IN = ROTR or OP_IN = ROXL or OP_IN = ROXR then
            null;
        elsif ALU_INIT = '1' then
            REQ_SET := true;
        end if;
        -- [T6] A ready result waits in PAD_PEND until the padding is done. PAD_ON/PAD_DONE are those
        -- of the running operation; in the ALU_INIT clock itself they still describe the previous one,
        -- so the set is always parked there for a padded op and released by PAD_DONE.
        if ALU_ACK = '1' or RESET = '1' then
            PAD_PEND <= '0';
        elsif REQ_SET and ALU_INIT = '1' and PAD_EN = '1' and PAD_OP_IN = '1' then
            PAD_PEND <= '1'; -- Padded op: always parked, released by PAD_ZERO.
        elsif REQ_SET and ALU_INIT = '0' and PAD_EN = '1' and PAD_ZERO = '0' then
            PAD_PEND <= '1';
        elsif REQ_SET then
            ALU_REQ <= '1';
        elsif PAD_PEND = '1' and (PAD_ZERO = '1' or (OP = CHK and CHK_CMP_COND = true)) then
            -- [T6b] A trapping CHK is not padded (the trap is decided at ALU_ACK; the 68030 table
            -- lists CHK-with-trap as exception processing); only the no-trap CHK is padded to 8.
            PAD_PEND <= '0';
            ALU_REQ <= '1';
        end if;
    end process P_BUSY;
    ALU_BSY <= ALU_BSY_I; -- F57

    with OP_IN select
        PAD_OP_A <= '1' when MULS | MULU | CHK | BFTST | BFEXTS | BFEXTU | BFFFO |
                             ANDI_TO_CCR | ANDI_TO_SR | EORI_TO_CCR | EORI_TO_SR | ORI_TO_CCR | ORI_TO_SR,
                    '0' when others; -- Padded in every addressing mode.
    with OP_IN select
        PAD_OP_R <= '1' when BCHG | BCLR | BSET | NBCD | BFCHG | BFCLR | BFSET | BFINS,
                    '0' when others; -- Padded in register mode only.
    -- Shifts and DIV never set ALU_REQ in the ALU_INIT clock.
    PAD_OP_IN <= '1' when PAD_OP_A = '1' or (PAD_OP_R = '1' and ADR_MODE_IN = "000") else '0';
    
    with OP_SIZE select
        MSB <= 31 when LONG,
               15 when WORD,
                7 when BYTE;

    SIGNEXT: process(OP, OP1, OP2, OP3, OP_SIZE)
    -- This module provides the required sign extensions.
    begin
        case OP_SIZE is
            when LONG =>
                OP1_SIGNEXT <= OP1;
                OP2_SIGNEXT <= OP2;
                OP3_SIGNEXT <= OP3;
            when WORD =>
                for i in 31 downto 16 loop
                    OP1_SIGNEXT(i) <= OP1(15);
                    OP2_SIGNEXT(i) <= OP2(15);
                    OP3_SIGNEXT(i) <= OP3(15);
                end loop;
                OP1_SIGNEXT(15 downto 0) <= OP1(15 downto 0);
                OP2_SIGNEXT(15 downto 0) <= OP2(15 downto 0);
                OP3_SIGNEXT(15 downto 0) <= OP3(15 downto 0);
            when BYTE =>
                for i in 31 downto 8 loop
                    OP1_SIGNEXT(i) <= OP1(7);
                    OP2_SIGNEXT(i) <= OP2(7);
                    OP3_SIGNEXT(i) <= OP3(7);
                end loop;
                OP1_SIGNEXT(7 downto 0) <= OP1(7 downto 0);
                OP2_SIGNEXT(7 downto 0) <= OP2(7 downto 0);
                OP3_SIGNEXT(7 downto 0) <= OP3(7 downto 0);
        end case;
    end process SIGNEXT;

    P_BCDOP: process(OP, STATUS_REG, OP1, OP2)
    -- The BCD operations are all byte wide and unsigned.
    variable X_IN_I         : unsigned(0 downto 0);
    variable TEMP0          : unsigned(4 downto 0);
    variable TEMP1          : unsigned(4 downto 0);
    variable Z_0            : unsigned(3 downto 0);
    variable C_0            : unsigned(0 downto 0);
    variable Z_1            : unsigned(3 downto 0);
    variable C_1            : std_logic;
    variable S_0            : unsigned(3 downto 0);
    variable S_1            : unsigned(3 downto 0);
    begin
        X_IN_I(0) := STATUS_REG(4); -- Inverted extended Flag.

        case OP is
            when ABCD =>
                TEMP0 := unsigned('0' & OP2(3 downto 0)) + unsigned('0' & OP1(3 downto 0)) + ("0000" & X_IN_I);
            when NBCD =>
                TEMP0 := unsigned(OP1(4 downto 0)) - unsigned('0' & OP2(3 downto 0)) - ("0000" & X_IN_I);
            when others => -- Valid for SBCD.
                TEMP0 := unsigned('0' & OP2(3 downto 0)) - unsigned('0' & OP1(3 downto 0)) - ("0000" & X_IN_I);
        end case;

        if Std_Logic_Vector(TEMP0) > "01001" then
            Z_0 := "0110";
            C_0 := "1";
        else
            Z_0 := "0000";
            C_0 := "0";
        end if;

        case OP is
            when ABCD =>
                TEMP1 := unsigned('0' & OP2(7 downto 4)) + unsigned('0' & OP1(7 downto 4)) + ("0000" & C_0);
            when NBCD =>
                TEMP1 := unsigned(OP1(4 downto 0)) - unsigned('0' & OP2(7 downto 4)) - ("0000" & X_IN_I);
            when others => -- Valid for SBCD.
                TEMP1 := unsigned('0' & OP2(7 downto 4)) - unsigned('0' & OP1(7 downto 4)) - ("0000" & C_0);
        end case;

        if Std_Logic_Vector(TEMP1) > "01001" then
            Z_1 := "0110";
            C_1 := '1';
        else
            Z_1 := "0000";
            C_1 := '0';
        end if;

        case OP is
            when ABCD =>
                S_1 := TEMP1(3 downto 0) + Z_1;
                S_0 := TEMP0(3 downto 0) + Z_0;
            when others => -- Valid for SBCD, NBCD.
                S_1 := TEMP1(3 downto 0) - Z_1;
                S_0 := TEMP0(3 downto 0) - Z_0;
        end case;           
        --
        CB_BCD <= C_1;
        RESULT_BCDOP(7 downto 4) <= Std_Logic_Vector(S_1);
        RESULT_BCDOP(3 downto 0) <= Std_Logic_Vector(S_0);
    end process P_BCDOP;

    -- F23/H29-C: see PARAMETER_BUFFER. For a register operand the field is
    -- brought to the top of the window by rotation; memory keeps the F21
    -- right justified OP3 & OP2 form.
    BF_ROT_DATA <= Std_Logic_Vector(rotate_left(unsigned(OP3), BF_ROT));
    BF_DATA_IN  <= BF_ROT_DATA & x"00" when BF_REG = '1' else OP3 & OP2(7 downto 0);

    -- F23/H29-C: the read-modify-write forms hand back a whole modified
    -- operand and must be rotated back. BFEXTS/BFEXTU/BFFFO produce a result
    -- already right justified in (39 downto 8) and must NOT be rotated.
    BF_RESULT <= Std_Logic_Vector(rotate_right(unsigned(RESULT_BITFIELD(39 downto 8)), BF_ROT))
                   when BF_REG = '1' and (OP = BFCHG or OP = BFCLR or OP = BFINS or OP = BFSET)
                 else RESULT_BITFIELD(39 downto 8);

    P_BITFIELD_OP: process(BF_DATA_IN, BF_LOWER_BND, BF_OFFSET, BF_UPPER_BND, BF_WIDTH, BIW_1, OP, OP1)
    variable BF_NZ      : boolean;
    variable BFFFO_CNT  : std_logic_vector(5 downto 0);
    begin
        BF_NZ := false; -- F56: defined on every path (no latch); BFFFO sets it again below.
        BFFFO_CNT := "000000";
        RESULT_BITFIELD <= BF_DATA_IN; -- Default.
        case OP is
            when BFCHG =>
                for i in RESULT_BITFIELD'range loop
                    if i >= BF_LOWER_BND and i <= BF_UPPER_BND then
                        RESULT_BITFIELD(i) <= not BF_DATA_IN(i);
                    end if;
                end loop;
            when BFCLR =>
                for i in RESULT_BITFIELD'range loop
                    if i >= BF_LOWER_BND and i <= BF_UPPER_BND then
                        RESULT_BITFIELD(i) <= '0';
                    end if;
                end loop;
            when BFEXTS => -- Result is in (39 downto 8).
                for i in 31 downto 0 loop
                    if i <= BF_WIDTH - 1 and BF_LOWER_BND + i <= 39 then
                        RESULT_BITFIELD(i + 8) <= BF_DATA_IN(BF_LOWER_BND + i);
                    end if;
                end loop;
                --
                for i in RESULT_BITFIELD'range loop
                    if i >= 8 + BF_WIDTH then
                        RESULT_BITFIELD(i) <= BF_DATA_IN(BF_UPPER_BND);
                    end if;
                end loop;
            when BFEXTU => -- Result is in (39 downto 8).
                for i in 31 downto 0 loop
                    if i <= BF_WIDTH - 1 and BF_LOWER_BND + i <= 39 then
                        RESULT_BITFIELD(i + 8) <= BF_DATA_IN(BF_LOWER_BND + i);
                    end if;
                end loop;
                --
                for i in RESULT_BITFIELD'range loop
                    if i >= 8 + BF_WIDTH then
                        RESULT_BITFIELD(i) <= '0';
                    end if;
                end loop;
            when BFFFO => -- Result is in (39 downto 8).
                BF_NZ := false;
                BFFFO_CNT := "000000";
                for i in BF_DATA_IN'range loop
                    if i <= BF_UPPER_BND and i >= BF_LOWER_BND then
                        if BF_DATA_IN(i) = '0' and BF_NZ = false then
                            BFFFO_CNT := BFFFO_CNT + '1';
                        else
                            BF_NZ := true;
                        end if;
                    end if;
                end loop;
                --
                RESULT_BITFIELD <= (BF_OFFSET + BFFFO_CNT) & x"00";
            when BFINS =>
                for i in RESULT_BITFIELD'range loop
                    if i <= BF_WIDTH - 1 and (BF_UPPER_BND - i) >= 0 then
                        RESULT_BITFIELD(BF_UPPER_BND - i) <= OP1(BF_WIDTH - i - 1);
                    end if;
                end loop;
            when BFSET =>
                for i in RESULT_BITFIELD'range loop
                    if i >= BF_LOWER_BND and i <= BF_UPPER_BND then
                        RESULT_BITFIELD(i) <= '1';
                    end if;
                end loop;
            when others => -- BFTST. 
                null; -- no calculation required for BFTST.
        end case;
    end process P_BITFIELD_OP;

    P_BITOP: process(BITPOS, OP, OP2)
    -- Bit manipulation operations.
    begin
        RESULT_BITOP <= OP2; -- The default is the unmanipulated data.
        --
        case OP is
            when BCHG =>
                RESULT_BITOP(BITPOS) <= not OP2(BITPOS);
            when BCLR =>
                RESULT_BITOP(BITPOS) <= '0';
            when BSET =>
                RESULT_BITOP(BITPOS) <= '1';
            when others => 
                RESULT_BITOP <= OP2; -- Dummy, no result required for BTST.
        end case;
    end process P_BITOP;

    DIVISION: process
    variable BITCNT         : integer range 0 to 64;
    variable DIVIDEND       : unsigned(63 downto 0);
    variable DIVISOR        : unsigned(31 downto 0);
    variable QUOTIENT_REST  : unsigned(31 downto 0);
    variable QUOTIENT_VAR   : unsigned(31 downto 0);
    variable REMAINDER_REST : unsigned(31 downto 0);
    variable REMAINDER_VAR  : unsigned(31 downto 0);
    -- Be aware, that the destination and source operands
    -- may be reloaded during the division operation. For
    -- this, we use the restore values in case of an overflow.
    begin
        wait until CLK = '1' and CLK' event;
        DIV_RDY <= '0';
        case DIV_STATE is 
            when IDLE => 
                if ALU_INIT = '1' and (OP_IN = DIVS or OP_IN = DIVU) then 
                    DIV_STATE <= INIT; 
                end if;
            when INIT =>
                if OP = DIVS and OP_SIZE = LONG and BIW_1(10) = '1' and OP3(31) = '1' then -- 64 bit signed negative dividend.
                    DIVIDEND := unsigned(not (OP3 & OP2) + '1');
                elsif (OP = DIVS or OP = DIVU) and OP_SIZE = LONG and BIW_1(10) = '1' then -- 64 bit positive or unsigned dividend.
                    DIVIDEND := unsigned(OP3 & OP2);
                elsif OP = DIVS and OP2(31) = '1' then -- 32 bit signed negative dividend.
                    DIVIDEND := x"00000000" & unsigned(not(OP2) + '1');
                else -- 32 bit positive or unsigned dividend.
                    DIVIDEND := x"00000000" & unsigned(OP2);
                end if;

                if OP = DIVS and OP_SIZE = LONG and OP1(31) = '1' then -- 32 bit signed negative divisor.
                    DIVISOR := unsigned(not OP1 + '1');
                elsif OP_SIZE = LONG then -- 32 bit positive or unsigned divisor.
                    DIVISOR := unsigned(OP1);
                elsif OP = DIVS and OP_SIZE = WORD and OP1(15) = '1' then -- 16 bit signed negative divisor.
                    DIVISOR := x"0000" & unsigned(not OP1(15 downto 0) + '1');
                else -- 16 bit positive or unsigned divisor.
                    DIVISOR := x"0000" & unsigned(OP1(15 downto 0));
                end if;

                VFLAG_DIV <= '0';
                QUOTIENT <= (others => '0');
                QUOTIENT_VAR := (others => '0');
                QUOTIENT_REST := unsigned(OP2);

                REMAINDER <= (others => '0');
                REMAINDER_VAR := (others => '0');

                case OP_SIZE is
                    when LONG => REMAINDER_REST := unsigned(OP3);
                    when others => REMAINDER_REST := unsigned(x"0000" & OP2(31 downto 16));
                end case;

                if OP_SIZE = LONG and BIW_1(10) = '1' then
                    BITCNT := 64;
                else
                    BITCNT := 32;
                end if;

                if DIVISOR = x"00000000" then -- Division by zero.
                    QUOTIENT <= (others => '1');
                    REMAINDER <= (others => '1');
                    DIV_STATE <= IDLE;
                    DIV_RDY <= '1';
                elsif x"00000000" & DIVISOR > DIVIDEND then -- Divisor > dividend.
                    REMAINDER <= DIVIDEND(31 downto 0);
                    DIV_STATE <= IDLE;
                    DIV_RDY <= '1';
                elsif x"00000000" & DIVISOR = DIVIDEND then -- Result is 1.
                    QUOTIENT <= x"00000001";
                    DIV_STATE <= IDLE;
                    DIV_RDY <= '1';
                else
                    DIV_STATE <= CALC;
                end if;
            when CALC =>
                BITCNT := BITCNT - 1;
                --
                if REMAINDER_VAR & DIVIDEND(BITCNT) < DIVISOR then
                    REMAINDER_VAR := REMAINDER_VAR(30 downto 0) & DIVIDEND(BITCNT);
                elsif OP_SIZE = LONG and BITCNT > 31 then -- Division overflow in 64 bit mode.
                    VFLAG_DIV <= '1';
                    DIV_STATE <= IDLE;
                    DIV_RDY <= '1';
                    QUOTIENT <= QUOTIENT_REST;
                    REMAINDER <= REMAINDER_REST;
                elsif OP_SIZE = WORD and BITCNT > 15 then -- Division overflow in 64 bit mode.
                    VFLAG_DIV <= '1';
                    DIV_STATE <= IDLE;
                    DIV_RDY <= '1';
                    QUOTIENT <= QUOTIENT_REST;
                    REMAINDER <= REMAINDER_REST;
                else
                    REMAINDER_VAR := (REMAINDER_VAR(30 downto 0) & DIVIDEND(BITCNT)) - DIVISOR;
                    QUOTIENT_VAR(BITCNT) := '1';
                end if;
                --
                if BITCNT = 0 then
                    -- Adjust signs:
                    if OP = DIVS and OP_SIZE = LONG and BIW_1(10) = '1' and (OP3(31) xor OP1(31)) = '1' then
                        QUOTIENT <= not QUOTIENT_VAR + 1; -- Negative, change sign.
                    elsif OP = DIVS and OP_SIZE = LONG and BIW_1(10) = '0' and (OP2(31) xor OP1(31)) = '1' then
                        QUOTIENT <= not QUOTIENT_VAR + 1; -- Negative, change sign.
                    elsif OP = DIVS and OP_SIZE = WORD and (OP2(31) xor OP1(15)) = '1' then
                        QUOTIENT <= not QUOTIENT_VAR + 1; -- Negative, change sign.
                    else
                        QUOTIENT <= QUOTIENT_VAR;
                    end if;
                    --
                    -- F27/H33: M68000PM, DIVS description: "The sign of the
                    -- remainder is the same as the sign of the dividend."
                    -- The block above sign-adjusts the QUOTIENT for all three
                    -- DIVS forms and then dropped REMAINDER_VAR through
                    -- UNSIGNED, so every signed divide with a negative dividend
                    -- returned a positive remainder. Measured: -123456/100 gave
                    -- r = +56 where -56 is required, and the two long forms
                    -- failed identically. The dividend-sign selection here
                    -- mirrors the quotient block exactly: OP3(31) for the 64-bit
                    -- Dr:Dq form, OP2(31) otherwise. OP1 is the divisor and must
                    -- NOT take part -- the remainder follows the dividend alone,
                    -- unlike the quotient which follows both.
                    -- Negating a zero remainder yields zero, so the "unless the
                    -- remainder is zero" caveat needs no special case.
                    if OP = DIVS and OP_SIZE = LONG and BIW_1(10) = '1' and OP3(31) = '1' then
                        REMAINDER <= not REMAINDER_VAR + 1;
                    elsif OP = DIVS and OP_SIZE = LONG and BIW_1(10) = '0' and OP2(31) = '1' then
                        REMAINDER <= not REMAINDER_VAR + 1;
                    elsif OP = DIVS and OP_SIZE = WORD and OP2(31) = '1' then
                        REMAINDER <= not REMAINDER_VAR + 1;
                    else
                        REMAINDER <= REMAINDER_VAR;
                    end if;
                    DIV_RDY <= '1';
                    DIV_STATE <= IDLE;
                end if;
            end case;
    end process DIVISION;

    P_INTOP: process(OP, OP1, OP1_SIGNEXT, OP2, OP2_SIGNEXT, ADR_MODE, STATUS_REG, RESULT_INTOP)
    -- The integer arithmetics ADD, SUB, NEG and CMP in their different variations are modelled here.
    variable X_IN_I         : Std_Logic_Vector(0 downto 0);
    variable RESULT         : unsigned(31 downto 0);
    begin
        X_IN_I(0) := STATUS_REG(4); -- Extended Flag.
        case OP is
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
                RESULT := unsigned(OP2_SIGNEXT) + unsigned(OP1_SIGNEXT);
            when ADDX =>
                RESULT := unsigned(OP2_SIGNEXT) + unsigned(OP1_SIGNEXT) + unsigned(X_IN_I);
            when CMPA | DBcc | SUBA => -- No sign extension for the destination.
                RESULT := unsigned(OP2) - unsigned(OP1_SIGNEXT);
            when CAS | CAS2 | CMP | CMPI | CMPM | SUB | SUBI =>
                RESULT := unsigned(OP2_SIGNEXT) - unsigned(OP1_SIGNEXT);
            when SUBX =>
                RESULT := unsigned(OP2_SIGNEXT) - unsigned(OP1_SIGNEXT) - unsigned(X_IN_I);
            when NEG =>
                RESULT := unsigned(OP1_SIGNEXT) - unsigned(OP2_SIGNEXT);
            when NEGX =>
                RESULT := unsigned(OP1_SIGNEXT) - unsigned(OP2_SIGNEXT) - unsigned(X_IN_I);
            when CLR =>
                RESULT := (others => '0');
            when others =>
                RESULT := (others => '0'); -- Don't care.
        end case;
        RESULT_INTOP <= Std_Logic_Vector(RESULT);
    end process P_INTOP;

    P_LOGOP: process(OP, OP1, OP2)
    -- This process provides the logic operations:
    -- AND, OR, XOR and NOT.
    -- The logic operations require no signed / unsigned
    -- modelling.
    begin
        case OP is
            when AND_B | ANDI | ANDI_TO_CCR | ANDI_TO_SR =>
                RESULT_LOGOP <= OP1 and OP2;
            when OR_B | ORI | ORI_TO_CCR | ORI_TO_SR =>
                RESULT_LOGOP <= OP1 or OP2;
            when EOR | EORI | EORI_TO_CCR | EORI_TO_SR =>
                RESULT_LOGOP <= OP1 xor OP2;
            when others => -- NOT_B.
                RESULT_LOGOP <= not OP2;
        end case;
    end process P_LOGOP;

    RESULT_MUL <= Std_Logic_Vector(signed(OP1_SIGNEXT) * signed(OP2_SIGNEXT)) when OP = MULS else
                  Std_Logic_Vector(unsigned(OP1) * unsigned(OP2)) when OP_SIZE = LONG else
                  Std_Logic_Vector(unsigned(x"0000" & OP1(15 downto 0)) * unsigned(x"0000" & OP2(15 downto 0)));

    P_OTHERS: process(ALU_COND_I, BIW_0, OP, OP1, OP2, OP3, OP1_SIGNEXT, OP2_SIGNEXT, OP_SIZE, HILOn)
    -- This process provides the calculation for special operations.
    variable RESULT : unsigned(31 downto 0);
    begin
        RESULT := (others => '0');
        case OP is
            when CAS =>
                RESULT := unsigned(OP2); -- Destination operand.
            when CAS2 => -- Destination operands.
                case HILOn is
                    when '1' => RESULT := unsigned(OP3);
                    when others => RESULT := unsigned(OP2);
                end case;
            when EXT =>
                case BIW_0(8 downto 6) is
                    when "011" =>
                        for i in 31 downto 16 loop
                            RESULT(i) := OP2(15);
                        end loop;
                        RESULT(15 downto 0) := unsigned(OP2(15 downto 0));
                    when others => -- Word.
                        for i in 15 downto 8 loop
                            RESULT(i) := OP2(7);
                        end loop;
                        RESULT(31 downto 16) := unsigned(OP2(31 downto 16));
                        RESULT(7 downto 0) := unsigned(OP2(7 downto 0));
                end case;
            when EXTB =>
                for i in 31 downto 8 loop
                    RESULT(i) := OP2(7);
                end loop;
                RESULT(7 downto 0) := unsigned(OP2(7 downto 0));
            when JSR =>
                RESULT := unsigned(OP1) + "10"; -- Add offset of two to the Pointer of the last extension word.
            when MOVEQ =>
                for i in 31 downto 8 loop
                    RESULT(i) := OP1(7);
                end loop;
                RESULT(7 downto 0) := unsigned(OP1(7 downto 0));
            when Scc =>
                if ALU_COND_I = true then
                    RESULT := (others => '1');
                else
                    RESULT := (others => '0');
                end if;
            when SWAP =>
                RESULT := unsigned(OP2(15 downto 0)) & unsigned(OP2(31 downto 16));
            when TAS =>
                RESULT := x"000000" & '1' & unsigned(OP2(6 downto 0)); -- Set the MSB.
            when PACK =>
                RESULT := x"0000" & (unsigned(OP1(15 downto 0)) + unsigned(OP2(15 downto 0)));
            when UNPK =>
                RESULT := x"0000" & (unsigned(OP1(15 downto 0)) + unsigned(x"0" & OP2(7 downto 4) & x"0" & OP2(3 downto 0)));
            when LINK | TST =>
                RESULT := unsigned(OP2);
            when MOVEA | MOVEM | MOVES =>
                RESULT := unsigned(OP1_SIGNEXT);
            when others => -- MOVE_FROM_CCR, MOVE_TO_CCR, MOVE_FROM_SR, MOVE_TO_SR, MOVE, MOVEC, MOVEP, STOP.
                RESULT := unsigned(OP1);
        end case;
        RESULT_OTHERS <= Std_Logic_Vector(RESULT);
    end process P_OTHERS;
    RESULT_MV <= RESULT_OTHERS; -- [F3]

    SHFT_LOAD <= '1' when ALU_INIT = '1' and (OP_IN = ASL or OP_IN = ASR) else
                 '1' when ALU_INIT = '1' and (OP_IN = LSL or OP_IN = LSR) else
                 '1' when ALU_INIT = '1' and (OP_IN = ROTL or OP_IN = ROTR) else
                 '1' when ALU_INIT = '1' and (OP_IN = ROXL or OP_IN = ROXR) else '0';

    SHIFT_WIDTH_IN <= "000001" when BIW_0_IN(7 downto 6) = "11" else -- Memory shifts.
                      "001000" when BIW_0_IN(5) = '0' and BIW_0_IN(11 downto 9) = "000" else -- Direct.
                      "000" & BIW_0_IN(11 downto 9) when BIW_0_IN(5) = '0' else -- Direct.
                      OP1_IN(5 downto 0);

    P_SHFT_CTRL: process
    -- The variable shift or rotate length requires a control
    -- to achieve the correct OPERAND manipulation.
    variable BIT_CNT    : std_logic_vector(5 downto 0);
    begin
        wait until CLK = '1' and CLK' event;

        SHFT_RDY <= '0';
        
        if SHIFT_STATE = IDLE then
            if SHFT_LOAD = '1' and SHIFT_WIDTH_IN = "000000" then
                SHFT_RDY <= '1';
            elsif SHFT_LOAD = '1' then
                SHIFT_STATE <= RUN;
                if FAST_SHIFT then BIT_CNT := "000001"; else BIT_CNT := SHIFT_WIDTH_IN; end if; -- [SH1]
                SHFT_EN <= '1';
            else
                SHIFT_STATE <= IDLE;
                BIT_CNT := (others => '0');
                SHFT_EN <= '0';
            end if;
        elsif SHIFT_STATE = RUN then
            if BIT_CNT = "000001" then
                SHIFT_STATE <= IDLE;
                SHFT_EN <= '0';
                SHFT_RDY <= '1';
            else
                SHIFT_STATE <= RUN;
                BIT_CNT := BIT_CNT - '1';
                SHFT_EN <= '1';
            end if;
        end if;
    end process P_SHFT_CTRL;

    -- [SH1] Barrel shifter: the whole count in one clock, from registered operand (RESULT_SHIFTOP after
    -- SHFT_LOAD), count (SHIFT_WIDTH, 1..63) and X (XFLAG_SHFT = X at load). Same result and C/V/X as
    -- the bit-serial loop: LSx/ASL C = last bit out (0 beyond the size), ASR fills with the sign,
    -- ASL V = any MSB change, ROx modulo size, ROXx modulo size+1 through X.
    P_FAST_SHIFT: process(RESULT_SHIFTOP, SHIFT_WIDTH, OP, OP_SIZE, XFLAG_SHFT)
        variable SZ, N, M  : natural;
        variable D, SM, R, X1, HM : unsigned(31 downto 0);
        variable E, F       : unsigned(32 downto 0);
        variable ES, FSG    : signed(32 downto 0);
        variable W          : unsigned(64 downto 0);
        variable L, LR, LM  : unsigned(32 downto 0);
        variable C, V, X    : std_logic;
    begin
        case OP_SIZE is
            when LONG => SZ := 32; SM := x"FFFFFFFF";
            when WORD => SZ := 16; SM := x"0000FFFF";
            when others => SZ := 8; SM := x"000000FF";
        end case;
        N := To_Integer(unsigned(SHIFT_WIDTH));
        D := unsigned(RESULT_SHIFTOP) and SM;
        R := D; C := '0'; V := '0'; X := XFLAG_SHFT;
        case OP is
            when ASL | LSL =>
                W := shift_left(resize(D, 65), N);
                R := W(31 downto 0) and SM;
                C := W(SZ);
                X1 := (D xor shift_left(D, 1)) and SM;
                HM := SM and not shift_right(SM, N);
                if OP = ASL and (X1 and HM) /= 0 then V := '1'; end if;
                X := C;
            when LSR =>
                E := D & '0';
                F := shift_right(E, N);
                R := F(32 downto 1); C := F(0); X := C;
            when ASR =>
                case OP_SIZE is
                    when LONG => ES := signed(D) & '0';
                    when WORD => ES := resize(signed(D(15 downto 0)), 32) & '0';
                    when others => ES := resize(signed(D(7 downto 0)), 32) & '0';
                end case;
                FSG := shift_right(ES, N);
                R := unsigned(FSG(32 downto 1)) and SM; C := FSG(0); X := C;
            when ROTL =>
                M := N mod SZ;
                R := (shift_left(D, M) or shift_right(D, SZ - M)) and SM;
                C := R(0);
            when ROTR =>
                M := N mod SZ;
                R := (shift_right(D, M) or shift_left(D, SZ - M)) and SM;
                C := R(SZ - 1);
            when ROXL | ROXR =>
                L := resize(D, 33); L(SZ) := XFLAG_SHFT;
                LM := resize(SM, 33); LM(SZ) := '1';
                M := N mod (SZ + 1);
                if OP = ROXL then
                    LR := (shift_left(L, M) or shift_right(L, SZ + 1 - M)) and LM;
                else
                    LR := (shift_right(L, M) or shift_left(L, SZ + 1 - M)) and LM;
                end if;
                R := LR(31 downto 0) and SM; C := LR(SZ); X := C;
            when others => null;
        end case;
        FS_R <= std_logic_vector(R); FS_C <= C; FS_V <= V; FS_X <= X;
    end process P_FAST_SHIFT;

    SHIFTER: process
    begin
        wait until CLK = '1' and CLK' event;
        if SHFT_LOAD = '1' then -- Load data in the shifter unit.
            RESULT_SHIFTOP <= OP2_IN; -- Load data for the shift or rotate operations.
        elsif SHFT_EN = '1' and FAST_SHIFT then
            RESULT_SHIFTOP <= FS_R; -- [SH1]
        elsif SHFT_EN = '1' then -- Shift and rotate operations:
            case OP is
                when ASL =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(30 downto 0) & '0';
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(14 downto 0) & '0';
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(6 downto 0) & '0';
                    end if;
                when ASR =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(31) & RESULT_SHIFTOP(31 downto 1);
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(15) & RESULT_SHIFTOP(15 downto 1);
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(7) & RESULT_SHIFTOP(7 downto 1);
                    end if;
                when LSL =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(30 downto 0) & '0';
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(14 downto 0) & '0';
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(6 downto 0) & '0';
                    end if;
                when LSR =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= '0' & RESULT_SHIFTOP(31 downto 1);
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & '0' & RESULT_SHIFTOP(15 downto 1);
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & '0' & RESULT_SHIFTOP(7 downto 1);
                    end if;
                when ROTL =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(30 downto 0) & RESULT_SHIFTOP(31);
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(14 downto 0) & RESULT_SHIFTOP(15);
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(6 downto 0) & RESULT_SHIFTOP(7);
                    end if;
                    -- X not affected;
                when ROTR =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(0) & RESULT_SHIFTOP(31 downto 1);
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(0) & RESULT_SHIFTOP(15 downto 1);
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(0) & RESULT_SHIFTOP(7 downto 1);
                    end if;
                    -- X not affected;
                when ROXL =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= RESULT_SHIFTOP(30 downto 0) & XFLAG_SHFT;
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & RESULT_SHIFTOP(14 downto 0) & XFLAG_SHFT;
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & RESULT_SHIFTOP(6 downto 0) & XFLAG_SHFT;
                    end if;
                when ROXR =>
                    if OP_SIZE = LONG then
                        RESULT_SHIFTOP <= XFLAG_SHFT & RESULT_SHIFTOP(31 downto 1);
                    elsif OP_SIZE = WORD then
                        RESULT_SHIFTOP <= x"0000" & XFLAG_SHFT & RESULT_SHIFTOP(15 downto 1);
                    else -- OP_SIZE = BYTE.
                        RESULT_SHIFTOP <= x"000000" & XFLAG_SHFT & RESULT_SHIFTOP(7 downto 1);
                    end if;
                when others => null; -- Unaffected, forbidden.
            end case;
        end if;
    end process SHIFTER;

    P_OUT: process
    begin
        wait until CLK = '1' and CLK' event;
        if ALU_REQ = '1' then
            case OP is
                when ABCD | NBCD | SBCD => 
                    RESULT <= x"00000000000000" & RESULT_BCDOP; -- Byte only.
                when BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST => 
                    case HILOn is
                        when '1' => RESULT <= x"00000000" & BF_RESULT; -- F23/H29-C.
                        when others => RESULT <= x"00000000000000" & RESULT_BITFIELD(7 downto 0);
                    end case;
                when BCHG | BCLR | BSET | BTST =>
                    RESULT <= x"00000000" & RESULT_BITOP;
                when ADD | ADDA | ADDI | ADDQ | ADDX | CLR | CMP | CMPA | CMPI =>
                    RESULT <= x"00000000" & RESULT_INTOP;
                when CMPM | DBcc | NEG | NEGX | SUB | SUBA | SUBI | SUBQ | SUBX =>
                    RESULT <= x"00000000" & RESULT_INTOP;
                when AND_B | ANDI | EOR | EORI | NOT_B | OR_B | ORI =>
                    RESULT <= x"00000000" & RESULT_LOGOP;
                when ANDI_TO_SR | EORI_TO_SR | ORI_TO_SR => -- Used for branch prediction.
                    RESULT <= x"00000000" & RESULT_LOGOP;
                when ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                    RESULT <= x"00000000" & RESULT_SHIFTOP;
                when DIVS | DIVU =>
                    case OP_SIZE is
                        when LONG => RESULT <= Std_Logic_Vector(REMAINDER) & Std_Logic_Vector(QUOTIENT);
                        when others => RESULT <= x"00000000" & Std_Logic_Vector(REMAINDER(15 downto 0)) & Std_Logic_Vector(QUOTIENT(15 downto 0));
                    end case;
                when MULS | MULU =>
                    RESULT <= RESULT_MUL;
                when PACK =>
                    RESULT <= x"00000000000000" & RESULT_OTHERS(11 downto 8) & RESULT_OTHERS (3 downto 0);
                when others =>
                    RESULT <= OP2 & RESULT_OTHERS; -- OP2 is used for EXG.
            end case;
        end if;
    end process P_OUT;

    -- Out of bounds condition:
    -- F29/H35 + H37: CHK2/CMP2 operand selection, M68000PM CHK2:
    --   "If Rn is a data register and the operation size is byte or word,
    --    only the appropriate low-order part of Rn is checked. If Rn is an
    --    address register and the operation size is byte or word, the bounds
    --    operands are sign-extended to 32 bits and the resultant operands are
    --    compared to the FULL 32 bits of An."
    -- So: the BOUNDS are always sign-extended (OP1/OP3_SIGNEXT). The OPERAND
    -- is the sign-extended low-order part for a data register, and the WHOLE
    -- 32 bits for an address register -- never truncated.
    --
    -- H35: the old data-register arms compared UNSIGNED, so signedness was
    -- being chosen by REGISTER TYPE. The manual makes it a property of the
    -- bounds the programmer supplies, not of the register file.
    -- ADJUDICATED ON REAL MC68030 SILICON 2026-08-24 (A1200 + ACA1233n,
    -- MC68030RC50C mask 1F91C): byte bounds $F0..$10 against 0 returned
    -- $0010 -- IN bounds, i.e. SIGNED -- through BOTH a data register and an
    -- address register, in both cache configurations. WinUAE agrees. Only
    -- this core answered $0011 through a data register.
    --
    -- H37: the old address-register arms used OP2_SIGNEXT, which truncates
    -- the operand to the operation size and sign-extends it back. That is
    -- exactly what the manual says NOT to do for An. Measured: a1 =
    -- $0001FFF8 with word bounds $FFF0..$0010 read IN bounds, because the
    -- low word $FFF8 sign-extends to -8. The true value is 131064.
    -- H37 was found only because H35's fix forced the operand question to be
    -- asked; V26i passed all along purely because $FFFFFFF8 happens to BE
    -- its own sign-extension.
    CHK2_RN <= OP2 when CHK2CMP2_DR = '0' else OP2_SIGNEXT;

    CHK_CMP_COND <= true when OP = CHK and OP2_SIGNEXT(MSB) = '1' else -- Negative destination.
                    true when OP = CHK and signed(OP2_SIGNEXT) > signed(OP1_SIGNEXT) else
                    true when (OP = CHK2 or OP = CMP2) and signed(CHK2_RN) < signed(OP1_SIGNEXT) else
                    true when (OP = CHK2 or OP = CMP2) and signed(CHK2_RN) > signed(OP3_SIGNEXT) else false;

    -- All traps must be modeled as strobes.
    TRAP_CHK <= '1' when ALU_ACK = '1' and (OP = CHK or OP = CHK2) and CHK_CMP_COND = true else '0';
    TRAP_DIVZERO <= '1' when ALU_INIT = '1' and (OP_IN = DIVS or OP_IN = DIVU) and OP1_IN = x"00000000" else '0';
    
    COND_CODES: process(BF_DATA_IN, BF_LOWER_BND, BF_UPPER_BND, BIW_1, BITPOS, CB_BCD, CHK_CMP_COND, CLK, OP1, OP1_SIGNEXT, OP2, OP2_SIGNEXT,
                        OP3, OP3_SIGNEXT, MSB, OP, OP_SIZE, QUOTIENT, RESULT_BCDOP, RESULT_INTOP, RESULT_LOGOP, RESULT_MUL, RESULT_SHIFTOP, 
                        RESULT_OTHERS, SHIFT_WIDTH, STATUS_REG, USE_DREG, VFLAG_DIV, XFLAG_SHFT, CHK2_RN) -- CHK2_RN: Gowin EX4749
    -- In this process all the condition codes X (eXtended), N (Negative)
    -- Z (Zero), V (oVerflow) and C (Carry / borrow) are calculated for
    -- all integer operations. Except for the MULS, MULU, DIVS, DIVU the
    -- new conditions are valid one clock cycle after the operation starts.
    -- For the multiplication and the division, the codes are valid after
    -- BUSY is released.
    variable TMP            : std_logic;
    variable Z, RM, SM, DM  : std_logic;
    variable CFLAG_SHFT     : std_logic;
    variable VFLAG_SHFT     : std_logic;
    variable NFLAG_DIV      : std_logic;
    variable NFLAG_MUL      : std_logic;
    variable VFLAG_MUL      : std_logic;
    variable RM_SM_DM       : bit_vector(2 downto 0);
    begin
        -- Shifter C, X and V flags:
        if CLK = '1' and CLK' event then
            if SHFT_LOAD = '1' or SHIFT_WIDTH = "000000" then
                XFLAG_SHFT <= STATUS_REG(4);
            elsif SHFT_EN = '1' and FAST_SHIFT then
                XFLAG_SHFT <= FS_X; -- [SH1]
            elsif SHFT_EN = '1' then
                case OP is
                    when ROTL | ROTR => 
                        XFLAG_SHFT <= STATUS_REG(4); -- Unaffected.
                    when ASL | LSL | ROXL =>
                        case OP_SIZE is
                            when LONG =>
                                XFLAG_SHFT <= RESULT_SHIFTOP(31);
                            when WORD =>
                                XFLAG_SHFT <= RESULT_SHIFTOP(15);
                            when BYTE =>
                                XFLAG_SHFT <= RESULT_SHIFTOP(7);
                        end case;
                    when others => -- ASR, LSR, ROXR.
                        XFLAG_SHFT <= RESULT_SHIFTOP(0);
                end case;
            end if;
            --
            if (OP = ROXL or OP = ROXR) and SHIFT_WIDTH = "000000" then
                CFLAG_SHFT := STATUS_REG(4);
            elsif SHIFT_WIDTH = "000000" then
                CFLAG_SHFT := '0';
            elsif SHFT_EN = '1' and FAST_SHIFT then
                CFLAG_SHFT := FS_C; -- [SH1]
            elsif SHFT_EN = '1' then
                case OP is
                    when ASL | LSL | ROTL | ROXL =>
                        case OP_SIZE is
                            when LONG =>
                                CFLAG_SHFT := RESULT_SHIFTOP(31);
                            when WORD =>
                                CFLAG_SHFT := RESULT_SHIFTOP(15);
                            when BYTE =>
                                CFLAG_SHFT := RESULT_SHIFTOP(7);
                        end case;
                    when others => -- ASR, LSR, ROTR, ROXR
                        CFLAG_SHFT := RESULT_SHIFTOP(0);
                end case;
            end if;
            --
            -- This logic provides a detection of any toggling of the most significant
            -- bit of the shifter unit during the ASL shift process. For all other shift
            -- operations, the V flag is always zero.
            if SHFT_LOAD = '1' or SHIFT_WIDTH = "000000" then
                VFLAG_SHFT := '0';
            elsif SHFT_EN = '1' and FAST_SHIFT then
                VFLAG_SHFT := FS_V; -- [SH1]
            elsif SHFT_EN = '1' then
                case OP is
                    when ASL => -- ASR MSB is always unchanged.
                        if OP_SIZE = LONG then
                            VFLAG_SHFT := (RESULT_SHIFTOP(31) xor RESULT_SHIFTOP(30)) or VFLAG_SHFT;
                        elsif OP_SIZE = WORD then
                            VFLAG_SHFT := (RESULT_SHIFTOP(15) xor RESULT_SHIFTOP(14)) or VFLAG_SHFT;
                        else -- OP_SIZE = BYTE.
                            VFLAG_SHFT := (RESULT_SHIFTOP(7) xor RESULT_SHIFTOP(6)) or VFLAG_SHFT;
                        end if;
                when others =>
                    VFLAG_SHFT := '0';
                end case;
            end if;
        end if;

        -- DIVISION:
        if OP_SIZE = LONG and QUOTIENT(31) = '1' then
            NFLAG_DIV := '1';
        elsif OP_SIZE = WORD and QUOTIENT(15) = '1' then
            NFLAG_DIV := '1';
        else
            NFLAG_DIV := '0';
        end if;

        -- Integer operations:
        case OP is
            -- [C1] CAS and CAS2 were missing here: their N, V and C came from don't-care sign bits
            -- (metavalue in simulation, whatever synthesis picked in hardware). MC68030UM CAS:
            -- Destination - Dc sets N, Z, V, C like CMP.
            -- [C2] CMPA.W compares all 32 bits of An with the sign-extended source (MC68030UM CMPA):
            -- the flags must come from bit 31, not bit 15 (EmuTOS TT-RAM probe: cmpa.w #0,a2 with
            -- a2 = $010FFFFF was "less than" and no TT-RAM was found).
            when CMPA =>
                RM := RESULT_INTOP(31);
                SM := OP1_SIGNEXT(31);
                DM := OP2(31);
            when ADD | ADDI | ADDQ | ADDX | CAS | CAS2 | CMP | CMPI | CMPM | NEG | NEGX | SUB | SUBI | SUBQ | SUBX  =>
                RM := RESULT_INTOP(MSB);
                SM := OP1_SIGNEXT(MSB);
                DM := OP2_SIGNEXT(MSB);
            when others =>
                RM := '-'; SM := '-'; DM := '-';
        end case;

        RM_SM_DM := To_Bit(RM) & To_Bit(SM) & To_Bit(DM);

        -- Multiplication:
        if OP_SIZE = LONG and BIW_1(10) = '1' and RESULT_MUL(63) = '1' then -- 64 bit result.
            NFLAG_MUL := '1';
        elsif RESULT_MUL(31) = '1' then -- 32 bit result.
            NFLAG_MUL := '1';
        else
            NFLAG_MUL := '0';
        end if;

        if OP_SIZE = LONG and BIW_1(10) = '0' and OP = MULS and RESULT_MUL(31) = '0' and  RESULT_MUL(63 downto 32) /= x"00000000" then
            VFLAG_MUL := '1';
        elsif OP_SIZE = LONG and BIW_1(10) = '0' and OP = MULS and RESULT_MUL(31) = '1' and RESULT_MUL(63 downto 32) /= x"FFFFFFFF" then
            VFLAG_MUL := '1';
        elsif OP_SIZE = LONG and BIW_1(10) = '0' and OP = MULU and RESULT_MUL(63 downto 32) /= x"00000000" then
            VFLAG_MUL := '1';
        else
            VFLAG_MUL := '0';
        end if;
            
        -- The Z Flag:
        TMP := '0';
        case OP is
            when CMPA => -- [C2] all 32 bits
                for i in RESULT_INTOP'range loop
                    if i <= 31 then
                        TMP:= TMP or RESULT_INTOP(i);
                    end if;
                end loop;
                Z := not TMP;
            when ADD | ADDI | ADDQ | ADDX | CAS | CAS2 | CMP | CMPI | CMPM | NEG | NEGX | SUB | SUBI | SUBQ | SUBX  =>
                for i in RESULT_INTOP'range loop
                    if i <= MSB then
                        TMP:= TMP or RESULT_INTOP(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP; -- Invert for Z fLAG .
            when AND_B | ANDI | EOR | EORI | OR_B | ORI | NOT_B =>
                for i in RESULT_LOGOP'range loop
                    if i <= MSB then
                        TMP:= TMP or RESULT_LOGOP(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP; -- Invert for Z fLAG .
            when ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                for i in RESULT_SHIFTOP'range loop
                    if i <= MSB then
                        TMP:= TMP or RESULT_SHIFTOP(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP; -- Invert for Z fLAG .
            when BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST =>
                for i in BF_DATA_IN'range loop
                    if i >= BF_LOWER_BND and i <= BF_UPPER_BND then
                        TMP := TMP or BF_DATA_IN(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP;
            when CHK2 | CMP2 =>
                -- F29/H35+H37: Z is "Rn equal to either bound", on the SAME
                -- operand the bounds check uses. The old address-register arms
                -- compared OP2_SIGNEXT, truncating An to the operation size --
                -- the H37 bug again, where an An whose low word matched a bound
                -- would read equal however wrong the upper half was.
                if CHK2_RN = OP1_SIGNEXT or CHK2_RN = OP3_SIGNEXT then
                    Z := '1';
                else
                    Z := '0';
                end if;
            when BCHG | BCLR | BSET | BTST =>
                Z := not OP2(BITPOS);
            when DIVS | DIVU =>
                if QUOTIENT = x"00000000" then
                    Z := '1';
                else
                    Z := '0';
                end if;
            when EXT | EXTB | MOVE | SWAP | TST =>
                for i in RESULT_OTHERS'range loop
                    if i <= MSB then
                        TMP:= TMP or RESULT_OTHERS(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP; -- Invert for Z fLAG .
            when MULS | MULU =>
                if OP_SIZE = LONG and BIW_1(10) = '1' and RESULT_MUL = x"0000000000000000" then -- 64 bit result.
                    Z := '1';
                elsif RESULT_MUL(31 downto 0) = x"00000000" then -- 32 bit result.
                    Z := '1';
                else
                    Z := '0';
                end if;
            when TAS =>
                for i in OP2_SIGNEXT'range loop
                    if i <= MSB then
                        TMP := TMP or OP2_SIGNEXT(i); -- Detect '1'.
                    end if;
                end loop;
                Z := not TMP; -- Invert for Z fLAG .
            when others =>
                Z := '0';
        end case;

        case OP is
            when ABCD | NBCD | SBCD =>
                if RESULT_BCDOP = x"00" then -- N and V are undefined, don't care.
                    XNZVC <= CB_BCD & '-' & STATUS_REG(2) & '-' & CB_BCD;
                else
                    XNZVC <= CB_BCD & '-' & '0' & '-' & CB_BCD;
                end if;
            when ADD | ADDI | ADDQ | ADDX =>
                if (SM = '1' and DM = '1') or (RM = '0' and SM = '1') or (RM = '0' and DM = '1') then
                    XNZVC(4) <= '1';
                    XNZVC(0) <= '1';
                else
                    XNZVC(4) <= '0';
                    XNZVC(0) <= '0';
                end if;
                --
                if Z = '1' then
                    if OP = ADDX then
                        XNZVC(3 downto 2) <= '0' & STATUS_REG(2);
                    else
                        XNZVC(3 downto 2) <= "01";
                    end if;
                else
                    XNZVC(3 downto 2) <= RM & '0';
                end if;
                --
                case RM_SM_DM is
                    when "011" => XNZVC(1) <= '1';
                    when "100" => XNZVC(1) <= '1';
                    when others => XNZVC(1) <= '0';
                end case;
            when AND_B | ANDI | EOR | EORI | OR_B | ORI | NOT_B =>
                XNZVC <= STATUS_REG(4) & RESULT_LOGOP(MSB) & Z & "00";
            when ANDI_TO_CCR | EORI_TO_CCR | ORI_TO_CCR =>
                XNZVC <= RESULT_LOGOP(4 downto 0);
            when ASL | ASR | LSL | LSR | ROTL | ROTR | ROXL | ROXR =>
                XNZVC <= XFLAG_SHFT & RESULT_SHIFTOP(MSB) & Z & VFLAG_SHFT & CFLAG_SHFT;
            when BCHG | BCLR | BSET | BTST =>
                XNZVC <= STATUS_REG(4 downto 3) & Z & STATUS_REG(1 downto 0);
            when BFCHG | BFCLR | BFEXTS | BFEXTU | BFFFO | BFINS | BFSET | BFTST =>
                XNZVC <= STATUS_REG(4) & BF_DATA_IN(BF_UPPER_BND) & Z & "00";
            when CLR =>
                XNZVC <= STATUS_REG(4) & "0100";
            when SUB | SUBI | SUBQ | SUBX =>
                if (SM = '1' and DM = '0') or (RM = '1' and SM = '1') or (RM = '1' and DM = '0') then
                    XNZVC(4) <= '1';
                    XNZVC(0) <= '1';
                else
                    XNZVC(4) <= '0';
                    XNZVC(0) <= '0';
                end if;                     
                --
                if Z = '1' then
                    if OP = SUBX then
                        XNZVC(3 downto 2) <= '0' & STATUS_REG(2);
                    else
                        XNZVC(3 downto 2) <= "01";
                    end if;
                else
                    XNZVC(3 downto 2) <= RM & '0';
                end if;
                --
                case RM_SM_DM is
                    when "001" => XNZVC(1) <= '1';
                    when "110" => XNZVC(1) <= '1';
                    when others => XNZVC(1) <= '0';
                end case;
            when CAS | CAS2 | CMP | CMPA | CMPI | CMPM =>
                XNZVC(4) <= STATUS_REG(4);
                --
                if Z = '1' then
                    XNZVC(3 downto 2) <= "01";
                else
                    XNZVC(3 downto 2) <= RM & '0';
                end if;
                --
                case RM_SM_DM is
                    when "001" => XNZVC(1) <= '1';
                    when "110" => XNZVC(1) <= '1';
                    when others => XNZVC(1) <= '0';
                end case;
                --
                if (SM = '1' and DM = '0') or (RM = '1' and SM = '1') or (RM = '1' and DM = '0') then
                    XNZVC(0) <= '1';
                else
                    XNZVC(0) <= '0';
                end if;                     
            when CHK =>
                if OP2_SIGNEXT(MSB) = '1' then
                    XNZVC <= STATUS_REG(4) & '1' & "000";
                elsif CHK_CMP_COND = true then
                    XNZVC <= STATUS_REG(4) & '0' & "000";
                else
                    XNZVC <= STATUS_REG(4 downto 3) & "000";
                end if;
            when CHK2 | CMP2 =>
                if CHK_CMP_COND = true then
                    XNZVC <= STATUS_REG(4) & '0' & '0' & '0' & '1';
                else
                    XNZVC <= STATUS_REG(4) & '0' & Z & '0' & '0';
                end if;
            when DIVS | DIVU =>
                XNZVC <= STATUS_REG(4) & NFLAG_DIV & Z & VFLAG_DIV & '0';
            when EXT | EXTB | MOVE | TST =>
                XNZVC <= STATUS_REG(4) & RESULT_OTHERS(MSB) & Z & "00";
            when MOVEQ =>
                if OP1_SIGNEXT(7 downto 0) = x"00" then
                    XNZVC <= STATUS_REG(4) & "0100";
                else
                    XNZVC <= STATUS_REG(4) & OP1_SIGNEXT(7) & "000";
                end if;
            when MULS | MULU =>
                XNZVC <= STATUS_REG(4) & NFLAG_MUL & Z & VFLAG_MUL & '0';
            when NEG | NEGX =>
                XNZVC(4) <= DM or RM;
                --
                if Z = '1' then
                    if OP = NEGX then
                        XNZVC(3 downto 2) <= '0' & STATUS_REG(2);
                    else
                        XNZVC(3 downto 2) <= "01";
                    end if;
                else
                    XNZVC(3 downto 2) <= RM & '0';
                end if;
                --
                XNZVC(1) <= DM and RM;
                XNZVC(0) <= DM or RM;
            when RTR =>
                XNZVC <= OP2(4 downto 0);
            when SWAP =>
                XNZVC <= STATUS_REG(4) & RESULT_OTHERS(MSB) & Z & "00";
            when others => -- TAS, Byte only.
                XNZVC <= STATUS_REG(4) & OP2_SIGNEXT(MSB) & Z & "00";
        end case;
    end process COND_CODES;

    CAS_CONDITIONS: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            if LOAD_OP2 = '1' and XNZVC(2) = '1' then
                CAS2_COND <= true;
            elsif LOAD_OP2 = '1' then
                CAS2_COND <= false;
            end if;
        end if;
    end process CAS_CONDITIONS;

    ALU_COND <= ALU_COND_I; -- This signal may not be registerd to meet a correct timing.
    -- Status register conditions: (STATUS_REG(4) = X, STATUS_REG(3) = N, STATUS_REG(2) = Z, STATUS_REG(1) = V, STATUS_REG(0) = C.)
    ALU_COND_I <= false when OP = CAS2 and CAS2_COND = false else
                  true when (OP = CAS or OP = CAS2) and OP_SIZE = LONG and RESULT_INTOP = x"00000000" else
                  true when (OP = CAS or OP = CAS2) and OP_SIZE = WORD and RESULT_INTOP (15 downto 0) = x"0000" else
                  true when OP = CAS and OP_SIZE = BYTE and RESULT_INTOP (7 downto 0) = x"00" else -- [RMC2] was unsized: a word/long CAS whose low byte matched counted as equal and wrote Du
                  false when OP = CAS or OP = CAS2 else
                  true when OP = TRAPV and STATUS_REG(1) = '1' else
                  false when OP = TRAPV else
                  true when BIW_0(11 downto 8) = x"0" else -- True.
                  true when BIW_0(11 downto 8) = x"2" and (STATUS_REG(2) nor STATUS_REG(0)) = '1' else -- High.
                  true when BIW_0(11 downto 8) = x"3" and (STATUS_REG(2) or STATUS_REG(0)) = '1' else -- Low or same.
                  true when BIW_0(11 downto 8) = x"4" and STATUS_REG(0) = '0' else -- Carry clear.
                  true when BIW_0(11 downto 8) = x"5" and STATUS_REG(0) = '1' else -- Carry set.
                  true when BIW_0(11 downto 8) = x"6" and STATUS_REG(2) = '0' else -- Not Equal.
                  true when BIW_0(11 downto 8) = x"7" and STATUS_REG(2) = '1' else -- Equal.
                  true when BIW_0(11 downto 8) = x"8" and STATUS_REG(1) = '0' else -- Overflow clear.
                  true when BIW_0(11 downto 8) = x"9" and STATUS_REG(1) = '1' else -- Overflow set.
                  true when BIW_0(11 downto 8) = x"A" and STATUS_REG(3) = '0' else -- Plus.
                  true when BIW_0(11 downto 8) = x"B" and STATUS_REG(3) = '1' else -- Minus.
                  true when BIW_0(11 downto 8) = x"C" and (STATUS_REG(3) xnor STATUS_REG(1)) = '1' else -- Greater or Equal.
                  true when BIW_0(11 downto 8) = x"D" and (STATUS_REG(3) xor STATUS_REG(1)) = '1' else -- Less than.
                  true when BIW_0(11 downto 8) = x"E" and STATUS_REG(3 downto 1) = "101" else -- Greater than.
                  true when BIW_0(11 downto 8) = x"E" and STATUS_REG(3 downto 1) = "000" else -- Greater than.
                  true when BIW_0(11 downto 8) = x"F" and STATUS_REG(2) = '1' else -- Less or equal.
                  true when BIW_0(11 downto 8) = x"F" and (STATUS_REG(3) xor STATUS_REG(1)) = '1' else false; -- Less or equal.

    P_STATUS_REG: process
    -- This process is the status register with it's related logic.
    -- The status register is written 16 bit wide for MOVE_TO_CCR (the ALU result is 16 bit wide).
    -- The status register is written entirely for ANDI_TO_SR, EORI_TO_SR, ORI_TO_SR.
    -- The status register lower byte is written for ANDI_TO_CCR, EORI_TO_CCR, ORI_TO_CCR.
    variable SREG_MEM : std_logic_vector(15 downto 0) := x"0000";
    begin
        wait until CLK = '1' and CLK' event;
        --
        -- [F46] SILICON-PROVEN FIX.  STATUS_REG is the one piece of
        -- architectural state hardware reset never touched.  This
        -- process only wrote it via CC_UPDT, SR_WR (instructions) and
        -- SR_INIT.  SR_INIT was F45's attempt -- but SR_INIT only
        -- asserts during the exception INIT state, which is TOO LATE:
        -- ALU_COND_I is combinational and evaluates
        --     true when OP = TRAPV and STATUS_REG(1) = '1'
        -- on the FIRST post-reset SLEEP->START_OP, reading the POWER-UP
        -- garbage in SREG_MEM before any exception (hence before SR_INIT)
        -- has run.  With V (bit 1) powering up '1' and OP aliasing TRAPV
        -- (F42), a spurious TRAPV fired on instruction #1 at the reset PC
        -- -- the vector-7/format-2 frame seen all session, opcode-
        -- independent (fired identically on a NOP), and cleared only
        -- after a full SR write.
        --
        -- PROOF: an auto-restart probe that did `move.w #$2700,%sr` in
        -- software after the fault and jumped back to the reset PC
        -- BOOTED on the second pass -- same code, same address, clean SR.
        -- So forcing the whole SR to its reset value BEFORE the first
        -- instruction is the fix.  That is what RESET must do here, and
        -- what neither an initial value (Gowin ignores it) nor SR_INIT
        -- (too late) achieved.
        --
        -- Reset value $2700: T1 T0 = 00 (trace off), S = 1 (supervisor),
        -- M = 0, mask = 111 (7), and X N Z V C = 0 -- so STATUS_REG(1)=0
        -- and the spurious-TRAPV condition cannot hold out of reset.
        if RESET = '1' then
            SREG_MEM := x"2700";
        elsif CC_UPDT = '1' then
            SREG_MEM(4 downto 0) := XNZVC;
        end if;
        --
        if SR_INIT = '1' then
            -- [F45] The reset exception must bring the ENTIRE status
            -- register to a defined state (MC68030UM 8.1.1, steps 1-3:
            -- clear trace, set S, clear M, set mask to 7).  The original
            -- wrote only bits 15:13 and 10:8, leaving bits 12 (M), 7:5
            -- and the CONDITION CODES 4:0 at their power-up value.
            --
            -- This process has NO reset branch and SREG_MEM is only given
            -- an INITIAL value (x"0000"), which GHDL honours but Gowin
            -- does not guarantee.  So on silicon the V bit (bit 1) could
            -- power up '1' and survive reset -- and ALU_COND_I for TRAPV
            -- is "true when OP = TRAPV and STATUS_REG(1) = '1'".  With OP
            -- also aliasing TRAPV on the first post-reset SLEEP->START_OP
            -- (the F42 condition), that fired a SPURIOUS TRAPV at the
            -- reset PC -- exactly the observed vector-7/format-2 frame at
            -- $400, with the handler's reported SR = $2700 (upper bits
            -- correct, but the trap already taken because the LOWER bits
            -- were never cleared).  F42 initialised OP but not this half.
            --
            -- Writing the whole register on SR_INIT makes silicon match
            -- the manual and the simulation: trace=0, S=1, M=0, mask=7,
            -- X/N/Z/V/C all cleared.
            SREG_MEM := "001" & '0' & '0' & IRQ_PEND & "000" & "00000";
            -- bits: 15:12=0010 (T1 T0 S M = 0 0 1 0)
            --       11    =0
            --       10:8  =IRQ_PEND (mask = 7 during reset init)
            --       7:5   =000
            --       4:0   =00000 (X N Z V C cleared)
        end if;
        --
        if SR_CLR_MBIT = '1' then 
            SREG_MEM(12) := '0';
        elsif SR_WR = '1' and OP_IN = RTE then -- Written by the exception handler, no ALU required.
            SREG_MEM := OP1_IN(15 downto 0);
        elsif SR_WR = '1' and (OP_WB = MOVE_TO_CCR or OP_WB = MOVE_TO_SR or OP_WB = STOP) then
            SREG_MEM := RESULT_OTHERS(15 downto 0);
        elsif SR_WR = '1' and (OP_WB = ANDI_TO_CCR or OP_WB = EORI_TO_CCR or OP_WB = ORI_TO_CCR) then
            SREG_MEM(7 downto 5) := RESULT_LOGOP(7 downto 5); -- Bits 4 downto 0 are written via CC_UPDT.
        elsif SR_WR = '1' then -- ANDI_TO_SR, EORI_TO_SR, ORI_TO_SR.
            SREG_MEM := RESULT_LOGOP(15 downto 0);
        end if;
        --
        STATUS_REG <= SREG_MEM; -- Fully populated status register.
        --STATUS_REG <= SREG_MEM(15 downto 12) & '0' & SREG_MEM(10 downto 8) & "000" & SREG_MEM(4 downto 0); -- Partially populated.
    end process P_STATUS_REG;
    --
    STATUS_REG_OUT <= STATUS_REG;
end BEHAVIOUR;