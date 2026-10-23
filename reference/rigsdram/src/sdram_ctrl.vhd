----------------------------------------------------------------------
-- sdram_ctrl.vhd
--
-- SDRAM controller for the W9825G6KH on the Sipeed Tang SDRAM X2
-- module (silkscreen V1.3), fitted to the Tang Console 138K SDRAM0
-- connector J9.
--
-- Checked against w9825g6kh.vhd, which was written from the datasheet
-- BEFORE this file existed and knows nothing about it.
--
-- ALL TIMING IS A GENERIC.  Not one literal delay in the body.  A
-- different speed grade or clock is a parameter change, and the
-- testbench can sweep them.
--
-- ------------------------------------------------------------------
-- CHIP SELECT, and a simplification worth stating
--
--   The module wires CS1 = NOT CS0 through U3, so exactly one of the
--   two chips is selected at any moment and there is no both-idle
--   state.  The module spec's answer was to park RAS/CAS/WE at the NOP
--   encoding whenever CS0 goes high, so that the unused chip decodes
--   only NOPs.
--
--   This controller does something stronger and simpler: CS0 is held
--   LOW PERMANENTLY and the bus idles on NOP (CS low, RAS/CAS/WE
--   high), which is the datasheet's own idle command (7.18).  U2's
--   select is then high forever, so U2 is DESELECTED forever and
--   never registers anything at all (7.19).  The entire "unused chip
--   decodes our commands" failure class stops existing rather than
--   being managed.
--
--   This does not reopen the one-chip decision; it is that decision
--   carried through.  Vector S2 asserts both properties: that CS0 is
--   never deasserted, and that IF it ever were, NOP would be held --
--   so the guarantee survives a later change by someone who has
--   forgotten why.
--
-- ------------------------------------------------------------------
-- ADDRESS MAP
--
--   addr(23 downto 0) is a WORD address -- 16M words, 32 MB.
--       col  = addr( 8 downto 0)     512 words, a 1 KB page
--       bank = addr(10 downto  9)
--       row  = addr(23 downto 11)
--
--   Bank from mid-order bits, deliberately.  A bus probe showed
--   instruction fetch and data access alternate, and they live in
--   different rows; if both mapped to one bank that alternation would
--   force precharge and activate on EVERY access -- a page miss every
--   time.  With the bank taken from addr(10:9) two streams more than
--   1 KB apart land in different banks and both rows stay open.
--   Same hardware, no extra cost, purely a bank-assignment decision.
--
-- ------------------------------------------------------------------
-- SCOPE
--
--   Burst length 1.  A 68030 longword is two requests, assembled by
--   whatever sits above this.  BL=2 would fetch a longword in one
--   command and is the obvious later optimisation, but correctness
--   first: the sequencing philosophy on this project is correct,
--   then bring-up, then performance.
--
--   No CDC here.  This is a single clock domain.  Crossing to the
--   68030 core clock is a separate block with its own vectors.
----------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_ctrl is
    generic (
        -- Controller clock.  100 MHz default.
        CLK_KHZ      : integer := 100000;

        -- W9825G6KH-6, datasheet A04 section 9.5.  Nanoseconds where
        -- the datasheet gives nanoseconds, clocks where it gives tCK.
        tRCD_NS      : integer := 15;
        tRP_NS       : integer := 15;
        tRC_NS       : integer := 60;
        tRAS_NS      : integer := 42;
        tWR_CK       : integer := 2;
        tRSC_CK      : integer := 2;

        -- 8192 rows in 64 ms = one refresh every 7812.5 ns.  Truncated
        -- deliberately: refreshing marginally early is free, and late
        -- is data loss.
        tREFI_NS     : integer := 7812;
        INIT_PAUSE_NS: integer := 200000;
        INIT_REFRESH : integer := 8;

        CAS_LATENCY  : integer := 3
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;

        -- Host side.  HANDSHAKE CONTRACT, and it is load bearing:
        --   the transfer happens on the rising edge where req AND
        --   ready are both high.  The host must HOLD req until it
        --   observes ready high at an edge -- it must not sample
        --   ready, then pulse req for one cycle.  A refresh can fall
        --   due in that gap, and the controller will have left IDLE
        --   before the pulse arrives.  The request is then lost with
        --   no error anywhere: on hardware that is one silently
        --   corrupted memory location, phase dependent, and it will
        --   not reproduce.  This cost a debugging session.
        req       : in  std_logic;
        we        : in  std_logic;
        addr      : in  std_logic_vector(23 downto 0);
        wdata     : in  std_logic_vector(15 downto 0);
        be        : in  std_logic_vector(1 downto 0);  -- 1 = write lane
        rdata     : out std_logic_vector(15 downto 0);
        -- ack does NOT identify which transaction it belongs to.
        -- ready returns as soon as the command is issued, so a host
        -- that keeps presenting requests can have several in flight
        -- and cannot tell the acks apart -- and a write's ack would be
        -- mistaken for a preceding read's.  CONTRACT: one outstanding
        -- transaction.  Wait for ack before presenting the next.  A
        -- 68030 bus adapter does this naturally; the measured cost is
        -- in the throughput table in the handover.
        ack       : out std_logic;
        ready     : out std_logic;

        -- SDRAM side
        sd_cs_n   : out   std_logic;
        sd_ras_n  : out   std_logic;
        sd_cas_n  : out   std_logic;
        sd_we_n   : out   std_logic;
        sd_ba     : out   std_logic_vector(1 downto 0);
        sd_a      : out   std_logic_vector(12 downto 0);
        sd_dq     : inout std_logic_vector(15 downto 0);
        sd_ldqm   : out   std_logic;
        sd_udqm   : out   std_logic
    );
