# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read `CONTEXT.md` first. The `HANDOFF:` line is plain. The fenced block is standard base64 — decode it before use. There is no key. A new `HANDOFF` means the chat changed or the state file was updated. Re-read it. Do not build because of that. Echo `HANDOFF_SEEN` in the report.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260925-mn4-done
ACTION: NO_BUILD
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD:
WHAT_CHANGED: Idle. CONTEXT.md body is now obfuscated (base64, no key). HANDOFF 2026-09-26-3. Decode the block. Do not build.
CHECK: Idle. Echo HANDOFF_SEEN. No Gowin.
```
