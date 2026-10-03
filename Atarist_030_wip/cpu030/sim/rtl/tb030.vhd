-- Minimal RTL bench for WF68K30L_TOP: 16-bit port, DSACK1 after 2 clocks,
-- AVEC on IACK, ROM at 0..7 (vectors) and $FC0000-$FEFFFF, RAM $0-$FFFF,
-- everything else: BERR. Logs every bus cycle.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all;
entity tb030 is
  generic (IPL_MODE : integer := 0;   -- 0 none, 1 level 2 always, 2 level 4 raised after write to $3400
           IRQ_DLY  : integer := 0;   -- clocks after the $3400 write
           MAXCLK   : integer := 4000;
           WS       : integer := 0;
           ST       : integer := 0;     -- 1: 4MB RAM, ROM alias at E0, I/O at FF8000 (FFFF), BERR at FF8C80
           QUIET    : integer := 0;     -- extra wait clocks per cycle
           ROMFILE  : string := "prog.hex");
end;
architecture sim of tb030 is
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal adr, din, dout : std_logic_vector(31 downto 0);
  signal fc : std_logic_vector(2 downto 0);
  signal siz, dsackn : std_logic_vector(1 downto 0) := "11";
  signal asn, rwn, dsn, berrn, avecn : std_logic := '1';
  signal ipl : std_logic_vector(2 downto 0) := "111";
  signal halto, reso, ipendn : std_logic;
  type mem_t is array (0 to 131071) of std_logic_vector(15 downto 0);  -- 256K ROM
  type ram_t is array (0 to 2097151) of integer range 0 to 65535;      -- 4MB RAM
  impure function load return mem_t is
    file f : text open read_mode is ROMFILE; variable l : line; variable m : mem_t := (others => x"FFFF");
    variable i : integer := 0; variable v : std_logic_vector(15 downto 0);
  begin
    while not endfile(f) and i < 131072 loop readline(f, l); hread(l, v); m(i) := v; i := i + 1; end loop;
    return m;
  end;
  signal rom : mem_t := load;
  shared variable ram : ram_t := (others => 0);
  signal cyc : integer := 0;
  signal irq4 : std_logic := '0';
  signal done : boolean := false;
  signal clkn : integer := 0;
  signal trig_at : integer := -1;
  signal iack_clr : boolean := false;
begin
  clk <= not clk after 62.5 ns when not done;
  dut : entity work.WF68K30L_TOP port map (
    CLK => clk, ADR_OUT => adr, DATA_IN => din, DATA_OUT => dout, DATA_EN => open,
    BERRn => berrn, RESET_INn => rstn, RESET_OUT => reso, HALT_INn => rstn, HALT_OUTn => halto,
    FC_OUT => fc, AVECn => avecn, IPLn => ipl, IPENDn => ipendn, DSACKn => dsackn, SIZE => siz,
    ASn => asn, RWn => rwn, RMCn => open, DSn => dsn, ECSn => open, OCSn => open, DBENn => open,
    BUS_EN => open, STERMn => '1', STATUSn => open, REFILLn => open, BRn => '1', BGn => open, BGACKn => '1');

  process
    variable fired : boolean := false; variable last : boolean := false;
  begin
    wait until rising_edge(clk); clkn <= clkn + 1;
    if iack_clr /= last then irq4 <= '0'; last := iack_clr;
    elsif trig_at >= 0 and clkn >= trig_at and not fired then irq4 <= '1'; fired := true; end if;
  end process;
  ipl <= "101" when IPL_MODE = 1 else "011" when irq4 = '1' else "111";

  process
    variable a : unsigned(31 downto 0); variable w : std_logic_vector(15 downto 0);
    variable l : line; variable kind : string(1 to 4); variable wait_cnt : integer;
    variable n : integer := 0; variable isrom, isram, iack : boolean;
    variable wi : integer; variable isio : boolean;
  begin
    wait for 20 us; rstn <= '1';
    loop
      wait until rising_edge(clk); n := n + 1;
      if n > MAXCLK then
        write(l, string'("TIMEOUT at clk ")); write(l, n); writeline(output, l); done <= true; wait;
      end if;
      if asn = '0' then
        a := unsigned(adr); if ST = 1 then a(31 downto 24) := x"00"; end if;
        iack := fc = "111" and a(19 downto 16) = x"F";
        isrom := (a < 8) or (a >= x"00FC0000" and a < x"00FF0000") or (ST = 1 and a >= x"00E00000" and a < x"00E30000");
        isram := (a >= 8 and a < x"00010000") or (ST = 1 and a >= 8 and a < x"00400000");
        isio  := ST = 1 and ((a >= x"00FF8000" and a <= x"00FFFFFF" and a(23 downto 4) /= x"FF8C8") or (a >= x"00FA0000" and a < x"00FC0000"));
        wi := to_integer(a(21 downto 1));
        -- data
        if isrom then
          if a < 8 then w := rom(to_integer(a(2 downto 1)));
          elsif a >= x"00FC0000" then w := rom(to_integer(a - x"00FC0000") / 2);
          else w := rom(to_integer(a(17 downto 1))); end if;
        elsif isram then w := std_logic_vector(to_unsigned(ram(wi), 16));
        else w := x"FFFF"; end if;
        for k in 1 to 2 + WS loop wait until rising_edge(clk); n := n + 1; end loop;
        din <= w & w;
        if rwn = '0' and isram then
          if siz = "01" then
            if a(0) = '0' then ram(wi) := to_integer(unsigned(dout(31 downto 24))) * 256 + (ram(wi) mod 256);
            else ram(wi) := (ram(wi) / 256) * 256 + to_integer(unsigned(dout(23 downto 16))); end if;
          else ram(wi) := to_integer(unsigned(dout(31 downto 16))); end if;
          if a = x"00003400" then
            if IPL_MODE = 2 then trig_at <= clkn + IRQ_DLY; end if;
          end if;
          if a = x"00003300" then
            write(l, string'("DONE marker write at clk ")); write(l, n); writeline(output, l);
          end if;
        end if;
        if iack then avecn <= '0'; iack_clr <= not iack_clr;
        elsif isrom or isram or isio then dsackn <= "01";
        else berrn <= '0'; end if;
        -- log
        if iack then kind := "IACK"; elsif fc(1 downto 0) = "10" then kind := "PROG";
        elsif rwn = '1' then kind := "RD  "; else kind := "WR  "; end if;
        write(l, n, right, 6); write(l, string'(" ")); write(l, kind); write(l, string'(" A=")); hwrite(l, adr);
        write(l, string'(" FC=")); write(l, to_integer(unsigned(fc))); write(l, string'(" SIZ=")); write(l, to_integer(unsigned(siz)));
        if rwn = '1' then write(l, string'(" D=")); hwrite(l, w); else write(l, string'(" W=")); hwrite(l, dout); end if;
        write(l, string'(" IPL=")); write(l, to_integer(unsigned(not ipl)));
        if not (isrom or isram or iack or isio) then write(l, string'(" BERR")); end if;
        if QUIET = 0 or not (fc(1 downto 0) = "10" and a >= x"00FC0000") then writeline(output, l); else deallocate(l); end if;
        wait until asn = '1';
        dsackn <= "11"; berrn <= '1'; avecn <= '1';
      end if;
    end loop;
  end process;
end;
