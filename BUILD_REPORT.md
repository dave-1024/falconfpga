# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260926-hdmi2
ACTION: SIMULATE
RESULT: FAIL
GOWIN_VERSION: V1.9.12.03 (gw_sh via /usr/local/bin/gowin-sh / /workspace/tools/bin/gowin-sh, Linux)
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?; bash sim/run_hdmi_sim.sh; echo SIM_EXIT:$?
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE (set_option -replicate_resources 1 in build_tc138k.tcl)
REPO COMMIT BUILT: 054913b

STAGE REACHED: Gowin full flow PASS (synthesis, place, route, timing, bitstream, power). HDMI pin sim FAIL at iverilog compile. GW_EXIT:0 SIM_EXIT:1. ~4.2 min for Gowin.
LICENCE: OK (attempt 1, no retries)

WHAT WAS RUN:
  1. git pull origin main (already at 054913b; includes drop of -co-place_io_registers)
  2. cd misterynano_tc138k && gw_sh build_tc138k.tcl (gowin-sh wrapper)
  3. bash sim/run_hdmi_sim.sh (even though build passed; both steps required)
  No patch. No HDL edits. rigsdram/ untouched. setup_after_update.sh not needed (gowin-sh and iverilog already on PATH).

GW:
  GW_RESULT: PASS
  GW_EXIT: 0
  ERRORS: none (no ERROR lines in Gowin log)
  current device: GW5AST-138C GW5AST-LV138PG484AC1/I0
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

SETUP / HOLD SUMMARY:
  Cross-clock Setup Paths Table worst −19.679 ns:
    from ds2_p1/rx_buffer[4]_7_s0/Q (ds2_p1/clk_spi)
    to   misterynano/atarist/ikbd/.../rP_13_s0/D (CLKOUT1 pixel clock)
  Cross-clock Hold Paths Table worst −2.065 ns (video2hdmi packet_picker CDC / audio paths).
  Same-clock Fmax for CLKOUT1 is only just above constraint (33.313 vs 31.667 MHz).

BITSTREAM:
  impl/pnr/atarist_tc138k.fs 36538618 bytes (not committed)

SIM:
  Tool: Icarus Verilog 12.0 (stable) at /workspace/tools/iverilog/bin (also /usr/local/bin)
  HDMI_SIM FAIL compile
  HDMI_EDGES: not printed (compile failed before vvp)
  First real iverilog error:
    hdmi/packet_assembler.sv:75: error: cannot perform a part select on array parity.
  Also many "sorry: Assignment to an entire array or to an array slice is not yet supported"
  (packet_picker.sv / packet_assembler.sv / tmds_channel.sv) and "16 error(s) during elaboration."
  IV_EXIT:16
  SIM_EXIT:1

CHECK:
  1. Gowin build PASS/FAIL, errors, bitstream bytes   PASS — GW_EXIT 0, no ERROR lines, .fs 36538618 bytes
  2. HDMI pin sim HDMI_EDGES / HDMI_SIM                 FAIL — HDMI_SIM FAIL compile (error above); no HDMI_EDGES line

NOTES:
  CONTEXT.md CHANGED is 0: not decoded, not edited. No HANDOFF_SEEN.
  Dropping -co-place_io_registers let the Gowin build complete (hdmi1 had never reached synthesis on this box).
  The HDMI sim is the encoder with a free-running pixel clock and the logic serializer (TMDS_BY_LOGIC).
  It is not the Gowin PLL and not OSER10. It does not prove the placed pins on the board.
  Nothing flashed. No bitstream, vvp, logs, or impl/ committed.
```
