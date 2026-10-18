# TODO (in priority order)

## Status 18 Oct 2026 (midday)
F3 (MOVEM register-to-memory writes back to back) is done on `f3-write-queue` (304b885; merge to main approved by
David). Board build `st_helper_hdn_f3a_7919eb3_p3.fs` (sha256 56556195...e211d78e): GEMBENCH 6.08 RAM 101% / ROM
104% of a stock STE, Average 92% (STE20608) / 132% (STFM1048); GEMBench 4.03 135%. Rollback: F3a 7919eb3, then F2
c4de2ec, then dc_ff6af03.
- **New correctness item: bus-error frame stage B ($0E).** The long ($B) frame takes $0C/$0E from BIW_1/BIW_2
  (`top`, STACK_POS 8). For an instruction without a third word BIW_2 is a stale word from an earlier instruction,
  whose value depends on prefetch timing (seen in prog_movemx: F2 stacked $6000, F3 $0536, for `4CDA 142A` at
  $FCFF10 where the next word is $48F8). A 68030 stacks the pipe contents (stage B = the word after stage C, here
  PC+4). Fix: load stage B from the prefetch queue (the word following the instruction's last decoded word) instead
  of BIW_2, check against the A1200 oracle (FALCON_LESSONS: real silicon decides), and add a frame check to
  prog_fault/prog_movemx. Independent of F3; handler-recorded fields are unaffected.
- Remaining display gap vs STFM1048 (Dialog 90, Graphics 70, Window 94): see the instruction timing analysis
  (box notes `gb608_ramrom/INSN_TIMING.md`).

## Status 18 Oct 2026
MOVEM timing F1 (priority encoder) and F2 (MOVEM read-ahead) are merged on `main` (branch `f1-movem-timing`).
Board build `st_helper_hdn_f2_c4de2ec_p3.fs` (sha256 f7d2672c...a796fb): GEMBENCH 6.08 RAM 91% / ROM 104% of a stock
STE (was 71 / 73), GEMBench 4.03 134%. Rollback: F2 c4de2ec, then dc_ff6af03. Next: F3 (below), on `f3-write-queue`.
- **GEMBENCH 6 sees no blitter (new, 18 Oct 2026):** its System panel shows "BLiTTER NP" under TOS 2.06, so the
  Display group compares software drawing with a blitter STE (46%; Blitting 15%), while against the blitter-less
  STFM1048 set it is 93% (Blitting 90%). Check how GEMBENCH 6 detects the blitter (Blitmode / cookie / register
  probe) and whether TOS 2.06 uses ours; ties in with "EmuTOS blitter greyed out" below.

## Status 17 Oct 2026
The 68030 I and D caches (MC68030UM ch. 6) and the data-fault fixes are merged on `main` (branch `caches`, which
contains `fault-fixes`). Board build `st_helper_hdn_dc_ff6af03_p3.fs` (sha256 c9a160b6...41c39e): TOS 2.06 boots with
"Cache" ticked, GEMBENCH 133 / Display 89 / CPU 252, unchanged as expected (only $01000000-$01FFFFFF is cachable and
no fast RAM is fitted). Open from that work, in order:
1. **D-Q2 write-allocate check on the board** (DCACHE_DESIGN.md §3/§6): a small program that reads CACR with MOVEC
   and shows it (does TOS 2.06 set WA, i.e. $3919?), then a long-write/read-back test on an ST I/O register and a
   DMA buffer with WA on. With WA, aligned long writes allocate D cache entries even though CIIN is asserted (CIIN
   is ignored on writes), so a later read can hit stale data. Fallback: CDIS. Resolved for good by the PMMU (item 4).
2. **030-side fast RAM** (8-16 MB at $01000000), so that the caches have something to cache; then burst (IBE/DBE,
   CBREQ/CBACK/STERM).
3. **A3 request queue: deferred** (DCACHE_DESIGN.md §4, D-Q4): two requests in flight, per-request BERR, undo of
   the (An)+ step on a fault. A control-unit rework with no gain while the ST bus dominates.
4. **68030 PMMU: planned later step, in HDL inside WF68K30L (not a table walk on the AE350).** Its tables mark I/O
   and ST-RAM cache-inhibited as on the TT/Falcon (CI, CIOUT), which resolves D-Q2. Needed for TOS 3/4 (PMOVE).
- **Fault-fixes one-off halt (noted 17 Oct 2026):** a single "System halted!" was seen once while testing the
  fault-fixes build and has not come back; the ic_47eba71 and dc_ff6af03 cold boots were clean. Treated as the
  pinned warm-reset/bare-reload halt below until it shows a different pattern.
- **Pinned: the ~10% GEMBENCH display gap** (Display 89%), see below; the caches do not change it.

## MOVEM timing (f1-movem-timing merged on main 18 Oct 2026)
F1 (priority encoder) and F2 (MOVEM M->R read-ahead) are on main and on the board (MOVEM_TIMING_F1_F2.md).
Open:
1. ~~**F3: MOVEM R->M writes back to back.**~~ **Done 18 Oct 2026** (f3-write-queue, MOVEM_TIMING_F1_F2.md "F3"):
   the next register is taken in the S3 clock of the running posted write (outcome final there), S5 chain into its
   write, GAP 1; no queue/undo needed. 6.08 RAM 91 -> 101%. The original analysis kept below for reference:
   Writes still have a 3-clock register gap
   (WRITE_DEST WR_RDY -> EXECUTE -> WRITE_DEST), so 6.08 RAM write stays below a 68000. A bus chain can't help (no
   write request is pending at S5). Needs the control unit to present the next write before S5 (write queue or
   early posting), which must keep the synchronous write-fault model (WR_FLT = WR_RDY, DATA_VALID=0), the DOB of the
   faulted write and the (An)/-(An) state on a fault. Size it against the A3 queue (DCACHE_DESIGN.md §4).
   Measured on F2 (p608w, WS5): register-to-register write gap 3 (PW_GO from the second IDLE clock); the long's two
   word halves are already gap 1. Gap 1 needs WR_REQ(k+1) at S5 of write k, two clocks earlier: the ALU must be
   released when write k *starts* (data already in WP_BUFFER) instead of at WR_RDY (option A), so EXECUTE(k+1) runs
   during write k, and EXEC_WB must hold a second WRITE_DEST in flight; plus a write->write chain at S5 (OP_CHAIN
   only chains from prefetches today). A fault on write k then arrives with k+1 already set up: that is the queue
   and the undo the A3 item describes. 6.08 RAM is now 91% (reads at gap 1, writes at gap 3); ROM 104%.
