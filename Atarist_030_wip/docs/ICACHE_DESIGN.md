# 68030 instruction cache: design (step 1 of CACHE_PLAN.md)

Written 17 Oct 2026 before the RTL, on branch `caches` (off `fault-fixes` 667fcca).
Goal: an on-chip instruction cache that behaves like the MC68030's (MC68030UM ch. 6), with the real cache pins.
Unconditional (no switch): a 68030 has the cache, it is always built in full and kept through synthesis, and it
is enabled only by CACR EI (disabled only by CACR EI = 0 or the CDIS pin). CIIN never disables it: CIIN only stops
the data of the bus cycle it is asserted on from being stored. The bridge drives CIIN from a per-cycle address
decode (§2a): asserted on every ST-side cycle (David's TF536 decision, CACHE_PLAN.md §4), negated for a reserved
030-side fast-RAM range ($01000000–$01FFFFFF, nothing fitted yet). So on today's ST build no ST cycle is ever
stored and the bus is cycle-identical to `fault-fixes`; the cache fills once fast RAM (8–16 MB) is fitted there.

## 1. What a 68030 does (MC68030UM ch. 6, 5.7, 5.11; MC68EC030 data sheet; MC68020UM 4.2/4.3 for the shared rules)

- 256 bytes, 16 lines × 4 long words, direct-mapped. Index = A7:4, long-word select = A3:2.
- One tag per line: A31:8 and FC2 (user/supervisor). Only program space is stored, so FC1:0 is not needed.
- One valid bit per long word (4 per line). A fill whose tag differs from the line's tag replaces the tag and
  clears the other three valid bits.
- Fill on a miss, from the long word the bus brings in. Without burst (CBREQ/CBACK) one long word per miss
  (single-entry mode, 6.1.3.1); a 16-bit port gives that long word from two cycles (dynamic bus sizing, the bus
  controller assembles it).
- **CIIN** (5.7.1): stops the data of that bus cycle being stored, per cycle; latched at the start of S4
  (asynchronous) or with STERM; with dynamic sizing the long word is stored only if no portion had CIIN asserted.
  CIIN does not stop a hit and does not disable the cache (a hit has no bus cycle, so there is no CIIN to see).
- **CDIS** (5.11.1): dynamically disables the caches (no hits, no fills), for emulators. Contents are kept.

### 1a. Manual text and how the RTL matches it (MC68030UM/AD Rev. 2; quotes from the PDF text, OCR "CLOUT"/"El" read as CIOUT/EI)

| MC68030UM | Text | RTL |
|---|---|---|
| 5.7.1 | "This input signal prevents data from being loaded into the MC68030 instruction and data caches. It is a synchronous input signal and is interpreted on a bus-cycle-by-bus-cycle basis. CIIN is ignored during all write cycles." | `CIIN_LAT` is taken per bus cycle and recorded per word of the prefetch long (`PF_CI0`/`PF_CI1`); it only gates `FILL_OK`. Only instruction prefetch reads fill. |
| 6.1 | "Another input signal, cache inhibit in (CIIN), inhibits caching of data reads or instruction prefetches on a bus-cycle by bus-cycle basis." | Same: a cycle with CIIN asserted fills nothing; the next cycle is judged on its own CIIN. |
| 6.1 | "An external access is defined as "cachable" ... when all the following conditions apply: • The cache is enabled with the appropriate bit in the CACR set. • The CDIS signal is negated. • The CIIN signal is negated for the access. • The CLOUT signal is negated for the access. • The MMU validates the access." | `FL_GO = (FA_GO or FM_GO) and EI and not FI and not CDIS`, with `FILL_OK` = CIIN negated and no bus error on each word (no PMMU here, so CIOUT/MMU do not apply). |
| 6.1 | "Whenever a read access occurs and the required instruction word or data operand is resident in the appropriate on-chip cache (no external bus cycle is required), the MMU is completely ignored" | `HIT = EI and not CDIS and valid and tag match`: no CIIN term. Entries already present keep hitting while CIIN is asserted on other cycles (test cases 21–25). |
| 6.1 | "When a cachable read cycle provides data with both CIIN and BERR negated, the MC68030 attempts to fill the cache entry." / "If the device cannot supply its full port width of data, it must assert CIIN for all bus cycles corresponding to a cache entry." | A long word made of two 16-bit cycles is stored only if both portions had CIIN and BERR negated (`FILL_OK="11"`). |
| 7.2.8 | "For asynchronous read cycles, the value of CIIN is internally latched on the rising edge of bus cycle state 4." | `P_CIIN`: rising CLK edge that ends S3 (the start of S4, the last S3 edge when there are wait states). |
| 7.2.10 | "the assertion or negation of CBACK and CIIN is internally latched on the rising edge of the clock for which STERM is asserted in a synchronous cycle." ... "The assertion of CIIN is ignored when the appropriate cache is not enabled or when cache inhibit out (CIOUT) is asserted. It is also ignored during write cycles or translation table searches." | `P_CIIN` also latches at S1 with STERM asserted; with EI = 0 nothing fills anyway. |
| 5.11.1 | "The cache disable signal dynamically disables the on-chip caches to assist emulator support. ... CDIS does not flush the data and instruction caches; entries remain unaltered and become available again when CDIS is negated." | `CDIS_R` (registered pin) masks `HIT` and fills; no valid bit is touched (cases 12/13). |
| 6.1 | "System hardware can assert the cache disable (CDIS) signal to disable both caches. The assertion of CDIS disables the caches, regardless of the state of the enable bits in CACR." | CDIS is the only pin that disables; CIIN does not. |
| 6.3.1.11 | "Bit 0, the EI bit, is set to enable the instruction cache. When it is cleared, the instruction cache is disabled. A reset operation clears the EI bit. ... Disabling the instruction cache does not flush the entries. If it is enabled again, the previously valid entries remain valid and may be used." | `EI` = CACR(0) gates `HIT` and fills; valid bits kept (cases 4/5). |
| 6.3.1.10 | "When the FI bit is set and a miss occurs in the instruction cache, the entry (or line) is not replaced." | FI masks fills only; hits continue (cases 6/7). |
| 6.3.1.9 | "The processor clears only the specified long word by clearing the valid bit for the entry at the time a MOVEC instruction loads a one into the CEI bit of the CACR, regardless of the states of the EI and FI bits. The CEI bit is always read as a zero." | `IC_CEI` strobe clears VALID(CAAR 7:2) whatever EI/FI; read-back mask $3313 (case 8). |
| 6.3.1.8 | "The processor clears all valid bits in the instruction cache at the time a MOVEC instruction loads a one into the CI bit of the CACR. The CI bit is always read as a zero." | `IC_CI` clears all valid bits (case 9). |
| 6.3.1.7 | "Bit 4, the IBE bit, is set to enable burst filling of the instruction cache." | Stored and read back; no burst yet (Q3). |
| 6.2 | "When a hardware reset of the processor occurs, all valid bits of both caches are cleared. The cache enable bits, burst enable bits, and the freeze bits in the cache control register (CACR) for both caches ... are also cleared" | RESET clears VALID and CACR. |
| 6.3.2 | "The index field (bits 7-2) contains the address for the "clear cache entry" operations." | `CLR_IDX = CAAR(7:2)`. |

The ED/FD/DBE/WA/CD/CED bits belong to the data cache (step 2): ED/FD/DBE/WA are stored and read back (mask
$3313), CD/CED read as 0. The only change this check needed: CIIN used to be latched with the data (falling edge
at the end of S4) and is now latched at the start of S4 as 7.2.8 says (616946e). Same results, since a CIIN
from an address decode is stable for the whole cycle.
- **CACR** (6.3.1): EI (bit 0) enable, FI (1) freeze = hits still served but misses do not replace entries,
  CEI (2) clear entry, CI (3) clear all, IBE (4) burst enable. CEI/CI are strobes and read as 0.
  CEI and CI work whatever EI and FI are.
- **CAAR** (6.3.2): CEI clears the long word whose index and long-word select are CAAR bits 7:2.
- **Reset** (6.2): all valid bits cleared, CACR cleared.
- **No snooping:** the 68030 instruction cache is not updated or cleared by data writes. Software that writes code
  (loaders, self-modifying code) must clear it (CI/CEI). The old 4 Oct attempt cleared lines on writes; that is not
  030 behaviour and is not copied.
- A hit costs no bus cycle. The external cycle for a miss starts as it would with the cache off (the 030 starts
  the cycle with ECS and only drives AS when the cache misses), so a miss adds no clock.

## 2. Where it sits in our core

The core's instruction side is the F62 prefetch queue in `wf68k30L_bus_interface.vhd` (P_QUEUE). It fetches the
stream as long words at `F_ADR` whenever `PF_REQ` is set (queue at most one word full, no fault, stream valid,
PF_HOLD clear). That is the 030's long-word instruction fetch, so the cache is looked up there, not at the
decoder's word requests (the old module sat between the decoder and the bus and needed the queue turned off,
which changed every bus cycle even with EI = 0).

