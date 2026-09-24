# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-1
RESULT: FAIL
GOWIN_VERSION: V1.9.12.03
PROJECT: rigsdram
TOP: RIGSDRAM_TOP

ERRORS:
(none — synthesis/PnR completed; bitstream written to impl/pnr/rigsdram.fs)

WARNINGS:
AG0100 Find logical loop signal: 17 (wf68k30L_control.vhd / data registers; combinatorial loops in 68k core)
AG0101 netlist is not a DAG: 1
EX4664 buffer/out port mode mismatch: 6 (wf68k30L_pkg.vhd)
EX4967 Cannot read from 'out' object: 2 (wf68k30L_bus_interface.vhd:352)
EX4749 missing sensitivity: 2 (wf68k30L_alu.vhd:1135)
EX3791 truncated expression: 2 (pll_init.v:179,207)
EX4160 latch inferred: 1 (wf68k30L_alu.vhd:494)
EX4387 incomplete sensitivity: 1 (wf68k30L_alu.vhd:1309)
EX4545 array bounds mismatch: 1 (bus_trace.vhd:102)
NL0002 BUS_TRACE (U_TRC) swept in optimizing: 1 (rigsdram_top.vhd:390)
PR1014 generic routing for clock CLK_d: 1

RESOURCES:
LUT: 19228 / 138240 (Logic; 17731 LUT + 1497 ALU, 14%)
FF: 3555 / 138240 (3%)
BSRAM: 32 / 340 (10%)
DSP: 9 / 298 (4%)

TIMING:
Fmax:
  clk_ref  50.000 MHz constraint → 288.507 MHz actual
  clk50    50.000 MHz constraint → 140.292 MHz actual
  core_clk 12.500 MHz constraint → 17.637 MHz actual
Setup: worst slack +12.872 ns (clk50 path U_SDR/act_age→state); 0 violated endpoints; TNS 0
Hold: worst slack -0.355 ns (clk_ref→clk50, u_pll/u_pll_init/state_1_s0 → pll_lock_50_0_s0/RESET); 1 violated path in hold table (TNS endpoint summary shows 0 — see NOTES)

UART:
(not flashed; the bot cannot flash hardware)

NOTES:
Applied patches/H48_20260924-1.patch (CRLF mismatch on VHDL required LF convert then restore; content matches patch). Committed as Apply H48_20260924-1.
CHECK confirm: AUTO_WARM=0; sys_rst_n_50 exists; Replicate Resources = TRUE; device GW5AST-LV138PG484AC1/I0 version C.
Setup met; core_clk Fmax 17.637 MHz >= 12.5 MHz.
RESULT=FAIL: CHECK required ZERO hold paths from u_pll/u_pll_init/state_1_s0; one remains (see hold table). Prior oracle build had 28; H48 cleared the core_clk SET/CE fanout, left the first sync flop RESET.
```

---

## Hold table (paths from `u_pll/u_pll_init/state_1_s0`)

| # | Slack (ns) | From | To | Clocks | Skew (ns) | Data delay (ns) |
|---|------------|------|-----|--------|-----------|-----------------|
| 1 | **-0.355** | `u_pll/u_pll_init/state_1_s0/Q` | `pll_lock_50_0_s0/RESET` | clk_ref → clk50 | -1.274 | 0.869 |

No other hold-table paths launch from `state_1_s0`. Same-clock hold paths (U_SDR etc.) are positive (~+0.247 ns).

### Worst remaining path detail

- Launch: `clk_ref` via `CLK_ibuf` → `state_1_s0`
- Data: `state_1_s0/Q` → `u_pll/u_pll_init/O_LOCK_s2` → `pll_lock_50_0_s0/RESET`
- Latch: `clk50` from PLL CLKOUT0
- Relation 0.000 (related clocks); async-reset style endpoint on the first `pll_lock` synchroniser flop

### CHECK summary

1. AUTO_WARM=0, `sys_rst_n_50` present — **pass**
2. Zero hold paths from `u_pll/u_pll_init/state_1_s0` — **fail** (1 left)
3. Setup met; core_clk Fmax >= 12.5 MHz — **pass**
4. Report written with hold table + Fmax — done
5. Not flashed — done

RESULT=FAIL solely on (2).