2. **Read -> write gaps in copy loops** (RMW and MOVE (An)+,(An)+ read->write gap 6): same mechanism as F3.
3. ~~Merge decision~~: merged 18 Oct 2026 (David).

## Next fixes, in order (set by David, 15 Oct 2026)

Done items move to the "Bugs found" list in [`FALCON_LESSONS.md`](FALCON_LESSONS.md) (SD hardening + FDC error status,
FNOP probe, disk-change corruption, Float Math/gb403, BERR writeback F66: all closed 15 Oct 2026).

1. **Warm-reset halt**: PINNED, see "Pinned: warm-reset halt" below (no work on it for now).
2. **EmuTOS blitter greyed out** (works under TOS 2.06; HDL path inspected and correct).
3. **Helper port** (AE350 companion firmware port).
4. ~~Phase 2 of the CPU rework~~: **done** 16 Oct 2026 (merged; PHASE2_DESIGN.md, GEMBENCH 132%).

## Phase 2 follow-ups (open, 16 Oct 2026)
0. **Bridge timing left from the 32 MHz CPU clock**: reviewed 16 Oct 2026, see [`BRIDGE_REVIEW.md`](BRIDGE_REVIEW.md) (no bridge leftovers that cost speed; options 1-2 cleanup, gains are core-side).
1. **Option (a): pipelined control unit.** Steps 2/3 **done** 17 Oct 2026 (08e1cf8 MOVEM write overlap, 039c710 MOVEM
   early read request; GEMBENCH 133%, see [`OPTION_A_DESIGN.md`](OPTION_A_DESIGN.md)). **A3** (issue the next request
   before the current data: request queue, per-request BERR, undo of the (An)+ step) is **deferred** (it was planned
   with the cache work; the caches went in without it, DCACHE_DESIGN.md §4); no gain while the ST bus dominates.
2. ~~**Data-fault timing and the $A/$B frame.**~~ Fixed (FLT1/FLT2, 17 Oct 2026, merged on main with `caches`, on the
   board since ic_47eba71): no program bus cycle after a data write fault, short $A frame for a write fault at an instruction
   boundary. See [`FAULT_FIXES.md`](FAULT_FIXES.md).