New entity `WF68K30L_ICACHE` (rewrites `wf68k30L_icache.vhd`, same file name so the build lists stay as they are):
- storage: data 64 × 32 (index & long select), tag 16 × 25, valid 16 × 4 flip-flops (cleared by reset/CI/CEI);
- lookup port: `LK_ADR` (A31:2) and `LK_FC2` → `HIT`, `HIT_DATA` (combinational, async read);
- fill port: `FILL` strobe (every bus prefetch long, last portion), `FILL_MIS` (it started at 4n+2), `FILL_OK`
  (per word: no bus error and CIIN negated on its portion), `BREAK` (stream restart), `FILL_ADR`, `FILL_FC2`,
  `FILL_DATA`;
- control: `EI`, `FI`, `CDIS`, `CLR_ALL` (CI), `CLR_ENT` + `CLR_IDX` (CEI, CAAR 7:2), `RESET`.
  HIT needs EI = 1 and CDIS negated; FILL is ignored unless EI = 1, FI = 0, CDIS negated.

In the bus interface (tag `[IC]`):
- `IC_TAKE` = queue wants a long (`PF_REQ` as before, now `PF_REQ_RAW`) and the cache hits at F_ADR, and no stream
  restart (`Q_MISS`) this clock. The long goes into the queue in that clock, F_ADR moves on, no bus cycle.
  The bus may be running an operand cycle at the same time (a 030 also serves the pipe from the cache while the
  bus is busy).
