-- tb_falcon.vhd - FAL_01: behavioural Falcon030 bus around the shared WF68K30L core
--
-- FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Purpose: run Atari TOS 4.04 (512K, base $E00000) from reset on the cycle-tuned
-- WF68K30L (Atarist_030_wip/hdl/cpu030, shared by path, not copied) and log what
-- TOS probes, to find what the Falcon RTL must answer before the board build.
-- Behaviour follows reference/Hybrid030/hybrid_musashi/falcon_m28.c (which booted
-- TOS 4.04 under Musashi) and Hatari:
--   $000000-$000007  ROM vector mirror (reads)        16-bit port, DSACK1
--   $000008-$DFFFFF  14 MB ST-RAM                      16-bit port, DSACK1
--   $E00000-$E7FFFF  TOS ROM (writes ignored)
--   $FA0000-$FBFFFF  cartridge: reads $FFFF
--   $FF8000-$FFFFFF  IO, also at $FFFF8000-: whitelist of Falcon registers
--                    (latch, reset value $FF), anything else BERR
--   everything else  BERR
-- NVRAM (MC146818) at $FF8961/$FF8963 with a valid checksum, VGA monitor in $FF8006,
-- VBL autovector level 4 at 60 Hz, MFP timer C level 6 (vector from MFP VR) at 200 Hz.
-- Logs: IO accesses (first LOGIO lines), BERRs, exceptions, a PC heartbeat.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all;
entity tb_falcon is
  generic (MAXCLK  : integer := 2000000;
           ROMFILE : string  := "tos404.hex";
           LOGIO   : integer := 3000;
           HEART   : integer := 100000;
           VBLPER  : integer := 266667;  -- 16 MHz / 60
           TCPER   : integer := 80000;   -- 16 MHz / 200
           IRQON   : integer := 1;
           MEMCODE : integer := 5);  -- $FF8006 RAM size code TOS 4.04 reads: 5 = 14 MB, else 512K << code (sim: 1 = 1 MB, faster)
