# 68030 data cache and the A3 request queue: design (step 2 of CACHE_PLAN.md)

Written 17 Oct 2026, before the RTL, on branch `caches` (after the I cache, head cd7b70c).
Goal: an on-chip data cache that behaves like the MC68030's (MC68030UM/AD Rev. 2, ch. 6 and 11.4), on the same pins
and rules as the I cache (ICACHE_DESIGN.md): always built, kept through synthesis (`syn_keep`/`syn_preserve`),
enabled only by CACR ED, disabled by ED = 0 or the CDIS pin, CIIN per bus cycle from the bridge decode (only
$01000000–$01FFFFFF cachable). Unconditional: no switch. Then the A3 request queue (CACHE_PLAN §6 note,
OPTION_A_DESIGN.md "A3").

## 1. What a 68030 data cache does (manual text)

| MC68030UM | Text (quoted from the PDF; OCR "CLOUT" = CIOUT) |
|---|---|
| 6.1.2 | "The data cache stores data references to any address space except CPU space (FC =$7), including those references made with PC relative addressing modes and accesses made with the MOVES instruction." |
| 6.1.2 | "The tag of each line in the data cache contains function code bits FC0, FC1, and FC2 in addition to address bits A31-A8. The cache control circuitry selects the tag using bits A7-A4 ... Address bits A3-A2 select the valid bit for the appropriate long word" |
| 6.1.2 | "Misaligned data transfers may span two data cache entries. In this case, the processor checks for a hit one entry at a time. Therefore, it is possible that a portion of the access results in a hit and a portion results in a miss. The hit and miss are treated independently." |
| 6.1.2 | "A data read cycle operates exactly like an instruction cache read cycle; when a miss occurs, an external cycle is initiated to obtain the operand from memory, and the data is loaded into the cache if the access is cachable. In the case of a misaligned operand that spans two cache entries, two long words are required from memory. ... Read accesses from the CPU address space and address translation table search accesses are not stored in the data cache." |
| 6.1.2 | "The data cache on the MC68030 is a writethrough cache. When a hit occurs on a write cycle, the data is written both to the cache and to external memory ..., regardless of the operand size and even if the cache is frozen. ... Since the write to the cache completes before the write to external memory, the cache contains the new value even if the external write terminates in a bus error." |
| 6.1.2.1 | "When no write allocation is selected (WA=0), write cycles that miss do not alter the data cache contents. ... The cache is updated only during a write hit." |
| 6.1.2.1 | "When write allocation is selected (WA = 1), the processor always updates the data cache on cachable write cycles, but only validates an updated entry that hits or an entry that is updated with long-word data that is long-word aligned. When a tag miss occurs on a write of long-word data that is long-word aligned, the corresponding tag is replaced, and only the long word being written is marked as valid. The other three entries in the cache line are invalidated when a tag miss occurs on a misaligned long-word write or on a byte or word write, the data is not written in the cache, the tag is unaltered, and the valid bit(s) are cleared." (the PDF text lost a full stop after "invalidated": Figure 6-4 example 4, aligned long write tag miss, shows TAG replaced, V1 = 1, V0/V2/V3 = 0; example 5, misaligned long write $2056 with a tag miss, shows only "V2 <- 0") |
| 6.1.2.1 | "since the CIIN signal is ignored on write cycles, cache entries may be created for noncachable data (when CIIN is asserted on a write) when operating in the write-allocation mode." |
| 6.1.2.2 | "The read portion of a read-modify-write cycle is always forced to miss in the data cache. However, if the system allows internal caching of read-modify-write cycle operands (CIOUT and CIIN both negated), the processor either uses the data read from memory to update a matching entry in the data cache or creates a new entry with the read data in the case of no matching entry. The write portion of a read-modify-write operation also updates a matching entry in the data cache. In the case of a cache miss on the write, the allocation of a new cache entry for the data being written is controlled by the WA bit." |
| 11.4 | "RMC cycles (e.g., TAS and CAS) are forced to miss on data cache reads." / "Write accesses, however, always require bus cycles because the data cache is a writethrough cache." |
| 6.1.3.1 | "the bus controller transfers a single long word for the corresponding cache entry. An entire long word is required. If the port size of the responding device is smaller than 32 bits, the MC68030 executes all bus cycles necessary to fill the long word." Fig. 6-6 (16-bit port, byte at $03): cycle 1 byte $03, cycle 2 word $00. Fig. 6-9 (16-bit port, long at $06): $06, $04 (fill), $08, $0A (fill). |
| 6.1.3.1 | "If all bytes of a long word are cachable, CIIN must be negated for all bus cycles required to fill the entry. ... Write cycles (including the write portion of a read-modify-write cycle) ignore the assertion of the CIIN signal" |
| 6.1.3.1 | "If the bus error occurs on a read cycle for a portion of the required operand ... the processor immediately takes a bus error exception. If the read cycle in error is made only to fill the data cache (the data is not part of the target operand), no exception occurs, but the corresponding entry is marked invalid." |
| 6.1 | cachable when "The cache is enabled with the appropriate bit in the CACR set. • The CDIS signal is negated. • The CIIN signal is negated for the access. • The CIOUT signal is negated ... • The MMU validates the access." CDIS: "disables the caches, regardless of the state of the enable bits in CACR"; 5.11.1 "CDIS does not flush ... entries remain unaltered and become available again when CDIS is negated." |
| 6.3.1.1 | WA, bit 13: "A reset operation clears this bit. ... If the data cache is disabled or frozen, the WA bit is ignored." |
| 6.3.1.2 | DBE, bit 12: "set to enable burst filling of the data cache. ... A reset operation clears the DBE bit." |
| 6.3.1.3 | CD, bit 11: "The processor clears all valid bits in the data cache at the time a MOVEC instruction loads a one into the CD bit of the CACR. The CD bit is always read as a zero." |
| 6.3.1.4 | CED, bit 10: "The processor clears only the specified long word by clearing the valid bit for the entry at the time a MOVEC instruction loads a one into the CED bit of the CACR, regardless of the states of the ED and FD bits. The CED bit is always read as a zero." |
| 6.3.1.5 | FD, bit 9: "When the FD bit is set and a miss occurs during a read or write of the data cache, the indexed entry is not replaced. However, write cycles that hit in the data cache cause the entry to be updated even when the cache is frozen." |
| 6.3.1.6 | ED, bit 8: "When it is cleared, the data cache is disabled. A reset operation clears the ED bit. ... Disabling the data cache does not flush the entries. If it is enabled again, the previously valid entries remain valid and can be used." |
| 6.2 | reset: "all valid bits of both caches are cleared. The cache enable bits, burst enable bits, and the freeze bits in the cache control register (CACR) for both caches ... are also cleared ... The WA bit in the CACR is also cleared." |

