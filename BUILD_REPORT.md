# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-3
RESULT: FAIL
GOWIN_VERSION: V1.9.12.03
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C

ERRORS:
ERROR (TA2003): rigsdram/src/rigsdram.sdc:93 | Can't set timing constraint to object
  Constraint: set_false_path -from [get_pins {u_pll/u_pll_init/state_1_s0/Q}] -to [get_pins {lock_meta_s0/RESET}]
  Cause: after H48-3 the first lock flop is instance u_lock_meta, so pin lock_meta_s0/RESET no longer exists.
  Effect: Place&Route aborted; no bitstream, no post-PnR timing or resource totals from this run.

WARNINGS:
(summarised from synthesis; non-fatal; PnR did not run)
AG0100 logical loop signals in wf68k30L core ×17 (same family as prior builds)
EX4664 VHDL port-mode buffer/out mismatches in wf68k30L_* ×6
EX4967 / EX4749 / EX3791 / EX4160 / EX4387 / EX4545 (wf68k30L / pll_init / bus_trace; unchanged family)
NL0002 BUS_TRACE instance swept in optimising (as prior)
AG0101 netlist is not one directed acyclic graph (as prior with AG0100)

RESOURCES:
(not available — PnR did not complete)
LUT: n/a
FF: n/a
BSRAM: n/a
DSP: n/a

TIMING:
Fmax table (constraint MHz → achieved MHz):
  clk_ref  — n/a (PnR aborted)
  clk50    — n/a (PnR aborted)
  core_clk — n/a (PnR aborted)
CPU_TARGET_MHZ: 16.0 — CANNOT VERIFY (no post-route Fmax)
Setup: n/a
Hold: n/a

CHECK:
  1. u_lock_meta exists: YES in synth netlist (impl/gwsynthesis/rigsdram.vg)
     Mapped as DFFRE u_lock_meta (.D(pll_lock_3), .CLK(clk50), .RESET(GND), .CE(VCC))
     — Gowin promoted the declared DFF primitive to DFFRE with RESET tied to GND.
  2. Hold / lock_meta RESET path: NOT EVALUATED (no PnR). Note: RESET pin still present on
     the cell but driven by GND; lock_meta_s0 name is gone.
  3. Setup met: NOT EVALUATED
  4. Fmax table: missing (see TIMING)
  5. core_clk Fmax >= 16.0 MHz: UNKNOWN — build FAILed before timing
  6. Not flashed

UART:
(not flashed; the bot cannot flash hardware)

NOTES:
Applied patches/H48_20260924-3.patch and patches/H48_20260924-3_sdc.patch with
`git apply --recount --ignore-whitespace` (CRLF vs LF). Committed as
08fc186 Apply H48_20260924-3: DFF lock_meta + SDC false_path.
Replicate Resources: TRUE (build.tcl set_option -replicate_resources 1; process_config true).
Synthesis completed; PnR stopped at SDC parse on line 93.
Likely fix for Grok chat: drop or retarget the lock_meta_s0/RESET false_path (instance is
now u_lock_meta). Optional: also false-path to u_lock_meta/D (line 92 was not reached as a
second TA2003 because run aborted on 93; verify pin name against the vg).
Do NOT change the PLL (per request). AUTO_WARM left 0.
```
