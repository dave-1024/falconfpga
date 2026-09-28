# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260928-2
ACTION: NO_BUILD
PROJECT: rigsdram
WORKDIR:
BUILD_CMD:
WHAT_CHANGED:
  Consumed. 20260928-2 PASS. Do not rebuild. Do not flash. Do not build misterynano_tc138k.
  CONTEXT.md is unchanged. CHANGED is 0. Do not decode it. Do not edit CONTEXT.md.
CHECK:
  Idle. Write nothing.
```
