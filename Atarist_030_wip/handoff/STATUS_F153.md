# F153 status (speed)

**Date:** 2026-11-05  
**Base:** a91ce2d (F152, still hung)  
**Change:** Decoder now has a priority path that consumes both words whenever OPCODE_RDY_2 is set, regardless of which fill branch would otherwise run. Queue and pipe stay in sync.

**Why:** F152 still hung. PIPE_FULL = 0 is not the same as "decoder will take the second word". If the one-shot fired while the decoder was in a different branch, the queue dropped two words and the pipe advanced one.

**Board check:** LOOPTEST TT-RAM + I-cache, then FrontBench from TT-RAM.
