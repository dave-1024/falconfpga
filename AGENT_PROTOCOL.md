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

## Patch handoff (from 2026-10-02)

The fast way for Grok chat to hand code changes to Grok Bot, instead of editing files on GitHub one
line at a time. It runs alongside `BUILD_REQUEST.md`; a handoff does not need `BUILD_REQUEST.md` or
`CONTEXT.md` to be touched. Template and example: `handoff/README.md`.

### What Grok chat commits

**One commit per change**, adding two files with the same base name:

1. `handoff/<YYYYMMDD-HHMM>-<short-name>.patch`: a standard unified diff from the repo root
   (`git diff` style, `a/` and `b/` prefixes) that applies cleanly with `git apply` against current
   `main`. A change that touches several files goes in **one** patch.
2. `handoff/<YYYYMMDD-HHMM>-<short-name>.md` with:
   - `REQUEST_ID`: `YYYYMMDD-N`, unique
   - `ACTION`: `APPLY_ONLY` | `BUILD` | `BUILD_AND_FLASH`
   - `WORKDIR`: repo-relative folder, e.g. `Atarist_030_wip`
   - `BUILD_CMD`: default `gw_sh build_tc138k.tcl`
   - `TOS`: `keep` | `tos104` | `emutos`
   - a plain-English description of what the change does and why, and **what to look for on screen**

Alternative: commit the change directly to a branch named `handoff/<short-name>` (with the `.md`
in `handoff/` on that branch), and Grok Bot merges or applies it.

### What Grok Bot does

1. `git apply --check` first. If it does not apply, reject it: write the reason in
   `BUILD_REPORT.md` under the `REQUEST_ID` (`RESULT: NOT_RUN`) and apply nothing.
2. Apply and commit, with the `REQUEST_ID` in the commit message.
3. `APPLY_ONLY`: stop here (steps 7–8 still apply). `BUILD` / `BUILD_AND_FLASH`: build on David's
   Windows laptop in `WORKDIR` with `BUILD_CMD`, clean `impl/` first.
4. Check timing: `clk32_core` at least 32 MHz, `clk_cpu030` above 8 MHz, TNS 0. If timing fails,
   do not flash; report it.
5. Flash only when `ACTION` is `BUILD_AND_FLASH`: `programmer_cli` op 53, cable location **417
   only**. Never 418. Never bulk erase.
6. TOS swap when `TOS` is not `keep`: `programmer_cli` op 56 with `--mcuFile` at `--spiaddr 0x500000`
   on location 417, images from `C:\tosimg` (`tos104.bin`, `emutos-192uk-1.4.img`), then reflash the
   core `.fs` with op 53.
7. Append the result to `BUILD_REPORT.md` under the `REQUEST_ID`: timing, flash result, and David's
   observed screen result once he reports it.
8. Move the handled `.patch` and `.md` to `handoff/done/` (rejected ones too) and push.

### Screen results

Screen captures are **suspended**: the HDMI capture device was faulty and has been returned. Screen
results come from David looking at his monitor. Capture-based results from 2026-10-01 are unreliable.

### No polling

Grok Bot does not poll for handoffs. David tells Grok Bot when a handoff is waiting.

### Rules still apply

- No `.fs`, `impl/` or ROMs in git (see "Git is source only").
- Credit contributors (keep and extend the existing credits).
- No compatibility patches in the 030 builds: real-030 behaviour only.
