# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: if ACTION is BUILD/BUILD_AND_FLASH/PREPARE and this REQUEST_ID is not already in BUILD_REPORT.md, run BUILD_CMD in WORKDIR.

```
REQUEST_ID: 20260925-mn3
ACTION: BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  mn2 FAIL is EX3990: top.sv:243 .clk on misterynano, port gone.
  Console 60K top already has no .clk. Apply only:
    git apply --recount --ignore-whitespace patches/MN_20260925-mn3.patch
  Commit the top.sv change. Then cd WORKDIR and run BUILD_CMD.
  Do not touch rigsdram. Do not flash. No other HDL.
CHECK:
  1. PnR complete. impl/pnr/atarist_tc138k.fs exists
  2. device_version C. use_jtag_as_gpio 1 in tcl
  3. BUILD_REPORT ERRORS, LUT/FF/BSRAM/DSP, Fmax if any, .fs bytes
  4. FAIL on first error with file:line
```
