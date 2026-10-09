# Bug-fix history (68030 on the ST bus)

Each entry: symptom, cause, fix, commit. More detail: ST_HELPER.md (sections 7g-7m), notes/DEBUG2.md (lab log),
notes/RAM_PATH.md, notes/TF536_NOTES.md, notes/SPI_SDC.md. GEMBENCH 6.31 numbers are ratios to a stock STE.

| step | GEMBENCH RAM / ROM / Display / CPU / Average |
|---|---|
| F60 (CHK fix) 6c706f0 | 48 / 60 / 31 / 120 / 61 |
| F63 (bridge + SDRAM early start) f484271 | 61 / 69 / 37 / 137 / 71 |
| F62d (prefetch queue + JSR fix, on reset-sync main) 75bfc8c | 76 / 85 / 72 / 225 / 112 |
| BRIDGE_EARLY_AS d43f5fd | 86 / 86 / 74 / 230 / 115 |

1. **CHK operand (F60, 87fac46).** Symptom: GEMBENCH 6 "subscript error". Cause: WF68K30L CHK compared against A0
   (ALU operand 2 taken from address-register port 2) instead of Dn. Fix: CHK reads Dn.
2. **Bridge start and SDRAM early start (F61 0104f1b..6611246, F63 f484271).** Symptom: every ST RAM access ~0.9-1.6 us.
   Cause: request synchronisers and a late SDRAM row open; read data arrived after the 68000 latch point.
   Fix: synchronous bridge start from the 030's AS (F61, partly reverted when the corrected bench showed RAM data at
   A+406), gstmcu RAM_EARLY opens the SDRAM row one clk32 earlier for CPU/DMA reads (F63).
3. **Prefetch queue (F62 8f104b3, F62b 9e612d5, F62c ef56b11).** Symptom: CPU-bound code slow (one opcode word per
   request). Fix: opcode prefetch queue with aligned long fetches like a cache-off 68030. F62 caused a black screen
   (TOS vblank sync loop too slow: aligned long fetch at a 4n+2 branch target wasted a word); F62b restarts the stream
   with a long fetch at the requested word. F62c uses the decoder's OPCODE_FLUSH. Deviation kept in mind: the queue
   still fetches past taken branches (TODO.md).
4. **JSR SP writeback (F62d, 79f5951 on main, 75bfc8c on the queue).** Symptom: crash when a program quits, GEMBENCH menu
   freeze (found with the in-fabric trace, branch `diag-trace`). Cause: `ADDA.W #16,SP; JSR (d16,PC)` after an RTE:
   the ADDA writeback and the JSR predecrement hit A7 in the same clock and the decrement was lost. Fix: JSR waits for
   a pending A7 writeback in every addressing mode, as BSR already did. Bench: prog_spwb.s.
5. **SDC clocks (6fd2bad).** Symptom: STA warnings "determined to be a clock but was not created" (TA1132), unchecked paths.
   Fix: create the missing clocks and declare the asynchronous groups (notes/SPI_SDC.md part 1; part 2 = MISO pad, TODO).
6. **Reset synchronisers (382524f).** Symptom: recovery/removal violations -5 to -8 ns (PLL-lock POR into clk32/flash
   domains, DDR3 reset); one placement gave a dead helper. Fix: 3-flop async-assert/sync-deassert chains (por32,
   por_flash), clk_osc fabric loads on a DCE global buffer, SDC false paths only to the sync chains. Now
   recovery ~+7.5 ns, removal ~+0.25 ns.
7. **Early AS (d43f5fd, `BRIDGE_EARLY_AS`).** Symptom: RAM-code loops at 750 ns per word (1.5 slots). Cause: the core's
   156 ns gap between transfers plus the 68000 S0 length makes the ST AS miss the 500 ns GSTMCU slot (notes/RAM_PATH.md).
   Fix: AS for ST RAM cycles 62.5 ns after the address. +11-20% on RAM code in the bench, GEMBENCH RAM 76 -> 86.
   The proper fix is in the core (TODO.md item 1).
