# SDRAM64 progress (2026-10-26)
Work tree: linserver ~/sd64_wt (copy of ~/ovn_wtrmc2 = tt26rmc2 board tree, d270586 + rmc1/rmc2 patches), box copy /workspace/sd64.
Original copy: /workspace/sd64_orig. Not committed to git yet.

## Step 1 timing (tt26rmc2, ~/ovn_pnr_tt26rmc2)
- clk32_core 35.24 MHz (32 req), clk_cpu030 21.86 MHz, LUT 40309. No SDRAM pin I/O constraints exist (no set_input/output_delay) -> no pin margins reported.
## Step 2 PLL
- pll_hdmi (pll_160m): 50 MHz in, VCO 800, all 7 outputs used. 960 MHz VCO illegal (needs PFD 10 MHz < 19 MHz min, DS1239).
- Chosen: VCO 1600 (= max FVCO in DS1239 table): 64=/25 (clkout0, the 160 MHz HDMI x5 output is unused with HDMI_TESTPATTERN), 32=/50, pad 64 /25 @ 327.6 deg (1.4 ns lead as before), 100=/16, 16=/100. Gowin PnR accepted it.
## Step 3 design (SDRAM64 define)
- sdram.v on clk_sd64 with ce on clk32-coincident edges; commands 1 clk64 wide at the old times; read data captured 3 clk64 edges after READ, handed over at the old edge.
- SDC: multicycle clk32<->clk_sd64.
## Sims
- tb_ttram (box): sdram outputs at every clk32 edge identical 32 vs 64 (bench itself FAILs in both - stale vs C7/T10b, pre-existing).
- tb_bus prog_tt: log identical 32 vs 64. prog_bus ST trace: identical to 2.4 ms; one ROM-read sim race seen once at 2.29 ms (flash model, SDRAM commands identical); full rerun with sdtrace in progress.
## Build sd64a: ~/fpga_bitstreams/st_helper_hdn_sd64a.fs sha ca290e1a...; timing met, clk32 33.28, clk_sd64 144.1, clk_cpu030 21.83 MHz, LUT 40318. Flash script ~/flash_sd64.sh (fallback ~/flash_rmc2.sh).
- 19:24:39 full prog_bus trace identical 32/64 (with sdtrace); flashing sd64a
- 19:30:06 sd64a flashed: no HDMI, helper serial silent -> likely pll_hdmi not locking at VCO 1600. Reflashing tt26rmc2.
- 19:50 recovered: tt26rmc2 reflashed (flash_rmc2.sh had a stale root-owned /tmp/frmc_scan.log -> wrong LOC; now uses /tmp/frmc_scan_$$.log). Helper serial + core OK.
- Diagnosis: sd64a kills the whole fabric (helper silent, no HDMI). Same flow as tt26rmc2 except pll_hdmi VCO 1600 -> pll_hdmi most likely never locks (DS1239 text gives 650-1300 MHz for GW5AST-138; the table says 800-1600). por = !lock holds everything incl. the AE350 flash release.
- Next: keep VCO 800 for pll_hdmi. Either (a) a second PLL fed by clk32 (VCO 960 = 32x30: 64 /15 logic + 64 /15 shifted pad), or (b) clk_sd64 = clkout0 /12.5 (fractional) + pad clock via ODDR and read capture moved to the falling edge.
Files: /workspace/sd64 (box) and ~/sd64_wt (linserver); ~/fpga_bitstreams/st_helper_hdn_sd64a.fs (do not flash).
- 19:45 after the tt26rmc2 reflash(es): helper TX->host works (boot banner seen), but host->helper commands get no reply; HDMI capture black. Tried: ftdi_sio rmmod/modprobe (sudo), usbreset of the FTDI (port moved to ttyUSB0, by-id link updated), Hagibis usbreset. Not resolved; stopped (no power cycle per rules).

## sd64b (second PLL) — 2026-10-26 ~21:30
- pll_hdmi (pll_160m_mod.v) restored byte-identical to tt26rmc2 (VCO 800, all outputs as before; clkout2 left unconnected under SDRAM64).
- New pll_sd64 (gowin_pll/pll_sd64*.v): CLKIN = clk32 (pll_hdmi clkout1), IDIV 1 -> PFD 32 MHz (DS1239 19..400), FBDIV 1, MDIV 30 -> VCO 960 MHz
  (DS1239-1.0.3E GW5AST-138 650..1300, older table 800..1600: inside both). clkout0 /15 = 64 MHz phase 0 (clk_sd64); clkout1 /15 = 64 MHz,
  (13+5/8)/15*360 = 327 deg = 1.43 ns lead -> O_sdram_clk. clkout2..6 disabled. PLL_INIT MULTI_FAC 30, I_RST = !pll_lock_hdmi.