end;
architecture sim of tb_falcon is
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal adr, din, dout : std_logic_vector(31 downto 0);
  signal fc : std_logic_vector(2 downto 0);
  signal siz, dsackn : std_logic_vector(1 downto 0) := "11";
  signal asn, rwn, dsn, berrn, avecn : std_logic := '1';
  signal ipl : std_logic_vector(2 downto 0) := "111";
  signal dbgx : std_logic_vector(104 downto 0);
  signal halto, reso, ipendn, rmcn : std_logic;
  type rom_t is array (0 to 262143) of std_logic_vector(15 downto 0);  -- 512K
  impure function load return rom_t is
    file f : text open read_mode is ROMFILE; variable l : line; variable m : rom_t := (others => x"FFFF");
    variable i : integer := 0; variable v : std_logic_vector(15 downto 0);
  begin
    while not endfile(f) and i < 262144 loop readline(f, l); hread(l, v); m(i) := v; i := i + 1; end loop;
    return m;
  end;
  signal rom : rom_t := load;
  type ram_t is array (0 to 7340031) of integer range 0 to 65535;      -- 14 MB
  shared variable ram : ram_t := (others => 0);
  type io_t is array (0 to 32767) of integer range 0 to 255;           -- $FF8000-$FFFFFF byte shadow
  shared variable io : io_t := (others => 255);
  type nv_t is array (0 to 63) of integer range 0 to 255;
  shared variable nv : nv_t := (others => 0);
  shared variable nvsel : integer := 0;
  signal done : boolean := false;
  signal clkn : integer := 0;
  signal vbl_p, tc_p : std_logic := '0';
  signal vbl_ack, tc_ack : boolean := false;
  function nat(v : std_logic_vector) return integer is
    variable u : std_logic_vector(v'length - 1 downto 0) := (others => '0'); variable s : std_logic_vector(v'length - 1 downto 0);
  begin s := v; for i in s'range loop if s(i) = '1' then u(i) := '1'; end if; end loop; return to_integer(unsigned(u)); end;
  -- Falcon IO whitelist (falcon_m28.c falcon_io_valid), r = low 16 bits
  function io_ok(r : integer) return boolean is
  begin
    return (r >= 16#8000# and r <= 16#800F#) or (r >= 16#8200# and r <= 16#8211#) or
           (r >= 16#8240# and r <= 16#826F#) or (r >= 16#8280# and r <= 16#82C7#) or
           (r >= 16#8604# and r <= 16#860F#) or (r >= 16#8780# and r <= 16#878F#) or
           (r >= 16#8800# and r <= 16#88FF#) or (r >= 16#8900# and r <= 16#897F#) or
           (r >= 16#8A00# and r <= 16#8A3D#) or (r >= 16#8C80# and r <= 16#8C87#) or
           (r >= 16#9200# and r <= 16#921F#) or (r >= 16#9800# and r <= 16#9BFF#) or
           (r >= 16#A200# and r <= 16#A207#) or (r >= 16#FA00# and r <= 16#FA3F#) or
           (r >= 16#FC00# and r <= 16#FC07#);
  end;
begin
  clk <= not clk after 31.25 ns when not done;   -- 16 MHz
  dut : entity work.WF68K30L_TOP generic map (FAST_HANDOFF => 1) port map (
    CLK => clk, ADR_OUT => adr, DATA_IN => din, DATA_OUT => dout, DATA_EN => open,
    BERRn => berrn, RESET_INn => rstn, RESET_OUT => reso, HALT_INn => rstn, HALT_OUTn => halto,
    DBG_EXC => dbgx, FC_OUT => fc, AVECn => avecn, IPLn => ipl, IPENDn => ipendn, DSACKn => dsackn, SIZE => siz,
    ASn => asn, RWn => rwn, RMCn => rmcn, DSn => dsn, ECSn => open, OCSn => open, DBENn => open,
    BUS_EN => open, STERMn => '1', STATUSn => open, REFILLn => open, BRn => '1', BGn => open, BGACKn => '1',
    CIINn => '0', CDISn => '1', CBACKn => '1', CBREQn => open, CIOUTn => open);

  -- interrupt sources: VBL = level 4 autovector; MFP timer C = level 6 vectored
  irq : process
  begin
    wait until rising_edge(clk); clkn <= clkn + 1;
    if IRQON /= 0 and clkn > 0 and clkn mod VBLPER = 0 then vbl_p <= '1'; end if;
    -- timer C pending only when enabled+unmasked in IERB/IMRB bit 5 ($FFFA09/$FFFA15)
    if IRQON /= 0 and clkn > 0 and clkn mod TCPER = 0 and (io(16#7A09#) / 32) mod 2 = 1 and (io(16#7A15#) / 32) mod 2 = 1 then tc_p <= '1'; end if;
    if vbl_ack then vbl_p <= '0'; end if;
    if tc_ack then tc_p <= '0'; end if;
  end process;
  ipl <= "001" when tc_p = '1' else "011" when vbl_p = '1' else "111";

  bus_p : process
    variable a : unsigned(31 downto 0); variable a24 : integer; variable r : integer;
    variable w : std_logic_vector(15 downto 0); variable l : line;
    variable n : integer := 0; variable nio : integer := 0; variable nberr : integer := 0;
    variable isrom, isram, isio, iscart, iack, ok : boolean; variable wi, b, s : integer;
    variable lastpc : unsigned(31 downto 0) := (others => '0');
    variable hb : integer := 0; variable kind : string(1 to 2);
    procedure nv_init is variable sum : integer := 0; begin
      nv(10) := 16#26#; nv(11) := 16#02#; nv(13) := 16#80#;
      nv(6) := 7; nv(7) := 1; nv(8) := 1; nv(9) := 16#26#;
      nv(14+14) := 16#00#; nv(14+15) := 16#1A#;   -- video mode word (NVRAM 28/29): VGA|80COL|4 bpl = $001A
      for i in 14 to 61 loop sum := (sum + nv(i)) mod 256; end loop;
      nv(62) := 255 - sum; nv(63) := sum;
    end;
    impure function rdb(r : integer; n : integer) return integer is begin
      if r = 16#8006# then return 16#80# + (MEMCODE mod 2) * 2 + (MEMCODE / 2) * 8; end if;  -- b7:6 monitor 10 = VGA; b1 + b4:3 = RAM size code (TOS 4.04 $E0013A)
      if r = 16#8961# then return nvsel; end if;
      if r = 16#8963# then if nvsel = 12 then return 0; end if; return nv(nvsel); end if;
      if r = 16#FC00# then return 16#02#; end if;                -- kbd ACIA: TDRE, nothing received
      if r = 16#FC04# then return 16#02#; end if;                -- MIDI ACIA
      if r >= 16#FA00# and r <= 16#FA3F# then
        if r mod 2 = 0 then return 255; end if;
        if r = 16#FA01# then return 16#FF#; end if;              -- GPIP: all inactive (mono-detect 1 = colour)
        if r = 16#FA1F# or r = 16#FA21# or r = 16#FA23# or r = 16#FA25# then return 255 - (n / 64) mod 256; end if;
        return io(r - 16#8000#);
      end if;
      if r = 16#8607# then return 1; end if;                     -- DMA status: no error
      if r = 16#8605# then return 0; end if;                     -- FDC status 0
      if r = 16#A202# then return 16#06#; end if;                -- DSP host ISR: TXDE|TRDY
      return io(r - 16#8000#);
    end;
    procedure wrb(r : integer; v : integer) is begin
      if r = 16#8961# then nvsel := v mod 64; return; end if;
      if r = 16#8963# then if nvsel /= 12 and nvsel /= 13 then nv(nvsel) := v; end if; return; end if;
      io(r - 16#8000#) := v;
    end;
  begin
    nv_init;
    wait for 4 us; rstn <= '1';
    loop
      wait until rising_edge(clk); n := n + 1;
      if n > MAXCLK then
        write(l, string'("TIMEOUT at clk ")); write(l, n); write(l, string'(" lastPC=")); hwrite(l, std_logic_vector(lastpc));
        write(l, string'(" io=")); write(l, nio); write(l, string'(" berr=")); write(l, nberr); writeline(output, l);
        done <= true; wait;
      end if;
      if n >= hb then
        hb := hb + HEART;
        write(l, string'("HB clk=")); write(l, n); write(l, string'(" PC~")); hwrite(l, std_logic_vector(lastpc)); writeline(output, l);
      end if;
      if asn = '0' then
        a := unsigned(adr);
        iack := fc = "111";
        a24 := to_integer(a(23 downto 0));
        ok := a(31 downto 24) = x"00" or a(31 downto 24) = x"FF";
        isrom := ok and ((a24 < 8 and rwn = '1') or (a24 >= 16#E00000# and a24 < 16#E80000#));
        isram := ok and a(31 downto 24) = x"00" and a24 >= 8 and a24 < 16#E00000#;
        iscart := ok and a24 >= 16#FA0000# and a24 < 16#FC0000#;
        r := to_integer(a(15 downto 0));
        isio := ok and a24 >= 16#FF8000# and io_ok(r);
        if fc(1 downto 0) = "10" then lastpc := a; end if;
        w := x"FFFF";
        if iack then null;
        elsif isrom then
          if a24 < 8 then w := rom(a24 / 2); else w := rom((a24 - 16#E00000#) / 2); end if;
        elsif isram then
          wi := a24 / 2; w := std_logic_vector(to_unsigned(ram(wi), 16));
          if rwn = '0' then
            if siz = "01" or a(0) = '1' then
              if a(0) = '0' then ram(wi) := nat(dout(31 downto 24)) * 256 + (ram(wi) mod 256);
              else ram(wi) := (ram(wi) / 256) * 256 + nat(dout(23 downto 16)); end if;
            else ram(wi) := nat(dout(31 downto 16)); end if;
          end if;
        elsif isio then
          b := r - (r mod 2);
          if rwn = '1' then
            if siz = "01" or a(0) = '1' then
              s := rdb(r, n); w := std_logic_vector(to_unsigned(s * 257, 16));
            else
              w := std_logic_vector(to_unsigned(rdb(b, n) * 256 + rdb(b + 1, n), 16));
            end if;
          else
            if siz = "01" or a(0) = '1' then
              if a(0) = '0' then wrb(r, nat(dout(31 downto 24))); else wrb(r, nat(dout(23 downto 16))); end if;
            else wrb(b, nat(dout(31 downto 24))); wrb(b + 1, nat(dout(23 downto 16))); end if;
          end if;
        end if;
        for k in 1 to 2 loop wait until rising_edge(clk); n := n + 1; end loop;
        din <= w & w;
        if iack then
          if a(3 downto 1) = "110" then   -- level 6: MFP vector = VR high nibble + 5 (timer C)
            s := (io(16#7A17#) / 16) * 16 + 5; w := std_logic_vector(to_unsigned(s * 257, 16)); din <= w & w;
            dsackn <= "01"; tc_ack <= not tc_ack;
          else
            avecn <= '0'; if a(3 downto 1) = "100" then vbl_ack <= not vbl_ack; end if;
          end if;
        elsif isrom or isram or isio or iscart then dsackn <= "01";
        else berrn <= '0'; end if;
        if isio or not (isrom or isram or iscart or iack) then
          if not (isrom or isram or iscart or iack or isio) then nberr := nberr + 1; end if;
          nio := nio + 1;
          if nio <= LOGIO then
            if rwn = '1' then kind := "R "; else kind := "W "; end if;
            write(l, n, right, 9); write(l, string'(" ")); write(l, kind); write(l, string'("A=")); hwrite(l, adr);
            write(l, string'(" SIZ=")); write(l, to_integer(unsigned(siz)));
            if rwn = '1' then write(l, string'(" D=")); hwrite(l, w); else write(l, string'(" W=")); hwrite(l, dout); end if;
            write(l, string'(" PC~")); hwrite(l, std_logic_vector(lastpc));
            if not isio then write(l, string'(" BERR")); end if;
            writeline(output, l);
          end if;
        end if;
        wait until asn = '1';
        dsackn <= "11"; berrn <= '1'; avecn <= '1';
      end if;
    end loop;
  end process;

  exmon : process
    variable l : line; variable d : std_logic := '0';
  begin
    wait until rising_edge(clk);
    if dbgx(104) = '1' and d = '0' then
      write(l, string'("EXC vec=")); write(l, to_integer(unsigned(dbgx(103 downto 96))));
      write(l, string'(" SR=")); hwrite(l, dbgx(95 downto 80)); write(l, string'(" PC=")); hwrite(l, dbgx(79 downto 48));
      write(l, string'(" clk=")); write(l, clkn); writeline(output, l);
    end if;
    d := dbgx(104);
  end process;
end;
