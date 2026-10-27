------------------------------------------------------------------------
-- [PMMU2] WF68K30L MMU: address translation cache (ATC) and table walker (MC68030UM section 9).
--
-- Sits between the bus interface and the pins. With TC.E set, a cycle that is not CPU space (FC 7) and not in
-- a transparent window (TT0/TT1) is looked up in the 22-entry fully associative ATC (9.4, p9-17..9-20):
--   hit, B = 0 and no write-protect / M = 0 problem: the cycle goes out at once with the physical address;
--   hit with B = 1, or a write / RMW to a WP page: the core's cycle ends with BERR (fault address = logical);
--   miss, or a write to a page whose entry has M = 0: the core's cycle is held (it sees wait states), the
--   walker searches the tables (9.5.2, Figure 9-19) with its own bus cycles, RMC asserted for the whole
--   search (locked U/M updates, 9.5.3), stores a new entry and the held cycle then goes out (the retry).
-- Descriptors: short and long, table / page / early termination / invalid / indirect (9.5.1); root pointer
-- by SRE and FC2 (Table 9-2); FCL function code level; IS, TIA-TID; limits (long tables, L/U); WP and S
-- accumulated; U set on every table and page descriptor used, M on the page for writes.
-- Replacement: an invalid entry first, else not-recently-used (one used bit per entry; 9.4.1 calls it
-- pseudo-LRU). Flush: all entries on PMOVE (FD = 0) to CRP/SRP/TC/TT0/TT1 (9.4).
-- Table search bus cycles: FC = 5 (supervisor data), long accesses with dynamic bus sizing (16 or 32 bit).
------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;

entity WF68K30L_MMU is
    port (
        CLK         : in std_logic;
        RESET       : in std_logic;
        TC          : in std_logic_vector(31 downto 0);
        CRP         : in std_logic_vector(63 downto 0);
        SRP         : in std_logic_vector(63 downto 0);
        TT_HIT      : in std_logic; -- TT0 or TT1 match for the core's cycle (logical address).
        FLUSH_ALL   : in std_logic;
        -- Core side (from / to the bus interface).
        C_ADR       : in std_logic_vector(31 downto 0);
        C_FC        : in std_logic_vector(2 downto 0);
        C_SIZE      : in std_logic_vector(1 downto 0);
        C_ASn       : in std_logic;
        C_DSn       : in std_logic;
        C_RWn       : in std_logic;
        C_RMCn      : in std_logic;
        C_ECSn      : in std_logic;
        C_OCSn      : in std_logic;
        C_DBENn     : in std_logic;
        C_DATA_OUT  : in std_logic_vector(31 downto 0);
        C_DATA_EN   : in std_logic;
        C_BUS_EN    : in std_logic;
        C_DSACKn    : out std_logic_vector(1 downto 0);
        C_STERMn    : out std_logic;
        C_BERRn     : out std_logic;
        -- Pins.
        P_ADR       : out std_logic_vector(31 downto 0);
        P_FC        : out std_logic_vector(2 downto 0);
        P_SIZE      : out std_logic_vector(1 downto 0);
        P_ASn       : out std_logic;
        P_DSn       : out std_logic;
        P_RWn       : out std_logic;
        P_RMCn      : out std_logic;
        P_ECSn      : out std_logic;
        P_OCSn      : out std_logic;
        P_DBENn     : out std_logic;
        P_DATA_OUT  : out std_logic_vector(31 downto 0);
        P_DATA_EN   : out std_logic;
        P_BUS_EN    : out std_logic;
        P_DSACKn    : in std_logic_vector(1 downto 0);
        P_STERMn    : in std_logic;
        P_BERRn     : in std_logic;
        P_DATA_IN   : in std_logic_vector(31 downto 0);
        ATC_CI      : out std_logic; -- Page CI of the hit entry (CIOUT, cache inhibit).
        -- [PMMU2b] PFLUSHA / PFLUSH / PLOAD / PTEST from the core (9.8): strobe with the extension word, the
        -- effective address and the resolved function code; CMD_TT = TT0/TT1 match of that address (PTEST level 0).
        CMD         : in std_logic := '0';
        CMD_EXT     : in std_logic_vector(15 downto 0) := (others => '0');
        CMD_EA      : in std_logic_vector(31 downto 0) := (others => '0');
        CMD_FC      : in std_logic_vector(2 downto 0) := (others => '0');
        CMD_TT      : in std_logic := '0';
        CMD_BUSY    : out std_logic; -- A command is pending or its table search runs.
        SR_WR       : out std_logic; -- PTEST result for MMUSR (Table 9-3, p. 9-60).
        SR_OUT      : out std_logic_vector(15 downto 0);
        AN_WR       : out std_logic; -- [PMMU3] PTEST A = 1: write the last descriptor address to An (p. 9-63).
        AN_DATA     : out std_logic_vector(31 downto 0);
        WALKING     : out std_logic
    );
end entity WF68K30L_MMU;