- `PF_REQ` (bus) = `PF_REQ_RAW` and not a hit. The F65/PH2 chains (PF_CHAIN_GO, DP_CHAIN, DP_CHAIN_GO) use the
  masked request, so a long that hits never starts a bus cycle.
- Misaligned stream start (branch to 4n+2: F62 fetches words 4n+2 and 4n+4 on the bus, and the stream stays
  misaligned, 4n+6/4n+8 and so on): lookup of long n; a hit appends only word 4n+2 and F_ADR moves to 4n+4
  (aligned from then on).
- Fill, aligned fetch: at `PF_DONE` with both words OK the long goes into the cache at F_CUR.
- Fill, misaligned stream: each fetch holds the second half of one long and the first half of the next. The
  cache keeps the second word (`PH_W`, with its long address and FC2; valid only if that word was OK) and stores
  the long when the next fetch of the stream brings its other half (`PH_W` & first word). So every long word the
  bus has read in full is cached, as a 68030 caches every long it reads. Only the first long of a 4n+2 stream
  (its first word was never read) is not; see Q1. `BREAK` (Q_MISS), reset, CI and CEI drop the kept word.
- Fills also happen when the queue drops the long (INFL_STALE): the bus read it, so a 030 would have filled it.
- CIIN: latched into `CIIN_LAT` at the start of S4 (rising CLK edge that ends S3) or at S1 with STERM
  (`P_CIIN`, MC68030UM 7.2.8–7.2.10), kept per word (`PF_CI0`/`PF_CI1`, like the fault flags `PF_FLT0`/`PF_FLT1`).
