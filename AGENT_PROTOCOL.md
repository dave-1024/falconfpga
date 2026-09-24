# Agent protocol

Two files so Grok chat and Grok bot never overwrite each other.

## BUILD_REQUEST.md — Grok chat only

Written when chat wants a Gowin run. Fields:

- `REQUEST_ID` — bump each cycle (`YYYYMMDD-N`)
- `ACTION` — `BUILD` | `BUILD_AND_FLASH` | `NO_BUILD`
- `PROJECT` — Gowin folder (`rigsdram`)
- `TOP` — top module
- `DEVICE` / `DEVICE_VERSION`
- `REPLICATE_RESOURCES` — keep TRUE unless chat says otherwise
- `WHAT_CHANGED` — files and why
- `CHECK` — what the bot must paste back (Fmax, hold, errors with file:line)

## BUILD_REPORT.md — Grok bot only

Written after each Gowin run. Fields:

- `REQUEST_ID` — copy from the request that was built
- `RESULT` — `PASS` | `FAIL` | `NOT_RUN`
- `GOWIN_VERSION`
- Errors / warnings with **file and line**
- LUT / FF / BSRAM / DSP
- Fmax and any hold/setup violations
- UART log if flashed

## Rules

- Bot never edits `BUILD_REQUEST.md` or HDL unless the request says to apply a listed patch.
- Chat never edits `BUILD_REPORT.md` except clearing it to the template after consuming a report.
- `impl/`, `*.fs`, `*.bin` stay out of git.
- Chat does not notice a new report by itself. The human says: `read BUILD_REPORT.md and fix the errors`.
