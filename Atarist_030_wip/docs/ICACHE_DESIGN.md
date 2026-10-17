# 68030 instruction cache: design (step 1 of CACHE_PLAN.md)

Written 17 Oct 2026 before the RTL, on branch `caches` (off `fault-fixes` 667fcca).
Goal: an on-chip instruction cache that behaves like the MC68030's (MC68030UM ch. 6), with the real cache pins.
Unconditional (no switch): a 68030 has the cache. The bridge asserts CIIN on every ST-side cycle (David's TF536
decision, CACHE_PLAN.md §4), so on today's ST build nothing is ever stored and the bus is cycle-identical to
`fault-fixes`. The cache only does work once 030-side fast RAM (8–16 MB, not built yet) leaves CIIN negated.

## 1. What a 68030 does (MC68030UM ch. 6, 5.7, 5.11; MC68EC030 data sheet; MC68020UM 4.2/4.3 for the shared rules)

- 256 bytes, 16 lines × 4 long words, direct-mapped. Index = A7:4, long-word select = A3:2.
- One tag per line: A31:8 and FC2 (user/supervisor). Only program space is stored, so FC1:0 is not needed.
- One valid bit per long word (4 per line). A fill whose tag differs from the line's tag replaces the tag and
  clears the other three valid bits.
- Fill on a miss, from the long word the bus brings in. Without burst (CBREQ/CBACK) one long word per miss
  (single-entry mode, 6.1.3.1); a 16-bit port gives that long word from two cycles (dynamic bus sizing, the bus
  controller assembles it).
- **CIIN** (5.7.1): "prevents data from being loaded into the instruction and data caches". Sampled with the
  data; with dynamic sizing the long word is stored only if no portion had CIIN asserted. CIIN does not stop a hit.
- **CDIS** (5.11.1): dynamically disables the caches (no hits, no fills), for emulators. Contents are kept.
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
- fill port: `FILL` strobe, `FILL_ADR`, `FILL_FC2`, `FILL_DATA`;
- control: `EI`, `FI`, `CDIS`, `CLR_ALL` (CI), `CLR_ENT` + `CLR_IDX` (CEI, CAAR 7:2), `RESET`.
  HIT needs EI = 1 and CDIS negated; FILL is ignored unless EI = 1, FI = 0, CDIS negated.

In the bus interface (tag `[IC]`):
- `IC_TAKE` = queue wants a long (`PF_REQ` as before, now `PF_REQ_RAW`) and the cache hits at F_ADR, and no stream
  restart (`Q_MISS`) this clock. The long goes into the queue in that clock, F_ADR moves on, no bus cycle.
  The bus may be running an operand cycle at the same time (a 030 also serves the pipe from the cache while the
  bus is busy).
- `PF_REQ` (bus) = `PF_REQ_RAW` and not a hit. The F65/PH2 chains (PF_CHAIN_GO, DP_CHAIN, DP_CHAIN_GO) use the
  masked request, so a long that hits never starts a bus cycle.
- Misaligned stream start (branch to 4n+2: F62 fetches words 4n+2 and 4n+4 on the bus): lookup of long n; a hit
  appends only word 4n+2 and F_ADR moves to 4n+4 (aligned from then on). The misaligned bus fetch is **not** filled
  (it holds half of two long words; valid bits are per long word). See open question Q1.
- Fill: at `PF_DONE` of an aligned prefetch long with no bus error on either word and CIIN negated on both
  portions, the long goes into the cache at F_CUR. Also when the queue drops the long (INFL_STALE): the bus
  fetched it, as a 030 would have filled it.
- CIIN: sampled into `CIIN_LAT` on the same CLK_F edge that latches the data (IN_MUX condition), OR-ed over the
  portions of the long (`PF_CI`).
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

Bridge (`cpu030_st_bridge.v`): `CIINn = 0` on every cycle (all ST side), `CDISn = 1`, `CBACKn = 1`.

## 3. Cycle identity on the ST build

With CIIN asserted on every cycle no valid bit is ever set, so `HIT` is 0, `PF_REQ` equals the old `PF_REQ`,
and every chain and FSM decision is unchanged, whatever CACR holds (EmuTOS may set EI). The only new logic in
the bus path is the hit mask; it is 0. This is checked with the full regression (cmp_wr.sh, every program × WS
0/1/3/7, old = fault-fixes, new = caches) and by running the cache test with CIIN asserted.

## 4. Tests

- `sim/rtl/prog_icache.s` with tb030 `CIMODE=1` (CIIN negated for ROM $FC0000–$FEFFFF and RAM $8000–$FFFF,
  a fake cacheable region) and a tb control register at $3500 for CDIS. Cases: EI off, cold fill then hits,
  EI off keeps the entries, freeze, CEI on one long word, CI, user vs supervisor tag, CDIS, no snoop on a code
  write in RAM (stale result until CI), CACR read-back. The checker counts program-space bus cycles inside each
  loop between marker writes, and checks the results at $5000.
- The same program with `CIMODE=0` (CIIN asserted, as the ST bridge): no hits at all.
- Full regression cycle-identical (§3), run_rtl.sh PASS.

## 5. Open questions

- Q1: F62 starts a stream at 4n+2 with a misaligned long (4n+2, 4n+4) instead of the aligned long a 030 fetches.
  Those fetches cannot fill the cache, so a loop whose first long word starts at 4n+2 keeps one bus long per
  pass in a cacheable region. Making cacheable stream starts aligned changes timing only in cacheable memory,
  but the core cannot know CIIN before the cycle ends. Decide when fast RAM exists.
- Q2: CDIS tied negated in the bridge (cache usable, CIIN keeps it empty on the ST side). A jumper/OSD
  equivalent can drive it later.
- Q3: Burst fill (IBE, CBREQ/CBACK, STERM) waits for the fast RAM controller.
- Q4: The A3 request queue (CACHE_PLAN §6 note) is not needed for the I cache (hits do not use the bus); it comes
  with the D cache / fast RAM work.
