# F150 status (speed)

**Date:** 2026-11-05  
**Base:** 0f101e0 (F149 with F147_TWO_WORD = false)  
**Change:** Q_HIT2 now requires Q_CNT = 2 and INFL = 0 (exactly the original restart pair, no fill in flight). F147_TWO_WORD re-enabled.

**Why:** With the two-word path off, LOOPTEST matched F145 (TT I-cache 1307189) and FrontBench from TT-RAM ran (lastcount 1234). The hang and white-screen were confined to Q_HIT2. The CNT>2 / in-flight fill case was the leading race.

**Board check:** cold boot, LOOPTEST TT-RAM + I-cache, then FrontBench from TT-RAM. Expect either the F145 numbers or a hang. If it hangs, set F147_TWO_WORD := false again.
