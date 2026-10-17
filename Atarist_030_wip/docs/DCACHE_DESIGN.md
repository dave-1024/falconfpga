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

## 2. Design (as built, commit 706a0aa)

### 2.1 Storage (`WF68K30L_DCACHE`, replaces the old F59 `wf68k30L_dcache.vhd`)
- An operand touches entry E0 (A31:2) and, when it crosses a long word boundary, E1 = E0 + 1.
- Data: two banks by A2 (E0 and E1 are always in different banks), each 32 entries x 4 byte lanes (8 arrays of
  32 x 8, distributed RAM, one write and one read address each), so both entries are read or written in one clock.
- Tags: two banks by A4 (lines with A4 = 0 / 1), 8 x 27 bits (A31:8 & FC2:0) each; E0 and E1 are in the same line
  or in adjacent lines. Valid: 64 flat flip-flops (lesson from the I cache Gowin crash).
- `syn_keep` on every data and tag array and on VALID, `syn_preserve` on VALID (and on the bus interface's fill
  buffer and FILL_ACC). Nothing is tied constant: ED/FD/WA come from CACR, CIIN from the bridge decode per cycle.
- Reset and CD clear every valid bit; CED clears the bit at CAAR 7:2, whatever ED and FD are.

### 2.2 Reads (bus interface)
- **Lookup is registered.** Every clock the cache looks up the live request (ADR_NXT, FC_NXT, operand size, the
  values the address latch takes in IDLE) and the bus interface keeps hit + operand in flip-flops (DC_PH, DC_PD,
  DC_PV = a read was pending without DATA_RDY). A cache update in that clock cancels the registered hit. So no
  path goes from the address logic through the cache RAM into the bus state machine.
- **Hit** (ED set, CDIS negated, FC /= 7, not RMC, every touched entry valid with a matching tag):
  - in START_CYCLE (the request came while the bus was idle): DATA_RDY on the edge that ends START_CYCLE, no bus
    cycle; START_CYCLE goes to IDLE or straight into a waiting queue prefetch (the bus is free for it);
  - on the S5 edge of a prefetch (the read waited for it, the OP_CHAIN case): DATA_RDY on that edge instead of the
    chained read cycle.
  - So a hit costs the request clock plus one clock, a bus read on the ST at least six.
- **Not looked up:** a read presented in the IDLE clock right after a posted write (PW_GO) has no registered lookup
  yet. With ED set it goes through START_CYCLE (one clock more than the PW_GO chain, and it can hit there); with ED
  clear PW_GO is unchanged.
- **Partial hit** (misaligned operand, one entry hits): the whole operand goes to the bus and both entries are
  refreshed from it (the 030 reads only the missing half). Same data, more clocks. Deviation D-Q1.
- **Miss:** the bus cycles run as before. Each portion's whole port word (16-bit port: the aligned word; 32-bit
  port: the long word, 6.1.3.1) is kept for E0 or E1 with "CIIN negated (CIIN latched as for the I cache) and no
  bus error" (FB_D0/FB_D1, FB_OK0/FB_OK1, FB_BE0/FB_BE1).
- **Fill cycles** (`FILL_ACC`): when every operand portion was cachable, no bus error, not RMC, not CPU space and
  the cache is enabled and not frozen, word cycles read the missing words of the touched entries after the
  operand's DATA_RDY (the core goes on; its next request waits for the bus). Order: E0 offset 0, E0 offset 2, E1
  offset 0, E1 offset 2, skipping words already read. Figure 6-6 (byte at $03 -> word $00) is the same; Figure 6-9
  (long at $06: $06, $04, $08, $0A) runs here as $06, $08, $04, $0A (D-Q6, order only).
  A fill cycle with a bus error, CIIN asserted or an 8-bit port ends the fill of its entry: no exception, the
  entry is not validated (6.1.3.1). A read that may need fill cycles does not chain into a prefetch (DP_CHAIN).
  Fill cycles do not touch DATA_VALID, the SSW staging, the fault snapshot or DBUFFER; FC/address come from the
  read (DC_OFC, FILL_WADR).
- **Cache update** (`DC_FL_GO`), in the clock after the read's last cycle, only when something was read cachable
  or a bus error hit an entry, and ED set / CDIS negated, per entry:
  - both words OK: a valid matching entry is updated; otherwise, when not frozen, the entry is replaced (a new tag
    clears the line's other valid bits);
  - a bus error on the entry: valid bit cleared (also for a bus error on the operand itself, which takes its
    exception as before; clearing a valid bit can never return stale data, D-Q5);
  - some words OK and the entry valid with a matching tag: those words updated.
  The bus stays idle in that clock (the next read is looked up after the update). With CIIN asserted (every ST
  cycle) nothing is read cachable, so there is no such clock and no fill cycle.
- **RMC** (TAS, CAS, CAS2): the read never hits (6.1.2.2, 11.4); words it reads with CIIN negated update/create
  entries as above, but no fill cycles run inside the locked sequence (D-Q7).

### 2.3 Writes (write-through)
- Every write runs its bus cycles as before (posted writes unchanged). The cache is updated in the clock after the
  write's first bus cycle started (START_CYCLE, or the OP_CHAIN/PW_GO chain edge), from WP_BUFFER (the write data,
  right-justified), the address and FC of the cycle, i.e. before the external write ends.
