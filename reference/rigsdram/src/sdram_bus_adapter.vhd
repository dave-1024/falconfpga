----------------------------------------------------------------------
-- sdram_bus_adapter.vhd
--
-- Bridges the WF68K30L's asynchronous 68030 bus to sdram_ctrl.
--
-- ------------------------------------------------------------------
-- PORT WIDTH: 16 BITS, DELIBERATELY
--
--   DSACKn is driven "01" -- a 16-bit port.  The CPU then does its own
--   dynamic bus sizing and splits longwords into two word transfers,
--   which is exactly what a real Falcon's ST-RAM does.  Assembling
--   longwords in the adapter and answering "00" would be faster and
--   would be wrong: the guest would see a timing profile no Falcon
--   ever had, and the difference would surface later as software that
--   works here and not on the real machine.
--
-- ------------------------------------------------------------------
-- BYTE LANES
--
--   The SDRAM word at word-address W holds the 68000-order bytes at
--   byte addresses 2W (upper lane, DQ15:8) and 2W+1 (lower lane,
--   DQ7:0).  On a 16-bit port the CPU uses D31:D24 for the even byte
--   and D23:D16 for the odd byte.  So:
--
--     be = "11"   word    wdata <= DATA_OUT(31 downto 16)
--     be = "10"   even byte at A0=0, on D31:D24 -> upper lane
--     be = "01"   odd  byte at A0=1, on D23:D16 -> lower lane
--
--   A0=1 can only ever move one byte on a 16-bit port, whatever SIZE
--   says; the CPU re-runs the cycle for the rest.
--
-- ------------------------------------------------------------------
-- CLOCK DOMAINS, and why this is not really a crossing
--
--   The CPU runs on core_clk, which is clk50 divided by four in
--   fabric -- so the two are phase locked, not asynchronous, and no
--   metastability is possible.  What IS possible is a signal changing
--   on the same clk50 edge the CPU samples it.  So the adapter drives
--   its CPU-facing outputs (DSACKn, DATA_IN) only on the clk50 edge
--   marked by cpu_upd, chosen two clk50 cycles before the edge the CPU
--   captures on -- which is core_clk FALLING, the 68030's sampling
--   edge for DSACKn and the data bus.  See rigsdram_top.vhd: aiming
--   cpu_upd at the rising edge instead left every adapter-to-CPU path
--   with launch and capture coincident.
--
--   Do NOT replace this with a two-flop synchroniser out of habit.  It
--   would add latency to every bus cycle for a hazard that does not
--   exist here.
--
-- ------------------------------------------------------------------
--   sdram_ctrl's contract is one outstanding transaction and req held
--   until ready -- both natural here, because a 68030 bus cycle is
--   strictly one at a time and ASn stays low until DSACKn answers.
----------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_bus_adapter is
    port (
        clk       : in  std_logic;      -- clk50, the SDRAM domain
        rst_n     : in  std_logic;

        -- 68030 side
        sel       : in  std_logic;      -- address decode says this is ours
        ASn       : in  std_logic;
        RWn       : in  std_logic;
        SIZE      : in  std_logic_vector(1 downto 0);
        ADR       : in  std_logic_vector(24 downto 0);  -- byte address
        DATA_OUT  : in  std_logic_vector(31 downto 0);
        -- LEVEL handshake back to the core_clk bus process, which
        -- registers it and drives DSACKn itself.  The adapter no longer
        -- touches any CPU-facing signal directly: the previous version
        -- drove DSACKn from clk50 on a phase-picked strobe aimed at
        -- core_clk's RISING edge, and the 68030 samples DSACKn on the
        -- FALLING edge.  Handing a level to the other domain and letting
        -- it register the crossing removes that whole class of error.
        done      : out std_logic;
        rdata_out : out std_logic_vector(15 downto 0);

        -- controller side
        req       : out std_logic;
        we        : out std_logic;
        addr      : out std_logic_vector(23 downto 0);
        wdata     : out std_logic_vector(15 downto 0);
        be        : out std_logic_vector(1 downto 0);
        rdata     : in  std_logic_vector(15 downto 0);
        ack       : in  std_logic;
        ready     : in  std_logic
    );