- pll_lock = pll_lock_hdmi & pll_lock_sd (por waits for both).
- sdram.v: ce first stage now samples t32 on the falling clk_sd edge (+-7.8 ns margin against clk32/clk_sd64 skew between the two PLLs); same ce timing in sim.
- SDC: clk_sd64 now on pll_sd/u_pll/PLL_inst/CLKOUT0. Build script T=sd64b, reports ~/sd64b_pnr.
- Sims (box, netlist /workspace/sd64sim/wf030.vg): prog_tt 32 vs 64: bus trace + log identical; prog_bus (TTRAM, sdtrace) vs /tmp/sd32f: bus trace + log identical.
  SDRAM command trace identical except 2 init-only commands (PRECHARGE at 5.11 us, LOAD MODE at 7.86 us) one clk32 earlier, before ram ready; same as sd64a.
- Build sd64b: ~/fpga_bitstreams/st_helper_hdn_sd64b.fs sha 19928bfe...; all TNS 0. clk32_core 36.28, clk_sd64 122.94, clk_cpu030 23.66 MHz; 40440 LUT. PLL 5/12.
  Caveat: STA gives pll_sd CLKOUT0 zero insertion delay (does not model clk32 -> pll_sd CLKIN route), so real clk32/clk_sd64 skew is not verified.
  Worst clk32->clk_sd64 hold slack 1.815 ns (tt_wdata->tt_d). Custom report shows -1.296 hold clk_sd64[R mid edge]->clk32[F] (sdram dout -> shifter shdout3), false (dout only changes on ce edges).
- 21:5x flashed sd64b (~/flash_sd64b.sh, LOC 4641 now): PLLs lock, helper serial OK, but after c + key space HDMI shows a static field of random coloured dots
  (uninitialised/garbage RAM, TOS never reaches the desktop). -> SDRAM reads wrong on hardware (read capture / pad-clock phase or clk32-clk_sd64 skew).
- Reflashed tt26rmc2 (flash_rmc2.sh, LOC 4641): desktop back. Board left on tt26rmc2.
- Next ideas: signaltap-free probe = put the 64 MHz clock on the pad but keep sd at 32 MHz (only pad PLL change) to isolate; sweep pad phase / capture edge (2 vs 3 clk64 edges); feed pll_sd from 50 MHz ref is impossible for 64 integer (needs VCO 1600 or ODIV0 12.5);
  consider CLKFB external, or capture SDRAM data in IOB with clk_sd64 negedge.

## Overnight session (from 21:50)
- Analysis: on sd64b the SDRAM I/O itself (all from pll_sd) looks OK on paper: pad lead 1.43 ns -> cmd latched ~E+16.7, CL2 data window ~[E+40, E+53], capture edge 3 = E+46.9 centred.
  Prime suspect: clk32 <-> clk_sd64 skew. STA gave pll_sd CLKOUT0 tCL=0 (clk_sd64 declared from port clk/clk_osc; no traceable path), so hold/setup across
  the crossing were computed with a fictitious ~1.5 ns sd64 lead. Crossing margins are only ~[-1.8, +0.7] ns.
- Rejected: ODIV0 12.5 fractional on pll_160m (prim_sim model shows clkout0 not edge-aligned with clkout1, and alignment of a fractional divider on HW is undocumented).
- sd64c: same RTL as sd64b; SDC clk_sd64 now -source pll_sd CLKIN, -master_clock clk32_core, x2, so STA should see the real clk32->pll_sd route latency and PnR hold-fix can act.
- sd64c FAILED to build: Gowin TA2004 "Cannot get clock clk32_core" when clk_sd64 is -source pll_sd CLKIN (Gowin cannot propagate clocks through a PLL cascade). SDC reverted to the sd64b form.
  (build script had copied the stale fs after the failed gw_sh; script now exits on gw rc != 0, stale sd64c.fs deleted.)
- Estimate: real clk_sd64 lags clk32 by ~1.4..3 ns (pll_sd internal FB aligns to its CLKIN, which sits after the clk32 route), while STA assumed a 1.6 ns lead -> hold on clk32->sd64 crossings likely broken on HW.
- Phase sweep (builder ~/bv.sh T c0coarse c0fine c1coarse c1fine, trees ~/bt_T): pll_sd clkout0 and pad clkout1 shifted earlier together (VCO step 1.042 ns):
  sd64e: -3.125 ns (c0 12/0, pad 10/5); sd64f: -4.17 ns (c0 11/0, pad 9/5). Building in parallel.