3. **Stale bus-fault flag on a chained late BERR.** A BERR at S5 on a cycle that chained into the next updates BUS_FLT
   after VALIDATION used it; the flag can stay stale into the chained cycle. Pre-existing PH2 corner, no bench yet.
   Checked 17 Oct 2026: not the FLT1/FLT2 path (bus interface P_SYNC vs control unit); still open (FAULT_FIXES.md §3).
4. **Halt on a reload without a cold boot.** A bare op 1 reload (no `c`) can stop at "System halted!" after the
   cartridge self-test; 5246d00 and de35f5f alike, `c` clears it. Related to the pinned warm-reset halt below.
5. **clk_cpu030: tighten the decoder -> ADR_EFF path before caches.** Opcode decoder -> I_CONTROL fetch state -> AR
   select -> I_ADDRESSREGISTERS effective-address adders -> ADR_EFF_I, one full clk_cpu (50.8 ns in de35f5f,
   19.65 MHz; 45.0 ns in 5246d00). Placement-dependent; the caches will need the margin.
6. **clk32: blitter falling-edge path.** Half-period path blitter bltState -> blitter address -> gstmcu I/O decode ->
   gamecart_r/mde0_r/mde1_r (register.v samples on negedge), about 0.5 ns slack, mostly routing. The blitter arm has to
   stay; a fix needs register.v's sampling moved (timing change). Also jt49 -> sd_card data_out at 1.2 ns (full period).
7. **Helper serial silent after the first warm reset (open).** Seen on vchain and option-a: the first `w` after reloads gets no reply and `s` is silent until an op 1 reload. Not core-related (two cores). See FALCON_LESSONS "Helper serial silent". Check helper firmware/UART handling of the sysctrl reset.

## When the caches go in
Full plan: [`CACHE_PLAN.md`](CACHE_PLAN.md). Summary: real 030 I/D (256 B each, CIIN on ST-side, CDIS hard off,
no cache in the path when disabled; I then D; keep clk_cpu030 19–22 MHz headroom). Old attempt a7ccf76/e9a4fd9
stays out until that plan is followed.
- **Step 1, I cache: done** (17 Oct 2026, [`ICACHE_DESIGN.md`](ICACHE_DESIGN.md)); RTL unit test and full regression
  pass (ST build cycle-identical). Merged on main; board build ic_47eba71, GEMBENCH unchanged. Open: ICACHE_DESIGN Q1 (first
  long of a 4n+2 stream never cached), Q2 (CDIS source), Q3 (burst), Q4 (A3 queue with the D cache).
- **Step 2, D cache** (write-through, WA, CIIN, RMW rules; replaces wf68k30L_dcache.vhd), then 030-side fast RAM
  (8-16 MB) so that something is cacheable. **Done** (17 Oct 2026,
  [`DCACHE_DESIGN.md`](DCACHE_DESIGN.md)), data/tags in RAM16 (D-Q8), merged on main, board build dc_ff6af03
  (GEMBENCH unchanged); A3 queue deferred (D-Q4). Fast RAM still to do.
- **Later step, 68030 PMMU (in HDL, not on the AE350):** page tables mark I/O and ST-RAM cache-inhibited like TT/Falcon (CI/CIOUT), which
  resolves D-Q2 (WA allocating D cache entries on ST-side writes). Until then CDIS is the fallback.

## Pinned: warm-reset halt (pinned 16 Oct 2026, no work on it for now)
- **Symptom:** intermittent "System halted!" after the cartridge self-test, on FPGA reloads (op 1) and warm resets (`w`).
  Once it happens, stale SDRAM keeps it halting until `c` or a power cycle.
- **Status:**
  - F66 (st_helper_hdn_berr_7e3660e_p3) is on the board and shows no halts (10/10 reloads with the reference-frame check).
  - F67 (accept an external RESET+HALT during the RESET instruction) and F68 (an external reset clears RESET_TIMER)
    are correct per the MC68030 manual and the STE/TF534 wiring, but halt about 3 in 10 reloads.
  - ST_DR_PRECPU (cold-start second reset inside the CPU hold): 1 in 10. DIAG_OVERLAY builds: 0 in 27 (21 reloads + 6 `w`).
  - Likely timing-dependent: the plain build's clk32_core margin is only 0.04 MHz (32.04 against 32).
- **Evidence:** branch `warm-reset` @ 65e8b32, `docs/RESET_PATHS.md` sections 7-9 (on that branch), frames in `/workspace/gb`
  on the box (f67, f68, drp, f66base, diag).