- Synthesis: `syn_keep` on the data/tag arrays and valid bits, `syn_preserve` on the valid bits, the kept half
  word, CACR/CAAR/CDIS_R and CIIN_LAT/PF_CI0/PF_CI1, so Gowin never sweeps the cache as unused.
- The queue's flush on writes (F62) stays: that is the pipe, not the cache.

In the top (`wf68k30L_top.vhd`):
- New pins: `CIINn` (in, default '0' = inhibited), `CDISn` (in, default '1'), `CBACKn` (in, unused),
  `CBREQn` (out, '1': no burst until a burst-capable fast RAM exists), `CIOUTn` (out, '1': no PMMU).
  The defaults keep every existing bench and instantiation unchanged; the bridge drives them explicitly.
- CDISn is registered once (asynchronous pin).
- CI strobe = MOVEC to CACR with bit 3; CEI = bit 2 with CAAR(7:2). Old `G_CACHES`/`G_NO_CACHES` removed: the
  experimental 4 Oct I/D modules are no longer instantiated, the prefetch queue is always on, and the `CACHES`
  generic is kept only so old build scripts still elaborate (ignored). The D cache comes in step 2 with its own
  design note.
- CACR read-back mask $3313 already keeps EI/FI/IBE; IBE is stored and read back but has no effect (no burst).

Bridge (`cpu030_st_bridge.v`): `CIINn` from the per-cycle decode of §2a, `CDISn = 1`, `CBACKn = 1`.

## 2a. CIIN decode in the bridge (how a 030 board drives it)

A real 030 board decodes CIIN from the address of the running cycle (a PAL next to the address decoder) and holds
it for the cycle; the 030 latches it at S4. The bridge does the same, from the 030's own outputs:

    cpu_fast_sel = ~ASn & (FC != 7) & (A31:24 == $01)      // (* syn_keep *)
    CIINn        = cpu_fast_sel     // active low: 0 = inhibit (ST side), 1 = cachable (fast RAM)

- ST side (ROM, ST-RAM, I/O: every A31:24 other than $01) and CPU space: CIIN asserted, never cached (TF536 rule).
- Reserved fast RAM $01000000–$01FFFFFF (TT-RAM layout, CACHE_PLAN.md): CIIN negated, cachable. Not fitted yet:
  those cycles still go to the ST bus (A31:24 are ignored there, so they alias ST space), as they always have.
  The only difference from a constant CIIN is that code *executed* from $01xxxxxx would be cached; TOS and ST
  software never run code there. When fast RAM is fitted, this select also routes the cycle to it.
