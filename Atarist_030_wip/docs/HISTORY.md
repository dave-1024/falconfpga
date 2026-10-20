# Bug-fix history (68030 on the ST bus)

Each entry: symptom, cause, fix, commit. More detail: ST_HELPER.md (sections 7g-7m), notes/DEBUG2.md (lab log),
notes/RAM_PATH.md, notes/TF536_NOTES.md, notes/SPI_SDC.md. The table is GEMBench 4.03 (`gbref.st`; called "GEMBENCH 6.31" here before 18 Oct 2026), ratios to a stock STE.
GEMBENCH 6.08 (`gb608.st`) numbers are in item 18 and docs/MOVEM_TIMING_F1_F2.md.

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
| fault fixes + I cache 47eba71 (board build ic_47eba71) | 115 / 115 / 89 / 252 / 133 |
| + D cache, RAM16 data ff6af03 (board build dc_ff6af03) | 115 / 115 / 89 / 252 / 133 |
| F1 MOVEM priority encoder d696318 (board build f1_d696318) | 115 / 115 / 90 / 252 / 133 |
| F2 MOVEM read-ahead c4de2ec (board build f2_c4de2ec) | 115 / 115 / 90 / 254 / 134 |
| F3 MOVEM writes back to back 7919eb3 (board build f3a_7919eb3; branch 304b885) | 115 / 115 / 91 / 255 / 135 |

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
14. **Data-fault fixes FLT1/FLT2 (f045aa9, branch `fault-fixes`, merged on main with `caches` 17 Oct 2026).** Symptom:
    after a data write bus error the next instruction still ran (operand reads, register and CCR updates) before the
    exception, the frame PC pointed at it (RTE ran it twice), a MOVEM kept writing after the first fault, and a write
    fault always stacked format $B. Cause: the exception handler waited for the control unit to go idle while the
    faulting write ran in the write-back stage. Fix: no program bus cycle after a faulted data write (exception right
    after the faulted cycle); a write fault at an instruction boundary stacks the short $A frame (MC68030UM 8.1.2,
    Table 8-6). Unconditional. Bench prog_fault.s; regression otherwise identical. FAULT_FIXES.md.
15. **68030 instruction cache (fcb8673..47eba71, merged on main 17 Oct 2026).** 256 B, 16 lines × 4 longs, tag A31:8 + FC2,
    per-long valid, EI/FI/CEI/CI + CAAR, CDIS, CIIN latched per cycle (MC68030UM 7.2.8-7.2.10) and only inhibiting that
    cycle's fill, on the F62 prefetch queue (a hit costs no bus cycle); misaligned streams filled from consecutive
    fetches; no snooping (as a 030); syn_keep so Gowin keeps it. CIINn from a per-cycle decode in the bridge (TF536
    style): ST ROM/RAM/IO inhibited, reserved fast RAM $01000000-$01FFFFFF cachable (616946e had the polarity inverted,
    fixed in 47eba71). ST build cycle-identical (92/92). Board ic_47eba71: GEMBENCH 133% unchanged. ICACHE_DESIGN.md.
16. **68030 data cache (1cbfdcf, 706a0aa, merged on main 17 Oct 2026).** 256 B direct-mapped, tag = logical address +
    FC, write-through, write allocate (WA), CACR ED/FD/CED/CD/DBE (burst stubbed), CAAR, CIIN per cycle (ignored on
    writes), CDIS; TAS/CAS read forced to miss, single-entry fills on the 16-bit port, a bus error on a fill-only cycle
    marks the entry invalid without an exception. Regression 92/92 identical with ED off; new unit test prog_dcache.s
    (16 configs), gate-level run_dcache_net.sh. Deviations D-Q1..D-Q7 and the TOS 2.06 WA risk (D-Q2) in
    DCACHE_DESIGN.md; A3 queue deferred.
17. **D cache data in RAM16 (cbfcedb, ff6af03).** The first D cache build put the 256 data bytes in 2048 flip-flops
    (~6k LUTs): each bank had two write index ports and the lanes were read through a function taking whole arrays.
    Fix: one write port per data and tag bank (E0/E1 of an operand are always in different banks, so no write split
    and no timing change) and direct indexed reads. Now 74 RAM16SDP4; LUT 42.1k -> 37.7k, Reg 18.1k -> 15.6k, Fmax
    clk_cpu030 22.79 MHz, clk32_core 33.78 MHz. Behaviour cycle-identical (96/96 incl. cache-on prog_dcache). Board
    dc_ff6af03: TOS 2.06 boots with Cache on, GEMBENCH 133 / 89 / 252.
18. **MOVEM timing F1/F2 (branch `f1-movem-timing`: ab1f3ec, 890fbea; board builds f1_d696318, f2_c4de2ec; 18 Oct 2026; design note MOVEM_TIMING_F1_F2.md).** Symptom:
    GEMBENCH 6.x RAM/ROM Access at ~71-73% of a 68000 STE (back-to-back MOVEM.L loops), while 4.03 is at 115%.
    Cause: the core left the ST bus idle between MOVEM transfers: it walked all 16 list positions one clock each,
    and every MOVEM read started from IDLE after the control unit took the previous one, so RAM missed its ST slot.
    F1: register-list priority encoder (8+4n like a 68030; `MOVEM_END` ends the list and drives the -(An) last
    decrement). F2: MOVEM M->R read-ahead from S5 of the previous read (bus interface; data or bus error handed over
    on the matching request, CIIN-gated with the D cache on; DIB kept on a faulted read-ahead). Sim: run_rtl PASS,
    13-program write/exception compare at WS 0/1/3/7 identical except frame left-over buffers (DIB/DOB of read faults),
    new prog_movemx.s (2154 cases, results identical). GEMBENCH 6.08 vs STE20608: RAM 71 -> 76 (F1) -> 91% (F2),
    ROM 73 -> 78 -> 104%, CPU 147 -> 154 -> 180%, Average 82 -> 83 -> 91%. Fmax clk_cpu030 22.33 MHz, clk32_core
    32.44 MHz (F2), timing closed. 4.03: 133 -> 134%. Merged on main 18 Oct 2026. F3 (writes back to back): TODO.md,
    branch f3-write-queue.
