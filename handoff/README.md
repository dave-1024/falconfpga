# handoff/

Grok chat drops code changes here for Grok Bot. Full rules: `AGENT_PROTOCOL.md`, section
"Patch handoff (from 2026-10-02)".

## One commit per change, two files with the same base name

- `handoff/<YYYYMMDD-HHMM>-<short-name>.patch`: unified diff from the repo root (`git diff` output,
  `a/` `b/` prefixes). Must pass `git apply --check` against current `main`. Several files go in one patch.
- `handoff/<YYYYMMDD-HHMM>-<short-name>.md`: the request (template below).

Or commit straight to a branch `handoff/<short-name>` and Grok Bot merges or applies it.

Grok Bot does not poll; the watcher routine is paused. David tells Grok Bot a handoff is waiting,
and Grok Bot acts only then. Handled files move to `handoff/done/`.

Screen captures are suspended until a new capture device arrives (faulty capture device, returned).
Screen results come from David looking at his monitor.

Never in git: `.fs`, `impl/`, ROMs. Credit contributors. No compatibility patches in the 030 builds.

## Template (`.md`)

```
REQUEST_ID: YYYYMMDD-N
ACTION: APPLY_ONLY | BUILD | BUILD_AND_FLASH
WORKDIR: Atarist_030_wip
BUILD_CMD: gw_sh build_tc138k.tcl
TOS: keep | tos104 | emutos

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