architecture BEHAVIOUR of WF68K30L_MMU is
constant NE : integer := 22;
type T24 is array (0 to NE - 1) of std_logic_vector(23 downto 0);
type T3 is array (0 to NE - 1) of std_logic_vector(2 downto 0);
signal E_V, E_B, E_CI, E_WP, E_M, E_USED : std_logic_vector(NE - 1 downto 0) := (others => '0');
signal E_FC  : T3;
signal E_LA  : T24;
signal E_PA  : T24;

signal PMASK    : std_logic_vector(23 downto 0); -- 1 = logical address bit A(8+i) is compared / translated.
signal XLATE    : std_logic;
signal HITV     : std_logic_vector(NE - 1 downto 0);
signal HIT      : std_logic;
signal H_B, H_CI, H_WP, H_M : std_logic;
signal H_PA     : std_logic_vector(23 downto 0);
signal C_WR     : std_logic;
signal FAULT_NOW, HIT_OK : std_logic;
-- [F66] Kept nets: the bridge (cpu030_st_bridge.v) samples the pins one clk_cpu after AS while TC.E = 1,
-- and atarist_st_helper.sdc gives the paths through these nets (ATC lookup / TT match -> AS, address) two
-- clk32 cycles. With TC.E = 0 they are constant (XLATE = 0) and the pins are a wire, as before.
-- Separate kept copies for the pin side only, so the core-side paths (BLK -> C_DSACKn/C_BERRn) are optimised
-- as before and stay single-cycle.
signal BLK_PIN, XLATE_PIN : std_logic;
attribute syn_keep : integer;
attribute syn_keep of BLK_PIN, XLATE_PIN, H_PA : signal is 1;

type WSTATES is (W_IDLE, W_ROOT, W_LEVEL, W_FETCH, W_FETCH2, W_EVAL, W_UPD, W_UPDW, W_NEXT, W_DONE);
signal WS : WSTATES := W_IDLE;
-- Bus master of the walker.
type BSTATES is (B_IDLE, B_CYC, B_LAT, B_END, B_GAP);
signal BS : BSTATES := B_IDLE;
signal BM_GO, BM_WR, BM_DONE, BM_ERR : std_logic := '0';
signal BM_ADR, BM_WDATA, BM_RDATA : std_logic_vector(31 downto 0);
signal BM_HALF : std_logic := '0'; -- Second word of a long on a 16-bit port.
signal BM_A, BM_D : std_logic_vector(31 downto 0);
signal BM_SZ : std_logic_vector(1 downto 0);
signal BM_DS, BM_AS : std_logic := '0';
signal BM_CNT : std_logic_vector(1 downto 0);
signal BM_P32 : std_logic := '0'; -- The port answered 32 bits.
signal BM_P16 : std_logic := '0';

