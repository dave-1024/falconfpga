# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260927-1
ACTION: BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?
WHAT_CHANGED: HDMI constraint only, in tang/console138k/atarist.cst. P and N are now separate pins, same balls, same style as the working hybrid. No HDL change. CONTEXT.md is unchanged. CHANGED is 0. Do not decode it.
CHECK: Sanity build only. Do not simulate. Do not flash. Do not push a bitstream or anything under impl/.
1. git pull, then build misterynano_tc138k with build_tc138k.tcl.
2. Report PASS or FAIL. Paste any ERROR with file and line. Bitstream size in bytes only.
3. Ignore the three known warnings: old_flg, fdc1772 always-loop, rtc_index.
4. Confirm the top is exactly top, and that tmds_clk_n is constrained. A wall of CT1135 means the top was wrong. Stop and report that.
```
