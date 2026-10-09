--------------------------------------------
-- 68030 instruction cache, MC68030UM 6.1.1.
-- 16 lines of four long words. Each word has its own valid bit: the bus
-- interface delivers one instruction word per OPCODE_RDY, so a miss fills
-- that word only. A tag change clears the other words of the line.
-- Tag is A31:8 and FC2. CPU space is never stored.
-- CACR bit 0 enables, bit 1 freezes allocation, bit 3 clears. Bit 3 is a
-- write strobe and is not stored in CACR. A data write drops the line only
-- when its A31:8 matches the stored tag.
-- A miss passes BUS_RDY straight through. The core drops REQ when the bus
-- cycle starts, so gating the miss strobe on REQ blocks every fetch.
-- A hit strobe is registered, so ready does not feed back into the request.
-- FalconFPGA. The core is WF68K30L; this is the cache it did not have.
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
        CI        : in std_logic;
        REQ       : in bit;
        ADR       : in std_logic_vector(31 downto 0);
        FC        : in std_logic_vector(2 downto 0);
        WR        : in bit;
        WR_ADR    : in std_logic_vector(31 downto 0);
        BUS_RDY   : in bit;
        BUS_WORD  : in std_logic_vector(15 downto 0);
        BUS_REQ   : out bit;
        RDY       : out bit;
        WORD      : out std_logic_vector(15 downto 0)
    );
end entity WF68K30L_ICACHE;

architecture RTL of WF68K30L_ICACHE is
    type word_t is array (0 to 7) of std_logic_vector(15 downto 0);
    type line_t is array (0 to 15) of word_t;
    type tag_t is array (0 to 15) of std_logic_vector(24 downto 0);
    type val_t is array (0 to 15) of std_logic_vector(7 downto 0);
    signal lines : line_t := (others => (others => (others => '0')));
    signal tags  : tag_t := (others => (others => '0'));
    signal valid : val_t := (others => (others => '0'));
    signal served : bit := '0';
    signal hit_c  : std_logic := '0';
    signal hit_rdy : bit := '0';
begin
    hit_c <= '1' when EI = '1' and FC /= "111"
              and valid(to_integer(unsigned(ADR(7 downto 4))))(to_integer(unsigned(ADR(3 downto 1)))) = '1'
              and tags(to_integer(unsigned(ADR(7 downto 4)))) = ADR(31 downto 8) & FC(2)
             else '0';
    BUS_REQ <= '0' when hit_c = '1' or served = '1' else REQ;
    -- Miss: the bus strobe, even after REQ has fallen. Hit: the registered strobe.
    RDY <= hit_rdy when hit_c = '1' else BUS_RDY;
    WORD <= lines(to_integer(unsigned(ADR(7 downto 4))))(to_integer(unsigned(ADR(3 downto 1))))
            when hit_c = '1' else BUS_WORD;

    P_ICACHE: process (CLK)
        variable idx  : integer range 0 to 15;
        variable wsel : integer range 0 to 7;
        variable widx : integer range 0 to 15;
        variable tag  : std_logic_vector(24 downto 0);
        variable v    : std_logic_vector(7 downto 0);
    begin
        if CLK = '1' and CLK'event then
            idx  := to_integer(unsigned(ADR(7 downto 4)));
            wsel := to_integer(unsigned(ADR(3 downto 1)));
            widx := to_integer(unsigned(WR_ADR(7 downto 4)));
            tag  := ADR(31 downto 8) & FC(2);
            hit_rdy <= '0';

            if RESET = '1' or CI = '1' then
                valid <= (others => (others => '0'));
                served <= '0';
            else
                if WR = '1' and tags(widx)(24 downto 1) = WR_ADR(31 downto 8) then
                    valid(widx) <= (others => '0');
                end if;

                if REQ = '0' then
                    served <= '0';
                elsif hit_c = '1' and served = '0' then
                    hit_rdy <= '1';
                    served <= '1';
                elsif hit_c = '0' and BUS_RDY = '1' and EI = '1' and FI = '0' and FC /= "111" then
                    if tags(idx) /= tag then
                        v := (others => '0');
                    else
                        v := valid(idx);
                    end if;
                    v(wsel) := '1';
                    valid(idx) <= v;
                    lines(idx)(wsel) <= BUS_WORD;
                    tags(idx) <= tag;
                end if;
            end if;
        end if;
    end process P_ICACHE;
end architecture RTL;
