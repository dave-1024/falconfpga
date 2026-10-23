# 68030 cache audit: WF68K30L I/D cache vs MC68030 User's Manual

Read-only audit, 2026-10-22, branch `tt-ram` (after C10 71624aa). Nothing was built, flashed or committed.
Paths are relative to `Atarist_030_wip/hdl/cpu030/`. Line numbers are approximate and taken from the current tree.
"MC68030UM" means the MC68030 User's Manual, section 6 unless stated otherwise.

## Summary

The functional model is complete and close to the manual for a **non-burst, no-PMMU** 68030. The geometry, tags,
FC steering, CACR/CAAR, clear and clear-entry, freeze, write-through, WA, CIIN, CDIS, RMC and bus-error rules are
all present. What's missing is the **burst fill** (CBREQ/CBACK, IBE/DBE) and the **PMMU CI** path. There are also
three timing differences: chained and read-ahead reads skip the D-cache, there's no burst, and the ST side is never
cachable. All three affect cycle-exactness but not correctness.

## Feature table

| Feature | MC68030UM behaviour | Implemented? (evidence) | Cycle-exactness impact |
|---|---|---|---|
| Geometry | I and D each 256 B: 16 lines × 4 longs, direct-mapped; index A7:4, long select A3:2; one valid bit per long | **Yes**: `wf68k30L_icache.vhd:56-60,90-91`; `wf68k30L_dcache.vhd:73-78,121-138` | None |
| I-cache tag | A31:8 + FC2 | **Yes**: `icache:57,94,101-102` | None |
| D-cache tag | A31:8 + FC2:0 | **Yes**: `dcache:74,113-116` | None |
| FC steering | Program space (FC 2/6) to I-cache, data space to D-cache; extension words/immediates come through the prefetch, so they go to the I-cache | **Yes**: I-cache fed only by the prefetch queue (`bus_interface:900-916`); D-cache by operand reads/writes (`bus_interface:1103,1126-1149`) | None |
| CPU space (FC=7) | Never cached | **Yes**: `dcache:13,137,197`; `bus_interface:1171-1172,1189`; bridge asserts CIIN for FC=7 (`cpu030_st_bridge.v:~197`) | None |
| MOVES | Uses SFC/DFC; cachable like any data access with that FC | **Yes** (implicitly): FC2:0 in the D tag, only FC=7 excluded | None |
| CACR | WA13 DBE12 CD11 CED10 FD9 ED8 IBE4 CI3 CEI2 FI1 EI0; CD/CED/CI/CEI read as 0; reset clears | **Yes**: mask `x"00003313"` and reset `wf68k30L_top.vhd:715-717` | None |
| CAAR | Index bits 7:2 for CEI/CED; all 32 bits r/w | **Yes**: `top:720-721`; `CLR_IDX => CAAR(7 downto 2)` `top:1056,1088` | None |
| CI / CD (clear all) | Invalidate every entry, whatever the enable/freeze state | **Yes**: `top:1037,1073`; `icache:155-156`; `dcache:271-272` | None |
| CEI / CED (clear entry) | Invalidate the long at CAAR index | **Yes**: `icache:166-168` (wins over a same-clock fill); `dcache:283-285` | None |
| EI / ED enable | Disabled: no hits, no fills, contents kept | **Yes**: `icache:98,101`; `dcache:118,137`; `top:1075-1076` | None |
| FI / FD freeze | Hits allowed, misses don't replace | **Yes**: I `icache:98`; D fill `dcache:188`, writes still update hits when frozen (`dcache:211-212`), as the manual says | None |
| CDIS pin | Disables both caches, contents kept | **Yes**: registered (`top:1040-1045`); tied off (`cpu030_st_bridge.v:257` `CDISn=1`) | None |
| CIIN | Sampled per cycle (async at S4, sync with STERM); asserted means that cycle's data isn't cached; ignored on writes | **Yes**: `bus_interface:1442-1448`; I `bus_interface:910-913`; D `bus_interface:1253`; writes ignore it (`dcache:24`) | None |
| CIIN decode (system) | System-dependent; on a real Falcon/TT, TOS's PMMU marks ST-RAM as cachable and I/O as CI | **Partial**: ST side always CIIN-asserted, only $01xxxxxx (TT-RAM) cachable (`cpu030_st_bridge.v:~189-203`, TF536 rule) | **High for the Falcon target**: ST-RAM code and data never hit, so ST-RAM benchmarks show no cache gain where a real Falcon would. Needs a DMA/blitter coherency story first |
| Write policy | Write-through. A hit updates the cache, even when frozen. The cache keeps the new value even if the bus write errors | **Yes**: `dcache:209-228`; update in the clock after the write starts (`bus_interface:1126-1149`) | None |
| Write allocate (WA) | WA=1, FD=0: an aligned long write miss allocates; a byte/word/misaligned write miss invalidates the entry. WA=0: a miss leaves the cache alone | **Yes**: `dcache:213-226` | None |
| I-cache snooping | None: data writes don't touch the I-cache (software must CI) | **Yes**: `icache:23-24` | None |
| I-cache fill (single entry) | Without burst, each long the prefetch reads with CIIN negated and no BERR is stored | **Yes**, including a misaligned 4n+2 stream assembled from two fetches: `icache:95-99,133-148`; `bus_interface:904-916` | Low. The first half-read long of a 4n+2 stream isn't cached; this matches the 68030 behaviour per ICACHE_DESIGN Q1, worth confirming on silicon |
| D-cache fill on a 16-bit port | Cachable read miss: the CPU runs extra cycles so the whole touched long(s) can be validated (Fig. 6-6: byte at $03, then word at $00) | **Yes**: fill cycles `bus_interface:1153-1200`; an 8-bit port is never filled (`:1249`) | Medium: the extra fill cycles' order and count should be checked against Fig. 6-6 cycle by cycle in simulation |
| **Burst fill** (CBREQ/CBACK, IBE/DBE) | IBE/DBE set and CBACK asserted: fill the whole line, 4 longs, 2-1-1-1 via STERM, 32-bit port only | **No**: `CBREQn <= '1'` (`top:1111`); CBACKn unused (`top:238`); IBE/DBE stored with no effect (`top:1072`) | **Medium/low.** A Falcon has a 16-bit bus and can't burst; a TT with burst-capable fast RAM could. It matters only for TT-style fast RAM, which also needs STERM |
| STERM (sync 32-bit, 2-clock) | Fast-RAM cycles and cache fills in 2 clocks | **Partial**: the core handles STERM (`bus_interface:709,1442`), but the TT-RAM path doesn't use it (async + wait states) | **High for TT-RAM speed** (see the open STERM item) |
| RMC (TAS/CAS/CAS2) | The read always misses and doesn't allocate; the write updates the cache on a hit | **Yes**: `RMC` from `control:564`; read never looked up (`bus_interface:1103`) or filled (`:1171,1226`); writes go through the normal hit/WA path | None (a WA allocate on a CAS long write is allowed by the manual) |
| Bus error on a fill / operand | Entry not validated or invalidated; an error in a fill cycle beyond the operand raises no exception | **Yes**: I `icache:95`, `FILL_OK`; D `dcache:190-191`, `bus_interface:1162-1166,1235-1240` | None |
| Reset | All valid bits cleared, CACR = 0 | **Yes**: `icache:155`; `dcache:271`; `top:715` | None |
| **PMMU CI bit / CIOUT** | Page descriptor or TT register CI asserts CIOUT and inhibits caching (both caches) | **No** (no PMMU): `CIOUTn <= '1'` (`top:1112`). Caching is decided by CIIN alone | None until there's a PMMU. TOS 3/4 PMMU setup and CI pages will be missing |
| Hit timing: I-cache | Hit with no bus cycle; the prefetch runs in parallel with operand bus cycles | **Yes**: `IC_TAKE` serves the queue in one clock with no bus cycle (`bus_interface:900-901`) | Matches the "cache case" in principle; to be measured (below) |
| Hit timing: D-cache | Hit with no bus cycle | **Partial**: hit delivers DATA_RDY at START_CYCLE (`bus_interface:1103`), but **chained reads (OP_CHAIN/PW_GO) and MOVEM read-ahead are never looked up** (`:1058-1062,1103` comment) and use the bus | **Medium**: correct (write-through keeps memory equal) but slower than a 68030 for back-to-back operand reads and MOVEM from cachable memory |
| Read-after-write hazard (BRAM) | n/a (FPGA) | I-cache: **fixed** by C10 forwarding (`icache:103-119`). D-cache: assumed distributed RAM with async read (`dcache:231-233,249`); lookup is registered and cancelled on a same-clock update (`bus_interface:1118`) | Check the tt20 synthesis report: the D lane arrays (`D00..D13`, `TAG0/1`) must not be BSRAM. If they are, the same stale-read class as C10 applies |

