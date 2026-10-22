# 68030 I and D caches: plan for when we put them in

Prepared 16 Oct 2026, for use when the caches go in. No code change here.
Goal: the I and D caches behave as close to a real MC68030 as possible.
No software switches for behaviour, except a hardware-equivalent CDIS (hard
cache-off, like the TF534 jumper). ST-RAM is not cached on the ST bus path;
~100% GEMBENCH RAM/ROM without a cache is correct (TF536 photo, agranlund).

## 1. Real MC68030 facts (MC68030UM)

- Two separate 256-byte caches: instruction and data.
- Each: 16 lines × 4 longwords, direct-mapped.
- Tags: logical address + function code (supervisor and user do not mix).
- Data cache: write-through. Write-allocate on a write miss is set by CACR WA.
- Software control: CACR and CAAR.
  - I-side CACR bits: EI, FI, CEI, CI, IBE.
  - D-side CACR bits: ED, FD, CED, CD, DBE, WA.
  - CAAR picks the entry for a clear-entry (CEI/CED).
- Burst fill (a whole line in one go) only with burst-capable memory:
  CBREQ / CBACK / STERM. A 16-bit port (ST bus) fills a single longword on a
  miss; no burst.
- Dynamic bus sizing (UM ch. 7.2) assembles a longword from two 16-bit cycles
  in the **bus controller**, independent of the cache. With caches off or
  inhibited, a longword prefetch is still two ST cycles; the core always
  asks for a longword instruction fetch. The cache only decides whether that
  longword is kept for later.

## 2. Missing pins in WF68K30L (found 2026-10-07)

The WF68K30L core does not expose the real 030 cache pins:

| Pin | Role | Status in our tree |
|---|---|---|
| **CIIN** | Cache-inhibit input (active low): do not allocate / do not hit for this access | Missing |
| **CIOUT** | Cache-inhibit out (from the PMMU CI bit) | Missing |
| **CBREQ** | Cache burst request | Missing |
| **CBACK** | Cache burst acknowledge | Missing |
| **CDIS** | Cache disable (hard off) | Missing |
| STERM | Synchronous termination (used with burst) | Present; bridge ties it off |
| REFILL | (related) | Left unconnected |

Until these are wired in (or equivalent internal signals exist), any cache
enable is incomplete: ST-RAM and I/O can be cached, and there is no hard off.

## 3. TF534 / TF536 reference

Source: `rtl/fastram.v` on the TF534 (and the matching TF536 SDRAM path).

- **CIIN** for ST-side cycles: `CIIN = AS20 | ~ACCESS` (TF534 `fastram.v:60`);
  TF536: `CIIN = ~ACCESS` (`sdram.v:259`). Asserted (active low) on every
  access that is **not** the card's own fast RAM. ST-RAM, ROM and I/O are
  inhibited.
- Burst (CBREQ/CBACK/STERM) only for that fast RAM, not for the ST bus.
- **CDIS** goes to jumper JP5 (hard cache-off).
- agranlund (p84495): the TF536 asserts CIIN on ST-RAM access; GEMBENCH
  ~100% RAM/ROM in David's photo was without cache help.
- Notes already in-tree: `docs/notes/TF536_NOTES.md` (Caches section),
  `docs/ST_HELPER.md` §7g (caches out by default, 7 Oct 2026).

## 4. Plan for our bridge and core

1. **Bridge asserts CIIN (active low) on all ST-side cycles** (ST-RAM, ROM,
   I/O). Same rule as the TF534/TF536. Only a future 030-side fast RAM region
   leaves CIIN negated.
2. **CDIS hard off** until we want a board/jumper equivalent; default off
   matches "no cache in the path" below. Not a compile-time behaviour switch
   for experimental modes.
3. **CIOUT** comes from the PMMU's cache-inhibit bit once the PMMU exists.
4. **Burst (CBREQ/CBACK/STERM)** only for that future 030-side fast RAM.
   ST bus stays asynchronous DSACK, single-longword fill on a miss.
5. **Fast RAM later (not required for first I/D cache bring-up on ST):**
   16 MB+ on the 030 side. TOS 2.06 needs a Maddalt AUTO program to see it;
   EmuTOS and TOS 3+ detect it. Burst fills become useful only there.
6. **No cache logic in the bus path when disabled.** The F59 `CACHES`
   generic (default 0) already generates the cache modules out and wires the
   core straight to the bus interface. Keep that: when caches are off, the
   path must match a no-cache build cycle-for-cycle.
   - Old attempt: icache `a7ccf76` / dcache `e9a4fd9` (4 Oct 2026). Suspected
     of wrong branches even while "disabled" (logic still in the path, or
     stale lines after EI/ED without CI/CD). See `docs/ST_HELPER.md` §7g.
7. **CACR / CAAR stay present** even with `CACHES=0` (`P_CACHE_REGS`). MOVEC
   still works. GEMBENCH (and TOS) can read CACR bits as ON when software has
   set EI/ED, even if the caches are compiled out — that is expected and must
   not be treated as proof that caches are live.

