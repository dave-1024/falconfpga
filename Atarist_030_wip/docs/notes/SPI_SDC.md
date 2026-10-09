# SPI_SDC.md: AE350 helper flash/SPI constraints (proposal, NOT committed, NOT flashed)

9 Oct 2026, 11:00 BST. Scope: task A from David (09:15). Source: F62d = falconfpga 92a0a6a, Atarist_030_wip,
copied to /tmp/bSDC; the only change in the copy is tang/console138k/atarist_st_helper.sdc (diff below).
The repo SDC is unchanged. Nothing was flashed. The board is on F63 (see DEBUG2.md, 9 Oct 09:15-10:30).

## TL;DR
1. **Warnings.** Five nets were "determined to be a clock but not created" (TA1132): `ae350_flash_clk`, `spi_io_clk`,
   `i2s_bclk_d`, `ds2_p1/clk_spi` and the DDR3 PHY `fclkdiv/CLKOUT`. The proposed SDC creates all five
   (TA1132 count in the new builds: 0).
2. **SPI flash pin paths.** CS# T19, SCK L12, MOSI P22 (`mspi_di`), MISO R22 (`mspi_do`). All four pass through our
   one-way pad mux in top.sv (`sth_flash_to_st`). The SoC's SCK is a LUT output inside the encrypted core
   (`u_gwspiflash/u_spi_spiif/n250_s0/F`, net `n250_3`). It also clocks the SoC's own MISO capture flops
   (`spi_in_r*`) directly, with no pad loopback.
3. **MISO with the flash datasheet numbers.** Timed with datasheet worst cases at the 20 ns SCK period that Gowin's
   AE350 reference uses, the MISO round trip FAILS in every placement: slack -3.5 ns (p1), -4.1 ns (p3), -7.1 ns (p2).
   Gowin's per-clock TNS table still shows 0 for these clocks, so the path neither steers the placer nor shows up in
   a "TNS 0" sign-off. It is visible only in report_timing.
4. **The MISO timing does NOT explain p1-dead/p3-boots.** The p3 placement (the one whose original build boots) has
   the WORSE MISO slack. Either the real boot SCK is slower than 50 MHz (likely, since a 50 MHz SCK could not work at
   all with a 7 ns tCLQV through this pad mux), or the failure is somewhere STA cannot see. SDC alone will not fix the
   placement sensitivity.
