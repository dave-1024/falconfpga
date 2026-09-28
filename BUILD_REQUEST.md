# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260928-2
ACTION: BUILD
PROJECT: rigsdram
WORKDIR: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
BUILD_CMD: gw_sh build_rigsdram.tcl; echo GW_EXIT:$?
WHAT_CHANGED:
  20260928-1 is withdrawn. Do not build misterynano_tc138k. Do not flash a Nano bitstream if one is already sitting there.
  No HDL change in this request. The SDC fix is already on main (dropped the false path that named lock_meta_s0/RESET). That pin does not exist after H48-3. Naming it is TA2003 and stops the build.
  The remaining false path is u_pll/u_pll_init/state_1_s0/Q to u_lock_meta/D only. Do not put the RESET line back.
  CONTEXT.md is unchanged. CHANGED is 0. Do not decode it. Do not edit CONTEXT.md.
CHECK:
  1. git pull, then build rigsdram only, from rigsdram/, with build_rigsdram.tcl.
  2. Do not simulate. Do not flash. Do not edit HDL. Do not apply a patch. Do not push impl/ or a bitstream.
  3. RESULT=PASS only if GW_EXIT is 0 and the log has no TA2003. If TA2003 names lock_meta_s0/RESET, paste that line with file and line and stop.
  4. NL0002 BUS_TRACE swept is not a failure. AG0100 loops in wf68k30L are not a failure.
  5. Confirm top is RIGSDRAM_TOP, device version C, and replicate_resources 1 was applied.
  6. Paste core_clk Fmax, worst hold path (from/to/slack), LUT/FF/BSRAM/DSP, and bitstream size in bytes only.
```
