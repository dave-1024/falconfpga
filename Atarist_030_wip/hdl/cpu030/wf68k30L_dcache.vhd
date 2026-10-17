--------------------------------------------
-- WF68K30L_DCACHE: FalconFPGA addition to the WF68K30L core (Wolfgang Foerster).
-- Copyright (c) 2026 David Dunne (dave-1024), first added 2026-10-04, rewritten 2026-10-17.
-- Licensed under the CERN OHL v1.2, like the WF68K30L core
-- (license/cern_ohl_v_1_2.txt, http://ohwr.org/cernohl). This source is distributed
-- WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING OF MERCHANTABILITY,
-- SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
-- Please see the CERN OHL v1.2 for applicable conditions.
--------------------------------------------
-- [DC] 68030 on-chip data cache, MC68030UM 6.1.2, 6.1.3.1, 6.3.1 (docs/DCACHE_DESIGN.md).
-- 256 bytes: 16 lines x 4 long words, direct-mapped, write-through. Index A7:4, long
-- select A3:2. Tag per line: A31:8 and FC2:0. One valid bit per long word. CPU space
-- (FC = 7) is never looked up, filled or updated.
-- An operand touches one or two entries: E0 = A31:2 and, when it crosses a long word
-- boundary, E1 = E0 + 1. The data is two banks by A2 (E0 and E1 are always in different
-- banks) of four byte lanes, the tags two banks by A4 (E0 and E1 are in the same line or
-- in adjacent lines), so both entries are read and written in one clock.
-- LK_*: lookup of a read request (the bus interface's START_CYCLE): LK_HIT when the cache
--   is enabled (ED, CDIS negated) and every touched entry is valid with a matching tag;
--   LK_DATA is the operand right-justified, as the bus delivers it.
-- WR_*: a write (bus interface, the clock after its first bus cycle started). A hit updates
--   the bytes even when frozen; with WA set and FD clear a miss allocates an aligned long
--   word (tag replaced, the other three long words of the line invalid) and clears the
--   valid bit of every other entry it touches (6.1.2.1). CIIN is not looked at.
-- FL_*: end of a read (operand plus fill cycles): per entry the two words read with CIIN
--   negated and no bus error (FL_OK) and whether a bus error hit it (FL_BE). A complete long
--   updates a matching entry or, when not frozen, replaces it; read words also update a
--   matching valid entry; a bus error clears the entry's valid bit (6.1.3.1).
-- CLR_ALL (CACR CD) clears every valid bit, CLR_ENT (CACR CED) the long word at CLR_IDX
-- (CAAR 7:2), whatever ED and FD are. Reset clears every valid bit (6.2). ED = 0 or CDIS
-- keeps the contents. No snooping.
--------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity WF68K30L_DCACHE is
    port (
        CLK       : in std_logic;
        RESET     : in bit;
        ED        : in std_logic;
        FD        : in std_logic;
        WA        : in std_logic;
        CDIS      : in std_logic; -- '1': disabled (registered CDIS pin).
        CLR_ALL   : in std_logic;
        CLR_ENT   : in std_logic;
        CLR_IDX   : in std_logic_vector(7 downto 2);
        LK_ADR    : in std_logic_vector(31 downto 0);
        LK_FC     : in std_logic_vector(2 downto 0);
        LK_SZ     : in std_logic_vector(2 downto 0); -- Bytes: 1, 2 or 4.
        LK_HIT    : out std_logic;
        LK_DATA   : out std_logic_vector(31 downto 0);
        WR_GO     : in std_logic;
        WR_ADR    : in std_logic_vector(31 downto 0);
        WR_FC     : in std_logic_vector(2 downto 0);
        WR_SZ     : in std_logic_vector(2 downto 0);
        WR_DATA   : in std_logic_vector(31 downto 0); -- Right-justified.
        FL_GO     : in std_logic;
        FL_A0     : in std_logic_vector(31 downto 2);
        FL_FC     : in std_logic_vector(2 downto 0);
        FL_U1     : in std_logic; -- E1 touched.
        FL_D0     : in std_logic_vector(31 downto 0);
        FL_D1     : in std_logic_vector(31 downto 0);
        FL_OK0    : in std_logic_vector(1 downto 0); -- Bit 1: word at offset 0 (D 31:16), bit 0: offset 2.
        FL_OK1    : in std_logic_vector(1 downto 0);
        FL_BE0    : in std_logic;
        FL_BE1    : in std_logic
    );
end entity WF68K30L_DCACHE;

architecture RTL of WF68K30L_DCACHE is
    type lane_t is array (0 to 31) of std_logic_vector(7 downto 0);
    type tagb_t is array (0 to 7) of std_logic_vector(26 downto 0);
    signal D00, D01, D02, D03 : lane_t := (others => (others => '0')); -- Bank 0 (A2 = 0), lanes 0-3 (lane 0 = D31:24).
    signal D10, D11, D12, D13 : lane_t := (others => (others => '0')); -- Bank 1 (A2 = 1).
    signal TAG0, TAG1 : tagb_t := (others => (others => '0')); -- Lines with A4 = 0 / 1.
    signal VALID : std_logic_vector(63 downto 0) := (others => '0'); -- Bit line*4 + long word.
    signal EN : std_logic;
    -- Lookup.
    signal LA0, LA1 : unsigned(29 downto 0);
    signal LX : std_logic;
    signal LB0, LB1 : std_logic_vector(31 downto 0); -- Bank 0 / 1 read.
    signal LT0, LT1 : std_logic_vector(26 downto 0); -- Tag bank 0 / 1 read.
    signal LH0, LH1 : std_logic;
    signal LW : std_logic_vector(63 downto 0);
    -- Operation (write or fill end).
    signal OA0, OA1 : unsigned(29 downto 0);
    signal OFC : std_logic_vector(2 downto 0);
    signal OT0, OT1 : std_logic_vector(26 downto 0);
    signal OM0, OM1 : std_logic; -- Tag of E0 / E1 matches.
    signal OV0, OV1 : std_logic; -- Valid bit of E0 / E1.
    signal BE0, BE1 : std_logic_vector(3 downto 0); -- Byte enables (lane 0 = lowest address).
    signal WD0, WD1 : std_logic_vector(31 downto 0);
    signal TW0, TW1 : std_logic; -- Replace the tag of E0's / E1's line.
    signal SV0, SV1, CV0, CV1 : std_logic; -- Set / clear the valid bit.
    signal WWIN : std_logic_vector(63 downto 0); -- Write data placed at its byte offset.
    signal WBEW : std_logic_vector(7 downto 0);
    signal BI0, BI1 : unsigned(4 downto 0); -- Data bank write index.
    signal BB0, BB1 : std_logic_vector(3 downto 0); -- Data bank byte enables.
    signal BD0, BD1 : std_logic_vector(31 downto 0); -- Data bank write data.
    signal TI0, TI1 : unsigned(2 downto 0); -- Tag bank write index.
    signal TV0, TV1 : std_logic_vector(26 downto 0);
    signal TE0, TE1 : std_logic;
    attribute syn_keep : integer;
    attribute syn_preserve : integer;
    attribute syn_keep of D00, D01, D02, D03, D10, D11, D12, D13 : signal is 1;
    attribute syn_keep of TAG0, TAG1 : signal is 1;
    attribute syn_keep of VALID : signal is 1;
    attribute syn_preserve of VALID : signal is 1;

    function rd(b0 : lane_t; b1 : lane_t; b2 : lane_t; b3 : lane_t; i : integer) return std_logic_vector is
    begin
        return b0(i) & b1(i) & b2(i) & b3(i);
    end function;
    function tag(a : unsigned(29 downto 0); fc : std_logic_vector(2 downto 0)) return std_logic_vector is
    begin
        return std_logic_vector(a(29 downto 6)) & fc;
    end function;
begin
    EN <= ED and not CDIS;

    -- Lookup ----------------------------------------------------------------------------------------
    LA0 <= unsigned(LK_ADR(31 downto 2));
    LA1 <= unsigned(LK_ADR(31 downto 2)) + 1;
    LX  <= '1' when (LK_SZ = "100" and LK_ADR(1 downto 0) /= "00") or (LK_SZ = "010" and LK_ADR(1 downto 0) = "11") else '0';
    -- Data bank b holds the entry of E0/E1 whose A2 = b. Same line when E0 is in bank 0.
    LB0 <= rd(D00, D01, D02, D03, to_integer(LA0(5 downto 1))) when LA0(0) = '0' else
           rd(D00, D01, D02, D03, to_integer(LA1(5 downto 1)));
    LB1 <= rd(D10, D11, D12, D13, to_integer(LA0(5 downto 1)));
    -- Tag bank b holds the line of E0/E1 whose A4 = b.
    LT0 <= TAG0(to_integer(LA0(5 downto 3))) when LA0(2) = '0' else TAG0(to_integer(LA1(5 downto 3)));
    LT1 <= TAG1(to_integer(LA0(5 downto 3))) when LA0(2) = '1' else TAG1(to_integer(LA1(5 downto 3)));
    LH0 <= '1' when VALID(to_integer(LA0(5 downto 0))) = '1' and
                    ((LA0(2) = '0' and LT0 = tag(LA0, LK_FC)) or (LA0(2) = '1' and LT1 = tag(LA0, LK_FC))) else '0';
    LH1 <= '1' when VALID(to_integer(LA1(5 downto 0))) = '1' and
                    ((LA1(2) = '0' and LT0 = tag(LA1, LK_FC)) or (LA1(2) = '1' and LT1 = tag(LA1, LK_FC))) else '0';
    LK_HIT <= '1' when EN = '1' and LK_FC /= "111" and LH0 = '1' and (LX = '0' or LH1 = '1') else '0';
    LW <= LB0 & LB1 when LA0(0) = '0' else LB1 & LB0; -- E0 & E1.
    P_LKD: process(LW, LK_ADR, LK_SZ)
        variable O : integer range 0 to 3;
        variable W : std_logic_vector(63 downto 0);
    begin
        O := to_integer(unsigned(LK_ADR(1 downto 0)));
        W := std_logic_vector(shift_left(unsigned(LW), 8 * O)); -- First operand byte in 63:56.
        case LK_SZ is
            when "100" => LK_DATA <= W(63 downto 32);
            when "010" => LK_DATA <= x"0000" & W(63 downto 48);
            when others => LK_DATA <= x"000000" & W(63 downto 56);
        end case;
    end process P_LKD;

    -- Operation -------------------------------------------------------------------------------------
    OA0 <= unsigned(FL_A0) when FL_GO = '1' else unsigned(WR_ADR(31 downto 2));
    OA1 <= OA0 + 1;
    OFC <= FL_FC when FL_GO = '1' else WR_FC;
    OT0 <= TAG0(to_integer(OA0(5 downto 3))) when OA0(2) = '0' else TAG1(to_integer(OA0(5 downto 3)));
    OT1 <= TAG0(to_integer(OA1(5 downto 3))) when OA1(2) = '0' else TAG1(to_integer(OA1(5 downto 3)));
    OM0 <= '1' when OT0 = tag(OA0, OFC) else '0';
    OM1 <= '1' when OT1 = tag(OA1, OFC) else '0';
    OV0 <= VALID(to_integer(OA0(5 downto 0)));
    OV1 <= VALID(to_integer(OA1(5 downto 0)));

    P_WWIN: process(WR_ADR, WR_SZ, WR_DATA)
        variable O : integer range 0 to 3;
        variable B : std_logic_vector(7 downto 0);
        variable W : std_logic_vector(63 downto 0);
    begin
        O := to_integer(unsigned(WR_ADR(1 downto 0)));
        case WR_SZ is
            when "100" => W := WR_DATA & x"00000000"; B := "11110000";
            when "010" => W := WR_DATA(15 downto 0) & x"000000000000"; B := "11000000";
            when others => W := WR_DATA(7 downto 0) & x"00000000000000"; B := "10000000";
        end case;
        WWIN <= std_logic_vector(shift_right(unsigned(W), 8 * O));
        WBEW <= std_logic_vector(shift_right(unsigned(B), O));
    end process P_WWIN;

    P_OP: process(FL_GO, WR_GO, EN, OFC, FD, WA, OM0, OM1, OV0, OV1, WWIN, WBEW, WR_SZ, WR_ADR,
                  FL_U1, FL_D0, FL_D1, FL_OK0, FL_OK1, FL_BE0, FL_BE1)
        variable E : boolean;
        procedure fill(D : std_logic_vector(31 downto 0); OK : std_logic_vector(1 downto 0); BEF : std_logic;
                       M, V : std_logic; signal BEo : out std_logic_vector(3 downto 0);
                       signal TWo, SVo, CVo : out std_logic) is
        begin
            BEo <= "0000"; TWo <= '0'; SVo <= '0'; CVo <= '0';
            if OK = "11" and M = '1' and V = '1' then
                BEo <= "1111"; -- Update the matching entry.
            elsif OK = "11" and FD = '0' then
                BEo <= "1111"; TWo <= not M; SVo <= '1'; -- Replace (a new tag clears the line).
            elsif BEF = '1' then
                CVo <= '1'; -- Bus error on the entry: marked invalid.
            elsif M = '1' and V = '1' then
                BEo <= OK(1) & OK(1) & OK(0) & OK(0); -- Words read update the matching entry.
            end if;
        end procedure;
    begin
        E := EN = '1' and OFC /= "111";
        BE0 <= "0000"; BE1 <= "0000"; TW0 <= '0'; TW1 <= '0';
        SV0 <= '0'; SV1 <= '0'; CV0 <= '0'; CV1 <= '0';
        WD0 <= WWIN(63 downto 32); WD1 <= WWIN(31 downto 0);
        if FL_GO = '1' then
            WD0 <= FL_D0; WD1 <= FL_D1;
            if E then
                fill(FL_D0, FL_OK0, FL_BE0, OM0, OV0, BE0, TW0, SV0, CV0);
                if FL_U1 = '1' then
                    fill(FL_D1, FL_OK1, FL_BE1, OM1, OV1, BE1, TW1, SV1, CV1);
                end if;
            end if;
        elsif WR_GO = '1' and E then
            -- E0
            if OM0 = '1' and OV0 = '1' then
                BE0 <= WBEW(7 downto 4); -- Hit: update, even when frozen.
            elsif WA = '1' and FD = '0' then
                if WR_SZ = "100" and WR_ADR(1 downto 0) = "00" then
                    BE0 <= "1111"; TW0 <= not OM0; SV0 <= '1'; -- Aligned long: allocate.
                else
                    CV0 <= '1'; -- Byte, word or misaligned long miss: invalidate.
                end if;
            end if;
            -- E1 (bytes beyond the long word boundary)
            if WBEW(3 downto 0) /= "0000" then
                if OM1 = '1' and OV1 = '1' then
                    BE1 <= WBEW(3 downto 0);
                elsif WA = '1' and FD = '0' then
                    CV1 <= '1';
                end if;
            end if;
        end if;
    end process P_OP;

    -- Per-bank write port: E0 and E1 are always in different data banks (A2 differs), so each bank takes at most
    -- one entry per operation. Muxing the entry onto the bank's single address/data/byte-enable port lets each
    -- 32 x 8 lane array map to distributed RAM (RAM16SDP4) instead of flip-flops; same clock, same contents.
    BI0 <= OA0(5 downto 1) when OA0(0) = '0' else OA1(5 downto 1);
    BI1 <= OA1(5 downto 1) when OA0(0) = '0' else OA0(5 downto 1);
    BB0 <= BE0 when OA0(0) = '0' else BE1;
    BB1 <= BE1 when OA0(0) = '0' else BE0;
    BD0 <= WD0 when OA0(0) = '0' else WD1;
    BD1 <= WD1 when OA0(0) = '0' else WD0;
    -- Per-bank tag port: E0 and E1 are in the same line (same tag, same address) or in adjacent lines (different
    -- tag banks), so each tag bank also takes at most one distinct write.
    TI0 <= OA0(5 downto 3) when OA0(2) = '0' and TW0 = '1' else OA1(5 downto 3);
    TI1 <= OA0(5 downto 3) when OA0(2) = '1' and TW0 = '1' else OA1(5 downto 3);
    TV0 <= tag(OA0, OFC) when OA0(2) = '0' and TW0 = '1' else tag(OA1, OFC);
    TV1 <= tag(OA0, OFC) when OA0(2) = '1' and TW0 = '1' else tag(OA1, OFC);
    TE0 <= '1' when (TW0 = '1' and OA0(2) = '0') or (TW1 = '1' and OA1(2) = '0') else '0';
    TE1 <= '1' when (TW0 = '1' and OA0(2) = '1') or (TW1 = '1' and OA1(2) = '1') else '0';

    -- Storage without reset (distributed RAM, asynchronous read), one write port per array.
    P_RAM: process(CLK)
    begin
        if CLK = '1' and CLK'event then
            if BB0(3) = '1' then D00(to_integer(BI0)) <= BD0(31 downto 24); end if;
            if BB0(2) = '1' then D01(to_integer(BI0)) <= BD0(23 downto 16); end if;
            if BB0(1) = '1' then D02(to_integer(BI0)) <= BD0(15 downto 8); end if;
            if BB0(0) = '1' then D03(to_integer(BI0)) <= BD0(7 downto 0); end if;
            if BB1(3) = '1' then D10(to_integer(BI1)) <= BD1(31 downto 24); end if;
            if BB1(2) = '1' then D11(to_integer(BI1)) <= BD1(23 downto 16); end if;
            if BB1(1) = '1' then D12(to_integer(BI1)) <= BD1(15 downto 8); end if;
            if BB1(0) = '1' then D13(to_integer(BI1)) <= BD1(7 downto 0); end if;
            if TE0 = '1' then TAG0(to_integer(TI0)) <= TV0; end if;
            if TE1 = '1' then TAG1(to_integer(TI1)) <= TV1; end if;
        end if;
    end process P_RAM;

    P_VALID: process(CLK)
        variable V : std_logic_vector(63 downto 0);
        variable L0, L1, I0, I1 : integer range 0 to 63;
    begin
        if CLK = '1' and CLK'event then
            if RESET = '1' or CLR_ALL = '1' then
                VALID <= (others => '0');
            else
                V := VALID;
                L0 := to_integer(OA0(5 downto 2)) * 4; L1 := to_integer(OA1(5 downto 2)) * 4;
                I0 := to_integer(OA0(5 downto 0)); I1 := to_integer(OA1(5 downto 0));
                if TW0 = '1' then V(L0 + 3 downto L0) := "0000"; end if; -- New tag: the line's other long words.
                if TW1 = '1' then V(L1 + 3 downto L1) := "0000"; end if;
                if SV0 = '1' then V(I0) := '1'; end if;
                if CV0 = '1' then V(I0) := '0'; end if;
                if SV1 = '1' then V(I1) := '1'; end if;
                if CV1 = '1' then V(I1) := '0'; end if;
                if CLR_ENT = '1' then
                    V(to_integer(unsigned(CLR_IDX))) := '0';
                end if;
                VALID <= V;
            end if;
        end if;
    end process P_VALID;
end architecture RTL;
