-- =====================================================================
-- bus_trace.vhd -- SINGLE-FILE bus tracer: PACKAGE + ENTITY in one file.
--
-- Merged to defeat Gowin project-ordering.  Gowin compiles files in list
-- order and does not dependency-sort packages; as two files the package
-- kept landing after its users (EX4760/EX4759) however they were dragged.
-- In ONE file the package is always compiled immediately before the
-- entity (files compile top-to-bottom).  ONE rule remains: this file
-- must be BEFORE rigsdram_top.vhd in the project list.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package BUS_TRACE_PKG is

    -- One captured bus cycle, packed flat so the ring is a plain
    -- array of vectors and Gowin infers BSRAM rather than LUT RAM.
    --
    --   [89:58] ADR      32   address at AS falling
    --   [57:26] DAT      32   D_IN on a read, D_OUT on a write
    --   [25:23] FC        3   function code
    --   [22:21] SIZE      2   as driven, NOT as the slave honoured it
    --   [20]    RWn       1
    --   [19:18] DSACKn    2   termination as sampled
    --   [17]    BERRn     1
    --   [16]    AVECn     1
    --   [15:0]  DELTA    16   core clocks since the previous AS fall
    constant TRC_W : integer := 90;

    subtype TRC_T is std_logic_vector(TRC_W - 1 downto 0);

    function trc_pack(adr : std_logic_vector(31 downto 0);
                      dat : std_logic_vector(31 downto 0);
                      fc  : std_logic_vector(2 downto 0);
                      siz : std_logic_vector(1 downto 0);
                      rwn : std_logic;
                      dsk : std_logic_vector(1 downto 0);
                      brn : std_logic;
                      avn : std_logic;
                      dlt : std_logic_vector(15 downto 0)) return TRC_T;

    -- Line layout, 30 characters including CR LF:
    --
    --   AAAAAAAA:DDDDDDDD:F:S:T:dddd<CR><LF>
    --
    --   F = function code
    --   S = bit3 RWn, bits1:0 SIZE
    --   T = bit3 BERRn, bit2 AVECn, bits1:0 DSACKn
    --   d = DELTA, ADVISORY ONLY.  Simulation and silicon do not agree
    --       on wait-state counts (SDRAM refresh alone guarantees that),
    --       so DELTA is deliberately the LAST field: cut at column 24
    --       and diff the transaction sequence, which must match exactly.
    constant TRC_CHARS : integer := 30;

    function trc_char(rec : TRC_T; i : integer)
        return std_logic_vector;                    -- 8-bit ASCII

    -- Header and footer are part of the format so a truncated dump is
    -- detectable rather than merely short.
    constant HDR_CHARS : integer := 7;              -- "TRACE" CR LF
    constant FTR_CHARS : integer := 6;              -- "TEND"  CR LF

    function hdr_char(i : integer) return std_logic_vector;
    function ftr_char(i : integer) return std_logic_vector;

end package BUS_TRACE_PKG;


