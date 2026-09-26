# Agent protocol

Two files so Grok chat and Grok bot never overwrite each other.

Session state that must survive a new chat lives in **`CONTEXT.md`**. The body is obfuscated, not encrypted. Chat reads it when the window is empty and updates it when a bug, a test, a pinned idea, or the work state changes. Bump `HANDOFF` when it does. Write the body back in the same obfuscated form.

## Reading CONTEXT.md

1. The `HANDOFF:` line above the block is plain. Use that id. Do not build because it changed.
2. The fenced block is **standard base64** of the UTF-8 notes. Decode it before use.
3. There is no key. This is so a casual glance at GitHub does not read the notes. It is not a secret. The plaintext is still in older commits.
4. Bot never edits `CONTEXT.md`.

## Bot poll (every 15 min, 08:00–22:00 UK)

1. `git pull origin main`
2. Read **`CONTEXT.md` first.** Note the plain `HANDOFF` line. Decode the block. Re-read the open bugs, the in-flight test, and the pinned ideas. Do not start work because they are listed.
3. Read `BUILD_REQUEST.md` and `BUILD_REPORT.md`.
4. If `HANDOFF` differs from `HANDOFF_SEEN` in the last report, write one idle report and stop:
   - `RESULT: NOT_RUN`
   - `HANDOFF_SEEN:` the new id
   - one line: context re-read, no build
   - do not edit HDL, do not run Gowin
5. Otherwise run only if **all** of:
   - `ACTION` is `BUILD`, `BUILD_AND_FLASH`, or `PREPARE`
   - `REQUEST_ID` is **not** already the `REQUEST_ID` in `BUILD_REPORT.md`
6. If nothing matches, stop. Do not rebuild a consumed ID.

`PROJECT`, `WORKDIR`, and `BUILD_CMD` in the request say **what** to run. Do not assume `rigsdram`. Do not infer a job from `CONTEXT.md`.

## BUILD_REQUEST.md — Grok chat only

- `REQUEST_ID` — bump each cycle (`YYYYMMDD-N`)
- `ACTION` — `BUILD` | `BUILD_AND_FLASH` | `PREPARE` | `NO_BUILD`
- `PROJECT` — name only (`rigsdram` or `misterynano_tc138k`)
- `WORKDIR` — repo-relative folder to `cd` into
- `BUILD_CMD` — exact command (`gw_sh build_tc138k.tcl`). Empty on `PREPARE`/`NO_BUILD`
- `WHAT_CHANGED` `CHECK`

## BUILD_REPORT.md — Grok bot only

- `REQUEST_ID` — copy from the request that was run, or the current id on a handoff-only idle report
- `RESULT` — `PASS` | `FAIL` | `NOT_RUN`
- `HANDOFF_SEEN` — the plain `HANDOFF` id from `CONTEXT.md` this poll
- `GOWIN_VERSION` — or `NOT_RUN`
- Errors with **file:line**, LUT/FF/BSRAM/DSP, Fmax/hold if PnR ran
- Bitstream **size in bytes** only. Never attach the file.

## Git is source only (hard rule)

Bot and chat **never** push:

- `*.fs` `*.bin` `*.bit` `*.sof` `*.rbf`
- `impl/` (synth, pnr, timing html, reports)
- TOS ROMs, disk images, object files

Build products stay on the machine that ran Gowin. Report the path and byte count in `BUILD_REPORT.md`. David rebuilds locally when he wants a flash file.

## Rules

- Bot never edits `BUILD_REQUEST.md`, `CONTEXT.md`, or HDL unless the request names a patch to apply.
- Chat never edits `BUILD_REPORT.md` except after consuming a report.
- `NO_BUILD` means idle even if the bot wakes.
- A new `HANDOFF` is not a build.
