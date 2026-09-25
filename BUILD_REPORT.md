# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-3b
RESULT: PASS
GOWIN_VERSION: V1.9.12.03
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C

ERRORS:
(none — synthesis/PnR completed; bitstream written)

WARNINGS:
(summarised; non-fatal)
AG0100 logical loop signals in wf68k30L core ×17 (same family as prior builds)
EX4664 VHDL port-mode buffer/out mismatches in wf68k30L_* ×6
EX4967 / EX4749 / EX3791 ×2 each; EX4545 / EX4387 / EX4160 ×1 (wf68k30L / bus_trace; unchanged family)
NL0002 BUS_TRACE instance swept in optimising (as prior)
AG0101 netlist is not one directed acyclic graph (as prior with AG0100)
PR1014 generic routing for clock net CLK_d (as prior)

RESOURCES:
LUT: 19163 / 138240 (Logic; 17665 LUT + 1498 ALU, 14%)
FF: 3555 / 138240 (3%)
BSRAM: 32 / 340 (10%)
DSP: 9 / 298 (4%)

TIMING:
Fmax:
  clk_ref  50.000 MHz constraint → 310.692 MHz actual
  clk50    50.000 MHz constraint → 124.060 MHz actual
  core_clk 12.500 MHz constraint → 18.228 MHz actual
CPU_TARGET_MHZ: 16.0 — PASS (core_clk Fmax 18.228 >= 16.0)
Setup: 0 violated endpoints; worst slack in top-25 table +11.939 ns; TNS 0 all clocks
Hold: per-clock hold TNS reported 0; 1 cross-clock hold path with negative slack (see table)

HOLD TABLE (top hold paths):
  Slack    From                                      To                       Clocks
  -0.680   u_pll/u_pll_init/state_2_s0/Q             u_lock_meta/D            clk_ref→clk50
  +0.247   (next paths are same-clock SDRAM/CPU regs)

CHECK:
  1. PnR completes / bitstream written: YES (impl/pnr/rigsdram.fs)
  2. Fmax table present; core_clk 18.228 >= 16.0: PASS
  3. Hold fabric RESET/SET/CE from state_1_s0: NONE
     lock_meta D false_path (state_1_s0/Q → u_lock_meta/D): Actived (TC_FALSE_PATH)
     Remaining hold is state_2_s0/Q → u_lock_meta/D (not covered by the state_1 false_path)
  4. Not flashed
  Replicate Resources: TRUE (build.tcl set_option -replicate_resources 1; process_config true)
  AUTO_WARM: 0 (HDL generic default; unchanged)

UART:
(not flashed; the bot cannot flash hardware)

NOTES:
Applied only patches/H48_20260924-3b.patch with `git apply --recount --ignore-whitespace`
(deleted the dead lock_meta_s0/RESET false_path that caused TA2003 on 20260924-3).
Did NOT re-apply H48-3 VHDL (already on main). Did NOT need to delete the
u_lock_meta/D false_path — no TA2003; constraint Actived.
SDC change left unstaged (bot commits only BUILD_REPORT.md).
No PLL / wf68k30L edits. Bitstream: rigsdram/impl/pnr/rigsdram.fs (gitignored).
```