package body BUS_TRACE_PKG is

    function hex(n : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable u : integer;
    begin
        -- An 'X' or 'U' nibble must not print as a plausible digit.
        -- '?' in a trace column is a finding, a silent '0' is a trap.
        for k in 3 downto 0 loop
            if n(k) /= '0' and n(k) /= '1' then
                return x"3F";                       -- '?'
            end if;
        end loop;
        u := to_integer(unsigned(n));
        if u < 10 then
            return std_logic_vector(to_unsigned(48 + u, 8));      -- '0'-'9'
        else
            return std_logic_vector(to_unsigned(55 + u, 8));      -- 'A'-'F'
        end if;
    end function hex;

    function trc_pack(adr : std_logic_vector(31 downto 0);
                      dat : std_logic_vector(31 downto 0);
                      fc  : std_logic_vector(2 downto 0);
                      siz : std_logic_vector(1 downto 0);
                      rwn : std_logic;
                      dsk : std_logic_vector(1 downto 0);
                      brn : std_logic;
                      avn : std_logic;
                      dlt : std_logic_vector(15 downto 0)) return TRC_T is
    begin
        return adr & dat & fc & siz & rwn & dsk & brn & avn & dlt;
    end function trc_pack;

    function trc_char(rec : TRC_T; i : integer)
        return std_logic_vector is
        variable a : std_logic_vector(31 downto 0);
        variable d : std_logic_vector(31 downto 0);
        variable t : std_logic_vector(15 downto 0);
    begin
        a := rec(89 downto 58);
        d := rec(57 downto 26);
        t := rec(15 downto 0);
        case i is
            when  0 => return hex(a(31 downto 28));
            when  1 => return hex(a(27 downto 24));
            when  2 => return hex(a(23 downto 20));
            when  3 => return hex(a(19 downto 16));
            when  4 => return hex(a(15 downto 12));
            when  5 => return hex(a(11 downto  8));
            when  6 => return hex(a( 7 downto  4));
            when  7 => return hex(a( 3 downto  0));
            when  8 => return x"3A";                            -- ':'
            when  9 => return hex(d(31 downto 28));
            when 10 => return hex(d(27 downto 24));
            when 11 => return hex(d(23 downto 20));
            when 12 => return hex(d(19 downto 16));
            when 13 => return hex(d(15 downto 12));
            when 14 => return hex(d(11 downto  8));
            when 15 => return hex(d( 7 downto  4));
            when 16 => return hex(d( 3 downto  0));
            when 17 => return x"3A";
            when 18 => return hex('0' & rec(25 downto 23));      -- FC
            when 19 => return x"3A";
            when 20 => return hex(rec(20) & '0' & rec(22 downto 21));
            when 21 => return x"3A";
            when 22 => return hex(rec(17) & rec(16) & rec(19 downto 18));
            when 23 => return x"3A";
            when 24 => return hex(t(15 downto 12));
            when 25 => return hex(t(11 downto  8));
            when 26 => return hex(t( 7 downto  4));
            when 27 => return hex(t( 3 downto  0));
            when 28 => return x"0D";
            when others => return x"0A";
        end case;
    end function trc_char;

    function hdr_char(i : integer) return std_logic_vector is
    begin
        case i is
            when 0 => return x"54";     -- T
            when 1 => return x"52";     -- R
            when 2 => return x"41";     -- A
            when 3 => return x"43";     -- C
            when 4 => return x"45";     -- E
            when 5 => return x"0D";
            when others => return x"0A";
        end case;
    end function hdr_char;

    function ftr_char(i : integer) return std_logic_vector is
    begin
        case i is
            when 0 => return x"54";     -- T
            when 1 => return x"45";     -- E
            when 2 => return x"4E";     -- N
            when 3 => return x"44";     -- D
            when 4 => return x"0D";
            when others => return x"0A";
        end case;
    end function ftr_char;

end package body BUS_TRACE_PKG;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.BUS_TRACE_PKG.all;

entity BUS_TRACE is
    generic(
        DEPTH        : integer := 512;
        -- 0 = capture from reset, stop when full.        <-- this bug
        -- 1 = free-run, trigger on BERRn, keep POST more. <-- wild jumps
        -- 2 = free-run, trigger on address match.
        -- 3 = DISARMED.  Captures, never triggers, never halts the CPU
        --     and never touches the UART.  This is the PERTURBATION
        --     CONTROL: the tracer is in the fabric with its real BSRAM
        --     and real fanout, but silent, so a run with it can be
        --     compared byte-for-byte against a run without it.  Without
        --     this mode there is no way to separate "the tracer changed
        --     the design" from "the tracer works".
        TRIG_MODE    : integer := 0;
        POST         : integer := 64;
        TRIG_ADR     : std_logic_vector(31 downto 0) := x"00000000";
        TRIG_MASK    : std_logic_vector(31 downto 0) := x"FFFFFFFF";
        HALT_ON_DUMP : integer := 1;
        -- [COLD] Dump after this many stored AS cycles (0 = ignore).
        -- The old MODE-0 "wait until DEPTH is full" is why a hung CPU
        -- produced a silent UART: 512 cycles never arrived, so the
        -- dump never started.  16 is enough to see reset SSP/PC plus
        -- the first opcodes at $400.
        STOP_AFTER   : integer := 16;
        -- [COLD] Also dump this many core clocks after rst_n rises,
        -- EVEN IF n_ent=0.  0 = disabled.  2000 clocks @ 12.5 MHz is
        -- 160 us -- far past a healthy reset sequence, short enough
        -- that you are not staring at a dead terminal.
        TIMEOUT      : integer := 2000
    );
    port(
        clk      : in  std_logic;                       -- core_clk
        rst_n    : in  std_logic;
        -- observed CPU pins ------------------------------------------
        ASn      : in  std_logic;
        RWn      : in  std_logic;
        BERRn    : in  std_logic;
        AVECn    : in  std_logic;
        DSACKn   : in  std_logic_vector(1 downto 0);
        SIZE     : in  std_logic_vector(1 downto 0);
        FC       : in  std_logic_vector(2 downto 0);
        ADR      : in  std_logic_vector(31 downto 0);
        D_OUT    : in  std_logic_vector(31 downto 0);
        D_IN     : in  std_logic_vector(31 downto 0);
        HALTn    : in  std_logic := '1';                -- CPU HALT_OUTn
        -- borrowed UART ----------------------------------------------
        tx_busy  : in  std_logic;
        tx_load  : out std_logic;
        tx_byte  : out std_logic_vector(7 downto 0);
        active   : out std_logic;   -- '1' while dumping; top muxes UART
        halt_req : out std_logic;   -- '1' to freeze the CPU
        -- observation ------------------------------------------------
        trc_valid : out std_logic;
        trc_rec   : out TRC_T
    );
end entity BUS_TRACE;

architecture RTL of BUS_TRACE is

    type RING_T is array (0 to DEPTH - 1) of TRC_T;
    signal ring : RING_T;

    signal wr      : integer range 0 to DEPTH - 1 := 0;
    signal rd      : integer range 0 to DEPTH - 1 := 0;
    signal rd_rec  : TRC_T := (others => '0');
    signal wrapped : std_logic := '0';
    signal n_ent   : integer range 0 to DEPTH := 0;
    signal emitted : integer range 0 to DEPTH := 0;

    signal asn_d   : std_logic := '1';
    signal pend    : std_logic := '0';
    signal seen    : std_logic := '0';

    signal cyc     : unsigned(15 downto 0) := (others => '0');
    signal cyc_las : unsigned(15 downto 0) := (others => '0');

    signal c_adr   : std_logic_vector(31 downto 0) := (others => '0');
    signal c_dat   : std_logic_vector(31 downto 0) := (others => '0');
    signal c_fc    : std_logic_vector(2 downto 0)  := (others => '0');
    signal c_siz   : std_logic_vector(1 downto 0)  := (others => '0');
    signal c_rwn   : std_logic := '1';
    signal c_dsk   : std_logic_vector(1 downto 0)  := "11";
    signal c_brn   : std_logic := '1';
    signal c_avn   : std_logic := '1';
    signal c_dlt   : std_logic_vector(15 downto 0) := (others => '0');

    signal armed   : std_logic := '1';    -- capturing
    signal trig    : std_logic := '0';
    signal post_c  : integer range 0 to POST := POST;
    signal tmo     : unsigned(15 downto 0) := (others => '0');
    signal halt_s  : std_logic := '1';    -- HALTn sampled at stop

    function hex_d(n : integer) return std_logic_vector is
        variable u : integer;
    begin
        u := n mod 16;
        if u < 10 then
            return std_logic_vector(to_unsigned(48 + u, 8));
        else
            return std_logic_vector(to_unsigned(55 + u, 8));
        end if;
    end function hex_d;

    type ST_T is (S_RUN, S_HDR, S_FETCH, S_LINE, S_FTR, S_DONE);
    signal st : ST_T := S_RUN;
    -- UART handshake: tx_busy is registered and rises the cycle AFTER
    -- it samples tx_load.  Emitting again on that still-idle cycle
    -- overwrites the byte the shifter has not taken yet.  Silicon
    -- dropped every other character (T-A-E from TRACE).  holdoff is
    -- the missing half of the handshake.
    signal holdoff : std_logic := '0';
    -- ci must cover TRC_CHARS (30) and the extra header info line (12)
    signal ci : integer range 0 to 31 := 0;
    constant INFO_CHARS : integer := 12;  -- "N=HHH H=B" CR LF

begin

    -- =================================================================
    -- capture
    -- =================================================================
    process(clk)
        variable rec : TRC_T;
        variable stop_now : boolean;
    begin
        if rising_edge(clk) then
            trc_valid <= '0';
            rd_rec    <= ring(rd);          -- synchronous read: BSRAM

            if rst_n = '0' then
                wr      <= 0;
                wrapped <= '0';
                n_ent   <= 0;
                pend    <= '0';
                seen    <= '0';
                armed   <= '1';
                trig    <= '0';
                post_c  <= POST;
                cyc     <= (others => '0');
                cyc_las <= (others => '0');
                asn_d   <= '1';
                tmo     <= (others => '0');
                halt_s  <= '1';
            else
                cyc   <= cyc + 1;
                asn_d <= ASn;

                -- [COLD] timeout runs even with zero AS edges.  TRIG_MODE=3
                -- stays silent on purpose.
                if armed = '1' and TRIG_MODE /= 3 and TIMEOUT > 0 then
                    if tmo < to_unsigned(TIMEOUT, 16) then
                        tmo <= tmo + 1;
                    else
                        armed  <= '0';
                        halt_s <= HALTn;
                    end if;
                end if;

                if armed = '1' then

                    -- ---- address phase: AS falling --------------------
                    if asn_d = '1' and ASn = '0' then
                        c_adr <= ADR;
                        c_fc  <= FC;
                        c_siz <= SIZE;
                        c_rwn <= RWn;
                        c_dsk <= "11";
                        c_brn <= '1';
                        c_avn <= '1';
                        c_dat <= (others => '0');
                        c_dlt <= std_logic_vector(cyc - cyc_las);
                        cyc_las <= cyc;
                        pend  <= '1';
                        seen  <= '0';
                    end if;

                    -- ---- termination: first ack of this cycle ---------
                    -- Sampled when it is asserted, not at AS rising,
                    -- because the top clears DSACKn on AS rising and a
                    -- late sample would record "11" for every cycle.
                    if pend = '1' and ASn = '0' and seen = '0' then
                        if DSACKn /= "11" or BERRn = '0' or AVECn = '0' then
                            c_dsk <= DSACKn;
                            c_brn <= BERRn;
                            c_avn <= AVECn;
                            if RWn = '1' then
                                c_dat <= D_IN;
                            else
                                c_dat <= D_OUT;
                            end if;
                            seen <= '1';
                        end if;
                    end if;

                    -- ---- write the entry at AS rising ----------------
                    if pend = '1' and asn_d = '0' and ASn = '1' then
                        pend <= '0';
                        rec := trc_pack(c_adr, c_dat, c_fc, c_siz, c_rwn,
                                        c_dsk, c_brn, c_avn, c_dlt);
                        ring(wr) <= rec;
                        trc_rec   <= rec;
                        trc_valid <= '1';

                        if n_ent < DEPTH then
                            n_ent <= n_ent + 1;
                        end if;
                        if wr = DEPTH - 1 then
                            wr      <= 0;
                            wrapped <= '1';
                        else
                            wr <= wr + 1;
                        end if;

                        -- ---- trigger / stop -------------------------
                        stop_now := false;
                        if TRIG_MODE = 3 then
                            stop_now := false;
                        elsif STOP_AFTER > 0 and (n_ent + 1) >= STOP_AFTER then
                            -- n_ent is the OLD count; this write makes it +1
                            stop_now := true;
                        elsif TRIG_MODE = 0 then
                            if wr = DEPTH - 1 then
                                stop_now := true;
                            end if;
                        else
                            if trig = '0' then
                                if TRIG_MODE = 1 and c_brn = '0' then
                                    trig <= '1';
                                elsif TRIG_MODE = 2 and
                                      (c_adr and TRIG_MASK) =
                                      (TRIG_ADR and TRIG_MASK) then
                                    trig <= '1';
                                end if;
                            else
                                if post_c = 0 then
                                    stop_now := true;
                                else
                                    post_c <= post_c - 1;
                                end if;
                            end if;
                        end if;

                        if stop_now then
                            armed  <= '0';
                            halt_s <= HALTn;
                        end if;
                    end if;

                end if;   -- armed
            end if;
        end if;
    end process;

    -- =================================================================
    -- dump.  Runs only after capture has stopped.
    -- =================================================================
    active   <= '0' when st = S_RUN else '1';
    halt_req <= '1' when st /= S_RUN and HALT_ON_DUMP = 1 else '0';

    process(clk)
        variable oldest : integer;
    begin
        if rising_edge(clk) then
            tx_load <= '0';
            if rst_n = '0' then
                rd      <= 0;
                emitted <= 0;
                ci      <= 0;
                st      <= S_RUN;
                holdoff <= '0';
            elsif tx_busy = '1' then
                -- UART has accepted the last byte and is shifting.
                holdoff <= '0';
            elsif holdoff = '1' then
                -- Race cycle: we pulsed tx_load last clock, busy has
                -- not risen yet.  Do not emit.
                null;
            else
                case st is

                    -- armed falls when capture has stopped.  That is the
                    -- only coupling between the two processes, and it is
                    -- one-way: capture never sees the dump.
                    when S_RUN =>
                        if armed = '0' then
                            st <= S_HDR;
                            ci <= 0;
                        end if;

                    when S_HDR =>
                        -- "TRACE" CR LF then "N=HHH H=B" CR LF
                        -- N is stored-cycle count (0 is a FINDING).
                        -- H is HALT_OUTn at stop ('1' running, '0' halted).
                        tx_load <= '1';
                        holdoff <= '1';
                        if ci < HDR_CHARS then
                            tx_byte <= hdr_char(ci);
                        else
                            case ci - HDR_CHARS is
                                when 0 => tx_byte <= x"4E";              -- N
                                when 1 => tx_byte <= x"3D";              -- =
                                when 2 => tx_byte <= hex_d(n_ent / 256);
                                when 3 => tx_byte <= hex_d(n_ent / 16);
                                when 4 => tx_byte <= hex_d(n_ent);
                                when 5 => tx_byte <= x"20";
                                when 6 => tx_byte <= x"48";              -- H
                                when 7 => tx_byte <= x"3D";              -- =
                                when 8 =>
                                    if halt_s = '0' then
                                        tx_byte <= x"30";              -- 0 = HALTED
                                    else
                                        tx_byte <= x"31";              -- 1 = not halted
                                    end if;
                                when 9 => tx_byte <= x"0D";
                                when others => tx_byte <= x"0A";
                            end case;
                        end if;
                        if ci = HDR_CHARS + INFO_CHARS - 1 then
                            if n_ent = 0 then
                                st <= S_FTR;
                                ci <= 0;
                            else
                                if wrapped = '1' then
                                    oldest := wr;
                                else
                                    oldest := 0;
                                end if;
                                rd      <= oldest;
                                emitted <= 0;
                                st      <= S_FETCH;
                            end if;
                        else
                            ci <= ci + 1;
                        end if;

                    when S_FETCH =>
                        -- one dead cycle so the synchronous ring read
                        -- for the new rd has landed in rd_rec
                        ci <= 0;
                        st <= S_LINE;

                    when S_LINE =>
                        tx_byte <= trc_char(rd_rec, ci);
                        tx_load <= '1';
                        holdoff <= '1';
                        if ci = TRC_CHARS - 1 then
                            if emitted = n_ent - 1 then
                                st <= S_FTR;
                                ci <= 0;
                            else
                                emitted <= emitted + 1;
                                if rd = DEPTH - 1 then
                                    rd <= 0;
                                else
                                    rd <= rd + 1;
                                end if;
                                st <= S_FETCH;
                            end if;
                        else
                            ci <= ci + 1;
                        end if;

                    when S_FTR =>
                        tx_byte <= ftr_char(ci);
                        tx_load <= '1';
                        holdoff <= '1';
                        if ci = FTR_CHARS - 1 then
                            st <= S_DONE;
                        else
                            ci <= ci + 1;
                        end if;

                    when S_DONE =>
                        null;

                end case;
            end if;
        end if;
    end process;

end architecture RTL;