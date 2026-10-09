# RAM_PATH: where the 030's ST-RAM time goes (F62d-rb 75bfc8c)

Box-only analysis, 9 Oct 2026 ~13:00-13:40. No repo change, no flash. The board stays on F62d-rb p3.

## Bench
- Whole-ST bus bench (cpu030/sim/st: atarist.v, gstmcu, the real tang/mega138kpro/sdram.v + CL2 chip model,
  flash_dspi model). Netlist: /tmp/synF62d/impl/gwsynthesis/wf030.vg. Its cpu030/ tree is identical to 75bfc8c, and
  the rebase changed nothing in atarist/gstmcu/bridge. Scratch copy in /tmp/rampath (repo untouched):
  * prog_ram.s: 6 loops, each run from ROM and then from RAM (copied to $30000, same code):
    1 `move.l (a0)+,d0` x8 unrolled + dbra, 2 `move.w (a0)+,d0`, 3 `move.l d0,(a0)+`, 4 `move.w d0,(a0)+`,
    5 `move.l (a0)+,(a1)+`, 6 a tight `move.l (a0)+,d0 / dbra` loop. Tests 1-5 do 16 iterations, test 6 does 64.
    Marker writes to $FF8A00 split the trace into the tests.
  * tb_bus.v + a per-ST-cycle log (cyc.txt): previous 030 AS negate, 030 AS, bridge S0, ST AS fall, gstmcu ramcyc
    (CPU slot latch), DTACK, ST AS rise, FC, address, and the video counter (vidb).
  * an.py (statistics) and slotsim.py (replays the measured 030 request gaps through a timing model of the bridge
    and gstmcu). The model reproduces the measured times exactly (base and variant A, all 12 tests).
- clk_cpu phase +cph 15625 and 46875 give identical results. Video: the RAM pass ran with the display active
  (vidb low). `+novid` (force mcucontrol.vidb=1) gives bit-identical timing.

## Baseline numbers (code in RAM, as GEMBENCH)
"Ideal" = the same loop on an 8 MHz 68000 on an ST: 68000 cycle counts rounded up to 4 clocks (500 ns), dbra 12.

| test (RAM code) | ST cycles | time us | avg AS->AS | 68000 ideal | ratio | slot misses | waits | CPU not requesting |
|---|---|---|---|---|---|---|---|---|
| move.l (a0)+,d0 | 484 | 362 | 750 ns | 216 us | 60% | 50% | 21% of the time | 12% |
| move.w (a0)+,d0 | 356 | 298 | 840 | 152 | 51% | 68% | 25% | 15% |
| move.l d0,(a0)+ | 512 | 383 | 750 | 216 | 56% | 50% | 22% | 10% |
| move.w d0,(a0)+ | 384 | 319 | 834 | 152 | 48% | 67% | 27% | 12% |
| move.l (a0)+,(a1)+ | 772 | 578 | 750 | 344 | 59% | 50% | 19% | 13% |
| move.l/dbra loop | 516 | 386 | 750 | 192 | 50% | 50% | 23% | 9% |

The same code run from ROM is faster: move.l reads 314 us (69%), the copy loop 522 us (66%). ROM has no slot, and
the RAM data cycles in between then happen to land in phase.

- RAM->RAM AS->AS spacing is never 500 ns. It alternates 625 / 875 ns (5/7 x 125 ns), 750 ns on average, which is
  1.5 slots per word.
- 030 request -> ST S0 latency: 31 ns for 92-96% of requests, 94 ns for the rest. The bridge start is not the issue
  (the "bridge" share is <=2%).
- Gap between the two words of a long (dynamic bus sizing): the 030 re-asserts AS 31 ns after negating it. The ST
  AS->AS for that pair is 500 ns when the first word caught its slot.
- Gap between two separate 030 transfers (next operand, next prefetch long): 156 ns (5 clk32) in 95% of cases.
  Longer gaps (219/344/406 ns, about 3 per loop iteration) are real execution time (dbra, the queue refill after
  the branch).

