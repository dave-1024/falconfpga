-- =====================================================================
-- rigsdram_top.vhd -- FalconFPGA RIGSDRAM. Soft 68030 + SDRAM.
--
-- DERIVED BY PATCHING rigrev2_top.vhd, NOT BY REWRITING IT.  The first
-- attempt was a hand-port that compressed the proven bus process, and
-- it dropped the acked/region pipeline, the BERRn default slave and the
-- 8-bit port window.  It then failed on silicon in a way that survived
-- pulling the SDRAM module entirely -- so the fault was in the parts I
-- had retyped, not in anything to do with SDRAM.  Everything below is
-- RIGREV2 verbatim except the clearly marked SDRAM additions.
--
-- This is the synthesisable form of the GHDL bench that verified the
-- core: same memory map, same peripherals, same guest binary. Written
-- in VHDL so GHDL can simulate the ACTUAL fabric rather than a model
-- of it -- the sim and the bitstream are the same source.
--
--   $000000-$00FFFF  64K RAM, 32-bit port  (BSRAM, guest pre-loaded)
--   $2000000-$3FFFFFF 32MB SDRAM, 16-bit port (DSACKn="01")   [ADDED]
--   $F00000          UART TX, 8-bit port   (write = transmit, throttled)
--   $F00004          run-complete latch    (LED goes solid)
--   $F00010          IRQ controller        (level/mode/uninit/hold)
--   FC=7, A19:16=F   interrupt acknowledge
--   everything else  default slave -> BERRn
--
-- Boot broker: RESET_INn AND HALT_INn are driven low TOGETHER for well
-- over the 16 clocks RESET_FILTER requires. Holding RESET_INn alone
-- does NOT start this core -- that cost a simulation session to learn
-- and is the first thing to check if the terminal stays silent.
--
-- Core clock is CLK/4 = 12.5 MHz, exact 50% duty. Below the 22.169 MHz
-- synthesis Fmax with wide margin; speed is irrelevant to a sanity run.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.RIGGUEST_PKG.all;
use work.BUS_TRACE_PKG.all;   -- [TRACE]

entity RIGSDRAM_TOP is
    generic(
        CORE_HZ    : integer := 12_500_000;
        BAUD       : integer := 38400;
        RAM_WAIT   : integer := 2;
        DEFSLV_WAIT: integer := 4;
        CLK_HZ     : integer := 50_000_000;   -- [ADDED]
        CAS_LATENCY: integer := 3;            -- [ADDED]
        REFI_NS    : integer := 7812;         -- [ADDED]
        -- [COLD] 0 = measure (default).  After init+128 clocks the CPU
        -- is released once and the timeout tracer dumps the first cycles.
        -- 1 = ship workaround: after that first release, wait AW_FREE
        -- core clocks then pulse CPU reset again.  Warm reset already
        -- boots; this just does it without a finger on S1.
        -- Do NOT enable both a live dump (TRIG_MODE/=3) and AUTO_WARM=1
        -- in the same flash -- the second pulse re-arms the tracer and
        -- you will capture the *working* path.
        AUTO_WARM  : integer := 0;   -- [H48] trial: prove/disprove PLL-lock
                                     -- CDC as the cold-boot fault.  Oracle
                                     -- shipped 1.  If this bitstream cold-
                                     -- boots, leave at 0.  If it fails,
                                     -- revert this file (tag oracle).
        AW_FREE    : integer := 256
    );
    port(
        CLK       : in  std_logic;                     -- V22, 50 MHz
        RSTN      : in  std_logic;                     -- AA13, optional
        WARMN     : in  std_logic;                     -- AB13 (S1), ACTIVE LOW
                                                       -- [WARM] CPU-only reset
        UART2_TXD : out std_logic;                     -- U15
        -- [ADDED] UART2_RXD dropped.  RIGREV2 declares it and never reads
        -- it, so synthesis trims the port and the .cst constraint on V14
        -- then fails with CT1135 "Can't find object named 'UART2_RXD'".
        -- Better to not declare a pin we do not use than to constrain a
        -- port that will be optimised away.
        -- [COLD] 1-bit only.  The flashing .cst constrains LED[0] (V13).
        -- A 3-bit port leaves LED[1]/LED[2] unconstrained; Gowin will
        -- place them on arbitrary balls.  Do not re-widen this without
        -- matching IO_LOC lines.
        LED       : out std_logic_vector(0 downto 0);  -- V13, ACTIVE LOW
        -- [ADDED] SDRAM, J9 / SDRAM0
        O_sdram_clk   : out   std_logic;
        O_sdram_cs_n  : out   std_logic;
        O_sdram_ras_n : out   std_logic;
        O_sdram_cas_n : out   std_logic;
        O_sdram_wen_n : out   std_logic;
        O_sdram_ba    : out   std_logic_vector(1 downto 0);
        O_sdram_addr  : out   std_logic_vector(12 downto 0);
        O_sdram_dqm   : out   std_logic_vector(1 downto 0);
        IO_sdram_dq   : inout std_logic_vector(15 downto 0)
    );