- Per touched entry, with ED set, CDIS negated, FC /= 7 (CIIN is not looked at):
  - valid with a matching tag (hit): bytes updated, also when FD is set;
  - otherwise WA = 1 and FD = 0: an aligned long word is written and validated (tag miss: tag replaced, the line's
    other three valid bits cleared); a byte, word or misaligned long miss clears the entry's valid bit (for a
    misaligned long both touched entries; Fig. 6-4 example 5 lists only "V2 <- 0" because in its starting state
    V1 is already invalid, example 2: "b6-b7 result in a cache miss");
  - otherwise (WA = 0, or FD set): no change.
- RMC write portion: as any write. CPU space: never.

### 2.4 CACR
ED (8), FD (9), CED (10), CD (11), DBE (12), WA (13): ED/FD/DBE/WA are stored and read back (the mask $3313 already
keeps them), CED/CD are strobes and read as zero. DBE has no effect (no burst until a burst-capable fast RAM
exists; CBREQ stays negated). CDIS (registered pin) disables lookups, fills and updates of both caches and keeps
the contents.

### 2.5 Timing with the data cache disabled
With ED = 0 (reset value, every regression program except prog_dcache) every added path is inactive: no lookup is
used, no fill cycle, no update clock, PW_GO and the chains unchanged. The 92-run regression is clock-identical.

### 2.6 Timing changes with ED = 1 (intended)
- Read hits: no bus cycle (see 2.2).
- A read right after a posted write goes through START_CYCLE (+1 clock when it misses).
- After a cachable read (CIIN negated) or a read with a bus error: one idle clock for the cache update, and the
  fill cycles; a read that may need fill cycles does not chain into a prefetch.
- On the ST (CIIN asserted on every read) only the first point and hits on entries created by WA write allocation
  remain (section 3).

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

## 4. A3: the request queue (two requests in flight): not built in this run

Status 17 Oct 2026: designed, not implemented. The D cache above does not need it: hits, fills and write updates
work with one outstanding request, and the fill cycles run behind the operand's DATA_RDY.

What A3 needs (OPTION_A_DESIGN.md "A3" assessment, and the code read for this run):
- Control unit (wf68k30L_control.vhd, 2753 lines): the MOVEM read loop is DATA_RDY -> INIT_EXEC_WB -> SWITCH_STATE ->
  CALC_AEFF (request). To present read n+1 before read n's DATA_RDY, MOVEM_PNTR / ADDRESS_OFFSET / the (An)+ step
  must advance at the request, not at ALU_INIT, and RD_RDY / the ALU load in INIT_EXEC_WB must take the data of the
  oldest request (a tag per request). CYCLECONTROL / READ_CYCLE assume one request.
- Top (P_BUSREQ) drops requests while BUS_BSY; it must pass a second one to the bus interface.
- Bus interface: a one-deep queue (address, FC, size, RMC, tag) behind the running operand cycle, started on the
  S5 edge like OP_CHAIN (or served by the D cache); DATA_RDY/BERR returned with the tag; when the running cycle
  takes a bus error the queued request is cancelled, not run, and the control unit undoes its address step
  ((An)+ increment, MOVEM offset) so the frame and the registers show the faulting access only.
- Tests: prog_movemr/prog_berrwb/prog_fault variants with a bus error on read n (queued n+1 must never appear on
  the bus), regression timing documented per program (A3 changes MOVEM read timing on purpose).