## Main cause: the 156 ns 030 turnaround meets the 68000 S0 grid and misses the 500 ns slot
Measured sequence (RAM code, `move.l (a0)+,d0`), times relative to X = ST AS rise of the previous long's second word:
- The 030 negates AS at X (the bridge's DSACK comes at S4 en2, data at S6 en1).
- The next transfer's 030 AS comes at X+156: core FSM DATA_C1C4 -> IDLE -> START_CYCLE -> DATA_C1C4.
- The bridge can only begin S0 on an en1. The en1 at X+62.5 was missed, so S0 is at X+187.5 and the ST AS falls at
  X+312.5. A 68000 back to back would assert AS at X+187.5.
- gstmcu latches the CPU slot (ramcyc) at cycsel_en, once per 500 ns. The AS is 125 ns late, so it misses the latch
  and waits 375 ns for the next one. The first word takes 875 ns and the second 625 ns.
- Result: every 030 transfer that is not the second half of a long costs one extra 500 ns slot (minus 125 ns).
  This is the 50-68% "slot misses" above, 19-27% of the time.

Why a real ST does not lose this: the 68000 starts its next S0 62.5 ns after AS negation. An 030 at 16 MHz with this
core needs 156 ns before its next AS, and the bridge keeps the exact 68000 S0/S1 length (125 ns) before AS.

## Video DMA, gstmcu/MMU slots: no deviation found
- Video on vs off: identical timing to the ns (RAM pass 362.2 us both). The RAM->video path is not the limiter.
- CPU slot logic is the original GSTMCU behaviour:
  * DTACK = ~ramcycb (gstmcu/hdl/gstmcu.v:554).
  * ramcyc is latched once per 500 ns at cycsel_en = time6 & ~time7 (gstmcu.v:717), i.e. the lcycsel rise. The sync
    version is in mcucontrol.v:185-188; the schematic async version (VERILATOR, posedge lcycsel) is at :168-171.
  * ramcyc clears at once when AS/DS go away (async on !ramsel, mcucontrol.v:186), so there is no extra hold.
  * Video RAS/CAS is in the time0 half and CPU RAS/CAS in the other half (gstmcu.v:633-640), so video never takes a
    CPU slot.
  * The F63 RAM_EARLY (gstmcu.v:719-727) only moves the SDRAM row open, not the slot.
- SDRAM: no late read data (RAM reads valid at A+312/A+375, 0 late for A+375) in every run.

## Where the remaining time goes (secondary causes)
- No instruction cache: CACHES=0 (wf68k30L_top.vhd:167), so every opcode word is a 500 ns ST cycle. In the
  `move.l/dbra` loop 6 of 8 bus cycles per iteration are opcode fetches. The real TF board's 68030 runs such a loop
  from its 256-byte I-cache (TOS 2.06 enables CACR when it finds an 030), so only the 2 data words would go to the bus.
- Prefetch-queue overfetch: per loop iteration it fetches $0300C0-C6 and then C8/CA beyond the dbra.
  * Tight loop: 3 of the 6 fetched words are discarded (needed: move.l + dbra + displacement).
  * Unrolled loop: 228 fetched vs 160 needed per 16 iterations (+43%).
  * A 68000 does 5 bus cycles for this loop iteration; we do 8.
- Real CPU idle (dbra, decode): 9-15% of the time.

## Fix candidates (scratch-tested or modelled; none applied)
Times are for RAM code. Gain = speed-up vs the current build.

| # | change | rd.l | wr.l | copy | dbra loop | ROM-code rd.l |
|---|---|---|---|---|---|---|
| 0 | current | 363 us | 384 | 579 | 387 | 314 |
| A | bridge: RAM cycles assert AS (and read DS) at the S0 en2, 62.5 ns after the address; write DS at S2 en2 (still 125 ns after AS) | 315 (+15%) **measured** | 328 (+17%) | 523 (+11%) | 323 (+20%) | 307 (+2%) |
| C | core: no IDLE+START_CYCLE between back-to-back transfers (turnaround 156 -> 31 ns, as inside a sized long) | 276 (+32%) model | 281 (+37%) | 475 (+22%) | 291 (+33%) | 274 (+15%) |
| B | core -1 clock (skip IDLE only) + A + bridge S0 also on en2 | 284 (+28%) | 304 (+26%) | 483 (+20%) | 323 (+20%) | 282 (+11%) |
| D | C + A | 267 (+36%) | 273 (+41%) | 443 (+31%) | 275 (+41%) | 267 (+18%) |
| ref | 8 MHz 68000 on an ST | 216 | 216 | 344 | 192 | - |

Ranked by expected gain for GEMBENCH (RAM-code tests and the ROM-code Display tests):
1. **Instruction cache (largest, most work).** Make the F59 I-cache usable: the CACHES generic and `ST_030_CACHES`
   (build_st_helper.tcl:33). It needs CIIN for I/O and ROM handling, plus a flush on Pexec, which TOS 2.06 does
   through CACR. Not modelled. A loop held in the cache leaves only its data cycles on the bus, e.g. 2 of 8 cycles in
   the dbra loop. A real 68030/TF board behaves exactly this way. This is a separate project.
2. **C, core turnaround** (wf68k30L_bus_interface.vhd:530-568). DATA_C1C4 returns to IDLE (:565-566), and a new
   transfer goes IDLE -> START_CYCLE -> DATA_C1C4: 2 clocks before AS, versus 0 between the words of a sized long.
   Going from DATA_C1C4 straight on to the next pending request saves ~22-37% on RAM code and ~10-15% on ROM code.
   - Risk: SIZE_N load (:455), PF_START (:645), AERR_I (:622) and the write path (:692) key on START_CYCLE. It needs
     the RTL bench (run_rtl.sh) and a resynthesis.
   - It makes the core faster than its current 2.5-clock gap, but not faster than ST slots allow. Whether it gets
     below a real 030's minimum AS negation needs checking against MC68030UM spec #14.
3. **A, bridge early AS for RAM cycles.** cpu030_st_bridge.v: S0 currently starts only on en1 (:524) and AS follows
   at S2 (:491-499). Measured +11-20% on RAM code, about 0% on ROM code.
   - The trace was functionally identical (same cycle sequence, 1 extra prefetch).
   - The chipset still sees a legal 68000 cycle: address -> AS 62.5 ns (68000 8 MHz minimum 30 ns), AS high
     >= 187 ns, write DS still 125 ns after AS, same S4/S6 termination.
   - My first try kept write DS at S4 and lost the stack writes (DS too late for the SDRAM write slot). Moving write
     DS to S2 en2 fixed it.
   - Variant file: /tmp/rampath/exp/bridge_eas.v. With D it adds +4-9% over C.
   - Regression with the original prog_bus.s (RAM/ROM/IO/BERR/blitter): R1000/R1100/R1200 dumps are identical to
     the F62d reference, 0 late reads, 10082 vs 10081 ST cycles, 7.355 vs 7.453 ms.
4. **Prefetch overfetch.** Stop the queue from fetching past a Bcc/DBcc/JMP/RTS whose target is pending (only
   2-3 words per branch, but those are 500 ns ST cycles). Estimate: up to ~35% in tight loops, ~15% in unrolled
   code, less once (1) exists.
5. Not causes (checked): video DMA, gstmcu slot logic, SDRAM latency, bridge request latency (31 ns), the gap
   inside a long (31 ns), DSACK timing (already at S4 en2).

## Files
/tmp/rampath:
- prog_ram.s, tb_bus.v, run2.sh (BRIDGE= override), an.py, slotsim.py
- runs: r15625/r46875 (base), nv15625 (no video), ea15625/ea46875 (variant A), lt* (a late-S0 try with no effect:
  the 030 request lands exactly on an en1, so the S0->AS length is what matters)
- wreg (variant A with the original prog_bus.s)