end entity sdram_bus_adapter;


architecture rtl of sdram_bus_adapter is

    type st_t is (S_IDLE, S_REQ, S_WAITACK, S_RESPOND, S_DONE);
    signal st      : st_t := S_IDLE;

    signal hold_d  : std_logic_vector(15 downto 0) := (others => '0');
    signal done_i  : std_logic := '0';
    signal as_q    : std_logic := '1';
    -- req is mirrored internally because the handshake has to test
    -- req's CURRENT value, and a port cannot be read in VHDL-93.
    signal req_i   : std_logic := '0';

begin

    -- DSACKn is QUALIFIED BY ASn, the way a real memory controller
    -- does it.  Without this gate the adapter was still holding DSACK
    -- asserted from the previous cycle when the CPU started the next
    -- one, so the second half of a longword terminated instantly with
    -- the first half's data still latched -- the write was never
    -- issued and the read returned the previous word.  It looked like
    -- a byte-lane fault and was nothing of the kind.
    --
    -- Only the ASSERTION of DSACK needs the safe clock phase.  Its
    -- release does not: the CPU has already latched by then, and
    -- releasing late is what breaks back-to-back cycles.
    done      <= done_i;
    rdata_out <= hold_d;
    req     <= req_i;

    process (clk)
        variable ben : std_logic_vector(1 downto 0);
    begin
        if rising_edge(clk) then
            as_q <= ASn;

            if rst_n = '0' then
                st      <= S_IDLE;
                req_i   <= '0';
                done_i  <= '0';
            else
                case st is

                    when S_IDLE =>
                        req_i <= '0';
                        if sel = '1' and ASn = '0' then
                            -- Byte lane decode.  A0 = 1 can only ever
                            -- carry one byte on a 16-bit port.
                            if ADR(0) = '1' then
                                ben := "01";
                            elsif SIZE = "01" then
                                ben := "10";
                            else
                                ben := "11";
                            end if;
                            be    <= ben;
                            addr  <= ADR(24 downto 1);
                            we    <= not RWn;
                            case ben is
                                when "10" =>
                                    wdata <= DATA_OUT(31 downto 24) & x"00";
                                when "01" =>
                                    wdata <= x"00" & DATA_OUT(23 downto 16);
                                when others =>
                                    wdata <= DATA_OUT(31 downto 16);
                            end case;
                            st <= S_REQ;
                        end if;

                    when S_REQ =>
                        -- Hold req until taken.  Sampling ready and
                        -- then pulsing would lose the request to a
                        -- refresh; see the contract in sdram_ctrl.
                        --
                        -- req_i must be tested at its CURRENT value,
                        -- not the one being assigned this cycle.  The
                        -- first version wrote req <= '1' and then, in
                        -- the same cycle, req <= '0' when ready was
                        -- already high -- the later assignment won,
                        -- the controller never saw a request, and the
                        -- adapter waited forever for an ack that could
                        -- not come.  The CPU then hung with ASn low.
                        req_i <= '1';
                        if req_i = '1' and ready = '1' then
                            req_i <= '0';
                            st    <= S_WAITACK;
                        end if;

                    when S_WAITACK =>
                        if ack = '1' then
                            hold_d <= rdata;
                            st     <= S_RESPOND;
                        end if;

                    when S_RESPOND =>
                        -- Just raise a level.  The core_clk bus process
                        -- samples it and drives DSACKn itself, so the
                        -- domain crossing is registered on the receiving
                        -- side and no phase picking is needed.
                        done_i <= '1';
                        st     <= S_DONE;

                    when S_DONE =>
                        -- ASn rising ends the cycle.
                        if ASn = '1' then
                            done_i <= '0';
                            st     <= S_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
