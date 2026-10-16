# CPU-ST bridge review: latency left from the 32 MHz CPU clock (16 Oct 2026)

Read-only review of `hdl/cpu030/cpu030_st_bridge.v` (main db2ec52) with the CPU at 16 MHz (`CPU_DIV(2)` in atarist.v).
No RTL changed.

## Trace numbers (whole-ST netlist bench, DIAG_BUSTRACE, main)
- prog_cof: 030 AS -> ST S0 is 31 ns (1 clk_32) in 2091 of 2167 cycles. 030 AS negate -> next 030 AS is 31 ns in 1936 cycles.
- prog_bus: back-to-back ST AS->AS is 500 ns in 7103 cycles (the 68000 rate).
- prog_bus, longer back-to-back spacing (RAM to RAM): 750 ns (411) and 875 ns (648). Likely the GSTMCU 500 ns RAM slot
  grid, which a 68000 in an ST also rounds to (inference, not proven).
- prog_bus, gaps from AS end to next AS: 156 ns (702) and 719 ns (1149). The core has no request ready (CPU side).

## Findings
- **Request path:** no synchroniser (since F58). The 030 outputs are taken directly, because clk_cpu is phase-locked to clk_32.
  The F61 live path starts the ST S0 on the same clk_32 edge that sees AS. The only wait is alignment to the next en1
  (125 ns grid), which the ST's 68000 phases require.
- **DSACK:** given at S4 en2 from the live DTACK, where a 68000 samples DTACK. Read data is latched at the en1 into S6,
  before the 030 latches it one clk_cpu later. S4 waits are in 125 ns steps, as a 68000. Nothing is sized for 32 MHz.
  An earlier DSACK would deliver data that is not valid yet.
- **Synchronisers:** RMC, HALT out and RESET out go through 2-flop chains. The RMC lock is seen about 62 ns late, which
  only affects BG blocking. HALT and RESET out have no speed effect.
- **Leftover parameters:** `CPU_DIV` is used only in comments. `SYNC_STAGES` is unused.

## Options
| Option | Expected gain | 030-correct |
|---|---|---|
| 1. Take `cpu_rmcn` directly instead of the 2-flop sync, so the lock applies on the first edge | 0% speed. Closes a small window where a bus grant could slip in at the start of a TAS | Yes |
| 2. Remove `SYNC_STAGES` and `CPU_DIV` and fix the comments | Cleanup only | Yes |
| 3. Pipelined control unit: issue the next operand request during the current cycle (TODO.md Phase 2 follow-up 1) | Core side, not bridge. RAM_PATH.md estimate: +20-35% on RAM code | Yes (a 030 overlaps like this) |
| 4. Earlier DSACK, or AS for ROM/IO before S2 | At most about 62 ns per ROM cycle | No: ahead of DTACK/valid data, or not 68000 phase timing on the ST bus |

Conclusion: the bridge already follows the ST's 68000 timing at 16 MHz. Further bridge tightening is not worth doing.
The gains are on the CPU side (option 3) and the caches (TODO.md item 3).
