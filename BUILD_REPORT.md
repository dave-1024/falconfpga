# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260925-mn4
ACTION: BUILD
RESULT: PASS
GOWIN_VERSION: V1.9.12.03 (gw_sh via /usr/local/bin/gowin-sh, Linux)
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl (via gowin-sh wrapper)
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE (set_option -replicate_resources 1 in build_tc138k.tcl)
REPO COMMIT BUILT: ea8f905 (toolchain replay; no HDL change vs mn3)

STAGE REACHED: full flow — GowinSynthesis, place, route, timing, bitstream, power. Exit 0 in ~4.3 min.
LICENCE: OK (attempt 1, no retries)

WHAT WAS RUN:
  1. git pull origin main (to ea8f905)
  2. cd misterynano_tc138k && gowin-sh build_tc138k.tcl
  No patch. No HDL edits. rigsdram/ untouched.

ERRORS: none (no ERROR lines in build log)

WARNINGS OF NOTE (non-fatal):
  TA1123: clk_spi / clk_32 frequency vs PLL CLKOUT4/CLKOUT2 mismatch
  TA1132: inferred clocks without create_clock (i2s_bclk_d, ds2_p1/clk_spi, misterynano/mcu/n4_24, video2hdmi/clk_audio)
  PR1014: clk_d routed on generic routing (skew/delay risk)
  EX3670 bit-length mismatches on lcd_*/hdmi RGB ports in top.sv
  Many PA1001 dangling nets in HD63701_ALU / hdmi (typical for this core)

RESOURCES (from impl/pnr/atarist_tc138k.rpt.txt):
  Logic:    19268/138240 (14%)  — LUT 17366 + ALU 1704
  Register: 7518/139095 (6%)    — Logic FF 7483 + I/O FF 35
  BSRAM:    21/340 (7%)
  DSP:      1.5/298 (<1%)

FMAX (Max Frequency Summary):
  clk_osc                                              constraint 50.000  actual 234.087 MHz
  i2s_bclk_d                                           constraint 100.000 actual 477.640 MHz
  ds2_p1/clk_spi                                       constraint 100.000 actual 174.146 MHz
  misterynano/mcu/n4_24                                constraint 100.000 actual 551.078 MHz
  video2hdmi/clk_audio                                 constraint 100.000 actual 461.161 MHz
  pll_hdmi/.../CLKOUT1.default_gen_clk (pixel ~31.7)   constraint 31.667  actual 33.313 MHz
  pll_hdmi/.../CLKOUT3.default_gen_clk                 constraint 95.000  actual 245.685 MHz
  (no paths for clk_hdmi / clk_spi / clk_32 Fmax)

SETUP / HOLD SUMMARY:
  Per-clock TNS table all 0.000 (endpoint TNS by named clock).
  Cross-clock Setup Paths Table still shows negative slacks (worst −19.679 ns):
    from ds2_p1/rx_buffer[4]_7_s0/Q (ds2_p1/clk_spi)
    to   misterynano/atarist/ikbd/.../rP_13_s0/D (CLKOUT1 pixel clock)
  Cross-clock Hold Paths Table worst −2.065 ns (video2hdmi packet_picker CDC / audio paths).
  Same-clock Fmax for CLKOUT1 is only just above constraint (33.313 vs 31.667 MHz).

BITSTREAM:
  impl/pnr/atarist_tc138k.fs exists, 36538618 bytes
  (also .bin 4564062 bytes; not committed)

CHECK:
  1. RESULT PASS with file:line                  PASS — no errors
  2. LUT/FF/BSRAM/DSP and .fs bytes              PASS — same as mn3 (36538618 bytes)
  3. device_version C in log                     PASS — "current device: GW5AST-138C GW5AST-LV138PG484AC1/I0"

NOTES:
  Not flashed. rigsdram/ HDL and local dirt left alone. impl/ and build logs untracked.
```
