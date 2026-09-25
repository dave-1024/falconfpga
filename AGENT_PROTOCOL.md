# Agent protocol

Two files so Grok chat and Grok bot never overwrite each other.

## Bot poll (every 15 min, 08:00–22:00 UK)

1. `git pull origin main`
2. Read `BUILD_REQUEST.md` and `BUILD_REPORT.md`.
3. Run if **all** of:
   - `ACTION` is `BUILD`, `BUILD_AND_FLASH`, or `PREPARE`
   - `REQUEST_ID` is **not** already the `REQUEST_ID` in `BUILD_REPORT.md`
4. Otherwise stop. Do not rebuild a consumed ID.

`PROJECT`, `WORKDIR`, and `BUILD_CMD` in the request say **what** to run. Do not assume `rigsdram`.

## BUILD_REQUEST.md — Grok chat only

- `REQUEST_ID` — bump each cycle (`YYYYMMDD-N`)
- `ACTION` — `BUILD` | `BUILD_AND_FLASH` | `PREPARE` | `NO_BUILD`
- `PROJECT` — name only (`rigsdram` or `misterynano_tc138k`)
- `WORKDIR` — repo-relative folder to `cd` into
- `BUILD_CMD` — exact command (`gw_sh build_tc138k.tcl`). Empty on `PREPARE`/`NO_BUILD`
- `TOP` `DEVICE` `DEVICE_VERSION` `REPLICATE_RESOURCES`
- `WHAT_CHANGED` `CHECK`

## BUILD_REPORT.md — Grok bot only

- `REQUEST_ID` — copy from the request that was run
- `RESULT` — `PASS` | `FAIL` | `NOT_RUN`
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

- Bot never edits `BUILD_REQUEST.md` or HDL unless the request names a patch to apply.
- Chat never edits `BUILD_REPORT.md` except after consuming a report.
- `NO_BUILD` means idle even if the bot wakes.
