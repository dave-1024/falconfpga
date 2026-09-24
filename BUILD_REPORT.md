# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-2b
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
AG0100 logical loop signals in wf68k30L core (same family as prior builds)
EX* VHDL port-mode / sensitivity warnings in wf68k30L_* (unchanged family)
NL0002 BUS_TRACE instance swept in optimising (as prior)
PR1014 generic routing for a clock net (as prior)

RESOURCES:
LUT: 19252 / 138240 (Logic; 17731 LUT + 1497 ALU, 14%)
FF: 3555 / 138240 (3%)
BSRAM: 32 / 340 (10%)
DSP: 9 / 298 (4%)

TIMING:
Fmax:
  clk_ref  50.000 MHz constraint → 288.507 MHz actual
  clk50    50.000 MHz constraint → 140.848 MHz actual
  core_clk 12.500 MHz constraint → 18.901 MHz actual
Setup: 0 violated endpoints; worst slack in top-25 table +12.900 ns; TNS 0 all clocks
Hold: 1 violated endpoint (see table). Per-clock hold TNS reported 0.

HOLD TABLE (state_1_s0 / top hold paths):
  Slack    From                                      To                       Clocks
  -0.572   u_pll/u_pll_init/state_1_s0/Q             lock_meta_s0/RESET       clk_ref→clk50
  +0.247   (next paths are same-clock SDRAM regs; no fabric RESET/SET/CE from state_1_s0)

CHECK:
  lock_meta: PRESENT
  lock_sync: PRESENT
  pll_lock_50: GONE
  Hold fanout from state_1_s0 to tx_line/DATA_IN/wsc/DSACK/ref_due RESET|SET|CE: NONE
  Remaining hold: only lock_meta_s0/RESET (dedicated sync flop; allowed by REQUEST CHECK)
  Setup met; core_clk Fmax 18.901 >= 12.5 MHz
  Replicate Resources: TRUE (log: CONFIRM: set_option -replicate_resources 1 applied; process_config Replicate_Resources=true)

UART:
(not flashed)

NOTES:
Applied fixed patches/H48_20260924-2.patch via `git apply --recount` after CRLF→LF (hunk line counts still off by one trailing blank; --recount accepted). Restored CRLF. H48-1 not re-applied. Bitstream: rigsdram/impl/pnr/rigsdram.fs (gitignored).
```