- No 030 cycle (AS negated, e.g. the ST side owns the bus): CIIN asserted (don't care for the core).
- Gate-level check (`sim/run_icache_net.sh`, bridge + Gowin netlist on tb_bridge, where $01xxxxxx aliases the
  ST space): a loop run via $01FC1000 fetches 8 times cold and 0 warm; the same code via $00FC1000 (ST side,
  CIIN asserted) fetches 48 (no hit: other tag; no fill); via $01FC1000 again 0 (the entries are still there and
  hit); with EI = 0, 48. `run_unit.sh` traces are identical to the constant-CIIN bridge. This test found that the
  first version of the decode (616946e) had CIINn inverted (ST side cachable); fixed in 47eba71, that bitstream
  was deleted unflashed.
- CIIN never disables the cache: CACR EI enables it, CDIS (tied negated) is the only hardware disable, and lines
  already stored keep hitting whatever CIIN is on other cycles.

## 3. Cycle identity on the ST build

With CIIN asserted on every ST cycle no valid bit is ever set (unless code is executed from the reserved
$01xxxxxx range), so `HIT` is 0, `PF_REQ` equals the old `PF_REQ`,
and every chain and FSM decision is unchanged, whatever CACR holds (EmuTOS may set EI). The only new logic in
the bus path is the hit mask; it is 0. This is checked with the full regression (cmp_wr.sh, every program × WS
0/1/3/7, old = fault-fixes, new = caches) and by running the cache test with CIIN asserted.

## 4. Tests

- `sim/rtl/prog_icache.s` with tb030 `CIMODE=1` (CIIN negated for ROM $FD0000–$FEFFFF, RAM $8000–$FFFF and the
  BERR range $20000–$2FFFF: a fake cacheable region) and a tb control register at $3500 for CDIS. The driver code
  sits at $FC0000 (uncached), so it cannot evict the loop lines of the direct-mapped cache. The checker
  (`check_icache.py`) counts program-space bus cycles inside each loop's 16-byte line between marker writes
  ($3600), and the results at $5000. `run_icache.sh` runs WS 0/1/3/7 × FAST_HANDOFF 0/1 × CIMODE 1/0 against
  `expect_icache_ci1.txt` / `expect_icache_ci0.txt`; `run_rtl.sh` calls it.
- The same program with `CIMODE=0` (CIIN asserted on every cycle): no hits at all.
- Cases 21–25 (tb control $3502: CIIN asserted on every cycle mid-run): loop A filled first (21: 6), still hits
  with CIIN asserted (22: 0), loop B is not filled while CIIN is asserted (23, 24: 48 each), and fills on its first
  pass once CIIN is negated again (25: 6). CIIN inhibits fills of its own cycles only; it does not disable the cache.
- Full regression cycle-identical (§3), run_rtl.sh PASS.

### Results (17 Oct 2026, RTL, GHDL)

Bus cycles inside the loop line, 8 passes of `subq.l #1,d1; bne.s` (identical for every WS and FAST_HANDOFF):

| case | what | CIMODE=1 (cacheable) | CIMODE=0 (CIIN asserted) |
|---|---|---|---|
| 1 | EI = 0 | 48 | 48 |
| 2 | CI + EI, cold | 6 (first pass only) | 48 |
| 3 | warm | 0 | 48 |
| 4 | EI = 0 again | 48 (no hits) | 48 |
| 5 | EI = 1, no CI | 0 (entries kept) | 48 |
| 6 | FI + EI, new loop B | 48 (no fill) | 48 |
| 7 | FI + EI, loop A | 0 (hits while frozen) | 48 |
| 8 | CAAR = loop A, CEI | 2 (one long refetched) | 48 |
| 9 | CI | 6 (refill) | 48 |
| 10 | user mode (FC2) | 6 (supervisor entries do not hit) | 48 |
| 11 | supervisor again | 6 (user fill replaced the line) | 48 |
| 12 | CDIS asserted | 48 | 48 |
| 13 | CDIS negated | 0 (contents kept) | 48 |
| 16 | loop at 4n+2 via a branch | 24 (2 per pass: its first long) | 49 |
| 17 | loop at 4n+2 entered from 4n | 8 (first pass only) | 49 |
| 18 | case 16 with EI = 0 | 49 | 49 |

Results at $5000: case 14 (code rewritten in RAM without CI) returns the **old** code's D0 = 1 with CIMODE=1 (no
snooping, as a 68030) and 2 with CIMODE=0; after CI it returns 2. CACR read-back of $FFFFFFFF = $00003313. Case 19:
a bus error on a cacheable prefetch fills nothing (the second jump faults again: 2 bus errors in both modes).