19. **MOVEM timing F3: register-to-memory writes back to back (branch `f3-write-queue`: b33c140, 304b885; board build
    f3a_7919eb3; 18 Oct 2026; design note MOVEM_TIMING_F1_F2.md "F3").** Symptom: after F2, GEMBENCH 6.08 RAM Access
    stayed at 91%: MOVEM writes had a register-to-register gap of 3 clocks (AS high 2 clocks), so ST RAM missed slots.
    Cause: the control unit loaded the next register only on the write's DATA_RDY (S4/S5 clock), ran EXECUTE, and
    presented the write from IDLE (PW_GO). Fix: a posted write's outcome is final in the S3 clock of its last portion
    (WP_GO: DSACK, no BERR/retry); the control unit loads the next register there (`WR_EARLY`/`WR_TAKE`, same set-up
    as before, one clock earlier and only when certain), the bus interface drops that DATA_RDY and the S5 edge rolls
    into the next write (`WW_GO`, operand before a waiting prefetch). Data from the loaded ALU operand in that clock
    (`RESULT_MV`/`F3_BYP`), address without the calculation delay (`ADR_FAST`). No queue/undo: a fault can only hit
    the next write. Sim: run_rtl PASS; 13-program compare at WS 0/1/3/7 identical except frame $2C (DIB, undefined
    for write faults) and $0E (stale BIW_2, TODO.md item); FILT=5000 identical for prog_fault/wpberr/movemx;
    prog_movemx -9.5% clocks. Board: 2 cold boots clean; 6.08 RAM 91 -> 101%, CPU 180 -> 186%, Average 91 -> 92%
    (STE20608), 129 -> 132% (STFM1048); 4.03 134 -> 135%. Fmax clk_cpu030 20.94 MHz, clk32_core 34.02, LUT 37,870.
20. **C1-C4: CAS2 and memory-indirect correctness (`fix-c-indirect`, 19 Oct 2026; FULL_ISA_TIMING.md, FALCON_LESSONS).**
    Symptom: CAS2 wrote Du1/Du2 to the swapped operands, hung when run back to back, loaded Dc1/Dc2 swapped on a
    failed compare and left a wrong CCR; `([bd,An])` reads used a stale pointer address on an idle bus; JMP
    `([bd,An])` hung, JSR jumped to the pointer address; RMW `([bd,An])` did not read its pointer. Cause: registered
    ADR_EFF / ADR_EFF_WB used in the clock they were selected, MEMADR_RDY set by a write acknowledge, stale
    CAS2_COND, wrong Dc selector order, CAS/CAS2 missing from the ALU flag case. Fix: registered gates (CAS2_WGAP,
    MEMADR_IN, CAS2_CCHOLD), MEMADR_RDY from reads only, one SWITCH_STATE address clock for CLR/JMP/JSR/Scc/MOVE
    from SR indirect. Nothing new on the DSACK path. Sim: run_rtl with prog_cas2/prog_memind, cmpall vs main.
21. **T6: 68030 table timing for ALU ops, memory-indirect prefetch hold, CAS2 RMC lock (`t6-exact-timing`, 19 Oct 2026).**
    Goal: per-instruction clocks of MC68030UM ch. 11 (worst-case / no-cache column for ST code) with realistic
    bus placement for the Falcon DSP. ALU: registered pad table (T = table clocks, K = per-class overhead, down
    counter, PAD_ZERO flag) holds ALU_BSY for MUL/DIV, register BCHG/BCLR/BSET/NBCD, ANDI/ORI/EORI to SR/CCR,
    shifts/rotates (imm, Dx < size, Dx >= size), bit fields (reg, mem <5 / >=5 bytes). MUL/DIV use the table max
    (data-dependent in the manual). CHK is not padded (trap decision at ALU_ACK; a parked CHK let the next instruction
    run first). MI1: PF_HOLD during the pointer read and the following CALC_AEFF, so the operand read follows the
    pointer read. CS1: no queue prefetch between the CAS2 reads and writes (RMC sequence, as on the 68030).
    Sim: run_rtl PASS (incl. prog_cas2/prog_memind/prog_chk), cmpall 68/68 identical writes vs fix-c-indirect.
22. **T6 overnight (`t6-exact-timing`, 19/20 Oct 2026).** (1) CHK: register form padded to 8; the control unit
    now waits in SLEEP for the CHK acknowledge (trap decision) before the next instruction (prog_chk OK).
    (2) CS2: CAS2 marks the first write address in EXECUTE (ALU_COND valid there), -1 clock inside the locked
    sequence. (3) Memory-indirect move/sub/lea are at the 16-bit bus floor (1 control clock between pointer and
    operand read); JSR/JMP ([bd,An]) losses are queue fills the 68030 also does; left as is. (4) SH1: one-clock
    barrel shifter (result + C/V/X for counts 1..63, ROx mod size, ROXx mod size+1), shift pads K=4; register
    shifts/rotates now within 0.2 of the worst column for every count. New prog_shift regression (408 ops x CCR,
    expect from the bit-serial core). Sim: run_rtl PASS, cmpall 72/72 identical. Synthesis (876ffc2): clk_cpu030
    22.63 MHz, clk32_core 33.29 MHz, LUT 39,792 (+1,492 vs T6 28020c8), FF 15,637. Not flashed.