No snooping: nothing in ch. 6 updates or clears the data cache for another master's writes (DMA, blitter); software
clears it (CD/CED). There is no PMMU in the core, so CIOUT and "the MMU validates the access" are always true.

## 2. Design

### 2.1 Storage (`WF68K30L_DCACHE`, replaces the old F59 `wf68k30L_dcache.vhd`)
- Data 64 × 32 bits with byte enables (index A7:4 & long select A3:2), tag 16 × 27 (A31:8 & FC2:0), valid 64 flat
  bits (flat vector: lesson from the I cache Gowin crash). `syn_keep` on arrays, `syn_preserve` on valid bits.
- Two read ports for the lookup (entry of the first byte and of the last byte of the operand) and one write port.
- Reset, CD: all valid bits cleared. CED: valid bit CAAR(7:2) cleared, whatever ED/FD.

### 2.2 Reads
- Lookup with the live operand request (address, FC, size) in the bus interface.
- **Hit** (ED, CDIS negated, not RMC, FC /= 7, every entry the operand touches valid with a matching tag): the
  operand comes from the cache, no bus cycle; DATA_RDY one clock after the request, data aligned as from the bus.
  The request is masked from the bus FSM and from every chain (as the I cache masks PF_REQ).
- **Partial hit** (misaligned operand, one entry hits, the other misses): the 030 serves the hit half from the cache
  and runs bus cycles only for the missing half. Here: the whole operand goes to the bus (both halves), and both
  entries are refilled from it. Same data, a few clocks more; documented deviation (D-Q1).
- **Miss**: bus cycles as now. CIIN is latched per portion (as the I cache). The 16-bit port gives a full aligned
  word with each portion (6.1.3.1), so each portion fills one word of its entry.
  - The fill writes an entry only when both words of the long word were read with CIIN and BERR negated, and the
    tag is written with the first word (other valid bits of the line cleared on a tag change).
  - Words of a touched entry that the operand did not read are fetched by extra fill cycles, as Fig. 6-6/6-9, only
    when the operand's first portion had CIIN negated and the cache is enabled, not frozen, and CDIS negated.
    With CIIN asserted (every ST cycle) there are no extra cycles, so the ST bus is unchanged.
  - A bus error on a fill-only cycle: no exception, the entry stays invalid (6.1.3.1).
- RMC read portion: forced miss (no hit), but it fills/updates if CIIN is negated (6.1.2.2).

