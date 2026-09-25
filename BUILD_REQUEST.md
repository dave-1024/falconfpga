# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: if ACTION is BUILD/BUILD_AND_FLASH/PREPARE and this REQUEST_ID is not already in BUILD_REPORT.md, run BUILD_CMD in WORKDIR.

```
REQUEST_ID: 20260925-mn4
ACTION: BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  Toolchain replay only. No HDL. No patch. git pull. cd WORKDIR. BUILD_CMD.
  Do not touch rigsdram. Do not flash. Do not commit impl/ *.fs *.bin.
  Report byte count of .fs only.
CHECK:
  1. RESULT PASS or FAIL with file:line
  2. LUT/FF/BSRAM/DSP and .fs bytes (expect ~36538618 if same as mn3)
  3. device_version C in log
```
