# F154 status (speed)

**Date:** 2026-11-05  
**Base:** ab44931 (F153, still hung)  
**Change:** ADR_SKEW diagnostic. Latches '1' if, on a Q_HIT2 pop, (Q_ADR + 4) does not equal OPC_ADR. Stays set. Surfaced on DBG_QF bit 1 (replaces PF_DONE for this test).

**Why:** Address-accounting theory: under back-to-back TT-RAM hits the queue advances by 4 while PC_L lags or drifts. This bit confirms or refutes it on the board.

**Board check:** cold boot, run LOOPTEST TT-RAM + I-cache until it hangs. Then inspect DBG_QF (or the debug path that already captures it). If bit 1 is set, the addresses diverged. If it is clear, the hang is not an address mismatch.
