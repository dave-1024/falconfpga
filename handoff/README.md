# handoff/

**Agents: read [`CONTEXT.md`](CONTEXT.md) first** (goals, rules, access, board state, build, next fixes). Update it at each milestone.

Grok chat drops code changes here for Grok Bot. Full rules (retired flow, history): `docs/history/agent/AGENT_PROTOCOL.md`, section
"Patch handoff (from 2026-10-02)".

## One commit per change, two files with the same base name

- `handoff/<YYYYMMDD-HHMM>-<short-name>.patch`: unified diff from the repo root (`git diff` output,
  `a/` `b/` prefixes). Must pass `git apply --check` against current `main`. Several files go in one patch.
- `handoff/<YYYYMMDD-HHMM>-<short-name>.md`: the request (template below).

Or commit straight to a branch `handoff/<short-name>` and Grok Bot merges or applies it.

Grok Bot does not poll; the watcher routine is paused. David tells Grok Bot a handoff is waiting,
and Grok Bot acts only then. Handled files move to `handoff/done/`.

Screen results: Grok Bot grabs HDMI frames on the build box (`~/fpga_tools/grab.sh`), and David checks
his monitor. Board input goes through the helper console (`/dev/ttyUSB1`: `key`, `mouse`, `click`, `c`).

Never in git: `.fs`, `impl/`, ROMs, disk images. Credit contributors. No compatibility patches in the 030 builds.

## Before you write a change
- Build, switches, flash map and rules: [`Atarist_030_wip/docs/BUILD.md`](../Atarist_030_wip/docs/BUILD.md).
  Core = `gw_sh build_st_helper.tcl` (cart off, no SD debug; variants in `debug_builds/`, old ones in
  `build_legacy/`), flashed with op 53. TOS (0x500000) and the helper (0x600000) are written separately with op 56
  `--mcuFile`. Bulk erase and other flash areas: check with David first. Current state: [`CONTEXT.md`](CONTEXT.md).
- New behaviour goes behind a `define in `build_st_helper.tcl` (off until proven on the board).
- Open work and its order: [`docs/TODO.md`](../Atarist_030_wip/docs/TODO.md). Past bugs and lessons:
  [`docs/FALCON_LESSONS.md`](../Atarist_030_wip/docs/FALCON_LESSONS.md). SD path: [`docs/SD_WRITE_DEBUG.md`](../Atarist_030_wip/docs/SD_WRITE_DEBUG.md).
- Test images: check the CRC before and after a board test (gbref.st = 791ee820); use scratch images for writes.
- Merge to `main` normally (no force push) once the board test passes, and move fixed bugs from TODO.md to
  FALCON_LESSONS.md "Bugs found" (symptom, cause, fix, commit).

## Template (`.md`)

```
REQUEST_ID: YYYYMMDD-N
ACTION: APPLY_ONLY | BUILD | BUILD_AND_FLASH
WORKDIR: Atarist_030_wip
BUILD_CMD: gw_sh build_st_helper.tcl
TOS: keep | tos206 | emutos

WHAT: plain English, what the change does.
WHY: the reason for it.
LOOK FOR: what David should see on the monitor if it works, and if it does not.
```

## Example: `handoff/20261002-1430-clk32-margin.md`

```
REQUEST_ID: 20261002-3
ACTION: BUILD_AND_FLASH
WORKDIR: Atarist_030_wip
BUILD_CMD: gw_sh build_tc138k.tcl
TOS: emutos

WHAT: Registers the ikbd input from the ds2 SPI clock domain through a two-flop synchroniser
in atarist.v, and adds a clock group for ds2_p1/clk_spi in atarist.sdc.
WHY: clk32_core passes at 32.07 MHz with almost no margin; the negative-slack ds2 -> ikbd
paths look like an unconstrained clock-domain crossing.
LOOK FOR: EmuTOS boot screen then the GEM desktop. A black screen or "no signal" means it failed;
a crash dump on screen is useful, please read out the PC and exception number.
```

The matching patch would be `handoff/20261002-1430-clk32-margin.patch`.
