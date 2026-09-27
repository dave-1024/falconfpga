# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260927-1
ACTION: BUILD
RESULT: PASS
GOWIN_VERSION: V1.9.12.03 (gw_sh via /usr/local/bin/gowin-sh / /workspace/tools/bin/gowin-sh, Linux)
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE (set_option -replicate_resources 1 in build_tc138k.tcl)
REPO COMMIT BUILT: ea767ec

STAGE REACHED: Gowin full flow PASS (synthesis, place, route, timing, bitstream). GW_EXIT:0. ~5.2 min. No sim (CHECK: sanity build only).
LICENCE: OK (attempt 1, no retries)

WHAT WAS RUN:
  1. git pull origin main (457eb74..ea767ec; HDMI constraint pin fix in atarist.cst)
  2. cd misterynano_tc138k && gw_sh build_tc138k.tcl (gowin-sh wrapper)
  No patch. No HDL edits. No sim. rigsdram/ untouched. setup_after_update.sh not needed (gowin-sh already on PATH).

GW:
  GW_RESULT: PASS
  GW_EXIT: 0
  ERRORS: none (no ERROR lines in Gowin log)
  CT1135 count: 0 (top is correct)
  current device: GW5AST-138C GW5AST-LV138PG484AC1/I0
  NOTE (EX0101): Current top module is "top"
  tmds_clk_n constrained and placed: IO_LOC G16 (IOR105[B], LVCMOS33D), pair with tmds_clk_p G15
  WARNINGS OF NOTE (non-fatal; ignored per CHECK: old_flg, fdc1772 always-loop, rtc_index):
    TA1123: clk_spi / clk_32 frequency vs PLL CLKOUT4/CLKOUT2 mismatch
    TA1132: inferred clocks without create_clock (i2s_bclk_d, ds2_p1/clk_spi, misterynano/mcu/n4_24, video2hdmi/clk_audio)
    PR1014: clk_d routed on generic routing (skew/delay risk)
    Many PA1001 dangling nets in hdmi (typical for this core)

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

SETUP / HOLD SUMMARY:
  Cross-clock Setup Paths Table worst −19.679 ns:
    from ds2_p1/rx_buffer[4]_7_s0/Q (ds2_p1/clk_spi)
    to   misterynano/atarist/ikbd/.../rP_13_s0/D (CLKOUT1 pixel clock)
  Cross-clock Hold Paths Table worst −2.065 ns (video2hdmi packet_picker CDC / audio paths).
  Same-clock Fmax for CLKOUT1 is only just above constraint (33.313 vs 31.667 MHz).

BITSTREAM:
  impl/pnr/atarist_tc138k.fs 36538618 bytes (not committed)

CHECK:
  1. Sanity build PASS/FAIL, errors, bitstream bytes   PASS — GW_EXIT 0, no ERROR lines, .fs 36538618 bytes
  2. Top is exactly top                                 PASS — EX0101 Current top module is "top"; CT1135=0
  3. tmds_clk_n constrained                             PASS — IO_LOC "tmds_clk_n" G16, placed IOR105[B]

NOTES:
  CONTEXT.md CHANGED is 0: not decoded, not edited. No HANDOFF_SEEN.
  HDMI constraint-only change (P and N as separate pins). No HDL change.
  Nothing flashed. No bitstream, logs, or impl/ committed.
```
