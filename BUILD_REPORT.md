# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-manual-1
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
NL0002 BUS_TRACE (U_TRC) swept in optimizing: 1 (rigsdram_top.vhd:381)
PR1014 generic routing for clock CLK_d: 1

RESOURCES:
LUT: 19155 / 138240 (Logic; 17637 LUT + 1494 ALU, 14%)
FF: 3547 / 138240 (3%)
BSRAM: 32 / 340 (10%)
DSP: 9 / 298 (4%)

TIMING:
Fmax:
  clk_ref  50.000 MHz constraint → 329.584 MHz actual
  clk50    50.000 MHz constraint → 131.138 MHz actual
  core_clk 12.500 MHz constraint → 14.842 MHz actual
Setup: worst slack +12.374 ns (clk50 path); 0 violated endpoints; TNS 0
Hold: worst slack -0.403 ns (clk_ref→core_clk, u_pll/u_pll_init/state_1_s0 → tx_line_s0/SET); 28 violated endpoints

UART:
(not flashed)

NOTES:
Manual test build (toolchain). Replicate Resources = TRUE. BUILD_REQUEST.md untouched (20260924-0 NO_BUILD).
Device GW5AST-LV138PG484AC1/I0 version C. RESULT=FAIL due to 28 hold violations; setup/Fmax OK.
```

---

## Hold timing investigation (added for debug / cold-reset hunt)

**Why this matters:** David reports an intermittent cold-reset issue that has cost weeks. This build's hold failures are a strong static-timing candidate for that class of bug: a short path from the PLL init FSM on `clk_ref` into many flip-flops on `core_clk` / `clk50`, with PLL clock skew of about 1.3 ns. Silicon can still pass most of the time (margins are only tenths of a nanosecond), which matches "usually works, fails on cold reset".

### What hold means here

- **Setup / Fmax:** met. Design is not too slow.
- **Hold:** data from a launch flop arrives *too early* at a capture flop, so the new value can overwrite before the capture flop has finished holding the previous value. Checked in the fast silicon corner.
- All 28 failures share **one launch flop:** `u_pll/u_pll_init/state_1_s0` (PLL init FSM, clocked by `clk_ref` = board 50 MHz pin).
- Capture clocks: mostly `core_clk` (PLL CLKOUT1, 12.5 MHz), one path into `clk50` (PLL CLKOUT0).
- Hold relationship: **0.000** (same edge; clocks are related through the PLL, as intended in `rigsdram.sdc`).
- This is **not** the old fabric `/4` divider hold problem described in the SDC comments. That was fixed by using the PLL. What remains is a **cross-clock reset/control fanout** from `pll_init` into the PLL output domains.

### Worst path (Path 1)

| Item | Value |
|------|--------|
| Slack | **-0.403 ns** |
| From | `u_pll/u_pll_init/state_1_s0/Q` |
| To | `tx_line_s0/SET` |
| Launch clock | `clk_ref` |
| Latch clock | `core_clk` |
| Data delay | 0.851 ns |
| Clock skew | ~1.304 ns (`core_clk` arrives later at the capture flop, mainly PLL insertion delay) |

Data arrival path (abbreviated):

1. `clk_ref` → `CLK_ibuf` → `state_1_s0/CLK`
2. `state_1_s0/Q` → `LED_d_0_s` → `n2830_s3` → `tx_line_s0/SET`

Required path: `core_clk` from `u_pll/u_pll_0/PLL_inst/CLKOUT1` → `tx_line_s0/CLK`.

### All reported hold endpoints (tool listed top 25 of 28)

Every path launches from `u_pll/u_pll_init/state_1_s0/Q`.

| # | Slack (ns) | To node | To clock |
|---|------------|---------|----------|
| 1 | -0.403 | `tx_line_s0/SET` | core_clk |
| 2 | -0.182 | `DATA_IN_1_s0/CE` | core_clk |
| 3 | -0.092 | `DATA_IN_4_s0/CE` | core_clk |
| 4 | -0.084 | `DATA_IN_9_s0/CE` | core_clk |
| 5 | -0.084 | `DATA_IN_10_s0/CE` | core_clk |
| 6 | -0.084 | `DATA_IN_18_s0/CE` | core_clk |
| 7 | -0.084 | `DATA_IN_22_s0/CE` | core_clk |
| 8 | -0.072 | `wsc_0_s0/RESET` | core_clk |
| 9 | -0.072 | `wsc_1_s0/RESET` | core_clk |
| 10 | -0.072 | `wsc_2_s0/RESET` | core_clk |
| 11 | -0.072 | `wsc_3_s0/RESET` | core_clk |
| 12 | -0.072 | `irq_level_1_s1/RESET` | core_clk |
| 13 | -0.070 | `DATA_IN_12_s0/CE` | core_clk |
| 14 | -0.070 | `acked_s0/RESET` | core_clk |
| 15 | -0.068 | `DATA_IN_20_s0/CE` | core_clk |
| 16 | -0.068 | `DATA_IN_28_s0/CE` | core_clk |
| 17 | -0.067 | `DATA_IN_2_s0/CE` | core_clk |
| 18 | -0.067 | `DATA_IN_8_s0/CE` | core_clk |
| 19 | -0.067 | `DATA_IN_30_s0/CE` | core_clk |
| 20 | -0.065 | `DATA_IN_13_s0/CE` | core_clk |
| 21 | -0.044 | `U_SDR/ref_due_s0/RESET` | **clk50** |
| 22 | -0.032 | `DSACKn_1_s0/SET` | core_clk |
| 23 | -0.027 | `DATA_IN_19_s0/CE` | core_clk |
| 24 | -0.027 | `DATA_IN_27_s0/CE` | core_clk |
| 25 | -0.026 | `DATA_IN_29_s0/CE` | core_clk |

Three more endpoints exist (tool: 28 total) beyond this top-25 table; same launch, same family.

### Likely RTL / architecture meaning

`pll_init` (`src/pll_init.v`) runs on `clk_ref` and drives state that fans out into:

- UART / line logic (`tx_line` SET)
- 68k bus adapter capture enables (`DATA_IN_*` CE)
- Wait-state / ack / IRQ resets (`wsc_*`, `acked`, `irq_level`, `DSACKn`)
- SDRAM controller refresh timer reset (`U_SDR/ref_due`)

If that fanout is used as an async reset, sync reset, or clock-enable into the PLL domains **without a 2-flop synchroniser per destination clock**, cold power-up is exactly when you see it: PLL lock timing, voltage ramp, and routing delay all move, and a race that static timing already flags at −0.4 ns can leave flops in the wrong state after reset.

### Suggested investigation order (for David / Grok chat)

1. In `pll_init.v` / `rigsdram_top.vhd`, find every net driven from `state` (especially `state[1]` / unlock / reset / enable) that leaves the `clk_ref` domain.
2. Confirm whether destinations treat it as async reset, sync reset, or CE. Async into another clock is the highest risk for cold reset.
3. Prefer: synchronise once into `core_clk` and once into `clk50` (two flops each), then distribute only inside that domain. Or assert reset while PLL is unlocked and deassert only after lock, still synchronised.
4. Do **not** mark these paths false_path unless you can prove destinations ignore the signal except at a safe idle state.
5. Rebuild after the fix; hold endpoints from `state_1_s0` should go to 0. Keep Replicate Resources TRUE, device version C.

### Tooling notes

- Report source: `rigsdram/impl/pnr/rigsdram.tr` (local after build; gitignored under `impl/`).
- Same-clock hold inside `core_clk` / `clk50` / `clk_ref`: clean (TNS 0 for those rows).
- Gowin's "Total Negative Slack Summary" still shows 0.000 for hold on each clock — **do not trust it for cross-clock paths**; read the Hold Paths Table (as the SDC already warns).

### Raw hold table excerpt from Gowin

```
<Report Command>:report_timing -hold -max_paths 25 -max_common_paths 1
  Path Number   Path Slack             From Node                    To Node           From Clock      To Clock     Relation   Clock Skew   Data Delay  
 ============= ============ =============================== ======================== ============= ============== ========== ============ ============ 
  1             -0.403       u_pll/u_pll_init/state_1_s0/Q   tx_line_s0/SET           clk_ref:[R]   core_clk:[R]   0.000      -1.304       0.851       
  2             -0.182       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_1_s0/CE          clk_ref:[R]   core_clk:[R]   0.000      -1.321       1.112       
  3             -0.092       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_4_s0/CE          clk_ref:[R]   core_clk:[R]   0.000      -1.318       1.199       
  4             -0.084       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_9_s0/CE          clk_ref:[R]   core_clk:[R]   0.000      -1.312       1.201       
  5             -0.084       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_10_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.312       1.201       
  6             -0.084       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_18_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.312       1.201       
  7             -0.084       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_22_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.312       1.201       
  8             -0.072       u_pll/u_pll_init/state_1_s0/Q   wsc_0_s0/RESET           clk_ref:[R]   core_clk:[R]   0.000      -1.317       1.195       
  9             -0.072       u_pll/u_pll_init/state_1_s0/Q   wsc_1_s0/RESET           clk_ref:[R]   core_clk:[R]   0.000      -1.317       1.195       
  10            -0.072       u_pll/u_pll_init/state_1_s0/Q   wsc_2_s0/RESET           clk_ref:[R]   core_clk:[R]   0.000      -1.317       1.195       
  11            -0.072       u_pll/u_pll_init/state_1_s0/Q   wsc_3_s0/RESET           clk_ref:[R]   core_clk:[R]   0.000      -1.317       1.195       
  12            -0.072       u_pll/u_pll_init/state_1_s0/Q   irq_level_1_s1/RESET     clk_ref:[R]   core_clk:[R]   0.000      -1.310       1.188       
  13            -0.070       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_12_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.313       1.216       
  14            -0.070       u_pll/u_pll_init/state_1_s0/Q   acked_s0/RESET           clk_ref:[R]   core_clk:[R]   0.000      -1.313       1.193       
  15            -0.068       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_20_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.313       1.218       
  16            -0.068       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_28_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.313       1.218       
  17            -0.067       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_2_s0/CE          clk_ref:[R]   core_clk:[R]   0.000      -1.309       1.214       
  18            -0.067       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_8_s0/CE          clk_ref:[R]   core_clk:[R]   0.000      -1.309       1.214       
  19            -0.067       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_30_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.309       1.214       
  20            -0.065       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_13_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.310       1.218       
  21            -0.044       u_pll/u_pll_init/state_1_s0/Q   U_SDR/ref_due_s0/RESET   clk_ref:[R]   clk50:[R]      0.000      -1.287       1.193       
  22            -0.032       u_pll/u_pll_init/state_1_s0/Q   DSACKn_1_s0/SET          clk_ref:[R]   core_clk:[R]   0.000      -1.302       1.220       
  23            -0.027       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_19_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.302       1.248       
  24            -0.027       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_27_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.302       1.248       
  25            -0.026       u_pll/u_pll_init/state_1_s0/Q   DATA_IN_29_s0/CE         clk_ref:[R]   core_clk:[R]   0.000      -1.302       1.249       

