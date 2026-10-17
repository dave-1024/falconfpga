# Bug-fix history (68030 on the ST bus)

Each entry: symptom, cause, fix, commit. More detail: ST_HELPER.md (sections 7g-7m), notes/DEBUG2.md (lab log),
notes/RAM_PATH.md, notes/TF536_NOTES.md, notes/SPI_SDC.md. GEMBENCH 6.31 numbers are ratios to a stock STE.

| step | GEMBENCH RAM / ROM / Display / CPU / Average |
|---|---|
| F60 (CHK fix) 6c706f0 | 48 / 60 / 31 / 120 / 61 |
| F63 (bridge + SDRAM early start) f484271 | 61 / 69 / 37 / 137 / 71 |
| F62d (prefetch queue + JSR fix, on reset-sync main) 75bfc8c | 76 / 85 / 72 / 225 / 112 |
| BRIDGE_EARLY_AS d43f5fd | 86 / 86 / 74 / 230 / 115 |
| F65 prefetch handoff (switch off) | not built |
| F66 BERR no-writeback 7e3660e (board build) | 98 / 98 / 80 / 240 / 123 |
| PH2 handoff + Fmax 5246d00 | 115 / 115 / 89 / 251 / 132 |
| PH2-WP posted writes de35f5f (board build) | 115 / 115 / 89 / 251 / 132 |
| prefetch stop at change of flow db04754 | 115 / 115 / 89 / 251 / 132 |
| option (a) steps 2/3 039c710 (board build) | 115 / 115 / 89 / 252 / 133 |

8. **Prefetch handoff (F65, this tree, `WF030_FAST_HANDOFF` off).** A completing queue prefetch whose stream is still valid rolls S5 straight into S0 of the next long, when no operand request is waiting. Armed only at Q_CNT = 0 (this long's two words are not in the count yet; the queue is words 0 to 3). The next long starts only if the count after this long is queued is <= 2. An earlier arm at Q_CNT <= 2 overflowed the queue when the decoder stalled. Default off: the build define is commented out in `build_st_helper.tcl`. Operand cycles still take IDLE then START_CYCLE.

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
9. **CPU rework phase 2 (6b4f100, cpu-phase2, merged 16 Oct 2026).** Symptom: every operand cycle went S5 -> IDLE ->
   START_CYCLE (2 idle clk_cpu). Fix: a prefetch rolls S5 into S0 of a waiting operand cycle and an operand cycle into a
   waiting prefetch; the chain edge resets DSACK_MEM first (bus-width bug, FALCON_LESSONS.md). GEMBENCH 123 -> 132%.
10. **Fmax (5ca9e65, df0c6d7, 61b0fd2, 0913b33, 5246d00).** Cycle-neutral cuts of the PACK/UNPK select, gstmcu DIN
    shifter arm, bus address/FC from the latches and HD63701 ALU registers: clk_cpu030 16.2 -> 22.2 MHz, clk32 32.1 -> 33.0 MHz
    (PHASE2_DESIGN.md "Fmax work").
11. **Posted writes, option b (dfa0f15, de35f5f).** A write's DATA_RDY on the S3 edge of its last portion when DSACK ends it
    cleanly (never on BERR/retry/halt/RMC/STERM); PW_GO starts the next operand cycle from IDLE straight into S0; the frame DOB
    keeps the faulted write's data. Operand gaps after writes 6 -> 4 / 9 -> 7 clocks; GEMBENCH unchanged at 132% (ST-bus bound).
    Board: st_helper_hdn_ph2wp_de35f5f_p3.fs, clk_cpu030 19.65 MHz (placement spread, not the change).
12. **Prefetch stop at change of flow (db04754, prefetch-cof-vchain, merged 16 Oct 2026).** Symptom: the F62 queue kept
    fetching long words past taken branches, jumps and returns (15% of ST cycles in a branch-heavy bench). Fix: a hold
    from the control unit while a taken/unconditional COF executes (step 1) plus a predecode of complete unconditional COFs
    in the pipe/queue (step 2); Bcc/DBcc are not predicted; a hand-over already decided at S3 still completes (vchain).
    -2.7% ST cycles on prog_cof, GEMBENCH 132% unchanged. Blocking the decided S5 hand-over (step 1 as first built) halted
    reloads (FALCON_LESSONS.md). Board: st_helper_hdn_pfcofvchain_db04754_p3.fs. Shelved: prefetch-cof-qg.
13. **Option (a) steps 2/3, MOVEM overlap (08e1cf8, 039c710, option-a, merged 17 Oct 2026).** Symptom: after a MOVEM
   transfer's DATA_RDY the control unit took 3 (write) or 4 (read) clocks before the next request. Fix: register to
   memory loads the next register in the clock the current write completes (`ALU_BSY_M`, WRITE_DEST -> EXECUTE); memory
   to register requests the 2nd and later reads in CALC_AEFF, where the effective address is already valid. Both stay
   030-correct (only after the previous DATA_RDY; ADR_IN_USE and write priority unchanged). Tests `prog_movemw.s`,
   `prog_movemr.s`. MOVEM gaps 4 -> 3 and 7 -> 6 clocks; whole-ST bench unchanged; GEMBENCH 132 -> 133%. A3 (requests
   ahead of data) deferred to the caches. Details: OPTION_A_DESIGN.md.
14. **68030 instruction cache (branch `caches`, 17 Oct 2026, not merged).** 256 B, 16 lines × 4 longs, tag A31:8 + FC2,
    per-long valid, EI/FI/CEI/CI + CAAR, CDIS, CIIN sampled with the data, on the F62 prefetch queue (a hit costs no bus
    cycle); misaligned streams filled from consecutive fetches; no snooping (as a 030). CIIN asserted on all ST-side
    cycles (TF536 rule), so the ST build is cycle-identical to `fault-fixes` (92/92 whole-log SAME). ICACHE_DESIGN.md.