end entity sdram_ctrl;


architecture rtl of sdram_ctrl is

    -- Integer-only cycle arithmetic.  No math_real: constant folding
    -- with reals is exactly the sort of thing a synthesiser is
    -- entitled to handle differently from a simulator, and this
    -- project has been bitten by simulation and synthesis disagreeing
    -- before.
    function ceil_div (a : integer; b : integer) return integer is
    begin
        return (a + b - 1) / b;
    end function;

    -- ns * kHz / 1e6 = cycles.  Minimum delays round UP.
    --
    -- Split into whole-microsecond and remainder parts.  The obvious
    -- form, ceil_div(ns * (CLK_KHZ/1000), 1000), pre-divides the clock
    -- and truncates 133333 kHz to 133 -- which made the 200 us
    -- initialisation pause 0.25 % SHORT at 133 MHz.  Invisible at
    -- round clock rates; the chip model caught it the moment the
    -- sweep tried a non-round one.  The split keeps full precision
    -- without overflowing 32 bits on the large arguments.
    function ns_to_ck (ns : integer) return integer is
        variable q : integer := ns / 1000;
        variable r : integer := ns mod 1000;
    begin
        return ceil_div(q * CLK_KHZ, 1000) + ceil_div(r * CLK_KHZ, 1000000);
    end function;

    -- Same split, rounding DOWN, for the refresh interval.
    function ns_to_ck_floor (ns : integer) return integer is
        variable q : integer := ns / 1000;
        variable r : integer := ns mod 1000;
    begin
        return (q * CLK_KHZ) / 1000 + (r * CLK_KHZ) / 1000000;
    end function;

    constant C_RCD   : integer := ns_to_ck(tRCD_NS);
    constant C_RP    : integer := ns_to_ck(tRP_NS);
    constant C_RC    : integer := ns_to_ck(tRC_NS);
    constant C_RAS   : integer := ns_to_ck(tRAS_NS);
    constant C_INIT  : integer := ns_to_ck(INIT_PAUSE_NS);
    -- Refresh interval rounds DOWN: early is free, late is data loss.
    constant C_REFI  : integer := ns_to_ck_floor(tREFI_NS);

    -- Mode register, section 10.4.
    --   A2-A0 burst length 1, A3 sequential, A6-A4 CAS latency,
    --   A9 = 1 burst read and single write, everything else reserved 0.
    function mode_reg return std_logic_vector is
        variable v : std_logic_vector(12 downto 0) := (others => '0');
    begin
        v(2 downto 0) := "000";                 -- BL = 1
        v(3)          := '0';                   -- sequential
        if CAS_LATENCY = 2 then
            v(6 downto 4) := "010";
        else
            v(6 downto 4) := "011";
        end if;
        v(9) := '1';                            -- single write
        return v;
    end function;

    type state_t is (
        S_RESET, S_INIT_PAUSE, S_INIT_PRE, S_INIT_MRS, S_INIT_REF,
        S_IDLE, S_DISPATCH, S_PRECHARGE, S_ACTIVATE, S_READ, S_WRITE,
        S_REF_PRE, S_REFRESH, S_WAIT);
    signal state    : state_t := S_RESET;
    signal ret      : state_t := S_IDLE;

    signal wait_ct  : integer range 0 to C_INIT := 0;
    signal init_ct  : integer range 0 to 15    := 0;
    signal refi_ct  : integer range 0 to C_REFI := 0;
    signal ref_due  : std_logic := '0';

    type bank_row_t is array (0 to 3) of integer range 0 to 8191;
    type bank_age_t is array (0 to 3) of integer range 0 to 65535;
    signal row_open : std_logic_vector(3 downto 0) := (others => '0');
    signal open_row : bank_row_t := (others => 0);
    signal act_age  : bank_age_t := (others => 65535);

    -- latched request
    signal r_we     : std_logic := '0';
    signal r_bank   : integer range 0 to 3 := 0;
    signal r_row    : integer range 0 to 8191 := 0;
    signal r_col    : std_logic_vector(8 downto 0) := (others => '0');
    signal r_wdata  : std_logic_vector(15 downto 0) := (others => '0');
    signal r_be     : std_logic_vector(1 downto 0) := "11";
    signal req_pend : std_logic := '0';

    signal cmd_ras  : std_logic := '1';
    signal cmd_cas  : std_logic := '1';
    signal cmd_we   : std_logic := '1';
    signal o_ba     : std_logic_vector(1 downto 0)  := "00";
    signal o_a      : std_logic_vector(12 downto 0) := (others => '0');
    signal o_dq     : std_logic_vector(15 downto 0) := (others => '0');
    signal o_oe     : std_logic := '0';
    signal o_dqm    : std_logic_vector(1 downto 0) := "11";

    signal rd_pipe  : std_logic_vector(3 downto 0) := (others => '0');

