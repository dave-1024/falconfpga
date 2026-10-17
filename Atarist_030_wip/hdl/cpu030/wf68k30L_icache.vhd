--------------------------------------------
-- WF68K30L_ICACHE: FalconFPGA addition to the WF68K30L core (Wolfgang Foerster).
-- Copyright (c) 2026 David Dunne (dave-1024), first added 2026-10-04, rewritten 2026-10-17.
-- Licensed under the CERN OHL v1.2, like the WF68K30L core
-- (license/cern_ohl_v_1_2.txt, http://ohwr.org/cernohl). This source is distributed
-- WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING OF MERCHANTABILITY,
-- SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
-- Please see the CERN OHL v1.2 for applicable conditions.
--------------------------------------------
-- [IC] 68030 on-chip instruction cache, MC68030UM chapter 6 (docs/ICACHE_DESIGN.md).
-- 256 bytes: 16 lines x 4 long words, direct-mapped. Index A7:4, long select A3:2.
-- Tag per line: A31:8 and FC2. One valid bit per long word.
-- The bus interface's prefetch queue looks up the long word it is about to fetch
-- (LK_ADR) and reports every bus prefetch long (FILL) with, per word, "no bus error
-- and CIIN negated" (FILL_OK). An aligned long with both words OK is stored. A stream
-- that starts at 4n+2 fetches misaligned longs (4n+2, 4n+4): the second word of one
-- fetch is kept (PH_*) and stored with the first word of the next fetch, so every
-- long word the bus read in full is cached, as on a 68030 (its first, half-read long
-- is not; docs/ICACHE_DESIGN.md Q1).
-- EI enables hits and fills, FI freezes (hits only), CDIS (pin) disables both and
-- keeps the contents. CLR_ALL (CACR CI) clears every valid bit, CLR_ENT (CACR CEI)
-- the long word at CLR_IDX (CAAR 7:2), both whatever EI and FI are. Reset clears
-- every valid bit (MC68030UM 6.2). Data writes do not touch the cache: the 68030
-- instruction cache does not snoop.
--------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity WF68K30L_ICACHE is
    port (
        CLK       : in std_logic;
        RESET     : in bit;
        EI        : in std_logic;
        FI        : in std_logic;
        CDIS      : in std_logic; -- '1': disabled (registered CDIS pin).
        CLR_ALL   : in std_logic;
        CLR_ENT   : in std_logic;
        CLR_IDX   : in std_logic_vector(7 downto 2);
        LK_ADR    : in std_logic_vector(31 downto 2);
        LK_FC2    : in std_logic;
        HIT       : out std_logic;
        HIT_DATA  : out std_logic_vector(31 downto 0);
        FILL      : in std_logic;
        FILL_MIS  : in std_logic;
        FILL_OK   : in std_logic_vector(1 downto 0);
        BREAK     : in std_logic;
        FILL_ADR  : in std_logic_vector(31 downto 2);
        FILL_FC2  : in std_logic;
        FILL_DATA : in std_logic_vector(31 downto 0)
    );
end entity WF68K30L_ICACHE;

architecture RTL of WF68K30L_ICACHE is
    type data_t is array (0 to 63) of std_logic_vector(31 downto 0);
    type tag_t is array (0 to 15) of std_logic_vector(24 downto 0);
    type val_t is array (0 to 15) of std_logic_vector(3 downto 0);
    signal DATA_RAM : data_t := (others => (others => '0'));
    signal TAG_RAM  : tag_t := (others => (others => '0'));
    signal VALID    : val_t := (others => (others => '0'));
    signal LK_LINE  : integer range 0 to 15;
    signal LK_LW    : integer range 0 to 3;
    signal FL_LINE  : integer range 0 to 15;
    signal FL_LW    : integer range 0 to 3;
    signal FL_TAG   : std_logic_vector(24 downto 0);
    signal FL_GO    : std_logic;
    signal FL_DATA  : std_logic_vector(31 downto 0);
    signal FA_GO    : std_logic; -- Aligned long, both words OK.
    signal FM_GO    : std_logic; -- Misaligned stream: kept word + first word of this fetch.
    signal PH_V     : std_logic := '0';
    signal PH_W     : std_logic_vector(15 downto 0) := (others => '0');
    signal PH_L     : std_logic_vector(31 downto 2) := (others => '0');
    signal PH_FC2   : std_logic := '0';
begin
    LK_LINE <= to_integer(unsigned(LK_ADR(7 downto 4)));
    LK_LW   <= to_integer(unsigned(LK_ADR(3 downto 2)));
    FL_LINE <= to_integer(unsigned(FILL_ADR(7 downto 4)));
    FL_LW   <= to_integer(unsigned(FILL_ADR(3 downto 2)));
    FL_TAG  <= FILL_ADR(31 downto 8) & FILL_FC2;
    FA_GO   <= '1' when FILL = '1' and FILL_MIS = '0' and FILL_OK = "11" else '0';
    FM_GO   <= '1' when FILL = '1' and FILL_MIS = '1' and FILL_OK(0) = '1' and PH_V = '1' and
                        PH_L = FILL_ADR and PH_FC2 = FILL_FC2 else '0';
    FL_GO   <= (FA_GO or FM_GO) and EI and not FI and not CDIS;
    FL_DATA <= PH_W & FILL_DATA(31 downto 16) when FILL_MIS = '1' else FILL_DATA;

    HIT <= '1' when EI = '1' and CDIS = '0' and VALID(LK_LINE)(LK_LW) = '1' and
                    TAG_RAM(LK_LINE) = LK_ADR(31 downto 8) & LK_FC2 else '0';
    HIT_DATA <= DATA_RAM(LK_LINE * 4 + LK_LW);

    -- Storage without reset (distributed RAM, asynchronous read).
    P_RAM: process(CLK)
    begin
        if CLK = '1' and CLK'event then
            if FL_GO = '1' then
                DATA_RAM(FL_LINE * 4 + FL_LW) <= FL_DATA;
                TAG_RAM(FL_LINE) <= FL_TAG;
            end if;
        end if;
    end process P_RAM;

    -- Second word of a misaligned fetch: the first half of the next long word of the stream.
    P_HALF: process(CLK)
    begin
        if CLK = '1' and CLK'event then
            if FILL = '1' and FILL_MIS = '1' then
                PH_W <= FILL_DATA(15 downto 0);
                PH_L <= std_logic_vector(unsigned(FILL_ADR) + 1);
                PH_FC2 <= FILL_FC2;
                PH_V <= FILL_OK(1);
            elsif FILL = '1' then
                PH_V <= '0';
            end if;
            if RESET = '1' or CLR_ALL = '1' or CLR_ENT = '1' or BREAK = '1' then
                PH_V <= '0';
            end if;
        end if;
    end process P_HALF;

    P_VALID: process(CLK)
        variable V : std_logic_vector(3 downto 0);
    begin
        if CLK = '1' and CLK'event then
            if RESET = '1' or CLR_ALL = '1' then
                VALID <= (others => (others => '0'));
            else
                if FL_GO = '1' then
                    if TAG_RAM(FL_LINE) = FL_TAG then
                        V := VALID(FL_LINE);
                    else
                        V := "0000"; -- New tag: the other long words of the line are not valid.
                    end if;
                    V(FL_LW) := '1';
                    VALID(FL_LINE) <= V;
                end if;
                if CLR_ENT = '1' then -- After the fill: a clear in the same clock wins.
                    VALID(to_integer(unsigned(CLR_IDX(7 downto 4))))(to_integer(unsigned(CLR_IDX(3 downto 2)))) <= '0';
                end if;
            end if;
        end if;
    end process P_VALID;
end architecture RTL;
