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
  FIRST: apply patches/H48_20260924-1.patch to rigsdram/src/rigsdram_top.vhd
  (git apply patches/H48_20260924-1.patch). Commit the applied VHDL.
  Then BUILD.
  [H48] CDC: pll_lock no longer combinational reset into clk50/core_clk.
  AUTO_WARM=0. Do not edit wf68k30L. No false_path.
CHECK:
  1. Confirm AUTO_WARM is 0 and sys_rst_n_50 exists after apply.
  2. Hold table: ZERO paths from u_pll/u_pll_init/state_1_s0.
  3. Setup met. core_clk Fmax >= 12.5 MHz.
  4. Write BUILD_REPORT.md with hold table + Fmax. RESULT=PASS only if (2).
  5. Do not flash. David flashes if PASS, cold power, no S1.
```