begin

    ------------------------------------------------------------------
    -- CS0 low forever.  See the header.
    ------------------------------------------------------------------
    sd_cs_n  <= '0';
    sd_ras_n <= cmd_ras;
    sd_cas_n <= cmd_cas;
    sd_we_n  <= cmd_we;
    sd_ba    <= o_ba;
    sd_a     <= o_a;
    sd_ldqm  <= o_dqm(0);
    sd_udqm  <= o_dqm(1);
    sd_dq    <= o_dq when o_oe = '1' else (others => 'Z');

    -- ready no longer depends on ref_due.  It used to, and that was a
    -- RACE: the host sampled ready high, committed to the transfer,
    -- and a refresh fell due in the intervening cycle -- whereupon
    -- S_IDLE took the refresh branch and silently DROPPED the request.
    -- The host then waited for an ack that never came.  It presented
    -- as a hang whose appearance depended on clock rate, because the
    -- rate sets the phase between the refresh timer and the access
    -- stream.  On hardware that is an occasional unexplained lockup.
    -- A request is now always latched and always eventually served,
    -- and refresh still takes priority over serving it.
    ready <= '1' when state = S_IDLE and req_pend = '0' else '0';

    process (clk)
        variable bank : integer range 0 to 3;
    begin
        if rising_edge(clk) then

            -- default: NOP, and nothing acknowledged
            cmd_ras <= '1'; cmd_cas <= '1'; cmd_we <= '1';
            o_oe    <= '0';
            ack     <= '0';

            -- Refresh interval.  Free-running; the request is only
            -- cleared when a refresh is actually issued, so a refresh
            -- deferred by an in-flight access is never lost.
            if refi_ct >= C_REFI - 1 then
                refi_ct <= 0;
                ref_due <= '1';
            else
                refi_ct <= refi_ct + 1;
            end if;

            -- Row age, for tRAS(min) before any precharge.
            for b in 0 to 3 loop
                if act_age(b) < 65535 then
                    act_age(b) <= act_age(b) + 1;
                end if;
            end loop;

            -- Read data capture pipeline.  A read issued now lands
            -- CAS_LATENCY clocks later; the device drives the bus one
            -- clock earlier than that, so sampling sd_dq on the edge
            -- the token reaches stage 0 captures a stable word.
            rd_pipe <= '0' & rd_pipe(3 downto 1);
            if rd_pipe(0) = '1' then
                rdata <= sd_dq;
                ack   <= '1';
            end if;

            if rst_n = '0' then
                state   <= S_RESET;
                wait_ct <= 0; init_ct <= 0; refi_ct <= 0;
                ref_due <= '0';
                row_open <= (others => '0');
                req_pend <= '0';
                rd_pipe <= (others => '0');
                o_dqm   <= "11";
            else
                case state is

                    ------------------------------------------------
                    when S_RESET =>
                        -- 7.1: DQM and CKE high through the pause.
                        -- CKE is hardwired high on this module; DQM
                        -- is ours to hold.
                        o_dqm   <= "11";
                        wait_ct <= C_INIT;
                        state   <= S_INIT_PAUSE;

                    when S_INIT_PAUSE =>
                        if wait_ct = 0 then
                            state <= S_INIT_PRE;
                        else
                            wait_ct <= wait_ct - 1;
                        end if;

                    when S_INIT_PRE =>
                        cmd_ras <= '0'; cmd_cas <= '1'; cmd_we <= '0';
                        o_a     <= (10 => '1', others => '0');
                        row_open <= (others => '0');
                        wait_ct <= C_RP - 1;
                        ret     <= S_INIT_MRS;
                        state   <= S_WAIT;

                    when S_INIT_MRS =>
                        cmd_ras <= '0'; cmd_cas <= '0'; cmd_we <= '0';
                        o_ba    <= "00";
                        o_a     <= mode_reg;
                        wait_ct <= tRSC_CK - 1;
                        init_ct <= 0;
                        ret     <= S_INIT_REF;
                        state   <= S_WAIT;

                    when S_INIT_REF =>
                        cmd_ras <= '0'; cmd_cas <= '0'; cmd_we <= '1';
                        wait_ct <= C_RC - 1;
                        if init_ct >= INIT_REFRESH - 1 then
                            ret <= S_IDLE;
                        else
                            ret <= S_INIT_REF;
                        end if;
                        init_ct <= init_ct + 1;
                        state   <= S_WAIT;

                    ------------------------------------------------
                    when S_IDLE =>
                        o_dqm <= "00";
                        if req = '1' then
                            -- Accept unconditionally: ready promised it.
                            r_we    <= we;
                            r_bank  <= to_integer(unsigned(addr(10 downto 9)));
                            r_row   <= to_integer(unsigned(addr(23 downto 11)));
                            r_col   <= addr(8 downto 0);
                            r_wdata <= wdata;
                            r_be    <= be;
                            req_pend <= '1';
                            state   <= S_DISPATCH;
                        elsif ref_due = '1' then
                            state <= S_REF_PRE;
                        end if;

                    when S_DISPATCH =>
                        -- One cycle later, so the decision reads the
                        -- latched request rather than duplicating the
                        -- address decode across two paths.
                        if ref_due = '1' then
                            state <= S_REF_PRE;   -- request stays pending
                        elsif row_open(r_bank) = '1' and
                              open_row(r_bank) = r_row then
                            if r_we = '1' then state <= S_WRITE;
                            else                  state <= S_READ;  end if;
                        elsif row_open(r_bank) = '1' then
                            state <= S_PRECHARGE;
                        else
                            state <= S_ACTIVATE;
                        end if;

                    ------------------------------------------------
                    when S_PRECHARGE =>
                        -- tRAS(min) since the ACTIVE that opened it.
                        if act_age(r_bank) >= C_RAS then
                            cmd_ras <= '0'; cmd_cas <= '1'; cmd_we <= '0';
                            o_ba    <= std_logic_vector(to_unsigned(r_bank,2));
                            o_a     <= (others => '0');   -- A10 = 0
                            row_open(r_bank) <= '0';
                            wait_ct <= C_RP - 1;
                            ret     <= S_ACTIVATE;
                            state   <= S_WAIT;
                        end if;

                    when S_ACTIVATE =>
                        -- tRC since this bank was last activated.
                        if act_age(r_bank) >= C_RC then
                            cmd_ras <= '0'; cmd_cas <= '1'; cmd_we <= '1';
                            o_ba    <= std_logic_vector(to_unsigned(r_bank,2));
                            o_a     <= std_logic_vector(to_unsigned(r_row,13));
                            row_open(r_bank) <= '1';
                            open_row(r_bank) <= r_row;
                            act_age(r_bank)  <= 0;
                            wait_ct <= C_RCD - 1;
                            if r_we = '1' then ret <= S_WRITE;
                            else                  ret <= S_READ;  end if;
                            state   <= S_WAIT;
                        end if;

                    when S_READ =>
                        cmd_ras <= '1'; cmd_cas <= '0'; cmd_we <= '1';
                        o_ba    <= std_logic_vector(to_unsigned(r_bank,2));
                        o_a     <= (others => '0');
                        o_a(8 downto 0) <= r_col;        -- A10 = 0, no AP
                        o_dqm   <= "00";
                        -- Depth CAS_LATENCY, not CAS_LATENCY-1.  The
                        -- command register adds a cycle before the
                        -- device even sees the READ, and the device
                        -- then drives the bus one cycle before the
                        -- edge that captures it.  Sampling a cycle
                        -- early returns the previous word, which in a
                        -- back-to-back stream still looks like
                        -- plausible data.
                        rd_pipe(CAS_LATENCY) <= '1';
                        req_pend <= '0';
                        state   <= S_IDLE;

                    when S_WRITE =>
                        cmd_ras <= '1'; cmd_cas <= '0'; cmd_we <= '0';
                        o_ba    <= std_logic_vector(to_unsigned(r_bank,2));
                        o_a     <= (others => '0');
                        o_a(8 downto 0) <= r_col;
                        -- Data must be on DQ at the same edge as the
                        -- WRITE command (7.6), and DQM masks with zero
                        -- latency.  be(n)='1' writes lane n, so the
                        -- mask is its inverse.
                        o_dq    <= r_wdata;
                        o_oe    <= '1';
                        o_dqm   <= not r_be;
                        ack     <= '1';
                        req_pend <= '0';
                        state   <= S_IDLE;

                    ------------------------------------------------
                    when S_REF_PRE =>
                        -- AUTO REFRESH needs every bank idle.
                        if act_age(0) >= C_RAS and act_age(1) >= C_RAS and
                           act_age(2) >= C_RAS and act_age(3) >= C_RAS then
                            cmd_ras <= '0'; cmd_cas <= '1'; cmd_we <= '0';
                            o_a     <= (10 => '1', others => '0');
                            row_open <= (others => '0');
                            wait_ct <= C_RP - 1;
                            ret     <= S_REFRESH;
                            state   <= S_WAIT;
                        end if;

                    when S_REFRESH =>
                        cmd_ras <= '0'; cmd_cas <= '0'; cmd_we <= '1';
                        ref_due <= '0';
                        for b in 0 to 3 loop
                            act_age(b) <= 0;
                        end loop;
                        wait_ct <= C_RC - 1;
                        if req_pend = '1' then ret <= S_DISPATCH;
                        else                   ret <= S_IDLE;  end if;
                        state   <= S_WAIT;

                    ------------------------------------------------
                    when S_WAIT =>
                        if wait_ct = 0 then
                            state <= ret;
                        else
                            wait_ct <= wait_ct - 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