signal L_LA     : std_logic_vector(31 downto 0); -- Logical address of the search.
signal L_FC     : std_logic_vector(2 downto 0);
signal L_WR     : std_logic;
signal SH       : std_logic_vector(31 downto 0); -- Logical address bits not yet used as an index.
signal LVL      : integer range 0 to 4;          -- 0 = FC level (if FCL), 1..4 = TIA..TID.
signal TADR     : std_logic_vector(31 downto 0); -- Address of the current table.
signal TLONG    : std_logic;                     -- Current table holds 8-byte descriptors.
signal LIM_ON, LIM_LU : std_logic;
signal LIM      : std_logic_vector(14 downto 0);
signal DADR     : std_logic_vector(31 downto 0); -- Address of the current descriptor.
signal D0, D1   : std_logic_vector(31 downto 0); -- Descriptor (short: D0; long: D0 = status, D1 = address).
signal ACC_WP, ACC_S, BAD : std_logic;
signal USED_BITS: integer range 0 to 32;         -- IS + index bits used so far.
signal LAST_PAGE: std_logic;                     -- The descriptor being updated is the page descriptor.
signal IND      : std_logic;
signal RMC_W    : std_logic := '0';
signal P_PA     : std_logic_vector(23 downto 0);
signal P_CI, P_M: std_logic;
-- A cycle the pins already run keeps the translation it started with (TC, TTx or a flush may change in the
-- middle of it, e.g. the PMOVE to TC writes back while the next prefetch is on the bus).
signal CYC_ON   : std_logic := '0';
signal CYC_X    : std_logic := '0';
signal CYC_CI   : std_logic := '0';
signal CYC_PA   : std_logic_vector(23 downto 0);
signal CYC_MASK : std_logic_vector(23 downto 0);
signal XLATE_L  : std_logic; -- XLATE for a new cycle only.
signal C_PEND   : std_logic := '0';
signal C_HITV   : std_logic_vector(NE - 1 downto 0);
signal C_EXT    : std_logic_vector(15 downto 0);
signal C_EA     : std_logic_vector(31 downto 0);
signal C_CFC    : std_logic_vector(2 downto 0);
signal C_TT     : std_logic;
signal M_LOAD, M_TEST : std_logic := '0'; -- The running search is a PLOAD / a PTEST.
signal R_BERR, R_LIM : std_logic;           -- PTEST: bus error / limit violation during the search.
signal NLEV     : integer range 0 to 7;     -- Descriptors fetched (PTEST N).
signal TLEV     : integer range 0 to 7;     -- PTEST level.
-- [PMMU3] 11.7 table search timing (MC68030UM pp. 11-51..11-57): the search is held until the clocks of the
-- Motorola shell script (overhead + per descriptor + U/M writes + indirection + early termination) have passed.
-- Bus times are the measured ones of each descriptor access, so wait states stretch it as on a real 68030.
signal BM_CLKS  : integer range 0 to 63;    -- Bus cycle time of the last walker access (AS to termination, both halves).
signal BUSA     : integer range 0 to 63;    -- First long of a long descriptor.
signal W_TGT    : integer range 0 to 1023;  -- Script clocks of the running search.
signal W_NCK    : integer range 0 to 1023;  -- Clocks since the search began.
-- [PMMU3] 11.7.2 MMU instruction clocks (p. 11-60, I-cache case + (An) EA 4 where an <ea> is used): CMD_BUSY
-- is held for I_PAD clocks after the command (PFLUSH(A), PTEST #0) or after the search (PLOAD, PTEST #1-7).
-- The K constants are the clocks the core spends outside that window (decode, EA, write back), measured with
-- prog_mmut.s at 0 wait states.
signal I_PAD    : integer range 0 to 63 := 0;
constant K_FL   : integer := 4;
constant K_LD   : integer := -7; -- The search overlaps the core by 7 clocks.
constant K_T0   : integer := 4;

function TIW(T : std_logic_vector; L : integer) return integer is
begin
    case L is
        when 1 => return conv_integer(T(15 downto 12));
        when 2 => if T(15 downto 12) = x"0" then return 0; end if; return conv_integer(T(11 downto 8));
        when 3 => if T(15 downto 12) = x"0" or T(11 downto 8) = x"0" then return 0; end if; return conv_integer(T(7 downto 4));
        when 4 => if T(15 downto 12) = x"0" or T(11 downto 8) = x"0" or T(7 downto 4) = x"0" then return 0; end if; return conv_integer(T(3 downto 0));
        when others => return 0;
    end case;
end function;

begin
    -- Page size mask (PS = TC 23-20, 8 .. 15).
    P_MASK: process(TC)
    begin
        for i in 0 to 23 loop
            if i + 8 >= conv_integer(TC(23 downto 20)) then PMASK(i) <= '1'; else PMASK(i) <= '0'; end if;
        end loop;
    end process P_MASK;

    XLATE_L <= '1' when TC(31) = '1' and C_FC /= "111" and TT_HIT = '0' and C_BUS_EN = '1' else '0';
    XLATE <= XLATE_L and not CYC_ON;

    P_CYC: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            if C_ASn = '1' or RESET = '1' then
                CYC_ON <= '0'; CYC_X <= '0'; CYC_CI <= '0';
            elsif CYC_ON = '0' and WS = W_IDLE and (XLATE = '0' or HIT_OK = '1') then
                CYC_ON <= '1'; CYC_X <= XLATE; CYC_PA <= H_PA; CYC_MASK <= PMASK; CYC_CI <= XLATE and H_CI;
            end if;
        end if;
    end process P_CYC;
    C_WR <= not C_RWn;

    -- Fully associative lookup (9.4: logical address and FC; fewer bits compared for bigger pages).
    G_HIT: for i in 0 to NE - 1 generate
        HITV(i) <= '1' when E_V(i) = '1' and E_FC(i) = C_FC and ((E_LA(i) xor C_ADR(31 downto 8)) and PMASK) = x"000000" else '0';
    end generate;
    HIT <= '1' when HITV /= (HITV'range => '0') else '0';
    G_CHIT: for i in 0 to NE - 1 generate
        C_HITV(i) <= '1' when E_V(i) = '1' and E_FC(i) = C_CFC and ((E_LA(i) xor C_EA(31 downto 8)) and PMASK) = x"000000" else '0';
    end generate;
    CMD_BUSY <= '1' when CMD = '1' or C_PEND = '1' or M_LOAD = '1' or M_TEST = '1' or SR_WR = '1' or I_PAD /= 0 else '0'; -- [PMMU3] SR_WR: An write clock
    P_HITMUX: process(HITV, E_B, E_CI, E_WP, E_M, E_PA)
        variable B, CI, WP, M : std_logic;
        variable PA : std_logic_vector(23 downto 0);
    begin
        B := '0'; CI := '0'; WP := '0'; M := '0'; PA := (others => '0');
        for i in 0 to NE - 1 loop
            if HITV(i) = '1' then
                B := B or E_B(i); CI := CI or E_CI(i); WP := WP or E_WP(i); M := M or E_M(i); PA := PA or E_PA(i);
            end if;
        end loop;
        H_B <= B; H_CI <= CI; H_WP <= WP; H_M <= M; H_PA <= PA;
    end process P_HITMUX;

    FAULT_NOW <= '1' when XLATE = '1' and HIT = '1' and (H_B = '1' or (H_WP = '1' and (C_WR = '1' or C_RMCn = '0'))) else '0';
    HIT_OK <= '1' when XLATE = '1' and HIT = '1' and H_B = '0' and FAULT_NOW = '0' and not (C_WR = '1' and H_M = '0') else '0';

    -- Pin multiplexer.
    BLK_PIN <= '1' when WS /= W_IDLE or (XLATE = '1' and HIT_OK = '0') else '0'; -- [F66] pin-side copy of BLK
    XLATE_PIN <= XLATE; -- [F66]
    P_PINS: process(WS, XLATE, HIT_OK, BLK_PIN, XLATE_PIN, C_ADR, C_FC, C_SIZE, C_ASn, C_DSn, C_RWn, C_RMCn, C_ECSn, C_OCSn, C_DBENn,
                    C_DATA_OUT, C_DATA_EN, C_BUS_EN, H_PA, PMASK, BM_A, BM_D, BM_SZ, BM_AS, BM_DS, BM_WR, BS, RMC_W,
                    P_DSACKn, P_STERMn, P_BERRn, FAULT_NOW, H_CI, CYC_ON, CYC_X, CYC_PA, CYC_MASK)
        variable BLK : boolean;
    begin
        BLK := WS /= W_IDLE or (XLATE = '1' and HIT_OK = '0');
        if WS /= W_IDLE then -- The walker owns the bus.
            P_ADR <= BM_A; P_FC <= "101"; P_SIZE <= BM_SZ;
            P_ASn <= not BM_AS; P_DSn <= not BM_DS; P_RWn <= not BM_WR; P_RMCn <= not RMC_W;
            if BS = B_CYC and BM_AS = '1' and BM_CNT = "00" then P_ECSn <= '0'; P_OCSn <= '0'; else P_ECSn <= '1'; P_OCSn <= '1'; end if;
            if BM_AS = '1' then P_DBENn <= '0'; else P_DBENn <= '1'; end if;
            P_DATA_OUT <= BM_D; P_DATA_EN <= BM_WR; P_BUS_EN <= '1';
        else
            if CYC_ON = '1' and CYC_X = '1' then
                for i in 0 to 23 loop
                    if CYC_MASK(i) = '1' then P_ADR(i + 8) <= CYC_PA(i); else P_ADR(i + 8) <= C_ADR(i + 8); end if;
                end loop;
                P_ADR(7 downto 0) <= C_ADR(7 downto 0);
            elsif XLATE_PIN = '1' then
                for i in 0 to 23 loop
                    if PMASK(i) = '1' then P_ADR(i + 8) <= H_PA(i); else P_ADR(i + 8) <= C_ADR(i + 8); end if;
                end loop;
                P_ADR(7 downto 0) <= C_ADR(7 downto 0);
            else
                P_ADR <= C_ADR;
            end if;
            P_FC <= C_FC; P_SIZE <= C_SIZE; P_RWn <= C_RWn; P_RMCn <= C_RMCn;
            P_DATA_OUT <= C_DATA_OUT; P_DATA_EN <= C_DATA_EN; P_BUS_EN <= C_BUS_EN;
            if BLK_PIN = '1' then
                P_ASn <= '1'; P_DSn <= '1'; P_ECSn <= '1'; P_OCSn <= '1'; P_DBENn <= '1';
            else
                P_ASn <= C_ASn; P_DSn <= C_DSn; P_ECSn <= C_ECSn; P_OCSn <= C_OCSn; P_DBENn <= C_DBENn;
            end if;
        end if;
        if BLK then
            C_DSACKn <= "11"; C_STERMn <= '1';
            if WS = W_IDLE and FAULT_NOW = '1' and C_ASn = '0' then C_BERRn <= '0'; else C_BERRn <= '1'; end if;
        else
            C_DSACKn <= P_DSACKn; C_STERMn <= P_STERMn; C_BERRn <= P_BERRn;
        end if;
    end process P_PINS;

    ATC_CI <= CYC_CI when CYC_ON = '1' else '1' when WS = W_IDLE and HIT_OK = '1' and H_CI = '1' else '0';
    WALKING <= '1' when WS /= W_IDLE else '0';

    -- Walker bus master: one long (or a word pair on a 16-bit port), AS from a rising edge, data latched the
    -- clock after the termination, one idle clock between cycles.
    P_BM: process(CLK)
    begin
        if CLK = '1' and CLK' event then
            BM_DONE <= '0';
            if RESET = '1' then
                BS <= B_IDLE; BM_AS <= '0'; BM_DS <= '0';
            else
                case BS is
                    when B_IDLE =>
                        if BM_GO = '1' then
                            BM_A <= BM_ADR; BM_D <= BM_WDATA; BM_SZ <= "00"; BM_HALF <= '0'; BM_ERR <= '0';
                            BM_AS <= '1'; BM_DS <= not BM_WR; BM_CNT <= "00"; BS <= B_CYC; BM_CLKS <= 0;
                        end if;
                    when B_CYC => -- Wait for the termination (sampled on the rising edge).
                        if BM_CLKS < 63 then BM_CLKS <= BM_CLKS + 1; end if;
                        if BM_CNT /= "11" then BM_CNT <= BM_CNT + '1'; end if;
                        BM_DS <= '1';
                        if P_BERRn = '0' then
                            BM_ERR <= '1'; BS <= B_END;
                        elsif P_STERMn = '0' or P_DSACKn = "00" then
                            BM_P32 <= '1'; BM_P16 <= '0'; BS <= B_LAT;
                        elsif P_DSACKn = "01" then
                            BM_P32 <= '0'; BM_P16 <= '1'; BS <= B_LAT;
                        elsif P_DSACKn = "10" then -- 8-bit port: not for translation tables.
                            BM_ERR <= '1'; BS <= B_END;
                        end if;
                    when B_LAT => -- Data one clock after the termination (as the core's S4/S5).
                        if BM_P32 = '1' then BM_RDATA <= P_DATA_IN;
                        elsif BM_HALF = '0' then BM_RDATA(31 downto 16) <= P_DATA_IN(31 downto 16);
                        else BM_RDATA(15 downto 0) <= P_DATA_IN(31 downto 16); end if;
                        BS <= B_END;
                    when B_END =>
                        BM_AS <= '0'; BM_DS <= '0';
                        if BM_ERR = '0' and BM_P16 = '1' and BM_HALF = '0' then
                            BS <= B_GAP; -- Second word on the 16-bit port.
                        else
                            BS <= B_IDLE; BM_DONE <= '1';
                        end if;
                    when B_GAP =>
                        BM_HALF <= '1';
                        BM_A <= BM_A + x"2"; BM_D <= BM_D(15 downto 0) & BM_D(15 downto 0); BM_SZ <= "10";
                        BM_AS <= '1'; BM_DS <= not BM_WR; BM_CNT <= "00"; BS <= B_CYC;
                end case;
            end if;
        end if;
    end process P_BM;

    -- Table walker (Figure 9-19) and the ATC registers.
    P_WALK: process(CLK)
        variable RP : std_logic_vector(63 downto 0);
        variable DT : std_logic_vector(1 downto 0);
        variable W, IDXI : integer range 0 to 31;
        variable IDX : std_logic_vector(31 downto 0);
        variable NEXTW : integer range 0 to 15;
        variable REM_BITS : integer range 0 to 32;
        variable PA32, OFF : std_logic_vector(31 downto 0);
        variable FREE : integer range -1 to NE - 1;
        variable NRU : integer range -1 to NE - 1;
        variable DST, DWP, DU, DM, DCI : std_logic;
        variable TG : integer range 0 to 255;
    begin
        if CLK = '1' and CLK' event then
            BM_GO <= '0';
            -- Used bits for the replacement (set on a hit by a cycle that goes out).
            if WS = W_IDLE and HIT_OK = '1' and C_ASn = '0' then
                if (E_USED or HITV) = (E_USED'range => '1') then E_USED <= HITV; else E_USED <= E_USED or HITV; end if;
            end if;
            SR_WR <= '0'; AN_WR <= '0';
            if WS /= W_IDLE and W_NCK < 1023 then W_NCK <= W_NCK + 1; end if;
            if I_PAD /= 0 then I_PAD <= I_PAD - 1; end if;
            if CMD = '1' then
                C_PEND <= '1'; C_EXT <= CMD_EXT; C_EA <= CMD_EA; C_CFC <= CMD_FC; C_TT <= CMD_TT;
            end if;
            if RESET = '1' then
                WS <= W_IDLE; RMC_W <= '0'; C_PEND <= '0'; M_LOAD <= '0'; M_TEST <= '0';
            elsif FLUSH_ALL = '1' and WS = W_IDLE then
                E_V <= (others => '0'); E_USED <= (others => '0');
            else
                case WS is
                    when W_IDLE =>
                        M_LOAD <= '0'; M_TEST <= '0'; R_BERR <= '0'; R_LIM <= '0'; NLEV <= 0;
                        W_NCK <= 1; -- The clock the search starts is the first after the missed cycle's start.
                        -- Overhead: cough 7 + startup 8 + termination 8; startup 2 less with an FC lookup (p. 11-54).
                        if TC(24) = '1' then W_TGT <= 21; else W_TGT <= 23; end if;
                        if C_PEND = '1' and C_ASn = '1' and CYC_ON = '0' then
                            C_PEND <= '0';
                            if C_EXT(15 downto 13) = "001" and C_EXT(12 downto 10) /= "000" then
                                -- PFLUSHA (mode 001), PFLUSH FC,#MASK (100), PFLUSH FC,#MASK,<ea> (110): M68000PRM p. 6-34.
                                -- 11.7.2: PFLUSHA 12; PFLUSH 16, FC from SFC/DFC 20; the <ea> form + 4 (An).
                                if C_EXT(12 downto 10) = "001" then I_PAD <= 12 - K_FL; -- PFLUSHA 12.
                                else
                                    if C_EXT(4 downto 3) = "00" then TG := 20; else TG := 16; end if;
                                    if C_EXT(11) = '1' then TG := TG + 4; end if;
                                    I_PAD <= TG - K_FL;
                                end if;
                                for i in 0 to NE - 1 loop
                                    if C_EXT(12 downto 10) = "001" or -- [PMMU3] PFLUSHA is mode 001 (was tested as 010; PFLUSHA
                                       -- still flushed all through the FC/mask path with mask 000).
                                       (((E_FC(i) xor C_CFC) and C_EXT(7 downto 5)) = "000" and
                                        (C_EXT(11) = '0' or ((E_LA(i) xor C_EA(31 downto 8)) and PMASK) = x"000000")) then
                                        E_V(i) <= '0'; E_USED(i) <= '0';
                                    end if;
                                end loop;
                            elsif C_EXT(15 downto 13) = "100" and C_EXT(12 downto 10) = "000" then
                                -- PTEST level 0: ATC search only (Table 9-3). 11.7.2: 22 + EA 4.
                                SR_WR <= '1'; I_PAD <= 26 - K_T0;
                                if C_TT = '1' then
                                    SR_OUT <= x"0040"; -- T
                                else
                                    SR_OUT <= (others => '0');
                                    for i in 0 to NE - 1 loop
                                        if E_V(i) = '1' and E_FC(i) = C_CFC and ((E_LA(i) xor C_EA(31 downto 8)) and PMASK) = x"000000" then
                                            SR_OUT(15) <= E_B(i); SR_OUT(11) <= E_WP(i); SR_OUT(10) <= E_B(i); SR_OUT(9) <= E_M(i);
                                        end if;
                                    end loop;
                                    if C_HITV = (C_HITV'range => '0') then SR_OUT(10) <= '1'; end if;
                                end if;
                            else
                                -- PLOAD (R/W = ext bit 9: 1 = read) or PTEST levels 1-7: a table search for <ea>, FC.
                                L_LA <= C_EA; L_FC <= C_CFC; L_WR <= not C_EXT(9); WS <= W_ROOT;
                                if C_EXT(15 downto 13) = "100" then
                                    M_TEST <= '1'; TLEV <= conv_integer(C_EXT(12 downto 10));
                                else
                                    M_LOAD <= '1';
                                    -- The new entry replaces an existing one for that page.
                                    E_V <= E_V and not C_HITV;
                                end if;
                            end if;
                        elsif XLATE = '1' and C_ASn = '0' and HIT_OK = '0' and FAULT_NOW = '0' then
                            L_LA <= C_ADR; L_FC <= C_FC; L_WR <= C_WR; WS <= W_ROOT;
                            -- A write that hit an entry with M = 0: that entry is replaced by the new one (9.4.1 M bit).
                            if HIT = '1' then E_V <= E_V and not HITV; end if;
                        end if;
                    when W_ROOT =>
                        if TC(25) = '1' and L_FC(2) = '1' then RP := SRP; else RP := CRP; end if;
                        RMC_W <= '1'; ACC_WP <= '0'; ACC_S <= '0'; BAD <= '0'; IND <= '0';
                        -- SH: logical address shifted left by IS (TC 19-16).
                        SH <= std_logic_vector(shl(L_LA, TC(19 downto 16)));
                        USED_BITS <= conv_integer(TC(19 downto 16));
                        TADR <= RP(31 downto 4) & "0000";
                        LIM_ON <= '1'; LIM_LU <= RP(63); LIM <= RP(62 downto 48);
                        DT := RP(33 downto 32);
                        if DT = "01" or DT = "00" then W_TGT <= 0; end if; -- No descriptor access: no script time.
                        if DT = "01" then -- Root page descriptor: early termination at the root, PA = address + LA.
                            D0 <= x"00000001"; D1 <= RP(31 downto 8) & x"00"; TLONG <= '1'; LAST_PAGE <= '1';
                            DADR <= (others => '0'); -- [PMMU3] PTEST An: $0 when the root pointer is a page (PRM p. 6-64).
                            WS <= W_DONE; -- No descriptor in memory: no U/M update.
                        elsif DT = "00" then
                            BAD <= '1'; WS <= W_DONE;
                        else
                            TLONG <= DT(0); -- 2 = 4-byte, 3 = 8-byte descriptors in the first table.
                            if TC(24) = '1' then LVL <= 0; else LVL <= 1; end if;
                            WS <= W_LEVEL;
                        end if;
                    when W_LEVEL =>
                        if LVL = 0 then
                            IDX := x"0000000" & '0' & L_FC; -- Function code level: not limited (9.5.3.2).
                            W := 0;
                        else
                            W := TIW(TC, LVL);
                            IDX := (others => '0');
                            for k in 0 to 15 loop
                                if k < W then IDX(k) := SH(31 - W + 1 + k); end if;
                            end loop;
                        end if;
                        if LVL /= 0 and LIM_ON = '1' and
                           ((LIM_LU = '0' and IDX(14 downto 0) > LIM) or (LIM_LU = '1' and IDX(14 downto 0) < LIM)) then
                            BAD <= '1'; R_LIM <= '1'; WS <= W_DONE; -- Limit violation.
                        else
                            if LVL /= 0 then
                                SH <= std_logic_vector(shl(SH, conv_std_logic_vector(W, 5)));
                                USED_BITS <= USED_BITS + W;
                            end if;
                            if TLONG = '1' then DADR <= TADR + (IDX(28 downto 0) & "000"); BM_ADR <= TADR + (IDX(28 downto 0) & "000");
                            else DADR <= TADR + (IDX(29 downto 0) & "00"); BM_ADR <= TADR + (IDX(29 downto 0) & "00"); end if;
                            BM_WR <= '0'; BM_GO <= '1'; WS <= W_FETCH;
                        end if;
                    when W_FETCH =>
                        if BM_DONE = '1' then
                            if BM_ERR = '1' then BAD <= '1'; R_BERR <= '1'; WS <= W_DONE;
                            elsif TLONG = '1' then
                                BUSA <= BM_CLKS;
                                D0 <= BM_RDATA; BM_ADR <= DADR + x"4"; BM_WR <= '0'; BM_GO <= '1'; WS <= W_FETCH2;
                            else
                                D0 <= BM_RDATA; D1 <= BM_RDATA; WS <= W_EVAL;
                            end if;
                        end if;
                    when W_FETCH2 =>
                        if BM_DONE = '1' then
                            if BM_ERR = '1' then BAD <= '1'; R_BERR <= '1'; WS <= W_DONE; else D1 <= BM_RDATA; WS <= W_EVAL; end if;
                        end if;
                    when W_EVAL =>
                        DT := D0(1 downto 0);
                        if NLEV < 7 then NLEV <= NLEV + 1; end if;
                        if LVL = 0 then NEXTW := TIW(TC, 1); elsif LVL < 4 then NEXTW := TIW(TC, LVL + 1); else NEXTW := 0; end if;
                        -- [PMMU3] Script clocks for this descriptor (p. 11-55).
                        DT := D0(1 downto 0);
                        if LVL = 0 then NEXTW := TIW(TC, 1); elsif LVL < 4 then NEXTW := TIW(TC, LVL + 1); else NEXTW := 0; end if;
                        if IND = '1' then -- Indirection level: short 3 + bus, long 2 + 2 * bus.
                            if TLONG = '1' then TG := 2 + BUSA + BM_CLKS; else TG := 3 + BM_CLKS; end if;
                        elsif TLONG = '1' then -- Long: 6 + bus + max(bus - 4, 0).
                            TG := 6 + BUSA;
                            if BUSA > 4 then TG := TG + BUSA - 4; end if;
                        else -- Short: 3 + bus.
                            TG := 3 + BM_CLKS;
                        end if;
                        if IND = '0' and DT = "01" then
                            if LVL = 0 or NEXTW /= 0 then TG := TG + 3;      -- Early termination penalty.
                            elsif TLONG = '1' then TG := TG - 2; end if;      -- A long page: one box less.
                        end if;
                        W_TGT <= W_TGT + TG;
                        if IND = '1' then
                            -- Descriptor reached through an indirect descriptor: must be a page.
                            if DT /= "01" then BAD <= '1'; WS <= W_DONE;
                            else
                                LAST_PAGE <= '1';
                                if TLONG = '1' then ACC_S <= ACC_S or D0(8); end if;
                                ACC_WP <= ACC_WP or D0(2);
                                WS <= W_UPD;
                            end if;
                        elsif DT = "00" then
                            BAD <= '1'; WS <= W_DONE; -- Invalid descriptor.
                        else
                            -- [PMMU3] An indirect descriptor has no WP or S bit (9.5.1.11/12, Figures 9-17/9-18 pp. 9-27/9-28: bits 31-2
                            -- are the address), so only a table or page descriptor adds to WP/S.
                            if not (DT(1) = '1' and NEXTW = 0 and LVL /= 0) then
                                if TLONG = '1' then ACC_S <= ACC_S or D0(8); end if;
                                ACC_WP <= ACC_WP or D0(2);
                            end if;
                            if DT = "01" then
                                LAST_PAGE <= '1'; WS <= W_UPD; -- Page (early termination if levels remain).
                            elsif NEXTW = 0 and LVL /= 0 then
                                -- No more TIx: an indirect descriptor (DT 2 = to a short, 3 = to a long page descriptor).
                                IND <= '1'; TLONG <= DT(0);
                                if TLONG = '1' then BM_ADR <= D1(31 downto 2) & "00"; DADR <= D1(31 downto 2) & "00";
                                else BM_ADR <= D0(31 downto 2) & "00"; DADR <= D0(31 downto 2) & "00"; end if;
                                BM_WR <= '0'; BM_GO <= '1'; WS <= W_FETCH;
                                LAST_PAGE <= '0';
                            elsif M_TEST = '1' and NLEV + 1 >= TLEV then
                                LAST_PAGE <= '0'; WS <= W_DONE; -- PTEST: the level given is reached.
                            else
                                LAST_PAGE <= '0'; WS <= W_UPD; -- Table descriptor: update U, go down.
                            end if;
                        end if;
                    when W_UPD =>
                        -- U for every descriptor used, M on the page for a write without WP or S violation (9.5.3).
                        DU := D0(3); DM := D0(4);
                        if LAST_PAGE = '1' and L_WR = '1' and ACC_WP = '0' and not (ACC_S = '1' and L_FC(2) = '0') then
                            DM := '1';
                        end if;
                        if M_TEST = '1' then -- PTEST does not change the history bits.
                            WS <= W_NEXT;
                        elsif DU = '0' or DM /= D0(4) then -- Locked write of the descriptor's first long (RMC held).
                            D0(3) <= '1'; D0(4) <= DM;
                            BM_ADR <= DADR; BM_WDATA <= D0(31 downto 5) & DM & '1' & D0(2 downto 0);
                            BM_WR <= '1'; BM_GO <= '1'; WS <= W_UPDW;
                        else
                            WS <= W_NEXT;
                        end if;
                    when W_UPDW =>
                        if BM_DONE = '1' then
                            -- U set in a pointer: 4 + max(bus - 3, 0); U/M in the page: 2 + max(bus - 3, 0).
                            if LAST_PAGE = '1' then TG := 2; else TG := 4; end if;
                            if BM_CLKS > 3 then TG := TG + BM_CLKS - 3; end if;
                            W_TGT <= W_TGT + TG;
                            if BM_ERR = '1' then BAD <= '1'; WS <= W_DONE; else WS <= W_NEXT; end if;
                        end if;
                    when W_NEXT =>
                        if LAST_PAGE = '1' then WS <= W_DONE;
                        else -- Next table.
                            if TLONG = '1' then TADR <= D1(31 downto 4) & "0000"; LIM_ON <= '1'; LIM_LU <= D0(31); LIM <= D0(30 downto 16);
                            else TADR <= D0(31 downto 4) & "0000"; LIM_ON <= '0'; end if;
                            TLONG <= D0(0);
                            if LVL < 4 then LVL <= LVL + 1; end if;
                            WS <= W_LEVEL;
                        end if;
                    when W_DONE =>
                      if W_NCK < W_TGT then
                        null; -- [PMMU3] 11.7: hold until the script time has passed.
                      else
                        -- synthesis translate_off
                        report "MMUWALK clocks=" & integer'image(W_NCK) & " script=" & integer'image(W_TGT) & " bus=" & integer'image(BM_CLKS) severity note;
                        -- synthesis translate_on
                        -- Physical page: descriptor address + logical bits below the last index used (early term.).
                        if TLONG = '1' then PA32 := D1(31 downto 8) & x"00"; else PA32 := D0(31 downto 8) & x"00"; end if;
                        OFF := (others => '0');
                        for k in 8 to 31 loop
                            if k < 32 - USED_BITS then OFF(k) := L_LA(k); end if;
                        end loop;
                        PA32 := PA32 + OFF;
                        DCI := D0(6);
                        -- Replacement: invalid entry first, else the first not-recently-used one.
                        FREE := -1; NRU := -1;
                        for i in NE - 1 downto 0 loop
                            if E_V(i) = '0' then FREE := i; end if;
                            if E_USED(i) = '0' then NRU := i; end if;
                        end loop;
                        if M_TEST = '1' then
                            -- PTEST levels 1-7 result (Table 9-3 p. 9-60): B, L, S, W, I, M, N; T = 0; no ATC entry.
                            SR_WR <= '1'; AN_WR <= C_EXT(8); AN_DATA <= DADR;
                            I_PAD <= 26 - K_LD; -- PTEST #1-7: as level 0 plus the search ("somewhat longer", p. 11-52).
                            SR_OUT <= R_BERR & R_LIM & (ACC_S and not L_FC(2)) & '0' & ACC_WP & BAD & (D0(4) and LAST_PAGE and not BAD)
                                      & "000000" & conv_std_logic_vector(NLEV, 3);
                            RMC_W <= '0'; WS <= W_IDLE;
                        else
                        if FREE >= 0 then IDXI := FREE; elsif NRU >= 0 then IDXI := NRU; else IDXI := 0; end if;
                        E_V(IDXI) <= '1'; E_FC(IDXI) <= L_FC; E_LA(IDXI) <= L_LA(31 downto 8) and PMASK;
                        E_PA(IDXI) <= PA32(31 downto 8);
                        E_B(IDXI) <= BAD or (ACC_S and not L_FC(2));
                        E_CI(IDXI) <= DCI and not BAD; E_WP(IDXI) <= ACC_WP;
                        -- M of the entry: the page descriptor's M after the update; a write through a root-pointer
                        -- page (no descriptor in memory, 9.5.3.3) marks the entry modified directly, else the
                        -- retried write would miss again (M = 0) and search forever.
                        E_M(IDXI) <= D0(4) or (L_WR and not BAD);
                        E_USED(IDXI) <= '1';
                        RMC_W <= '0'; WS <= W_IDLE;
                        if M_LOAD = '1' then -- PLOAD: 8, FC from SFC/DFC 12, + EA 4, then the search.
                            if C_EXT(4 downto 3) = "00" then I_PAD <= 16 - K_LD; else I_PAD <= 12 - K_LD; end if;
                        end if;
                        end if;
                      end if;
                end case;
            end if;
        end if;
    end process P_WALK;
end architecture BEHAVIOUR;