Regression (`cmp_full.sh`, whole bench log: every bus cycle with its clock, every exception), `fault-fixes` 667fcca
vs `caches`, all 22 programs × WS 0/1/3/7 (+ prog_fpbr with TAKEN 0 and 1, IRQ programs with periodic level 4/6):
**92 of 92 SAME**. That includes prog_icache.s itself, which sets EI, FI, CEI, CI and CDIS: with CIIN asserted the
new core is cycle-identical to the old one. `run_rtl.sh`: PASS (prog_loop WS=5 DONE at clk 40289, unchanged).

### Gowin checkpoint (17 Oct 2026, `47eba71`, not flashed)

- Gowin 1.9.12.03, `build_st_helper_hdn.tcl`, niced on linserver. Bitstream
  `~/fpga_bitstreams/st_helper_hdn_ic_47eba71_p3.fs`, sha256
  `da5f2238620f665c192dfabdaf02e12580247b20b20b86620c282b17716ce034`. **Not flashed, no board test.**
- The cache is in the ST build (CIINn from the decode of §2a plus syn_keep/syn_preserve). Cells of
  `WF68K30L_ICACHE` in the synthesised netlist: 1 SDPB (data), 119 RAM16SDP4 (tags, read copies), 112 DFFRE
  (valid bits, kept half word), 484 ALU (tag compares), 249 LUT2-4 and 30 MUX2.
- Full ST build vs `fault-fixes` 667fcca and vs `75c4c18` (CIINn tied asserted, cache swept), same script:

| | 667fcca | 75c4c18 (swept) | 47eba71 |
|---|---|---|---|
| LUT / ALU | 36146 / 4089 | 35792 / 4079 | 35955 / 4590 |
| Registers | 15176 | 15209 | 15347 |
| SSRAM (RAM16) / BSRAM | 127 / 170 | 127 / 170 | 246 / 172 |
| clk_cpu030 Fmax (16 MHz) | 22.045 MHz | 19.360 MHz | 23.069 MHz |
| clk32_core Fmax (32 MHz) | 35.279 MHz | 34.845 MHz | 35.537 MHz |
| TNS | 0 | 0 | 0 |

- Slowest clk_cpu030 paths are now cache paths: half-cycle clk_cpu030_n -> clk_cpu030 (31.25 ns), `RETRY` -> stream
  address -> `IC_LK_ADR` -> data BSRAM read address, slack 17.8 ns. In 667fcca the limiting path was the opcode
  decoder -> ADR_EFF adder (same-edge, 62.5 ns). Plenty of margin at 16 MHz.
- (75c4c18 had the first Gowin crash fix; 616946e had the inverted CIINn and its bitstream was deleted.)
- Netlist benches: `run_unit.sh` ERRORS=0, traces identical to 75c4c18; `run_icache_net.sh` PASS.

## 5. Open questions

- Q1: F62 starts a stream at 4n+2 with a misaligned long (4n+2, 4n+4) instead of the aligned long a 030 fetches
  (4n, 4n+2). The rest of the stream is cached (assembled fills), but its first long word never is, so a loop
  whose target is at 4n+2 and that is entered only by the branch costs one bus long (2 ST-size cycles) per pass in
  a cacheable region; a 030 would cost none. Fetching aligned at a cacheable 4n+2 target would fix it, but the
  core only knows CIIN at the end of the cycle (and F62 exists because the aligned fetch made the TOS 2.06 vblank
  loop too slow on the ST side). Decide when fast RAM exists (e.g. an address decode that says "030-side" early).
- Q2: CDIS tied negated in the bridge (cache usable, CIIN keeps it empty on the ST side). A jumper/OSD
  equivalent can drive it later.
- Q3: Burst fill (IBE, CBREQ/CBACK, STERM) waits for the fast RAM controller.
- Q4: The A3 request queue (CACHE_PLAN §6 note) is not needed for the I cache (hits do not use the bus); it comes
  with the D cache / fast RAM work.