- **Next step:** a seed/place_option sweep of the plain F67+F68 build, or more clk32 margin, then re-run the stress test.

## Pinned: remaining GEMBENCH display gap (pinned 17 Oct 2026)
- **Symptom:** GEMBENCH Display is 89% of a stock STE (CPU 252%): about 10% short on the screen tests (GEM Dialog Box
  80%, VDI Graphics 72%, GEM Window 81%, New Dialogs 81%).
- **Cause (working theory):** the 030 makes extra fetch cycles on the ST bus compared with a 68000: long-word prefetches
  split into two ST word cycles, queue prefetches beyond what the 68000 would fetch, and bridge hand-over slots. On the
  500 ns ST bus every extra cycle costs a full slot, and the display tests are bus-bound.
- **Next step:** count ST-bus cycles per GEMBENCH display loop (whole-ST bench / board bus trace) against a 68000 run;
  then trim fetches the 68000 would not make. Caches do not help here: by the CIIN decision (CACHE_PLAN.md) everything
  on the ST side stays uncached, so only 030-side fast RAM would.
- **Status:** deferred by David; no work on it for now.

## Pinned: final stage
- **Remove the ST/STE chipset switch.** The helper's ST/STE option misbehaves because the compile default
  is STE, and David only wants STE. Final stage: remove the helper option and its HDL option/plumbing
  (system_chipset etc.), hardwire STE, and simplify the code. Keep it until then for debugging.

## Older list

1. ~~WF68K30L bus request handoff rework~~ (**done**: F65 + phase 2, 16 Oct 2026; history below). Patch 1 (F65) is done and on
   `main` (`bb9baa2`): prefetch-to-prefetch S5-to-S0, `WF030_FAST_HANDOFF` on. Operand cycles still take IDLE.
   The next bus cycle must start straight after S5 when a
   request is pending, like a real 68030 (cycle-correct; also a speedup). Wanted, not optional.
   - Full handover: [`handoff/HANDOVER_2026-10-09_cpu_rework.md`](../../handoff/HANDOVER_2026-10-09_cpu_rework.md); rollback tag `rollback-2026-10-09-eas`.
   - Patch 1 (branch `f65-handoff`): prefetch-to-prefetch only. `WF030_FAST_HANDOFF` is commented out in `build_st_helper.tcl`. Operand cycles still take IDLE then START_CYCLE.
   - Now: DATA_C1C4 -> IDLE -> START_CYCLE, 2 extra clocks per transfer (hdl/cpu030/wf68k30L_bus_interface.vhd, DATA_C1C4 returns to IDLE). Requests are masked while BUS_BSY (wf68k30L_top.vhd P_BUSREQ); DATA_RDY is strobed on the edge that ends the cycle, so the control unit only issues the next operand afterwards.
   - Expected (notes/RAM_PATH.md, RAM code): reads +32%, writes +37%, copy +22%, dbra loop +33%, ROM code +10-15%.
   - Skipping only IDLE (156 -> 94 ns) gives nothing; the request must reach the bridge within 62.5 ns.
2. ~~**Prefetch queue fetches past taken branches**~~: **done** 16 Oct 2026 (vchain merged, PREFETCH_COF.md).
   Shelved: `prefetch-cof-qg` (look-ahead at real opcode positions, no extra gain, clk_cpu030 17.2 MHz).
3. ~~**Caches**~~ (**done** 17 Oct 2026: I and D cache merged, see the status at the top; text below is the old plan) (`ST_030_CACHES`): plan ready in [`CACHE_PLAN.md`](CACHE_PLAN.md). Needs CIIN (bridge asserts
   on all ST-side cycles), CDIS hard off, CIOUT from PMMU later, burst only for future 030-side fast RAM;
   no cache logic in the bus path when disabled. I-cache first, then D. Match real MC68030 (CACR/CAAR).
   GEMBENCH may show CACHE D=ON I=ON from CACR bits even with caches compiled out.
4. **Blitter** shows as disabled under TOS 2.06.
5. **Dialog exit-button click loss:** OK/Cancel ignore mouse clicks inside form_do (radio buttons work, Return works).
   Present on F63 too: helper mouse/button injection or IKBD path.
7. **Async reset / PR1014 leftovers:** PR1014 still reported for the clk_osc pad -> DCE hop.
8. **AE350 flash MISO pad constraint (SPI_SDC part 2):** MISO at 20 ns fails in every placement; not in the TNS table.
