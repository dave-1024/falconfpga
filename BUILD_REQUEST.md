# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260924-2
ACTION: BUILD
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  H48 is already applied on main. NOW apply patches/H48_20260924-2.patch
  (git apply patches/H48_20260924-2.patch). Commit the VHDL.
  Replaces pll_lock_50 with lock_meta/lock_sync in a process that only
  does D<=pll_lock. No false_path. AUTO_WARM stays 0. No wf68k30L edits.
CHECK:
  1. lock_meta and lock_sync exist; pll_lock_50 is gone.
  2. Hold table: no paths from state_1_s0 to RESET/SET/CE of fabric.
     If one path remains to lock_meta/D that is acceptable to NOTE but
     RESULT=PASS only if there is no path to pll_lock_50_* / RESET and
     no fanout to tx_line/DATA_IN/wsc/DSACK/ref_due.
     Prefer ZERO paths from state_1_s0 at all.
  3. Setup met. core_clk Fmax >= 12.5 MHz.
  4. Write BUILD_REPORT with hold table + Fmax. Do not flash.
```
