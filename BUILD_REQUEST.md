# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260925-mn2
ACTION: BUILD
PROJECT: misterynano_tc138k
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  Sanity-check Gowin build of OUR repo tree, not a fresh upstream clone.
  git pull origin main.
  cd misterynano_tc138k
  Confirm build_tc138k.tcl line is:
    set_device GW5AST-LV138PG484AC1/I0 -device_version C
  Run: gw_sh build_tc138k.tcl
  Working directory MUST be misterynano_tc138k (gprj paths are relative).
  Do NOT touch rigsdram/. Do NOT flash. Do NOT rewrite HDL.
CHECK:
  1. Synthesis + PnR complete. Bitstream impl/pnr/atarist_tc138k.fs
  2. Log shows device_version C and use_jtag_as_gpio 1
  3. BUILD_REPORT: RESULT, ERRORS, resource LUT/FF/BSRAM/DSP,
     Fmax if Gowin printed any, bitstream size in bytes.
  4. FAIL on first error with file:line. Do not keep iterating HDL.
```