```

### Raw worst-path excerpt

```
Report Command:report_timing -hold -max_paths 25 -max_common_paths 1
						Path1						
Path Summary:
Slack             : -0.403
Data Arrival Time : 83.441
Data Required Time: 83.844
From              : u_pll/u_pll_init/state_1_s0
To                : tx_line_s0
Launch Clk        : clk_ref:[R]
Latch Clk         : core_clk:[R]

Data Arrival Path:
    AT     DELAY    TYPE   RF   FANOUT        LOC                     NODE                
 ======== ======== ====== ==== ======== =============== ================================= 
  80.000   80.000                                        active clock edge time           
  80.000   0.000                                         clk_ref                          
  80.000   0.000    tCL    RR   1        IOB104[B]       CLK_ibuf/I                       
  80.608   0.608    tINS   RR   40       IOB104[B]       CLK_ibuf/O                       
  82.590   1.982    tNET   RR   1        R33C150[0][B]   u_pll/u_pll_init/state_1_s0/CLK  
  82.719   0.130    tC2Q   RR   10       R33C150[0][B]   u_pll/u_pll_init/state_1_s0/Q    
  82.826   0.106    tNET   RR   1        R34C150[1][A]   LED_d_0_s/I1                     
  83.009   0.184    tINS   RR   7        R34C150[1][A]   LED_d_0_s/F                      
  83.137   0.128    tNET   RR   1        R26C150[0][A]   n2830_s3/I0                      
  83.371   0.234    tINS   RR   1        R26C150[0][A]   n2830_s3/F                       
  83.441   0.070    tNET   RR   1        R26C150[2][A]   tx_line_s0/SET                   

Data Required Path:
    AT     DELAY    TYPE   RF   FANOUT        LOC                     NODE               
 ======== ======== ====== ==== ======== =============== ================================ 
  80.000   80.000                                        active clock edge time          
  80.000   0.000                                         core_clk                        
  82.594   2.594    tCL    RR   3222     PLL_B[2]        u_pll/u_pll_0/PLL_inst/CLKOUT1  
  83.894   1.300    tNET   RR   1        R26C150[2][A]   tx_line_s0/CLK                  
  83.929   0.035    tUnc                                                                 
  83.844   -0.085   tHld        1        R26C150[2][A]   tx_line_s0                      

Path Statistics:
Clock Skew: 1.304
Hold Relationship: 0.000
Logic Level: 3
Arrival Clock Path delay: (cell: 0.608 23.475%, 
                     route: 1.982 76.525%)
Arrival Data Path Delay: (cell: 0.418 49.049%, 
                    route: 0.304 35.729%, 
                    tC2Q: 0.130 15.222%)
Required Clock Path Delay: (cell: 0.000 0.000%, 
                     route: 1.300 100.000%)

```
