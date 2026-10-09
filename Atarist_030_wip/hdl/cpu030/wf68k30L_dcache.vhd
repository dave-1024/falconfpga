--------------------------------------------
-- 68030 data cache, MC68030UM 6.1.2. Write-through.
-- 16 lines of four long words. A valid bit per long word. Only an aligned
-- long-word read can hit or fill. A byte, a word, or a misaligned read is
-- the bus path and is not stored. A tag change clears the other long words.
-- Tag is A31:8 and FC2:0. CPU space is never stored.
-- CACR bit 8 enables, bit 9 freezes allocation, bit 11 clears. Bit 11 is a
-- write strobe and is not stored in CACR. A write still goes to memory and
-- drops the matching long word.
-- A miss passes BUS_RDY straight through. The core drops the request when
-- the bus cycle starts, so gating the miss strobe on the request blocks it.
-- A hit strobe is registered.
-- FalconFPGA. The core is WF68K30L; this is the data cache it did not have.
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
        CD        : in std_logic;
        REQ       : in bit;
        LONG_OK   : in std_logic;                      -- aligned long-word read
        ADR       : in std_logic_vector(31 downto 0);
        FC        : in std_logic_vector(2 downto 0);
        WR        : in bit;
        WR_ADR    : in std_logic_vector(31 downto 0);
        WR_FC     : in std_logic_vector(2 downto 0);
        BUS_RDY   : in bit;
        BUS_DATA  : in std_logic_vector(31 downto 0);
        BUS_REQ   : out bit;
        RDY       : out bit;
        DATA      : out std_logic_vector(31 downto 0)
    );
end entity WF68K30L_DCACHE;

architecture RTL of WF68K30L_DCACHE is
    type lw_t is array (0 to 3) of std_logic_vector(31 downto 0);
    type line_t is array (0 to 15) of lw_t;
    type tag_t is array (0 to 15) of std_logic_vector(26 downto 0); -- A31:8 & FC
    type val_t is array (0 to 15) of std_logic_vector(3 downto 0);
    signal lines : line_t := (others => (others => (others => '0')));
    signal tags  : tag_t := (others => (others => '0'));
    signal valid : val_t := (others => (others => '0'));
    signal served : bit := '0';
    signal hit_c  : std_logic := '0';
    signal hit_rdy : bit := '0';
begin
    hit_c <= '1' when ED = '1' and LONG_OK = '1' and FC /= "111"
              and valid(to_integer(unsigned(ADR(7 downto 4))))(to_integer(unsigned(ADR(3 downto 2)))) = '1'
              and tags(to_integer(unsigned(ADR(7 downto 4)))) = ADR(31 downto 8) & FC
             else '0';
    BUS_REQ <= '0' when hit_c = '1' or served = '1' else REQ;
    RDY <= hit_rdy when hit_c = '1' else BUS_RDY;
    DATA <= lines(to_integer(unsigned(ADR(7 downto 4))))(to_integer(unsigned(ADR(3 downto 2))))
            when hit_c = '1' else BUS_DATA;

    P_DCACHE: process (CLK)
        variable idx  : integer range 0 to 15;
        variable lsel : integer range 0 to 3;
        variable widx : integer range 0 to 15;
        variable wsel : integer range 0 to 3;
        variable tag  : std_logic_vector(26 downto 0);
        variable v    : std_logic_vector(3 downto 0);
    begin
        if CLK = '1' and CLK'event then
            idx  := to_integer(unsigned(ADR(7 downto 4)));
            lsel := to_integer(unsigned(ADR(3 downto 2)));
            widx := to_integer(unsigned(WR_ADR(7 downto 4)));
            wsel := to_integer(unsigned(WR_ADR(3 downto 2)));
            tag  := ADR(31 downto 8) & FC;
            hit_rdy <= '0';

            if RESET = '1' or CD = '1' then
                valid <= (others => (others => '0'));
                served <= '0';
            else
                if WR = '1' and tags(widx) = WR_ADR(31 downto 8) & WR_FC then
                    valid(widx)(wsel) <= '0';
                end if;

                if REQ = '0' then
                    served <= '0';
                elsif hit_c = '1' and served = '0' then
                    hit_rdy <= '1';
                    served <= '1';
                elsif hit_c = '0' and BUS_RDY = '1' and LONG_OK = '1'
                      and ED = '1' and FD = '0' and FC /= "111" then
                    if tags(idx) /= tag then
                        v := (others => '0');
                    else
                        v := valid(idx);
                    end if;
                    v(lsel) := '1';
                    valid(idx) <= v;
                    lines(idx)(lsel) <= BUS_DATA;
                    tags(idx) <= tag;
                end if;
            end if;
        end if;
    end process P_DCACHE;
end architecture RTL;
