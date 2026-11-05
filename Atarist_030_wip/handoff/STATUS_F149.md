# F149 status (speed)

**Date:** 2026-11-05  
**Base:** 40f939b (F148)  
**Change:** RESTART_PEND is also set on IPIPE_FLUSH; RESTART_ADR captures the address at the restart; Q_HIT2 only fires while Q_ADR still equals that address. Constant F147_TWO_WORD (default true) can be set false to restore F145 two-word behaviour.

**Why:** F148 still hung on the first TT-RAM LOOPTEST iteration with the I-cache on. Leading theory is a one-cycle race or Q_ADR misalignment when back-to-back cache hits arrive at full speed (not reproduced in sim).

**Board check:** cold boot, LOOPTEST, TT-RAM with I-cache on. Expect either the F145 number (1307189) or a clear hang. Also confirm ST-RAM + I-cache and caches-off still match F145.

**Fallback:** set F147_TWO_WORD := false and rebuild to confirm the hang is confined to the two-word path.
