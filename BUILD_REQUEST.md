# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260928-1
ACTION: BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?
WHAT_CHANGED: Timer C life-sign only. atarist/mfp.v exports timerc_pulse (assign from timerc_done). tang/console138k/top.sv samples misterynano.atarist.mfp.timerc_pulse hierarchically and holds leds_n[0] on the 2 Hz fabric blink until 100 Timer C pulses, then switches to a slower blink. No new port on misterynano or atarist. A later commit also dropped a dead lock_meta_s0/RESET false path in rigsdram/src/rigsdram.sdc. Do not build rigsdram for this request. CONTEXT.md is unchanged. CHANGED is 0. Do not decode it. Do not edit CONTEXT.md.
CHECK: Sanity build only. Do not simulate. Do not flash. Do not push a bitstream or anything under impl/. Do not edit HDL.
1. git pull, then build misterynano_tc138k with build_tc138k.tcl.
2. Report PASS or FAIL. Paste any ERROR with file and line. Bitstream size in bytes only.
3. Ignore the three known warnings: old_flg, fdc1772 always-loop, rtc_index.
4. Confirm the top is exactly top. A wall of CT1135 means the top was wrong. Stop and report that.
5. Confirm the hierarchical probe compiled. If Gowin rejects misterynano.atarist.mfp.timerc_pulse, paste that error with file and line and stop. Do not add a port to fix it.
```