- 22:5x sd64e flashed (LOC 4641): TOS starts! Atari logo, 'WARNING: BAD ROM CRC', 2 bombs (/workspace/sd64b/sd64e.png). Skew hypothesis confirmed direction. Trying sd64f (-4.17 ns).
- 23:0x sd64f flashed: helper serial stopped answering after boot, HDMI capture no picture (6 KB grabs). Reflashing sd64e to recover.
- 23:1x after sd64f: serial input dead + HDMI black; also after reflashing sd64e and tt26rmc2 (FTDI usbreset tried). Same wedge as after sd64a -> needs a power cycle by David.
  Suspect: jtagseln = !(!pll_lock ...) toggles toward the BL616 when the combined lock drops; sd64b/e/f had pll_lock = hdmi & sd lock.
  Fix in tree (sd64g+): pll_lock (jtagseln, BL616 pins) = pll_hdmi lock only, as tt26rmc2; por = !(pll_lock && pll_lock_sd).
- Building sd64g (-3.65 ns: c0 11/4, pad 10/1) and sd64h (-2.6 ns: c0 12/4, pad 11/1) with the jtagsel fix.
- 23:3x sd64g / sd64h built OK (both: clk32 34.64, clk_sd64 112.41, clk_cpu030 23.71 MHz, TNS 0; fs sha a769d5e7 / 93edc893).
  Flashed sd64g: helper banner seen, but serial input still dead and HDMI black (the wedge persists across bitstreams) -> cannot test until power cycle.
- Reflashed tt26rmc2 (LOC 4641) as known-good. STOPPED: waiting for David to power-cycle the board (+USB hub).
- Test order after power cycle (try.sh <tag>): sd64h (-2.6 ns), sd64g (-3.65 ns), then sd64e (-3.1 ns, booted TOS with BAD ROM CRC). sd64f (-4.17 ns) untested (wedged on its flash).
- 06:45 after power cycle: tt26rmc2 healthy (serial '?', c+key space, desktop /workspace/sd64b/rmc2_0645.png; capture needed usbreset). Next sd64h.
- 06:5x sd64h (-2.6 ns): TOS memory test passes (4096 KB ST RAM), but 'BAD ROM CRC IN CHIP E/O' and hangs after (/workspace/sd64b/sd64h.png). Serial OK.
- 07:0x sd64g (-3.65 ns, has jtagsel fix): '?' answered right after flash, then 'c'/'key space' got no reply and HDMI black = one-way-serial wedge AGAIN.
  So the jtagsel/pll_lock change does NOT prevent it. Reflashed tt26rmc2 (LOC 4689): still one-way (no reply to '?', HDMI black). STOPPED board work; needs remote power cycle.
  Observation: the wedge seems to follow a cold boot ('c') on a build where the ST side misbehaves (sd64a, sd64f, sd64g), not the flash itself.
- 07:1x (board untouched, build only). sdram.v: optional SD64_NEGCAP = DQ sampled on falling clk_sd 2.5 clocks after READ, handed on at edge 3.
  Building sd64i (-2.08 ns: c0 13/0 pad 11/5), sd64j (-1.56 ns: c0 13/4 pad 12/1); sd64k (-2.6 ns as h + SD64_NEGCAP) next. Sims for NEGCAP running in /tmp/k_bus, /tmp/k_tt.
- 07:12 after 07:07 power cycle: tt26rmc2 healthy (serial ?, c + key space, desktop /workspace/sd64b/rmc2_0712.png).
- 07:2x sims for SD64_NEGCAP: prog_tt and prog_bus bus traces + logs identical to 32 MHz; SDRAM cmd trace differs only by the 2 known init commands.
- sd64i, sd64j built: clk32 34.64, clk_sd64 112.41, clk_cpu030 23.71 MHz, TNS 0, 40440 LUT. sd64k (h + NEGCAP) building.
- 07:3x sd64i (-2.08 ns) flashed (LOC 4817), no 'c' sent: TOS auto-starts; memory test shows several X errors + BAD ROM CRC E/O (/workspace/sd64b/sd64i_noc.png). Serial OK (answers ~50 s after flash). Worse than sd64h (-2.6). Waiting for sd64k.
- 07:4x STOP board work (David). Reflashed tt26rmc2 (LOC 4817) + reload: serial answers, desktop auto-boots (/workspace/sd64b/final_state.png). Board left on tt26rmc2.
- 07:5x sd64k built (h -2.6 ns + SD64_NEGCAP): clk32 34.40, clk_sd64 91.41, clk_cpu030 23.20 MHz, TNS 0, 40440 LUT, sha a383df50. NOT tested. sd64j built, NOT tested.