**Decision (David, 17 Oct 2026): TF536 style.** CIIN inhibits everything on the ST side: ROM, ST-RAM and I/O. Only a
future 030-side fast RAM region is cacheable. ROM is deliberately not cached even though TT/Falcon/EmuTOS and the
Mega STE cache it (research in `/workspace/rom_cache_research.md` on the box, 17 Oct 2026: ROM caching is safe; the
TOS 1.x ROM at $FC0000 sits inside the $F00000 block the TT tree inhibits). Reason: period-correct ST accelerator
behaviour, one simple rule in the bridge, no coherency questions with stock TOS 1.x/2.06.

## 5. Timing and resources

- Tag compare and hit/miss mux land on the **clk_cpu030** critical path.
  Keep the current 19–22 MHz headroom (16 MHz target). Phase 2 follow-up #5
  (decoder → ADR_EFF path) should be tightened before the caches go in
  (`docs/TODO.md`).
- Block RAM budget is small: one BRAM-ish data store per cache plus a small
  tag store. Save BRAM for the caches and for DSP; current p3 use is about
  164/340 (49%).

## 6. Order of work

Status (17 Oct 2026): **steps 1 and 2 done and merged on `main`** (branch `caches`, which contains `fault-fixes`).
I cache: [`ICACHE_DESIGN.md`](ICACHE_DESIGN.md); D cache: [`DCACHE_DESIGN.md`](DCACHE_DESIGN.md). CIIN, CDIS, CBACK in
and CBREQ, CIOUT out are pins of WF68K30L_TOP. The bridge drives CIIN from a per-cycle decode (TF536 rule: every ST
ROM/RAM/IO cycle inhibited, only the reserved fast-RAM range $01000000-$01FFFFFF cachable). With the caches off the ST
build is cycle-identical to `fault-fixes`. Board build dc_ff6af03: TOS 2.06 enables the caches at boot, GEMBENCH 133%
unchanged. The old F59 modules are gone. Still to do: 030-side fast RAM, burst, A3 (deferred), PMMU (below).

1. **Instruction cache first.** Bus trace (`branch bus-trace`, `BUSTRACE.md`):
   instruction fetches are about 72–87% of ST cycles on the weak display
   tests (VDI Graphics, GEM Dialog/Window). Biggest ST-bus cycle cut once
   something cacheable exists; on the ST path CIIN still inhibits ST-RAM/ROM,
   so the I-cache only helps once fast RAM (or a non-inhibited region) is
   present — on the Falcon, TOS enables caches against a different map.
2. **Data cache second**, same CIIN / CDIS / CACR rules, write-through + WA.
3. Match the 030 exactly: CACR, CAAR, CIIN, CDIS, CIOUT (with PMMU), burst
   only with CBREQ/CBACK/STERM. No behaviour switches beyond hardware CDIS.

Note (17 Oct 2026): option (a) **A3** belongs here. Issuing the next operand request before the current data arrives
needs a request queue in the bus interface, DATA_RDY/BERR tagged per request (a queued read is cancelled, not run, when
the current one faults) and an undo of the (An)+/offset step on a fault. The cache line fills and the cache-miss path
need the same queue, so build it once with the caches. See OPTION_A_DESIGN.md (A3 assessment).

Planned later step (17 Oct 2026): **68030 PMMU.** Its page tables will mark I/O and ST-RAM cache-inhibited, as TOS
does on the TT and Falcon (the CI bit in the page descriptors, driven out on CIOUT). That resolves DCACHE_DESIGN D-Q2:
with WA set (TOS 2.06 writes CACR=$3919), aligned long writes to ST addresses would otherwise allocate D cache
entries, because CIIN is ignored on writes. Until the PMMU is in, hardware CDIS is the fallback if the board test shows
a problem.

## 7. Falcon

TOS on the Falcon enables the caches. Same cache logic and pins; different
address map and CIIN decode (Falcon bus / fast RAM regions). Do not special-case
the ST build beyond the bridge's CIIN map.

## 8. Related docs

- `docs/TODO.md` — caches item and phase 2 follow-ups (clk_cpu030 headroom).
- `docs/ST_HELPER.md` §7g — caches out by default (`ST_030_CACHES`).
- `docs/notes/TF536_NOTES.md` — TF CIIN behaviour and ~100% without cache.
- `docs/notes/RAM_PATH.md` — I-cache as largest speedup once usable.
- `docs/BUILD.md` — `ST_030_CACHES` switch (off; incomplete until CIIN etc.).
- `handoff/CONTEXT.md` — board state and next-fix order.
- Old scratch: `handoff/20261004-1540-icache.md`, `20261004-1806-dcache.md` (removed in cleanup 22 Oct 2026; see git history before bb65998)
  (and patches); do not revive without this plan.
