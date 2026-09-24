# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260924-2b
ACTION: BUILD
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  H48 already on main. Tree was left clean after 20260924-2 apply failure.
  Apply the FIXED patches/H48_20260924-2.patch (hunk counts corrected).
  git apply patches/H48_20260924-2.patch
  Commit VHDL. Then BUILD.
  AUTO_WARM stays 0. No wf68k30L. No false_path.
CHECK:
  1. lock_meta and lock_sync exist; pll_lock_50 gone.
  2. Prefer ZERO hold paths from state_1_s0. PASS if no fanout to
     tx_line/DATA_IN/wsc/DSACK/ref_due RESET/SET/CE.
  3. Setup met. core_clk Fmax >= 12.5 MHz.
  4. BUILD_REPORT with hold table + Fmax. Do not flash.
```
