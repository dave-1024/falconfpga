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
WHAT_CHANGED:
  Tree is H48-2. Apply BOTH:
    git apply --recount patches/H48_20260924-3.patch
    git apply --recount patches/H48_20260924-3_sdc.patch
  Commit both files. Then BUILD.
  DFF primitive for lock_meta (no RESET pin) plus two pin-local false_paths.
  AUTO_WARM stays 0. No wf68k30L.
CHECK:
  1. u_lock_meta exists. lock_meta is not assigned in a clocked process.
  2. Hold table: no lock_meta RESET path. Prefer zero state_1_s0 paths.
  3. Setup met. core_clk Fmax >= 12.5 MHz.
  4. BUILD_REPORT. Do not flash. David may already be flashing 2b.
```