## Prioritised gaps

1. **D-cache arrays and BRAM inference (correctness check, cheap).** Confirm in the tt20 `.syr` / resource report that the
   D-cache lanes and tags are RAM16SDP/LUT RAM, not SDPB. If any are SDPB, add C10-style forwarding.
2. **D-cache lookup on chained, posted-write-follow (PW_GO) and MOVEM read-ahead reads.** This is the biggest cycle-exactness
   gap with TT-RAM: a real 68030 would hit these with no bus cycle.
3. **STERM / zero-wait TT-RAM.** This is the fill-cost side; the miss penalty dominates FrontBench (990 → 1169 → 1362).
4. **ST-RAM cachable (Falcon target).** A real Falcon caches ST-RAM, with I/O CI'd by the PMMU TT registers. This needs
   a decision on DMA/blitter/video coherency first (the 68030 doesn't snoop; Falcon TOS relies on flushes).
5. **Burst fill (IBE/DBE, CBREQ/CBACK).** Only useful with a 32-bit STERM fast-RAM path, and irrelevant for the Falcon 16-bit bus.
6. **PMMU CI / CIOUT.** This comes with the PMMU.
7. **Verify the D-fill cycle order against Fig. 6-6** and the I-cache 4n+2 first-long rule against silicon (A1200 later).

## Measuring per-instruction clocks against the MC68030UM timing tables (no A1200 needed)

The manual (section 11, Instruction Execution Timing) gives three columns per instruction: **best case** (cache hit,
full overlap), **cache case** (cache hit, no overlap) and **worst case** (no cache, external bus at the stated
wait states). Note that every clock count our core produces is in clk_cpu030 clocks (≥17 MHz). The manual's counts
are in CPU clocks too, so the two compare directly.

**A. Simulation: exact, per instruction**
1. Use the existing RTL testbench (as for the MOVEM/T1 tests). Load the T1 loop at $010001C0 (TT-RAM model, CIIN negated,
   CACR = $0101, so EI+ED, after one warm-up pass) and the FrontBench hot loops (disassemble them from the FrontBench
   binary at the addresses the overnight ring showed).
2. Log one line per instruction boundary: the clock number at each decoder opcode-accept strobe (the same point
   DBG_EXC/DBG_STR already tap), plus per clock `IC_TAKE`, `PF_REQ`, `DC_RHIT`, `READ_ACCESS`, `WRITE_ACCESS`, `FILL_ACC`
   and wait-state clocks.
3. Clocks per instruction = the delta between boundaries. Split each into *execute* clocks, *bus-wait* clocks (AS
   asserted, no DSACK) and *cache-hit* clocks. Compare with the manual's cache case and best case for that
   instruction/EA. Worst case can be compared by running the same loop with CIIN asserted and modelling the TT-RAM wait states.
4. The T1 loop's expected figure is the sum of the manual entries for `move.l (a0),d0`, `cmp.l a0,d0`, `beq.s` (taken),
   `addq.l #4,a0`, `subq.l #1,d7` and `bpl.s` (taken), looked up in the cache-case/best-case columns. Any instruction
   over the manual's figure is a gap; under it is a bug.

**B. On the board: a whole-loop average, cheap**
1. Run a tight loop N times (for example N = 10^6) from TT-RAM with caches warm, and time it with a free-running counter.
   The simplest is a 32-bit clk_cpu030 cycle counter exposed at an unused I/O register (a debug-only build). Without a
   new build, use the 200 Hz timer ($4BA) or MFP Timer A at the known clock.
2. Clocks per iteration = (elapsed × f_clk_cpu030) / N. Subtract an empty `dbra` loop to remove the loop overhead,
   then compare with the summed manual figures from A4.
3. Repeat with I only (CACR=$0001), D only ($0100), both, and none, to get the per-cache contribution. Repeat from
   ST-RAM for the miss penalty, which settles the earlier "how much is memory" question.
4. Compare A with B. If they agree, the simulation can be trusted for FrontBench loops that are too long to hand-time.
   The A1200 check later only validates the manual's numbers against silicon.

## Pinned for later (David, 2026-10-22)
- Implement full 68030 burst mode in WF68K30L (CBREQ/CBACK, CACR IBE/DBE, burst line fills), even if the Falcon target never uses it, so the community gets a more complete core.