### 2.3 Writes (write-through)
- Every write runs its bus cycles as now (posted writes unchanged). The cache is updated when the write's first bus
  cycle starts (the 030 writes the cache before the external write), from the operand's data and byte lanes.
- Per touched entry, with ED set and CDIS negated (CIIN is not looked at: ignored on writes):
  - tag match and entry valid (hit): bytes updated, even when FD is set;
  - otherwise WA = 1 and FD = 0: aligned long word with a tag miss: tag replaced, the long written and marked valid,
    the other three entries of the line invalid; aligned long word, tag match, entry invalid: written and validated;
    any other write (byte, word, misaligned long) that misses: the entry's valid bit cleared, tag and data unchanged
    (for a misaligned long, both touched entries; Fig. 6-4 example 5 lists only "V2 <- 0" because in its
    starting state V1 is already invalid, example 2: "b6-b7 result in a cache miss");
  - otherwise (WA = 0, or FD set): no change.
- RMC write portion: as any write (updates a matching entry, WA for allocation).
- CPU space (FC = 7): never looked up, filled or updated.

### 2.4 CACR
ED (8), FD (9), CED (10), CD (11), DBE (12), WA (13): ED/FD/DBE/WA are stored and read back (the mask $3313 already
keeps them), CED/CD are strobes and read as zero. DBE has no effect (no burst until a burst-capable fast RAM
exists; CBREQ stays negated).

## 3. What this means on the ST build
- With ED = 0 (reset, and every regression program) nothing changes.
- TOS 2.06 (`tos206.hex`, $E3043E/$E1A984) writes CACR = $3919 when its Cache option is on: CI, CD, then EI, ED,
  IBE, DBE and **WA**. Under the TF536 rule every ST read has CIIN asserted, so reads never fill. But writes ignore
  CIIN: with WA = 1 every aligned long-word write to ST-RAM or I/O creates a valid entry, and a later read of the
  same long word hits and needs no ST bus cycle. That is what a real 030 does on a TF536 with TOS's cache option
  on. Consequences (real 030 behaviour, no snooping):
  - fewer ST read cycles after long writes (faster, and not cycle-identical to the cache-less build);
  - coherency is software's job: a DMA, blitter or shifter change to memory the CPU wrote with longs is not seen
    until the cache is cleared (TOS's flush routine at $E00620 sets CI|CD);
  - an I/O register written with a long and read back (e.g. a long write to $FF8604, DMA data + mode) returns the
    written value from the cache instead of the device status.
  This needs a board test before the D cache is used with TOS's Cache option; CDIS (a hardware disable, today tied
  negated) is the safe fallback. D-Q2.

## 4. A3: the request queue (two requests in flight)
Separate step after the D cache works (OPTION_A_DESIGN.md A3 assessment):
- A one-deep queue behind the running operand request in the bus interface: the control unit may present the next
  operand request (address computed, (An)+ step done) before the current read's DATA_RDY.
- DATA_RDY/BERR tagged per request; a queued request is cancelled, not run, when the running one faults, and the
  (An)+/-(An)/offset step of the cancelled request is undone so the fault frame and registers are those of the
  faulting access.
- A read hit in the D cache completes the queued request without a bus cycle.
Scope decided in its own design checkpoint once the D cache is in (§6).

## 5. Tests
- `sim/rtl/prog_dcache.s` + `check_dcache.py` + `run_dcache.sh` (tb030 CIMODE=1: $8000–$FFFF RAM and
  $FD0000–$FEFFFF ROM cachable; tb control $3502 asserts CIIN on every cycle): hits (no bus read), misaligned
  operands across two entries, write-through (bus write always), write hit update, WA = 0 vs 1 (aligned long
  allocate, byte/word/misaligned invalidate), FD, CD, CED via CAAR, ED off/on (entries kept), CDIS, user vs
  supervisor (FC in the tag), CIIN asserted mid-run (hits kept, no fills, writes still allocate with WA), TAS/CAS
  read portion never hits, bus errors on operand and on fill-only cycles, CPU space never cached; CIMODE 0 and 1,
  WS 0/1/3/7, FAST_HANDOFF 0/1.
- Full regression (`cmp_full.sh`, 92 runs) vs the I cache head: must be identical (ED is never set there).
- Gate level: `run_icache_net.sh`-style test through the bridge with the netlist (`run_dcache_net.sh`).

## 6. Open questions
- D-Q1: partial hits of misaligned operands go to the bus for the whole operand (correct data, not 030 timing).
- D-Q2: WA write allocation of ST-side writes with TOS 2.06's $3919 (§3): board test before use.
- D-Q3: no burst (DBE) until fast RAM.