end entity RIGSDRAM_TOP;

architecture RTL of RIGSDRAM_TOP is

    constant BAUD_DIV : integer := CORE_HZ / BAUD;     -- 325 @12.5 MHz

    -- clocking / reset -------------------------------------------------
    -- [F43] core_clk and clk50 now come from a PLL (Gowin_PLL), NOT from
    -- a fabric /4 counter.  The counter made core_clk a logic net that
    -- the timing tool modelled as a clock edge at t=0 while clocking the
    -- flop 2.68 ns later -- the -0.415 ns hold path on the divider's own
    -- feedback in the pre-PLL build.  It also left the controller and
    -- adapter on the raw CLK pin, phase-unrelated to core_clk, which is
    -- where the two real -0.13 ns hold paths into the adapter came from.
    -- Both outputs from one PLL are de-skewed together, so every fourth
    -- clk50 edge coincides with a core_clk edge by construction.
    signal core_clk  : std_logic;          -- 12.5 MHz, PLL CLKOUT1
    signal clk50     : std_logic;          -- 50 MHz,   PLL CLKOUT0
    signal pll_lock  : std_logic;

    -- [TRACE] cold-boot capture. On a cold boot the guest never reaches its
    -- UART writes (that is the fault), so the tracer has the UART to itself
    -- -- no contention. Captures from reset, stops when the ring is full,
    -- then freezes the CPU and dumps.
    signal cpu_tx_load : std_logic := '0';
    signal cpu_tx_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal trc_tx_load : std_logic;
    signal trc_tx_byte : std_logic_vector(7 downto 0);
    signal trc_active  : std_logic;
    signal trc_halt    : std_logic;
    signal trc_v       : std_logic;
    signal trc_r       : TRC_T;

    -- [WARM] CPU-only warm reset. Asserting this resets ONLY the 68030 --
    -- the PLL stays locked, the SDRAM controller keeps running (no
    -- re-init, no 200 us pause), and BSRAM contents are untouched. So the
    -- CPU re-runs its reset sequence from SETTLED fabric state instead of
    -- from arbitrary power-up state.
    --
    -- DIAGNOSTIC PURPOSE: every silicon boot so far has been a COLD boot,
    -- so we have never separated "power-up flop state" from "reset
    -- sequencing". This does:
    --   warm reset BOOTS      -> fault is power-up state; the fix must be
    --                            in what the BITSTREAM initialises.
    --   warm reset FAILS same -> power-up state exonerated; the fault is
    --                            in the reset sequence itself.
    signal warm_sync : std_logic_vector(2 downto 0) := "111";
    signal warm_req  : std_logic := '0';
    signal warm_cnt  : unsigned(7 downto 0) := (others => '0');
    signal por_cnt   : unsigned(15 downto 0) := (others => '0');
    signal por_n     : std_logic := '0';
    signal rstn_sync : std_logic_vector(2 downto 0) := "000";
    -- [H48] pll_lock is made on clk_ref inside pll_init.  Using it
    -- combinationally as reset into clk50 / core_clk was the 28-hold
    -- launch (state_1_s0 -> SET/RESET/CE).  Two-flop sync per domain.
    signal pll_lock_50    : std_logic_vector(1 downto 0) := "00";
    signal sys_rst_pipe   : std_logic_vector(1 downto 0) := "00";
    signal sys_rst_n_50   : std_logic := '0';
    signal sys_rst_n      : std_logic := '0';  -- core_clk domain

    component Gowin_PLL
        port ( clkin    : in  std_logic;
               init_clk : in  std_logic;
               clkout0  : out std_logic;
               clkout1  : out std_logic;
               lock     : out std_logic );
    end component;

    signal sd_sel    : std_logic;
    signal sd_done   : std_logic;
    signal sd_rdata  : std_logic_vector(15 downto 0);
    signal s_req, s_we, s_ack, s_ready : std_logic;
    signal s_addr    : std_logic_vector(23 downto 0);
    signal s_wdata   : std_logic_vector(15 downto 0);
    signal s_rd      : std_logic_vector(15 downto 0);
    signal s_be      : std_logic_vector(1 downto 0);
    signal init_done : std_logic := '0';

    -- boot broker ------------------------------------------------------
    signal brk_cnt   : unsigned(7 downto 0) := (others => '0');
    -- [COLD] automatic second CPU reset.  AW_WAIT is the original broker.
    type AW_ST_T is (AW_WAIT, AW_FREE_RUN, AW_PULSE, AW_DONE);
    signal aw_st     : AW_ST_T := AW_WAIT;
    signal aw_cnt    : unsigned(8 downto 0) := (others => '0');
    signal cpu_rst_n : std_logic := '1';  -- [F53] starts DEASSERTED so the
    -- first clocked evaluation drives it low = a real falling edge into
    -- reset, instead of it simply powering up already-low with no edge.
    signal cpu_halt_n: std_logic := '1';  -- [F53] ditto

    -- CPU pins ---------------------------------------------------------
    signal ADR_OUT   : std_logic_vector(31 downto 0);
    signal DATA_IN   : std_logic_vector(31 downto 0) := (others => '0');
    signal DATA_OUT  : std_logic_vector(31 downto 0);
    signal DATA_EN   : std_logic;
    signal BERRn     : std_logic := '1';
    signal RESET_OUT : std_logic;
    signal HALT_OUTn : std_logic;
    signal FC_OUT    : std_logic_vector(2 downto 0);
    signal AVECn     : std_logic := '1';
    signal IPLn      : std_logic_vector(2 downto 0) := "111";
    signal IPENDn    : std_logic;
    signal DSACKn    : std_logic_vector(1 downto 0) := "11";
    signal SIZE      : std_logic_vector(1 downto 0);
    signal ASn, RWn, RMCn, DSn, ECSn, OCSn, DBENn, BUS_EN : std_logic;
    signal STERMn    : std_logic := '1';
    signal STATUSn, REFILLn, BGn : std_logic;

    -- RAM --------------------------------------------------------------
    signal l0 : LANE_T := GUEST_L0;
    signal l1 : LANE_T := GUEST_L1;
    signal l2 : LANE_T := GUEST_L2;
    signal l3 : LANE_T := GUEST_L3;
    signal rd0, rd1, rd2, rd3 : std_logic_vector(7 downto 0);
    -- 8-bit peripheral window at $F00020 (32 bytes), mirrors the sim rig
    type M8_T is array (0 to 31) of std_logic_vector(7 downto 0);
    signal m8 : M8_T := (others => x"00");

    -- UART -------------------------------------------------------------
    signal tx_div   : unsigned(11 downto 0) := (others => '0');
    signal tx_sh    : std_logic_vector(9 downto 0) := (others => '1');
    signal tx_bit   : unsigned(3 downto 0) := (others => '0');
    signal tx_busy  : std_logic := '0';
    signal tx_line  : std_logic := '1';
    signal tx_load  : std_logic := '0';
    signal tx_byte  : std_logic_vector(7 downto 0) := (others => '0');

    -- IRQ controller ---------------------------------------------------
    signal irq_level : unsigned(2 downto 0) := "000";
    signal irq_mode  : std_logic_vector(1 downto 0) := "00";
    signal irq_uninit: std_logic := '0';
    signal irq_hold  : std_logic := '0';
    signal irq_clear : std_logic := '0';

    -- bus sequencer ----------------------------------------------------
    signal wsc    : unsigned(3 downto 0) := (others => '0');
    signal acked  : std_logic := '0';
    signal region   : integer range 0 to 7 := 3;
    signal berr_count : unsigned(15 downto 0) := (others => '0');
    signal run_done   : std_logic := '0';
    signal led_div    : unsigned(23 downto 0) := (others => '0');
    signal led_r      : std_logic := '0';

    function vecbyte(lvl : unsigned(2 downto 0); un : std_logic)
        return std_logic_vector is
    begin
        if un = '1' then
            return x"0F";
        else
            return std_logic_vector(to_unsigned(16#40# + to_integer(lvl), 8));
        end if;
    end function;

begin

    -- [WARM] button synchroniser + one-shot. Button is ACTIVE LOW with an
    -- internal pull-up: idle = '1', pressed = '0'. Held low, warm_req stays
    -- asserted; on release it extends for 128 core clocks so the core's own
    -- RESET_FILTER (which needs RESET_IN and HALT_In together for >10
    -- clocks) is comfortably satisfied.
    process(core_clk)
    begin
        if rising_edge(core_clk) then
            warm_sync <= warm_sync(1 downto 0) & WARMN;
            if warm_sync(2) = '0' then          -- pressed (active low)
                warm_req <= '1';
                warm_cnt <= (others => '0');
            elsif warm_cnt /= x"80" then        -- extend 128 clocks after release
                warm_cnt <= warm_cnt + 1;
                warm_req <= '1';
            else
                warm_req <= '0';
            end if;
        end if;
    end process;

    -- ---------------- clock / reset ---------------------------------
    u_pll: Gowin_PLL
        port map ( clkin    => CLK,        -- 50 MHz input, pin V22
                   init_clk => CLK,        -- init clock = the input clock
                   clkout0  => clk50,      -- 50   MHz
                   clkout1  => core_clk,   -- 12.5 MHz
                   lock     => pll_lock );

    -- POR and the RSTN synchroniser run on clk50 (always toggling once
    -- the PLL locks).  [H48] pll_lock is synced two flops on clk50
    -- before it enters sys_rst_n_50; that reset is then synced two
    -- flops on core_clk before it enters sys_rst_n.  Do not AND raw
    -- pll_lock into either domain.
    process(clk50)
    begin
        if rising_edge(clk50) then
            if por_cnt /= x"FFFF" then
                por_cnt <= por_cnt + 1;
                por_n   <= '0';
            else
                por_n   <= '1';
            end if;
            rstn_sync    <= rstn_sync(1 downto 0) & RSTN;
            pll_lock_50  <= pll_lock_50(0) & pll_lock;
            sys_rst_n_50 <= por_n and rstn_sync(2) and pll_lock_50(1);
        end if;
    end process;

    process(core_clk)
    begin
        if rising_edge(core_clk) then
            sys_rst_pipe <= sys_rst_pipe(0) & sys_rst_n_50;
            sys_rst_n    <= sys_rst_pipe(1);
        end if;
    end process;

    -- ---------------- boot broker -----------------------------------
    -- RESET_INn AND HALT_INn low together, 128 core clocks (>= 16).
    process(core_clk)
    begin
        if rising_edge(core_clk) then
            if sys_rst_n = '0' then
                -- [H48] lock is already inside sys_rst_n (synced).
                -- Raw pll_lock must not appear in this process.
                brk_cnt    <= (others => '0');
                cpu_rst_n  <= '0';
                cpu_halt_n <= '0';
                aw_st      <= AW_WAIT;
                aw_cnt     <= (others => '0');
            elsif warm_req = '1' then
                -- [WARM] CPU-only reset. Deliberately does NOT clear
                -- brk_cnt and does NOT wait on init_done again, so the
                -- SDRAM controller is left running and this is a genuine
                -- warm reset rather than a cold boot with extra steps.
                cpu_rst_n  <= '0';
                cpu_halt_n <= '0';
            elsif aw_st = AW_FREE_RUN then
                cpu_rst_n  <= '1';
                cpu_halt_n <= '1';
                if aw_cnt = to_unsigned(AW_FREE, 9) then
                    aw_st  <= AW_PULSE;
                    aw_cnt <= (others => '0');
                else
                    aw_cnt <= aw_cnt + 1;
                end if;
            elsif aw_st = AW_PULSE then
                cpu_rst_n  <= '0';
                cpu_halt_n <= '0';
                if aw_cnt = to_unsigned(128, 9) then
                    aw_st <= AW_DONE;
                else
                    aw_cnt <= aw_cnt + 1;
                end if;
            elsif aw_st = AW_DONE then
                cpu_rst_n  <= '1';
                cpu_halt_n <= '1';
            elsif init_done = '0' or brk_cnt /= x"80" then
                -- [ADDED] also wait for the SDRAM controller, so the guest
                -- can never touch it during the mandatory 200 us pause.
                -- brk_cnt only advances once the SDRAM is up, so the
                -- post-init hold is a full 128 core clocks either way.
                if init_done = '1' then brk_cnt <= brk_cnt + 1; end if;
                cpu_rst_n  <= '0';
                cpu_halt_n <= '0';
            else
                cpu_rst_n  <= '1';
                cpu_halt_n <= '1';
                if AUTO_WARM /= 0 then
                    aw_st  <= AW_FREE_RUN;
                    aw_cnt <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- ---------------- the CPU ---------------------------------------
    U_CPU: entity work.WF68K30L_TOP
        port map(
            CLK => core_clk, ADR_OUT => ADR_OUT, DATA_IN => DATA_IN,
            DATA_OUT => DATA_OUT, DATA_EN => DATA_EN,
            BERRn => BERRn, RESET_INn => cpu_rst_n, RESET_OUT => RESET_OUT,
            HALT_INn => cpu_halt_n, HALT_OUTn => HALT_OUTn, FC_OUT => FC_OUT,
            AVECn => AVECn, IPLn => IPLn, IPENDn => IPENDn,
            DSACKn => DSACKn, SIZE => SIZE, ASn => ASn, RWn => RWn,
            RMCn => RMCn, DSn => DSn, ECSn => ECSn, OCSn => OCSn,
            DBENn => DBENn, BUS_EN => BUS_EN, STERMn => STERMn,
            STATUSn => STATUSn, REFILLn => REFILLn,
            BRn => '1', BGn => BGn, BGACKn => '1'
        );

    IPLn <= not std_logic_vector(irq_level);
    UART2_TXD <= tx_line;
    -- [DIAG] LED[0] only (V13), ACTIVE LOW.  pll_lock already proven.
    -- The dump is the measurement.
    LED(0) <= not pll_lock;

    -- [COLD] rst_n is cpu_rst_n, NOT sys_rst_n.  A warm button press
    -- (and AUTO_WARM's second pulse) must re-arm the tracer; sys_rst_n
    -- stays high through both.  STOP_AFTER=16 / TIMEOUT=2000 is the
    -- measurement that was missing: dump what you have, including
    -- nothing.  HALT_ON_DUMP=1 freezes the CPU only AFTER capture
    -- (halt_req is '1' when st /= S_RUN).  Capture itself is live.
    -- Freeze is what keeps the guest off the UART during the dump,
    -- including on S1 / a surprisingly-alive cold path.
    U_TRC: entity work.BUS_TRACE
        -- [PRODUCT] TRIG_MODE => 3: the tracer CAPTURES but never stops, so it
        -- never dumps and never touches the UART. The guest owns the port.
        -- Required with AUTO_WARM=1: a live dump plus a second reset pulse
        -- would re-arm the tracer on the path that already works.
        generic map (DEPTH => 512, TRIG_MODE => 3, POST => 0,
                     HALT_ON_DUMP => 1, STOP_AFTER => 16, TIMEOUT => 2000)
        port map (clk => core_clk, rst_n => cpu_rst_n,
                  ASn => ASn, RWn => RWn, BERRn => BERRn, AVECn => AVECn,
                  DSACKn => DSACKn, SIZE => SIZE, FC => FC_OUT,
                  ADR => ADR_OUT, D_OUT => DATA_OUT, D_IN => DATA_IN,
                  HALTn => HALT_OUTn,
                  tx_busy => tx_busy,
                  tx_load => trc_tx_load, tx_byte => trc_tx_byte,
                  active => trc_active, halt_req => trc_halt,
                  trc_valid => trc_v, trc_rec => trc_r);

    -- [TRACE] Once the tracer goes active it OWNS the UART outright; the
    -- guest's writes are discarded rather than interleaved. On the cold boot
    -- we are debugging the guest never writes anything anyway, so this only
    -- matters in simulation (where the guest DOES talk and would otherwise
    -- garble the dump).
    tx_load <= trc_tx_load when trc_active = '1' else cpu_tx_load;
    tx_byte <= trc_tx_byte when trc_active = '1' else cpu_tx_byte;

    -- ---------------- [ADDED] SDRAM ---------------------------------
    -- 32 MB at a 32 MB boundary, so the word address is just ADR_OUT(24:1).
    sd_sel <= '1' when ADR_OUT(31 downto 25) = "0000001" else '0';

    O_sdram_clk <= not clk50;   -- [F43] was not CLK

    U_ADP: entity work.sdram_bus_adapter
        port map(clk => clk50, rst_n => sys_rst_n_50,  -- [H48] clk50 domain
                 sel => sd_sel, ASn => ASn, RWn => RWn, SIZE => SIZE,
                 ADR => ADR_OUT(24 downto 0), DATA_OUT => DATA_OUT,
                 done => sd_done, rdata_out => sd_rdata,
                 req => s_req, we => s_we, addr => s_addr,
                 wdata => s_wdata, be => s_be, rdata => s_rd,
                 ack => s_ack, ready => s_ready);

    U_SDR: entity work.sdram_ctrl
        generic map(CLK_KHZ => CLK_HZ/1000, CAS_LATENCY => CAS_LATENCY,
                    tREFI_NS => REFI_NS)
        port map(clk => clk50, rst_n => sys_rst_n_50,  -- [H48] clk50 domain
                 req => s_req, we => s_we, addr => s_addr,
                 wdata => s_wdata, be => s_be, rdata => s_rd,
                 ack => s_ack, ready => s_ready,
                 sd_cs_n => O_sdram_cs_n, sd_ras_n => O_sdram_ras_n,
                 sd_cas_n => O_sdram_cas_n, sd_we_n => O_sdram_wen_n,
                 sd_ba => O_sdram_ba, sd_a => O_sdram_addr,
                 sd_dq => IO_sdram_dq,
                 sd_ldqm => O_sdram_dqm(0), sd_udqm => O_sdram_dqm(1));

    -- ready first rises only after precharge-all, MRS and eight refreshes.
    -- On clk50 [F43]: it samples s_ready from the controller, which now
    -- runs on clk50, so sampling it on any other clock would be a new CDC.
    process(clk50)
    begin
        if rising_edge(clk50) then
            if sys_rst_n_50 = '0' then init_done <= '0';
            elsif s_ready = '1'   then init_done <= '1'; end if;
        end if;
    end process;

    -- ---------------- UART transmitter ------------------------------
    process(core_clk)
    begin
        if rising_edge(core_clk) then
            if sys_rst_n = '0' then
                tx_busy <= '0'; tx_line <= '1'; tx_div <= (others => '0');
                tx_bit  <= (others => '0'); tx_sh <= (others => '1');
            elsif tx_busy = '0' then
                tx_line <= '1';
                if tx_load = '1' then
                    tx_sh   <= '1' & tx_byte & '0';
                    tx_bit  <= (others => '0');
                    tx_div  <= (others => '0');
                    tx_busy <= '1';
                end if;
            else
                if tx_div = to_unsigned(BAUD_DIV - 1, 12) then
                    tx_div  <= (others => '0');
                    tx_line <= tx_sh(0);
                    tx_sh   <= '1' & tx_sh(9 downto 1);
                    if tx_bit = x"9" then
                        tx_busy <= '0';
                    else
                        tx_bit <= tx_bit + 1;
                    end if;
                else
                    tx_div <= tx_div + 1;
                end if;
            end if;
        end if;
    end process;

    -- ---------------- LED heartbeat (pre-completion) ----------------
    process(core_clk)
    begin
        if rising_edge(core_clk) then
            if led_div = to_unsigned(CORE_HZ/2 - 1, 24) then
                led_div <= (others => '0');
                led_r   <= not led_r;
            else
                led_div <= led_div + 1;
            end if;
        end if;
    end process;

    -- ---------------- bus sequencer + peripherals -------------------
    process(core_clk)
        variable a    : integer;
        variable wa   : integer;
        variable w8   : integer;
        variable sz   : integer;
        variable vb   : std_logic_vector(7 downto 0);
        variable rgn  : integer range 0 to 7;  -- 7 = 8-bit window
    begin
        if rising_edge(core_clk) then
            cpu_tx_load <= '0';

            if sys_rst_n = '0' then
                DSACKn <= "11"; BERRn <= '1'; AVECn <= '1';
                wsc <= (others => '0'); acked <= '0';
                berr_count <= (others => '0'); run_done <= '0';
                irq_level <= "000"; irq_clear <= '0';

            elsif ASn = '0' then
                a  := to_integer(unsigned(ADR_OUT(23 downto 0)));
                wa := to_integer(unsigned(ADR_OUT(15 downto 2)));
                w8 := to_integer(unsigned(ADR_OUT(4 downto 0)));

                if FC_OUT = "111" and ADR_OUT(19 downto 16) = x"F" then
                    rgn := 5;                              -- IACK
                elsif sd_sel = '1' then
                    -- [ADDED] MUST be tested before the RAM arm: `a` is only
                    -- ADR_OUT(23:0), so $2000000 masks to 0 and would have
                    -- decoded as RAM.
                    rgn := 6;                              -- SDRAM
                elsif a <= 16#00FFFF# then
                    rgn := 0;                              -- RAM
                elsif a >= 16#F00000# and a <= 16#F00003# then
                    rgn := 1;                              -- UART
                elsif a >= 16#F00004# and a <= 16#F00007# then
                    rgn := 2;                              -- run-complete
                elsif a >= 16#F00010# and a <= 16#F00013# then
                    rgn := 4;                              -- IRQ control
                elsif a >= 16#F00020# and a <= 16#F0003F# then
                    rgn := 7;                              -- 8-bit port RAM
                else
                    rgn := 3;                              -- default slave
                end if;
                region <= rgn;

                -- registered RAM read; address is stable while ASn low
                rd0 <= l0(wa); rd1 <= l1(wa);
                rd2 <= l2(wa); rd3 <= l3(wa);

                if rgn = 0 then
                    DATA_IN <= rd0 & rd1 & rd2 & rd3;
                elsif rgn = 6 then
                    -- [ADDED] 16-bit port: the word rides D31:D16 and the
                    -- lower half is poisoned so a wrong-lane sample FAILS
                    -- rather than passing, same convention as rgn 7.
                    DATA_IN <= sd_rdata & x"EEEE";
                elsif rgn = 7 then
                    -- Table 7-5: an 8-bit port connects to D31:D24 ONLY, so the
                    -- addressed byte always rides the top lane. D23:0 poisoned
                    -- so a wrong-lane sample FAILS instead of passing.
                    DATA_IN <= m8(w8) & x"EEEEEE";
                elsif rgn = 5 and irq_mode /= "00" and irq_mode /= "11"
                      and unsigned(ADR_OUT(3 downto 1)) = irq_level
                      and irq_level /= "000" then
                    vb := vecbyte(irq_level, irq_uninit);
                    if irq_mode = "10" then
                        DATA_IN <= vb & x"EEEEEE";         -- 8-bit port
                    else
                        case ADR_OUT(1 downto 0) is        -- 32-bit lanes
                            when "00"   => DATA_IN <= vb & x"EEEEEE";
                            when "01"   => DATA_IN <= x"EE" & vb & x"EEEE";
                            when "10"   => DATA_IN <= x"EEEE" & vb & x"EE";
                            when others => DATA_IN <= x"EEEEEE" & vb;
                        end case;
                    end if;
                else
                    DATA_IN <= x"FFFFFFFF";
                end if;

                if acked = '0' then
                    case rgn is

                    when 6 =>                               -- [ADDED] SDRAM
                        -- The adapter runs on clk50 and presents a LEVEL.
                        -- Sampling it here registers the handoff into
                        -- core_clk, so nothing the CPU sees is ever driven
                        -- from the other domain.  That removes the whole
                        -- edge-alignment problem the first version tried to
                        -- solve with a phase-picked update strobe -- and got
                        -- wrong, because the 68030 samples DSACKn on the
                        -- FALLING edge.  Costs up to one core_clk of extra
                        -- latency per access; the CPU is waiting anyway.
                        if sd_done = '1' then
                            DSACKn <= "01";                 -- 16-bit port
                            acked  <= '1';
                        end if;

                    when 3 =>                               -- default slave
                        if wsc >= to_unsigned(DEFSLV_WAIT, 4) then
                            BERRn      <= '0';
                            acked      <= '1';
                            berr_count <= berr_count + 1;
                        else
                            wsc <= wsc + 1;
                        end if;

                    when 5 =>                               -- IACK
                        if unsigned(ADR_OUT(3 downto 1)) = irq_level
                           and irq_level /= "000" then
                            case irq_mode is
                            when "00" =>                    -- autovector
                                AVECn <= '0'; acked <= '1';
                                if irq_hold = '0' then irq_clear <= '1'; end if;
                            when "11" =>                    -- spurious
                                if wsc >= to_unsigned(DEFSLV_WAIT, 4) then
                                    BERRn <= '0'; acked <= '1';
                                    if irq_hold = '0' then irq_clear <= '1'; end if;
                                else
                                    wsc <= wsc + 1;
                                end if;
                            when others =>                  -- vectored
                                if wsc >= to_unsigned(RAM_WAIT, 4) then
                                    if irq_mode = "10" then
                                        DSACKn <= "10";
                                    else
                                        DSACKn <= "00";
                                    end if;
                                    acked <= '1';
                                    if irq_hold = '0' then irq_clear <= '1'; end if;
                                else
                                    wsc <= wsc + 1;
                                end if;
                            end case;
                        else
                            if wsc >= to_unsigned(DEFSLV_WAIT, 4) then
                                BERRn <= '0'; acked <= '1';
                            else
                                wsc <= wsc + 1;
                            end if;
                        end if;

                    when 1 =>                               -- UART, throttled
                        if RWn = '0' then
                            if tx_busy = '0' and cpu_tx_load = '0' then
                                cpu_tx_byte <= DATA_OUT(31 downto 24);
                                cpu_tx_load <= '1';
                                DSACKn  <= "10";
                                acked   <= '1';
                            end if;
                        else
                            DSACKn <= "10"; acked <= '1';
                        end if;

                    when 2 =>                               -- run complete
                        if RWn = '0' then run_done <= '1'; end if;
                        DSACKn <= "10"; acked <= '1';

                    when 7 =>                               -- 8-bit port RAM
                        -- One byte per cycle on D31:D24. The CPU splits its own
                        -- word/longword accesses, which is the point: this
                        -- window is what V14 uses to prove the byte-wide
                        -- peripheral path the Falcon's MFP/ACIA/PSG/FDC need.
                        if RWn = '0' then
                            m8(w8) <= DATA_OUT(31 downto 24);
                        end if;
                        DSACKn <= "10"; acked <= '1';

                    when 4 =>                               -- IRQ control
                        if RWn = '0' then
                            irq_level  <= unsigned(DATA_OUT(26 downto 24));
                            irq_mode   <= DATA_OUT(28 downto 27);
                            irq_uninit <= DATA_OUT(29);
                            irq_hold   <= DATA_OUT(30);
                        end if;
                        DSACKn <= "10"; acked <= '1';

                    when others =>                          -- RAM
                        if wsc >= to_unsigned(RAM_WAIT, 4) then
                            if RWn = '0' then
                                case SIZE is
                                    when "01"   => sz := 1;
                                    when "10"   => sz := 2;
                                    when "11"   => sz := 3;
                                    when others => sz := 4;
                                end case;
                                for k in 0 to 3 loop
                                    if k >= (a mod 4) and
                                       k < (a mod 4) + sz then
                                        case k is
                                        when 0 => l0(wa) <= DATA_OUT(31 downto 24);
                                        when 1 => l1(wa) <= DATA_OUT(23 downto 16);
                                        when 2 => l2(wa) <= DATA_OUT(15 downto 8);
                                        when others => l3(wa) <= DATA_OUT(7 downto 0);
                                        end case;
                                    end if;
                                end loop;
                            end if;
                            DSACKn <= "00";
                            acked  <= '1';
                        else
                            wsc <= wsc + 1;
                        end if;

                    end case;
                end if;

            else                                            -- ASn high
                DSACKn <= "11"; BERRn <= '1'; AVECn <= '1';
                wsc <= (others => '0'); acked <= '0';
                if irq_clear = '1' then
                    irq_level <= "000";
                    irq_clear <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture RTL;