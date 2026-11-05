# F152 status (speed)

**Date:** 2026-11-05  
**Base:** 0ca0bc4 (F151, still hung)  
**Change:** The Q_HIT2 one-shot is only armed when PIPE_FULL = 0. This guarantees the decoder is in a plain-fill branch (PNTR 0 or 1) that will consume the second word. Prevents the queue from dropping two words while the decoder only advances one.

**Why:** F151 still hung on TT-RAM + I-cache. Review showed the one-shot could arm on any even IC_MTAKE, even when the pipe was not empty. The queue then lost two words and the pipe/queue addresses diverged.

**Board check:** LOOPTEST TT-RAM + I-cache, then FrontBench from TT-RAM.
