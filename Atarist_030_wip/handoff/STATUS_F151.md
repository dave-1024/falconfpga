# F151 status (speed)

**Date:** 2026-11-05  
**Base:** ddcedde (F150, still hung)  
**Change:** Q_HIT2 is now a registered one-shot. It is set only in the cycle after IC_MTAKE (when the queue has just been loaded with exactly two words) and is cleared on the first Q_HIT, on OPC_DISMISS, or on reset. It can fire at most once per restart.

**Why:** F150 (Q_CNT = 2 and INFL = 0) still hung on TT-RAM + I-cache. The combinational Q_HIT2 could still see a later hit. A one-shot tied to the IC_MTAKE cycle removes that window.

**Board check:** LOOPTEST TT-RAM + I-cache, then FrontBench from TT-RAM. If it hangs, the two-word path needs a different approach (or stays off).
