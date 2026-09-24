# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-manual-1
RESULT: FAIL
GOWIN_VERSION: V1.9.12.03
PROJECT: rigsdram
TOP: RIGSDRAM_TOP

ERRORS:
(none — synthesis/PnR completed; bitstream written to impl/pnr/rigsdram.fs)

WARNINGS:
AG0100 Find logical loop signal: 17 (wf68k30L_control.vhd / data registers; combinatorial loops in 68k core)
AG0101 netlist is not a DAG: 1
EX4664 buffer/out port mode mismatch: 6 (wf68k30L_pkg.vhd)
EX4967 Cannot read from 'out' object: 2 (wf68k30L_bus_interface.vhd:352)
EX4749 missing sensitivity: 2 (wf68k30L_alu.vhd:1135)
EX3791 truncated expression: 2 (pll_init.v:179,207)
EX4160 latch inferred: 1 (wf68k30L_alu.vhd:494)
EX4387 incomplete sensitivity: 1 (wf68k30L_alu.vhd:1309)
EX4545 array bounds mismatch: 1 (bus_trace.vhd:102)
NL0002 BUS_TRACE (U_TRC) swept in optimizing: 1 (rigsdram_top.vhd:381)
PR1014 generic routing for clock CLK_d: 1

RESOURCES:
LUT: 19155 / 138240 (Logic; 17637 LUT + 1494 ALU, 14%)
FF: 3547 / 138240 (3%)
BSRAM: 32 / 340 (10%)
DSP: 9 / 298 (4%)

TIMING:
Fmax:
  clk_ref  50.000 MHz constraint → 329.584 MHz actual
  clk50    50.000 MHz constraint → 131.138 MHz actual
  core_clk 12.500 MHz constraint → 14.842 MHz actual
Setup: worst slack +12.374 ns (clk50 path); 0 violated endpoints; TNS 0
Hold: worst slack -0.403 ns (clk_ref→core_clk, u_pll/u_pll_init/state_1_s0 → tx_line_s0/SET); 28 violated endpoints

UART:
(not flashed)

NOTES:
Manual test build requested by David in chat. Replicate Resources = TRUE (confirmed in log: "CONFIRM: set_option -replicate_resources 1 applied"; process_config Replicate_Resources=true). BUILD_REQUEST.md left untouched (still 20260924-0 NO_BUILD). Device GW5AST-LV138PG484AC1/I0 device_version C. RESULT=FAIL due to 28 hold violations (worst -0.403 ns); setup and Fmax vs constraints are met.
```
