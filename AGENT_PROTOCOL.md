# Agent protocol

Two files so Grok chat and Grok bot never overwrite each other.

## Legacy CONTEXT.md / BUILD_REQUEST.md flow (retired)

The former 15-minute watcher routine polled `CONTEXT.md` and `BUILD_REQUEST.md`, using the old
`CHANGED`/`READ` flags and base64 block to decide whether to build. The watcher routine is paused;
this flow is retained only as short history and is superseded by the **Patch handoff (from
2026-10-02)** section below. Grok Bot acts only when David says work is waiting.

Former file roles: `CONTEXT.md` held session state; `BUILD_REQUEST.md` carried `REQUEST_ID`,
`ACTION`, `PROJECT`, `WORKDIR`, `BUILD_CMD`, `WHAT_CHANGED`, and `CHECK`; `BUILD_REPORT.md` recorded
job or decode results. The old idle-poll/decode rules are retired and must not be used for new work.

## Git is source only (hard rule)

Bot and chat **never** push:

- `*.fs` `*.bin` `*.bit` `*.sof` `*.rbf`
- `impl/`
- TOS ROMs, disk images, object files

## Legacy file-ownership rules (retired)

The former ownership and `NO_BUILD` rules above are retained for history only; the Patch handoff
below is the current workflow.

## Patch handoff (from 2026-10-02)

The fast way for Grok chat to hand code changes to Grok Bot, instead of editing files on GitHub one
line at a time. It supersedes the retired `BUILD_REQUEST.md`/`CONTEXT.md` flow; a handoff does not
need either file to be touched. Template and example: `handoff/README.md`.

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
5. Grok Bot may flash on David's laptop when `ACTION` is `BUILD_AND_FLASH` or David asks. Use
   `programmer_cli` op 53, cable location **417 only**. Never 418. Never bulk erase.
6. Touch TOS at `0x500000` only when a TOS swap is requested: use `programmer_cli` op 56 with
   `--mcuFile` at `--spiaddr 0x500000` on location 417, images from `C:\tosimg`
   (`tos104.bin`, `emutos-192uk-1.4.img`), then reflash the core `.fs` with op 53.
7. Append the result to `BUILD_REPORT.md` under the `REQUEST_ID`: timing, flash result, and David's
   observed screen result once he reports it.
8. Move the handled `.patch` and `.md` to `handoff/done/` (rejected ones too) and push.

### Screen results

Screen captures are **suspended until a new capture device arrives**: the HDMI capture device was
faulty and has been returned. Screen results come from David looking at his monitor. Capture-based
results from 2026-10-01 are unreliable.

### No polling

Grok Bot does not poll for handoffs. The watcher routine is paused. David tells Grok Bot when a
handoff is waiting, and Grok Bot acts only then.

### Rules still apply

- No `.fs`, `impl/` or ROMs in git (see "Git is source only").
- Credit contributors (keep and extend the existing credits).
- No compatibility patches in the 030 builds: real-030 behaviour only.
