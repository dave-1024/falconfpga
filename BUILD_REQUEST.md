# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read `CONTEXT.md` first and note `HANDOFF`. Then read this file. A new `HANDOFF` means the chat changed or the state file was updated. Re-read it. Do not build because of that. Echo `HANDOFF_SEEN` in the report.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260925-mn4-done
ACTION: NO_BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD:
WHAT_CHANGED: mn4 PASS consumed. Replay matched mn3. No binaries pushed. Idle. CONTEXT.md is now the cross-chat handoff (HANDOFF 2026-09-26-2). Read it every poll. Do not build.
CHECK: Idle. Echo HANDOFF_SEEN. No Gowin.
```
