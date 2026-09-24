# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260924-3
ACTION: BUILD
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
CPU_TARGET_MHZ: 16.0
WHAT_CHANGED:
  Tree is H48-2. Apply BOTH:
    git apply --recount patches/H48_20260924-3.patch
    git apply --recount patches/H48_20260924-3_sdc.patch
  Commit both files. Then BUILD.
  Do NOT change the PLL. Fabric still runs core_clk at 12.5 MHz.
  AUTO_WARM stays 0. No wf68k30L.
CHECK:
  1. u_lock_meta exists.
  2. Hold: no lock_meta RESET path. Prefer zero state_1_s0 paths.
  3. Setup met.
  4. BUILD_REPORT MUST include an Fmax table for clk_ref, clk50, core_clk
     with constraint MHz and achieved MHz. Also worst setup slack.
  5. Note whether core_clk Fmax >= 16.0 MHz (CPU target). Do not FAIL
     the build only because the PLL is still 12.5. FAIL if core_clk
     Fmax < 16.0 (cannot hit the target when we retune).
  6. Do not flash.
```
