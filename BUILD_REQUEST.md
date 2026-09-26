# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260925-mn4-done
ACTION: NO_BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD:
WHAT_CHANGED: Idle. CONTEXT.md flags are HANDOFF 2026-09-26-4, CHANGED 0, READ 0. Do not decode.
CHECK: Idle. No Gowin. No decode.
```
