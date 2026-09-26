# Agent protocol

Two files so Grok chat and Grok bot never overwrite each other.

Session state that must survive a new chat lives in **`CONTEXT.md`**. The body is obfuscated, not encrypted. Chat updates it when a bug, a test, a pinned idea, or the work state changes.

## CONTEXT.md — three plain lines, then a block

Every poll, read **only** these lines. Do not decode the block on an idle wake.

```
HANDOFF: 2026-09-26-4
CHANGED: 0
READ: 0
```

- `HANDOFF` — chat bumps this when the notes change. Not a build.
- `CHANGED: 1` — notes are newer than the last time the bot decoded them. Chat sets this. Bot clears it after a real read.
- `READ: 1` — someone asked the bot to read, with no build. Chat sets this. Bot clears it after a real read. Ignored if `CHANGED` is 0.

Decode the block only when **`CHANGED` is 1** and any of:

- `ACTION` is `BUILD`, `BUILD_AND_FLASH`, `PREPARE`, or `SIMULATE`
- `READ` is 1

If `CHANGED` is 0, do not decode. Not on a build. Not because `READ` is 1. Not because `HANDOFF` looks new.

After a decode, and only then:

- set `CHANGED` to 0 and `READ` to 0
- commit **only those two lines**. Do not touch `HANDOFF` or the block
- echo `HANDOFF_SEEN` in the report
- then run the build or simulate if one was requested

An idle poll writes nothing.

The block is standard base64. No key. Not a secret.

## Bot poll (every 15 min, 08:00–22:00 UK)

1. `git pull origin main`
2. Read the three plain lines in `CONTEXT.md`. Stop there unless the rule above says decode.
3. Read `BUILD_REQUEST.md` and `BUILD_REPORT.md`.
4. Decode only if the rule above says so. Then clear the two flags.
5. Otherwise run only if **all** of:
   - `ACTION` is `BUILD`, `BUILD_AND_FLASH`, `PREPARE`, or `SIMULATE`
   - `REQUEST_ID` is **not** already the `REQUEST_ID` in `BUILD_REPORT.md`
6. If nothing matches, stop. Do not rebuild a consumed ID. Do not write a report.

`PROJECT`, `WORKDIR`, and `BUILD_CMD` say **what** to run. Do not assume `rigsdram`. Do not infer a job from `CONTEXT.md`.

## BUILD_REQUEST.md — Grok chat only

- `REQUEST_ID` — bump each cycle (`YYYYMMDD-N`)
- `ACTION` — `BUILD` | `BUILD_AND_FLASH` | `PREPARE` | `SIMULATE` | `NO_BUILD`
- `PROJECT` — name only (`rigsdram` or `misterynano_tc138k`)
- `WORKDIR` — repo-relative folder to `cd` into
- `BUILD_CMD` — exact command. Empty on `NO_BUILD`
- `WHAT_CHANGED` `CHECK`

## BUILD_REPORT.md — Grok bot only

Write a report only when a job ran, or when a decode actually happened.

- `REQUEST_ID`
- `RESULT` — `PASS` | `FAIL` | `NOT_RUN`
- `HANDOFF_SEEN` — only if the block was decoded this poll
- `GOWIN_VERSION` — or `NOT_RUN`
- Errors with **file:line**, LUT/FF/BSRAM/DSP, Fmax/hold if PnR ran
- Bitstream **size in bytes** only. Never attach the file.

## Git is source only (hard rule)

Bot and chat **never** push:

- `*.fs` `*.bin` `*.bit` `*.sof` `*.rbf`
- `impl/`
- TOS ROMs, disk images, object files

## Rules

- Bot never edits `BUILD_REQUEST.md` or HDL unless the request names a patch.
- Bot may edit `CONTEXT.md` only to set `CHANGED: 0` and `READ: 0` after a decode.
- Chat never edits `BUILD_REPORT.md` except after consuming a report.
- `NO_BUILD` means idle. Do not decode.
