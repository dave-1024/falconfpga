-- Minimal RTL bench for WF68K30L_TOP: 16-bit port, DSACK1 after 2 clocks,
-- AVEC on IACK, ROM at 0..7 (vectors) and $FC0000-$FEFFFF, RAM $0-$FFFF,
-- everything else: BERR. Logs every bus cycle.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all;
entity tb030 is
  generic (IPL_MODE : integer := 0;   -- 0 none, 1 level 2 always, 2 level 4 raised after write to $3400, 3 periodic 4/6
           IRQ_DLY  : integer := 0;   -- clocks after the $3400 write (mode 3: phase)
           IRQ_PER  : integer := 0;   -- mode 3: level 4 every IRQ_PER clocks (cleared on IACK)
           IRQ_PER6 : integer := 0;   -- mode 3: level 6 every IRQ_PER6 clocks (0 = off)
           MAXCLK   : integer := 4000;
           WS       : integer := 0;
           ST       : integer := 0;     -- 1: 4MB RAM, ROM alias at E0, I/O at FF8000 (FFFF), BERR at FF8C80
           STOPDONE : integer := 0;     -- 1: end the run 200 clocks after the DONE write
           QUIET    : integer := 0;     -- extra wait clocks per cycle
           ROMFILE  : string := "prog.hex";
           RAMFILE  : string := "";       -- ST=1: initial RAM image (hex words from $0), e.g. a Hatari snapshot
           RSSP     : integer := 0;       -- nonzero: reset SSP/PC read at 0..7 instead of the ROM vectors
           RPC      : integer := 0;
           VEC6     : integer := 0;       -- nonzero: level 6 IACK returns this vector number (MFP-like) instead of AVEC
           TRIG6    : integer := 0;       -- IPL_MODE=2: raise level 6 instead of level 4
           WSRND    : integer := 0;        -- extra random 0..WSRND wait clocks per cycle (seed IRQ_DLY)
           GAPLOG   : integer := 0;        -- [PH2] 1: log the clocks between AS negation and the next AS assertion
           RMCMON   : integer := 0;        -- [RMC1] 1: tag cycles run with RMCn low (" RMC") and log RMCn/ASn edges
           FASTH    : integer := 1;        -- [PH2] FAST_HANDOFF generic of the core (the board builds use 1)
           CIMODE   : integer := 0);       -- [IC] 0: CIINn asserted on every cycle (as the ST bridge). 1: negated for ROM
                                           -- $FD0000-$FEFFFF, RAM $8000-$FFFF and the BERR range $20000-$2FFFF (a fake cacheable region); log marks them " C".
                                           -- A word write to $3500 drives CDISn = not D16 (both modes).
                                          -- A word write to $3502 with D16 = 1 asserts CIIN on every cycle (CIMODE 1 overridden).
                                          -- [DC] A word write to $3504: reads of that RAM word ($xxxx, 0 = off) end with BERR.
end;
architecture sim of tb030 is
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal adr, din, dout : std_logic_vector(31 downto 0);
  signal fc : std_logic_vector(2 downto 0);
  signal siz, dsackn : std_logic_vector(1 downto 0) := "11";
  signal asn, rwn, dsn, berrn, avecn : std_logic := '1';
  signal ipl : std_logic_vector(2 downto 0) := "111";
  signal dbgx : std_logic_vector(104 downto 0);
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
  signal irq4, irq6 : std_logic := '0';
  signal iack_lvl : integer := 0;
  signal done : boolean := false;
  signal clkn : integer := 0;
  signal trig_at : integer := -1;
  signal iack_clr : boolean := false;
  signal ciinn : std_logic := '0'; -- [IC]
  signal rmcn : std_logic; -- [RMC1]
  signal cdisn : std_logic := '1'; -- [IC]
  signal ciforce : std_logic := '0'; -- [IC] 1: CIIN asserted on every cycle (word write to $3502, D16)
  signal berrw : integer := 0; -- [DC] RAM word whose reads bus-error (word write to $3504)
  -- [TT] 64 KB 32-bit port at $01000000 (DSACK1:0 = 00), cachable (CIIN negated), as the TTRAM bridge
  type tt_t is array (0 to 16383) of std_logic_vector(31 downto 0);
  shared variable ttm : tt_t := (others => (others => '0'));
