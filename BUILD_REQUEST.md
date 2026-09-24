# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260924-1
ACTION: BUILD
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  rigsdram/src/rigsdram_top.vhd only.
  [H48] CDC: pll_lock is no longer combinational reset into clk50/core_clk.
  two-flop sync on clk50 -> sys_rst_n_50; two-flop sync on core_clk -> sys_rst_n.
  removed raw elsif pll_lock=0 in broker. adapter/sdram_ctrl/init_done use sys_rst_n_50.
  AUTO_WARM=0 so silicon is a real cold-boot test. Do not edit wf68k30L. No false_path.
CHECK:
  1. Hold table: ZERO paths from u_pll/u_pll_init/state_1_s0.
  2. Setup still met. core_clk Fmax >= 12.5 MHz.
  3. Paste hold table (max_paths 25) and Fmax into BUILD_REPORT.md.
  4. RESULT=PASS only if (1) is true. Bot does not flash.
  5. If PASS, David cold-powers the Tang (no S1) and looks for 12345 + DONE P.
```
