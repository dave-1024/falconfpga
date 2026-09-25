# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: if ACTION is BUILD/BUILD_AND_FLASH/PREPARE and this REQUEST_ID is not already in BUILD_REPORT.md, run BUILD_CMD in WORKDIR. PROJECT is not always rigsdram.

```
REQUEST_ID: 20260925-mn2
ACTION: BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  Sanity-check Gowin of OUR repo tree.
  git pull. cd WORKDIR. Confirm tcl device_version C.
  Run BUILD_CMD. Do not touch rigsdram. Do not flash. Do not rewrite HDL.
CHECK:
  1. PnR complete. Bitstream impl/pnr/atarist_tc138k.fs
  2. Log: device_version C and use_jtag_as_gpio 1
  3. BUILD_REPORT with ERRORS, LUT/FF/BSRAM/DSP, Fmax if printed, .fs bytes
  4. FAIL on first error with file:line. No HDL iteration.
```