Why not now: it is a control-unit rework with a fault/undo path (OPTION_A: "a control-unit and bus-interface
rework, not a small step"), measured gain on the ST bench was nil for steps 2/3 (bridge-bound), and it is
independent of the cache correctness above. Proposed as its own branch step after the D cache board test.

## 5. Tests
- `sim/rtl/prog_dcache.s` + `check_dcache.py` + `run_dcache.sh` (tb030 CIMODE=1: $8000–$FFFF RAM and
  $FD0000–$FEFFFF ROM cachable; tb control $3502 asserts CIIN on every cycle): hits (no bus read), misaligned
  operands across two entries, write-through (bus write always), write hit update, WA = 0 vs 1 (aligned long
  allocate, byte/word/misaligned invalidate), FD, CD, CED via CAAR, ED off/on (entries kept), CDIS, user vs
  supervisor (FC in the tag), CIIN asserted mid-run (hits kept, no fills, writes still allocate with WA), TAS/CAS
  read portion never hits, bus errors on operand and on fill-only cycles, CPU space never cached; CIMODE 0 and 1,
  WS 0/1/3/7, FAST_HANDOFF 0/1.
- Full regression (92 runs + prog_dcache) vs the I cache head cd7b70c: 92/92 cycle-identical (ED is never set by
  those programs). A3 is not built, so no intended timing change exists on ST with CACR ED=0.
- Result (commit 706a0aa): `run_dcache.sh` PASS in all 16 configs (CIMODE 0/1 x WS 0/1/3/7 x FAST_HANDOFF 0/1);
  I cache unit test PASS.
- Gate level: `run_icache_net.sh`-style test through the bridge with the netlist (`run_dcache_net.sh`).

- Gate level (Gowin netlist wf030.vg of 706a0aa, sha256 31ced2c0...cdef6): run_unit.sh ERRORS=0 in all 6 phases,
  traces byte-identical to cd7b70c; run_icache_net.sh PASS; run_dcache_net.sh PASS
  (`c1:2/0 c2:2/0 c3:4/0 c4:0/0 c5:0/1 c6:0/2 c7:2/0 c8:0/0 | ... 3706:beef 3708:1234 370a:5678`).
- ST build 706a0aa (st_helper_hdn_dc_706a0aa_p3.fs, sha256 ae5651ee46db1b606c3368a687e9e2ed6061871dffd7173965aa81a3d4a9ffb8):
  LUT 42093 / ALU 4815 / Reg 18086 / RAM16 246 / BSRAM 172 (47eba71: 35955 / 4590 / 15347 / 246 / 172);
  Fmax clk_cpu030 22.393 MHz (16 MHz target; 47eba71 23.069), clk32_core 33.509 MHz (32; 47eba71 35.537), TNS 0 on both.
  WF68K30L_DCACHE is present: 2048 DFFCE (the 256 data bytes) + 496 DFFRE (tags, valid) + ~5.8k LUT/MUX.
  Slowest clk_cpu030 path is opcode decoder -> exception handler (slack 17.8 ns); no D cache cell in the
  reported worst paths.

- After D-Q8 (ff6af03, st_helper_hdn_dc_ff6af03_p3.fs, sha256
  c9a160b6c34df3c28a97826b73198999a57cbe03be9961f8217cdbae1d41c39e): WF68K30L_DCACHE = 74 RAM16SDP4 (32 for the
  eight 32 x 8 data lanes, 42 for the two tag banks, replicated per read port) + 64 DFFRE (valid bits); no data
  flip-flops left. LUT 37662 / ALU 4817 / Reg 15637 / RAM16 320 / BSRAM 172 (706a0aa: 42093 / 4815 / 18086 / 246 / 172).
  Fmax clk_cpu030 22.794 MHz (706a0aa 22.393), clk32_core 33.784 MHz (706a0aa 33.509), TNS 0 on both; slowest
  clk_cpu030 path opcode decoder -> ADR_EFF (slack 18.6 ns), no D cache cell in the reported paths.
  Behaviour: dcache + icache unit PASS (all configs), regression 96/96 cycle-identical to 706a0aa (prog_dcache
  included, cache on), gate-level netlist (sha256 d21d7c41...b6e64): run_unit ERRORS=0 with traces identical,
  run_icache_net PASS, run_dcache_net PASS.

## 6. Open questions
- D-Q1: partial hits of misaligned operands go to the bus for the whole operand (correct data, not 030 timing).
- D-Q2: WA write allocation of ST-side writes with TOS 2.06's $3919 (§3): board test before use. Resolved later by
  the planned 68030 PMMU (tables mark I/O and ST-RAM cache-inhibited, as on TT/Falcon); until then CDIS is the fallback.
- D-Q3: no burst (DBE) until fast RAM.
- D-Q4: A3 (two requests in flight) deferred (§4).
- D-Q5: any bus error seen on an operand or fill word clears that entry's valid bit (the manual only requires it
  for the fill-only cycle; clearing more can never return stale data).
- D-Q6: fill order for a misaligned operand follows the operand cycles, then the missing words (Fig. 6-9 order
  differs; data and final cache state are the same).
- D-Q7: no fill cycles inside a locked RMC sequence (TAS/CAS/CAS2); the RMC read is forced to miss as the manual
  requires and still updates/creates the entry from its own data.
- D-Q8 (resolved 17 Oct 2026, approved by David): each data bank now has one write port. E0 and E1 of an operand
  always sit in different banks (A2 differs), so the two entries are muxed onto per-bank index/data/byte-enable
  signals and written in the same clock as before; no write split, no timing change (regression incl. prog_dcache
  cycle-identical to 706a0aa). The tag banks get the same single-port treatment.