5. **PLL start-up hold.** The 0.015 ns in F62d p1 is not the discriminator: the booting p3 build has smaller margins
   (0.007 ns original, 0.005 ns with the new SDC). The real reason these holds are tiny is that `clk_osc` (V22) reaches
   the fabric pll_init FSMs over generic routing, not a global clock (PR1014 "Generic routing resource will be used to
   clock signal 'clk_d'"). The skew between adjacent flops is about 0.65 ns. With place_option 2 and the new SDC it
   goes negative (-0.235 / -0.218 ns). This is an RTL/clocking issue, not an SDC one.
6. **Recommendation.**
   - Accept part 1 of the diff (clock definitions and groups: housekeeping that turns untimed paths into timed or
     explicitly-async ones).
   - Treat part 2 (flash pad I/O delays + SCK source latency) as an analysis model until the real SCK period is known.
   - Build only with TNS 0, and from now on also read the flash report_timing and the recovery/removal tables,
     which the TNS table does not cover.

## 1. Warnings found (original SDC, F62d builds)
```
WARN (TA1132) : 'ae350_flash_clk' was determined to be a clock but was not created.
WARN (TA1132) : 'spi_io_clk' was determined to be a clock but was not created.
WARN (TA1132) : 'i2s_bclk_d' was determined to be a clock but was not created.
WARN (TA1132) : 'ds2_p1/clk_spi' was determined to be a clock but was not created.
WARN (TA1132) : 'u_RiscV_AE350_SOC_Top/.../u_ddr_phy_top/fclkdiv/CLKOUT.default_gen_clk' was determined to be a clock but was not created.
```
| net | what it is | proposed constraint |
|---|---|---|
| ae350_flash_clk | SoC SCK = LUT n250_s0/F in the encrypted core. It clocks the SoC's MISO capture flops and drives the SCK pad via our mux | create_clock 20 ns (as Gowin's flash_sysclk), exclusive to AHB/APB/DDR (as Gowin) |
| spi_io_clk | st_helper_mculink `sck` register (AHB_CLK flop, AE350 GPIO bit-bang, level accepted after 2 equal AHB samples) clocking misc/mcu_spi.v | create_clock 120 ns (half period >= 3 AHB cycles). Async to the fabric group (toggle + 2-flop sync into clk32) and to the AE350 group (MOSI/SS# are stable >= 2 AHB cycles around each SCK edge by construction) |
| ddr3 fclkdiv/CLKOUT | DDR3 PHY divider | create_clock ddr3_sysclk 20 ns plus the two async groups, copied in form from Gowin's reference |
| i2s_bclk_d | clk32/20 (MiSTeryNano audio) | generated clock from clk32_core, /20 |
| ds2_p1/clk_spi | clk32/252 (DualShock2) | generated clock from clk32_core, /252 |

Other clock-related warning, kept as is: PR1014 generic routing for `clk_d` (clk_osc), see section 5.

## 2. Flash pin paths
```
SoC (encrypted)                         top.sv pad mux (sth_flash_to_st, sticky, set once)      ball
n250_s0/F (=FLASH_SPI_CLK=FLASH_SPI_CLK_in) -> LUT3 mspi_clk_d_s -> OBUF mspi_clk_obuf -> L12 SCK
   \-> spi_in_r*/CLK (MISO capture, inside SoC)
spi_out_r (MOSI)                        -> mux LUT -> mspi_di OBUF                           -> P22 (flash DI)
spi1_csn_out (CS#)                      -> mux LUT -> mspi_cs OBUF                           -> T19
spi_in_r*/D <- ae350_flash_miso_s1 LUT  <- mspi_do IBUF                                      <- R22 (flash DO)
```
ST side after the switch: misterynano/flash on flash_clk = pll_hdmi CLKOUT3 (800/8 = 100 MHz), SCK = mspi_clk_pll (CLKOUT4).

MISO round trip, F62d p1 with the new SDC (report_timing ae350_flash_sck -> ae350_flash_clk):
```
launch  SCK fall at the ball       10.000
  + source latency (clock-out)     +6.0    (modelled, see 3.2)
  + flash tCLQV + board            +7.5
  IBUF                              0.619
  route IBUF -> miso mux LUT        2.838
  LUT                               0.511  -> arrival 27.468
capture SCK rise                   20.000
  + route n250_s0/F -> spi_in_r     4.058  (placement-dependent skew)
  - setup/uncertainty               0.092  -> required 23.966      slack -3.502
```
p3: route IBUF->LUT 5.271, capture route 5.617 -> slack -4.124. p2: -7.053.

## 3. Reasoning per constraint

### 3.1 Clock definitions (part 1)
These follow Gowin's own AE350 reference (Hybrid030/hybrid_falcon030/src/ae350_stage0.sdc, "taken verbatim in form
from Gowin's DDR3_Shared example"):
```
create_clock -name flash_sysclk -period 20 [get_nets {u_RiscV_AE350_SOC_Top/FLASH_SPI_CLK_in}]
create_clock -name flash_spi_clk_i -period 20 [get_pins {u_RiscV_AE350_SOC_Top/FLASH_SPI_CLK_iobuf/I}]
create_clock -name flash_spi_clk -period 20 [get_ports {FLASH_SPI_CLK}]
create_clock -name ddr3_sysclk -period 20 [get_pins {.../fclkdiv/CLKOUT}]
set_clock_groups -exclusive -group flash_sysclk -group ae350_ahb_clk -group ae350_apb_clk -group ae350_ddr_clk
set_clock_groups -asynchronous ddr3_clkin / ddr3_sysclk ; ddr3_sysclk / ddr3_memory_clk
set_clock_groups -exclusive ddr3_memory_clk / ddr3_clkin ; clk50m / ddr3_sysclk / ddr3_rw_clk
```
The reference has **no** set_input_delay/set_output_delay on the flash pins. The pins hang directly off the SoC
there, with no fabric mux. MiSTeryNano upstream (misterynano_tc138k atarist.sdc) only has `create_clock clk_spi 10 ns`
on the mspi_clk port (ST flash at 100 MHz) and no I/O delays either. Our existing SDC already has that.

What we do differently:
- The clock goes on our top-level net `ae350_flash_clk`, the same LUT output as Gowin's FLASH_SPI_CLK_in.
- The exclusive group is extended with the generated pad clock `ae350_flash_sck`.
- `st_flash_clk` (ST flash controller, pll_hdmi CLKOUT3) is made exclusive to the AE350 flash clocks. The two never
  use the pads at the same time. Without this, STA timed the ST flash controller against the AE350 pad clock
  (spurious -6.5 ns paths in an intermediate build).

### 3.2 Flash pad I/O (part 2, analysis model)
- `create_generated_clock ae350_flash_sck` on net mspi_clk_d (the mux output feeding the SCK OBUF). The flash's
  timing refers to this edge.
- Gowin keeps generated clocks **ideal** (latency 0 in the report). It also does **not** time a clock net as data:
  `set_max_delay n250_s0/F -> mspi_clk` gave "no paths to report", so it was dropped from the proposal. The clock-out
  delay is therefore entered as source latency: `set_clock_latency -source -late 6.0 / -early 2.0`. (`-max/-min` is a
  syntax error in Gowin; `-late/-early` is accepted.) Basis for 6.0: the placer gives the same net 4.06 ns
  (p1) / 5.62 ns (p3) to a flop next to the pad, plus the mux LUT 0.5 and the OBUF ~1.5. This is an estimate: the real
  per-placement clock-out is not reported by Gowin.
- The flash is JEDEC 0x0B4017 = XTX XT25F64B. I could not get the XT25F64B AC table (XTX lists it as replaced by
  XT25F64F), so the numbers are W25Q64-class stand-ins, **to be checked against the XT25F64B datasheet**: tCLQV 7 ns
  max, tCLQX 0 (conservative), tDVCH 2, tCHDX 3, tSLCH/tCHSH 5 ns, board ~0.3 ns each way (rounded to 0.5).
  - input mspi_do vs SCK fall: max 7.5, min 0.5
  - output mspi_di: max 2.5 (tDVCH+board), min -3.5 (-tCHDX-board)
  - output mspi_cs: max 5.5, min -5.5
- MOSI/CS# output paths are reported as "no paths" because their launch flops are AHB-domain registers, and the
  reference's exclusive grouping (flash_sysclk vs AHB) cuts them. The reference does the same. They change once per
  SCK cycle around the SoC's own SCK, so this is the vendor's choice, which we keep. Not verified, since the core is
  encrypted.

Effect: at 20 ns (the reference value) MISO fails in every placement (-3.5 to -7.1 ns). A 50 MHz SCK cannot meet a
7 ns tCLQV through any fabric pad path of this length. Most likely the AE350 boot ROM runs the flash slower (the
ATCSPI200 SCLK divider). I tried to see what drives n250_s0 (gated AHB_CLK = 50 MHz, or AHB flops = <= 25 MHz) with
`report_timing -to n250_s0/*`: "nothing to report" (inside the encrypted core). At 40 ns (25 MHz) the same path
would have about +6.5 ns slack in p1 and +5.9 ns in p3. **Open: the real SCK period (scope on L12, or a GAO probe
on ae350_flash_clk = a build + flash, needs David's OK).** Once known, set the ae350_flash_clk period to it and keep
the I/O delays.

Also: Gowin's per-clock TNS table reports 0 for ae350_flash_clk/ae350_flash_sck even with the -3.5 ns path, and the
p1 placement did not change for these paths across four SDC iterations (identical 4.058 / 2.838 ns routes). The
placer does not optimise this I/O path, so the constraint documents it but does not "fix placement".

### 3.3 spi_io_clk
120 ns, async to both sides as explained in the table. Its internal mcu_spi paths are now timed: setup slack
58.7 ns (p1) / 117.4 ns (p3), hold positive, Fmax ~387 MHz. It was never close; it was not the p1 problem.

### 3.4 Generated fabric dividers
i2s_bclk_d and ds2_clk_spi become generated clocks of clk32_core. Paths clk32 <-> divider are timed with the right
relation. They are async to the HDMI 640 clocks (no crossings other than the existing frame-buffer ones). No new
violations.

## 4. Build results (F62d 92a0a6a + proposed SDC, Gowin V1.9.12.03, box only, no flash)
| build | place | TNS all clocks (table) | clk32_core Fmax | clk_cpu030 Fmax | MISO setup (20 ns model) | MISO hold | spi_io setup | worst clk_osc hold (pll_init) | removal worst |
|---|---|---|---|---|---|---|---|---|---|
| f1 | 1 | **0 on all 48 rows** | 32.040 | 17.470 | -3.502 | +12.470 | +58.7 | +0.029 (ddr3 pll_init), ae350 pll_init +0.174 | -0.046 (pll_hdmi init -> misterynano/flash init, st_flash_clk) |
| f3 | 3 | **0 on all 48 rows** | 32.091 | 18.661 | -4.124 | +12.672 | +117.4 | +0.005 (ddr3 pll_init) | +0.271 |
| f2 | 2 | **FAIL**: clk32_core setup -73.054 (69 ep), clk_osc hold -1.630 (16 ep) | 26.610 | 17.299 | -7.053 | +13.794 | - | **-0.235 / -0.218** (ae350 pll_init waitcnt) | -0.387 |
| orig F62d | 1 | 0 | 32.023 | 17.833 | untimed | - | untimed | +0.015 ae350 pll_init | **-0.460** (pll_hdmi init -> sth_frel CLEAR) |
| orig F62d | 3 | 0 | 32.092 | 18.862 | untimed | - | untimed | +0.007 ddr3 pll_init | +0.216 |

Notes:
- The new SDC changes placement (Fmax differs from the original p1/p3), so f1/f3 are not the bitstreams that were
  tested on the board. Whether f1's helper boots is unknown without a flash (both f1 and f3 meet the TNS-0 rule).
  The bitstreams are in /tmp/bSDC/r_f1, r_f3.
- f2 fails timing: do not flash. Historically place_option 2 (diag build) met timing, so this is placer variance with
  the extra timed paths.
- "Setup Violated Endpoints" in the report header is ~3100 in ALL builds including the original F62d (3410/3547).
  Those are recovery/removal endpoints, which the per-clock TNS table does not include. The worst are async-reset
  releases from `pll_hdmi/u_pll_init` (por = !pll_lock) into clk32_core (recovery -6.4 to -8.6 ns) and the DDR3 PHY
  reset into ddr3_memory_clk (-5.2 ns, the reference makes ddr3_memory_clk/ddr3_clkin exclusive). Pre-existing, not
  touched here.
- Reports: st_helper_out/fetchfix/sdc_builds/tr_sdc_p1.html, tr_sdc_p3.html, tr_sdc_p2.html; proposed SDC:
  sdc_builds/atarist_st_helper.proposed.sdc; diff: sdc_builds/atarist_st_helper_sdc.diff.

## 5. Helper PLL start-up hold
- F62d p1: 0.015 ns, `clk_osc` u_gowin_pll_ae350/u_pll_init state_0 -> state_2. F62d p3 (boots): 0.007 ns
  (u_gowin_pll_ddr3/u_pll_init). New SDC: p1 0.029, p3 0.005, p2 **-0.218**.
- Cause: clk_osc (ball V22, clk_ibuf fan-out 173) is routed to the pll_init FSMs on **generic routing** (PR1014). In
  the f2 path the launch flop gets the clock at 1.648 ns and the capture flop next to it at 2.300 ns. That 0.65 ns
  skew is what eats the hold margin. "-correct_hold_violation 1" is on and fixes it in most placements, but not
  reliably.
- Not an SDC problem: the constraint (clk_osc 20 ns) is correct. The fix would be RTL/clocking: put clk_osc for the
  fabric pll_init logic on a global clock buffer, or clock those FSMs from a slow PLL-independent global. That needs
  a design decision (Gowin's pll_init is vendor IP, MiSTeryNano upstream has the same structure). Recommendation:
  keep monitoring (it is positive in all TNS-0 builds); no constraint change; consider the global-buffer change as a
  separate F64 item.
- It is not the p1/p3 discriminator (p3 boots with the smaller margin).

## 6. What could explain p1-dead / p3-boots (not resolvable by SDC)
1. SCK is a LUT-made clock inside the encrypted SoC (n250_s0). If it is a gated AHB_CLK, glitches on SCK and on the
   capture clock depend on routed input skew, which STA does not see. Placement-dependent by nature.
2. The real clock-out vs capture-skew difference per placement (Gowin does not report the clock-out). Measurable only
   on hardware (scope L12 vs R22) or by GAO.
3. The unsynchronised por release into clk32/flash_clk flops (recovery -6..-8 ns, removal -0.46 ns in the dead
   original p1 on sth_frel). sth_frel is benign (its D input is 0 at release). The same pattern into other helper
   FSMs is pre-existing in every build.

## 7. Proposed diff (against falconfpga 92a0a6a Atarist_030_wip/tang/console138k/atarist_st_helper.sdc)
Part 1 = blocks (1) first create_clock, st_flash_clk + exclusive, (2), (3), (4), groups. Part 2 = the
ae350_flash_sck generated clock, source latency and the set_input/output_delay lines. The report_timing lines at the
end only add reports.
```diff
--- tang/console138k/atarist_st_helper.sdc	2026-10-08 08:23:12.251215827 +0100
+++ tang/console138k/atarist_st_helper.sdc	2026-10-09 10:08:41.130161629 +0100
@@ -77,3 +77,86 @@
 // and the static, once-switched flash pad mux. Without this group STA would
 // time those crossings as if the 50 MHz and 32 MHz PLL outputs were related.
 set_clock_groups -asynchronous -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030 clk_cpu030_n}]
+
+// ---------------------------------------------------------------------------
+// F64-SDC (proposal, 9 Oct 2026): clocks that STA found but nobody created
+// (TA1132), and the AE350 boot-flash pad path. Before this, every path in or
+// out of these nets was untimed or timed against a default 100 MHz guess, so
+// their quality depended on the placer (F62d: place_option 1 = helper never
+// boots, place_option 3 = helper boots). See st_helper_out/fetchfix/SPI_SDC.md.
+
+// (1) AE350 flash SPI SCLK. RiscV_AE350_SOC_Top: FLASH_SPI_CLK = n250_3 (a LUT
+// in the SoC netlist, u_gwspiflash/u_spi_spiif/n250_s0), fed back into the SoC
+// as FLASH_SPI_CLK_in, which clocks the SoC's MISO capture flops (spi_in_r*).
+// Gowin's own AE350 reference (ae350_stage0.sdc / ae350_shared_ddr3.sdc)
+// creates it at 20 ns (flash_sysclk) and makes it exclusive to the SoC's
+// AHB/APB/DDR clocks. Same here, on the top-level net.
+create_clock -name ae350_flash_clk -period 20 -waveform {0 10} [get_nets {ae350_flash_clk}]
+// The same clock at the mspi_clk ball (L12), after the sth_flash_to_st pad
+// mux LUT (mspi_clk_d) and the OBUF: the flash's timing refers to this edge.
+// Gowin keeps a generated clock ideal (latency 0, checked in the report), and
+// it does not time a clock net as data (set_max_delay n250_s0/F -> mspi_clk
+// reports "no paths"), so the clock-out delay (SoC LUT -> mux LUT -> OBUF ->
+// ball) is entered as the generated clock's source latency: late 6.0 ns,
+// early 2.0 ns. 6.0 = the 4.06 ns route the placer gives the same net from
+// n250_s0/F to a flop next to the pad (F62d p1) + mux LUT 0.5 + OBUF ~1.5.
+create_generated_clock -name ae350_flash_sck -source [get_nets {ae350_flash_clk}] -master_clock ae350_flash_clk -divide_by 1 [get_nets {mspi_clk_d}]
+set_clock_latency -source -late 6.0 [get_clocks {ae350_flash_sck}]
+set_clock_latency -source -early 2.0 [get_clocks {ae350_flash_sck}]
+// Flash (JEDEC 0B 40 17 = XTX XT25F64B, 64 Mbit; W25Q64-class timing, 3.3 V,
+// SPI mode 0): data out valid tCLQV <= 7 ns after SCK falls, output hold
+// tCLQX >= 0 (conservative); data in setup tDVCH >= 2 ns and hold
+// tCHDX >= 3 ns to SCK rising; CS# setup tSLCH >= 5 ns, hold tCHSH >= 5 ns.
+// Board trace delay (< 5 cm, ~0.3 ns each way) is folded in as 0.5 ns.
+set_input_delay  -clock ae350_flash_sck -clock_fall -max 7.5 [get_ports {mspi_do}]
+set_input_delay  -clock ae350_flash_sck -clock_fall -min 0.5 [get_ports {mspi_do}]
+set_output_delay -clock ae350_flash_sck -max  2.5 [get_ports {mspi_di}]
+set_output_delay -clock ae350_flash_sck -min -3.5 [get_ports {mspi_di}]
+set_output_delay -clock ae350_flash_sck -max  5.5 [get_ports {mspi_cs}]
+set_output_delay -clock ae350_flash_sck -min -5.5 [get_ports {mspi_cs}]
+// The ST flash controller (misterynano/flash, flash_clk = pll_hdmi CLKOUT3,
+// 800/8 = 100 MHz) uses the same balls only after the one-time switch; it
+// never talks to the flash at the same time as the AE350.
+create_generated_clock -name st_flash_clk -source [get_ports {clk}] -master_clock clk_osc -multiply_by 2 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT3}]
+set_clock_groups -exclusive -group [get_clocks {st_flash_clk}] -group [get_clocks {ae350_flash_clk ae350_flash_sck}]
+
+// (2) spi_io_clk: st_helper_mculink's re-registered SCK (an AHB_CLK flop
+// output) is the clock of misc/mcu_spi.v. The AE350 bit-bangs it; mculink
+// only lets a level through after two equal AHB samples, so a half period is
+// at least 3 x 20 ns -> 120 ns minimum period (the firmware runs far slower).
+// Crossings: AHB_CLK -> spi_io_clk (MOSI/SS# from the same retiming flops,
+// stable for >= 2 AHB cycles around each SCK edge, by construction) and
+// spi_io_clk <-> clk32 (mcu_spi: toggle flag + 2-flop synchroniser, data held
+// stable by the protocol). So asynchronous to both groups; the internal
+// mcu_spi shift-register paths are timed (setup AND hold) at 120 ns.
+create_clock -name spi_io_clk -period 120 -waveform {0 60} [get_nets {spi_io_clk}]
+
+// (3) DDR3 PHY divider (CLKOUT of fclkdiv). Gowin's reference creates it as
+// ddr3_sysclk, 20 ns, with these relations (copied in form).
+create_clock -name ddr3_sysclk -period 20 -waveform {0 10} [get_pins {u_RiscV_AE350_SOC_Top/u_RiscV_AE350_SOC/u_riscv_ae350_ddr3_top/u_ddr3_memory_ahb_top/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
+set_clock_groups -asynchronous -group [get_clocks {ddr3_clkin}] -group [get_clocks {ddr3_sysclk}]
+set_clock_groups -asynchronous -group [get_clocks {ddr3_sysclk}] -group [get_clocks {ddr3_memory_clk}]
+
+// (4) Fabric clock dividers from clk32 (MiSTeryNano upstream): the i2s bit
+// clock (top.sv clk_audio = clk32 / 20 = 1.6 MHz) and the DualShock2 SPI
+// clock (dualshock2.v clk_spi = clk32 / 252). Generated from clk32_core, so
+// the paths into and out of them are timed with the right relation.
+create_generated_clock -name i2s_bclk_d -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 20 [get_nets {i2s_bclk_d}]
+create_generated_clock -name ds2_clk_spi -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 252 [get_nets {ds2_p1/clk_spi}]
+
+// Groups for the new clocks (the AE350 line above stays as it is).
+set_clock_groups -exclusive -group [get_clocks {ae350_flash_clk ae350_flash_sck}] -group [get_clocks {ae350_ahb_clk}] -group [get_clocks {ae350_apb_clk}] -group [get_clocks {ae350_ddr_clk}]
+set_clock_groups -asynchronous -group [get_clocks {ae350_flash_clk ae350_flash_sck spi_io_clk ddr3_sysclk}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030 clk_cpu030_n i2s_bclk_d ds2_clk_spi}]
+set_clock_groups -asynchronous -group [get_clocks {spi_io_clk}] -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk ddr3_sysclk ae350_flash_clk ae350_flash_sck}]
+set_clock_groups -asynchronous -group [get_clocks {i2s_bclk_d ds2_clk_spi}] -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}]
+// Reports for the new paths
+report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {ae350_flash_sck}] -to_clock [get_clocks {ae350_flash_clk}]
+report_timing -hold  -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {ae350_flash_sck}] -to_clock [get_clocks {ae350_flash_clk}]
+report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {ae350_flash_clk}] -to_clock [get_clocks {ae350_flash_sck}]
+report_timing -hold  -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {ae350_flash_clk}] -to_clock [get_clocks {ae350_flash_sck}]
+report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {spi_io_clk}] -to_clock [get_clocks {spi_io_clk}]
+report_timing -hold  -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {spi_io_clk}] -to_clock [get_clocks {spi_io_clk}]
+// MOSI/CS# launch registers: which clock? (report only)
+report_timing -setup -max_paths 5 -max_common_paths 1 -to [get_ports {mspi_di mspi_cs}]
+// What drives the SCLK LUT? (diagnostic: AHB_CLK gated = 50 MHz SCLK, AHB flops = <= 25 MHz)
+report_timing -setup -max_paths 4 -max_common_paths 1 -to [get_pins {u_RiscV_AE350_SOC_Top/u_RiscV_AE350_SOC/u_riscv_ae350_flash_top/u_gwspiflash/u_spi_spiif/n250_s0/*}]
```

## 8. Needs David
- OK to commit part 1 (clock definitions/groups) to the work branch? Part 2 only once the SCK period is known.
- Measure the AE350 boot SCK (scope on L12 during helper boot) or allow a GAO build+flash to probe it.
- Optional, needs a flash: f1 (place 1, new SDC, TNS 0) to see whether the new placement boots the helper. I did not
  flash (as instructed).
- Decide whether the clk_osc generic-routing / pll_init hold issue (section 5) becomes an RTL item.