begin
  clk <= not clk after 62.5 ns when not done;
  dut : entity work.WF68K30L_TOP generic map (FAST_HANDOFF => FASTH) port map (
    CLK => clk, ADR_OUT => adr, DATA_IN => din, DATA_OUT => dout, DATA_EN => open,
    BERRn => berrn, RESET_INn => rstn, RESET_OUT => reso, HALT_INn => rstn, HALT_OUTn => halto,
    DBG_EXC => dbgx, FC_OUT => fc, AVECn => avecn, IPLn => ipl, IPENDn => ipendn, DSACKn => dsackn, SIZE => siz,
    ASn => asn, RWn => rwn, RMCn => rmcn, DSn => dsn, ECSn => open, OCSn => open, DBENn => open,
    BUS_EN => open, STERMn => '1', STATUSn => open, REFILLn => open, BRn => '1', BGn => open, BGACKn => '1',
    CIINn => ciinn, CDISn => cdisn, CBACKn => '1', CBREQn => open, CIOUTn => open); -- [IC]

  process
    variable fired : boolean := false; variable last : boolean := false;
  begin
    wait until rising_edge(clk); clkn <= clkn + 1;
    if iack_clr /= last then
      if iack_lvl = 6 then irq6 <= '0'; else irq4 <= '0'; end if; last := iack_clr;
    elsif IPL_MODE = 3 then
      if IRQ_PER > 0 and clkn mod IRQ_PER = IRQ_DLY mod IRQ_PER then irq4 <= '1'; end if;
      if IRQ_PER6 > 0 and clkn mod IRQ_PER6 = (IRQ_DLY * 7) mod IRQ_PER6 then irq6 <= '1'; end if;
    elsif trig_at >= 0 and clkn >= trig_at and not fired then
      if TRIG6 /= 0 then irq6 <= '1'; else irq4 <= '1'; end if; fired := true; end if;
  end process;
  ipl <= "101" when IPL_MODE = 1 else "001" when irq6 = '1' else "011" when irq4 = '1' else "111";

  process
    variable a : unsigned(31 downto 0); variable w : std_logic_vector(15 downto 0);
    variable l : line; variable kind : string(1 to 4); variable wait_cnt : integer;
    variable n : integer := 0; variable isrom, isram, iack : boolean;
    variable wi : integer; variable isio : boolean; variable stop_at : integer := -1;
    file rf : text;
    variable lfsr : integer := 0; variable wr : integer;
    variable istt : boolean; variable ti, tn, tk : integer; variable tl : std_logic_vector(31 downto 0);
  begin
    if RAMFILE /= "" then
      file_open(rf, RAMFILE, read_mode); wi := 0;
      while not endfile(rf) and wi < 2097152 loop
        readline(rf, l); hread(l, w); ram(wi) := to_integer(unsigned(w)); wi := wi + 1;
      end loop;
      file_close(rf);
    end if;
    lfsr := IRQ_DLY + 1;
    wait for 20 us; rstn <= '1';
    loop
      wait until rising_edge(clk); n := n + 1;
      if stop_at > 0 and n > stop_at then done <= true; wait; end if;
      if n > MAXCLK then
        write(l, string'("TIMEOUT at clk ")); write(l, n); writeline(output, l); done <= true; wait;
      end if;
      if asn = '0' then
        a := unsigned(adr); if ST = 1 then a(31 downto 24) := x"00"; end if;
        iack := fc = "111" and a(19 downto 16) = x"F";
        isrom := (a < 8) or (a >= x"00FC0000" and a < x"00FF0000") or (ST = 1 and a >= x"00E00000" and a < x"00E40000");
        isram := (a >= 8 and a < x"00010000") or (ST = 1 and a >= 8 and a < x"00400000");
        isio  := ST = 1 and ((a >= x"00FF8000" and a <= x"00FFFFFF" and a(23 downto 4) /= x"FF8C8") or (a >= x"00FA0000" and a < x"00FC0000"));
        wi := to_integer(a(21 downto 1));
        istt := fc /= "111" and a(31 downto 16) = x"0100"; ti := to_integer(a(15 downto 2));
        if berrw /= 0 and rwn = '1' and isram and to_integer(a(15 downto 1)) = berrw / 2 and a(31 downto 16) = x"0000" then
          isram := false; -- [DC]
        end if;
        -- [IC] cache inhibit for this cycle
        if istt then
          ciinn <= '1';
        elsif CIMODE = 1 and ciforce = '0' and ((a >= x"00FD0000" and a < x"00FF0000") or (a >= x"00008000" and a < x"00010000") or
                            (a >= x"00020000" and a < x"00030000")) then -- (the last range is BERR: a faulting cacheable fetch)
          ciinn <= '1';
        else
          ciinn <= '0';
        end if;
        -- data
        if isrom then
          if a < 8 and RSSP /= 0 then
            case to_integer(a(2 downto 1)) is
              when 0 => w := std_logic_vector(to_unsigned(RSSP / 65536, 16));
              when 1 => w := std_logic_vector(to_unsigned(RSSP mod 65536, 16));
              when 2 => w := std_logic_vector(to_unsigned(RPC / 65536, 16));
              when others => w := std_logic_vector(to_unsigned(RPC mod 65536, 16));
            end case;
          elsif a < 8 then w := rom(to_integer(a(2 downto 1)));
          elsif a >= x"00FC0000" then w := rom(to_integer(a - x"00FC0000") / 2);
          else w := rom(to_integer(a(17 downto 1))); end if;
        elsif isram then w := std_logic_vector(to_unsigned(ram(wi), 16));
        elsif ST = 1 and (a(23 downto 3) = "111111111111101000100" or a(23 downto 1) = "11111111111110100001111") then
          -- MFP timer A/B/C/D data ($FFFA1F-$FFFA25) count down ([MINT] TOS/MiNT poll timer B data for a change)
          w := std_logic_vector(to_unsigned((255 - (n / 64) mod 256) * 257, 16));
        elsif ST = 1 and (a(23 downto 1) = "11111111111111000000000" or a(23 downto 1) = "11111111111111000000010") then
          w := x"0202"; -- [MINT] (see below)
        elsif ST = 1 and a(23 downto 1) = "11111111100000100110000" then
          w := x"0000"; -- [MINT] shifter mode $FF8260 = low res (FFFF = res 3: the VBL handler saw a monitor change and reset)
        elsif ST = 1 and a(23 downto 1) = "11111111111110100000000" then
          w := x"FFDF"; -- [MINT] MFP GPIP: bit 5 low = FDC/HDC done at once (no FDC model; TOS would wait for its timeout)
        elsif ST = 1 and a(23 downto 1) = "11111111100001100000010" then
          w := x"0000"; -- [MINT] FDC/DMA data $FF8604: FDC status 0 (no error)
        elsif ST = 1 and a(23 downto 1) = "11111111100001100000011" then
          w := x"0001"; -- [MINT] DMA status $FF8606: bit 0 = no DMA error
        elsif false then
          w := x"0202"; -- [MINT] ACIA $FFFC00/$FFFC04 status: transmit empty, nothing received (FFFF looked like a key stream)
        else w := x"FFFF"; end if;
        if WSRND > 0 then
          lfsr := (lfsr * 75 + 74) mod 65537; wr := (lfsr / 7) mod (WSRND + 1);
        else wr := 0; end if;
        for k in 1 to 2 + WS + wr loop wait until rising_edge(clk); n := n + 1; end loop;
        din <= w & w;
        if istt then
          tl := ttm(ti); din <= tl; w := tl(31 downto 16);
          if rwn = '0' then
            if siz = "00" then tn := 4; else tn := to_integer(unsigned(siz)); end if;
            for k in 0 to 3 loop
              if k >= to_integer(a(1 downto 0)) and k < to_integer(a(1 downto 0)) + tn then
                tl(31 - 8*k downto 24 - 8*k) := dout(31 - 8*k downto 24 - 8*k);
              end if;
            end loop;
            ttm(ti) := tl;
          end if;
        end if;
        if rwn = '0' and isram then
          if siz = "01" or a(0) = '1' then -- [TT] odd address: one byte (UDS/LDS), any SIZ
            if a(0) = '0' then ram(wi) := to_integer(unsigned(dout(31 downto 24))) * 256 + (ram(wi) mod 256);
            else ram(wi) := (ram(wi) / 256) * 256 + to_integer(unsigned(dout(23 downto 16))); end if;
          else ram(wi) := to_integer(unsigned(dout(31 downto 16))); end if;
          if a = x"00003500" then cdisn <= not dout(16); end if; -- [IC]
          if a = x"00003502" then ciforce <= dout(16); end if; -- [IC]
          if a = x"00003504" then berrw <= to_integer(unsigned(dout(31 downto 16))); end if; -- [DC]
          if a = x"00003400" then
            if IPL_MODE = 2 then trig_at <= clkn + IRQ_DLY; end if;
          end if;
          if a = x"00003300" then
            write(l, string'("DONE marker write at clk ")); write(l, n); writeline(output, l);
            if STOPDONE = 1 then stop_at := n + 200; end if;
          end if;
        end if;
        if iack and VEC6 /= 0 and a(3 downto 1) = "110" then
          w := std_logic_vector(to_unsigned(VEC6, 16)); din <= w & w; dsackn <= "01"; iack_lvl <= 6; iack_clr <= not iack_clr;
        elsif iack then avecn <= '0'; iack_lvl <= to_integer(a(3 downto 1)); iack_clr <= not iack_clr;
        elsif istt then dsackn <= "00";
        elsif isrom or isram or isio then dsackn <= "01";
        else berrn <= '0'; end if;
        -- log
        if iack then kind := "IACK"; elsif fc(1 downto 0) = "10" then kind := "PROG";
        elsif rwn = '1' then kind := "RD  "; else kind := "WR  "; end if;
        write(l, n, right, 6); write(l, string'(" ")); write(l, kind); write(l, string'(" A=")); hwrite(l, adr);
        write(l, string'(" FC=")); write(l, to_integer(unsigned(fc))); write(l, string'(" SIZ=")); write(l, to_integer(unsigned(siz)));
        if rwn = '1' and istt then write(l, string'(" D=")); hwrite(l, tl);
        elsif rwn = '1' then write(l, string'(" D=")); hwrite(l, w); else write(l, string'(" W=")); hwrite(l, dout); end if;
        write(l, string'(" IPL=")); write(l, to_integer(unsigned(not ipl)));
        if istt then write(l, string'(" TT")); end if;
        if not (isrom or isram or iack or isio or istt) then write(l, string'(" BERR")); end if;
        if CIMODE /= 0 and ciinn = '1' then write(l, string'(" C")); end if; -- [IC] (signal set before the wait clocks)
        if RMCMON /= 0 and rmcn = '0' then write(l, string'(" RMC")); end if; -- [RMC1]
        if QUIET = 0 or not (fc(1 downto 0) = "10" and (a >= x"00FC0000" or QUIET = 2)) then writeline(output, l); else deallocate(l); end if;
        wait until asn = '1';
        dsackn <= "11"; berrn <= '1'; avecn <= '1'; ciinn <= '0';
      end if;
    end loop;
  end process;
  -- [RMC1] RMCn / ASn edge log (time in ns) for the read-modify-write timing check.
  rmcmon_p : process(rmcn, asn)
    variable l : line;
  begin
    if RMCMON /= 0 and now > 0 ns then
      if rmcn'event then write(l, string'("EDGE RMCn=")); write(l, std_logic'image(rmcn)); write(l, string'(" t=")); write(l, now / 1 ns); writeline(output, l); end if;
      if asn'event and rmcn = '0' then write(l, string'("EDGE ASn=")); write(l, std_logic'image(asn)); write(l, string'(" t=")); write(l, now / 1 ns); writeline(output, l); end if;
    end if;
  end process;
  -- FalconFPGA DIAG: log the core's exception report (DBG_EXC) on its rising strobe
  exmon: process
    variable l : line; variable d : std_logic := '0'; variable wd : std_logic := '0';
  begin
    wait until rising_edge(clk);
    if dbgx(104) = '1' and d = '0' then
      write(l, string'("EXC vec=")); write(l, to_integer(unsigned(dbgx(103 downto 96))));
      write(l, string'(" SR=")); hwrite(l, dbgx(95 downto 80)); write(l, string'(" PC=")); hwrite(l, dbgx(79 downto 48));
      write(l, string'(" BIW0=")); hwrite(l, dbgx(15 downto 0)); writeline(output, l);
    end if;
    if asn = '0' and rwn = '0' and wd = '0' then
      write(l, string'("WPC PC=")); hwrite(l, dbgx(79 downto 48)); write(l, string'(" A=")); hwrite(l, adr); writeline(output, l);
    end if;
    wd := not asn and not rwn;
    d := dbgx(104);
  end process;
  -- [PH2] Bus gap monitor: counts the rising clock edges on which AS is negated between two
  -- cycles. One edge (the S5 half) = back to back, as on a 68030; each idle clock adds one.
  -- Logged as GAP <edges> <previous kind> <next kind> (P = program space, D = data).
  gapmon: process
    variable l : line; variable cnt : integer := -1; variable pk, nk : character := 'D';
  begin
    wait until rising_edge(clk);
    if GAPLOG /= 0 then
      if fc(1 downto 0) = "10" then nk := 'P'; else nk := 'D'; end if;
      if asn = '1' and cnt >= 0 then cnt := cnt + 1;
      elsif asn = '0' and cnt > 0 then
        write(l, string'("GAP ")); write(l, cnt); write(l, string'(" ")); write(l, pk); write(l, nk); writeline(output, l);
        cnt := 0;
      elsif asn = '0' then cnt := 0; pk := nk; end if;
      if asn = '0' then pk := nk; end if;
    end if;
  end process;
end;
