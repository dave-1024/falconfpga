# TODO (in priority order)

## Next fixes, in order (set by David, 15 Oct 2026)

Done items move to the "Bugs found" list in [`FALCON_LESSONS.md`](FALCON_LESSONS.md) (SD hardening + FDC error status,
FNOP probe, disk-change corruption, Float Math/gb403: all closed 15 Oct 2026).

1. **$FFFF bus-error writeback bug** (BERR Dn writeback, see `docs/float_panic/FLOAT_PANIC.md`).
2. **Warm-reset halt** (`$482`): after `w` the 030 build stops at "System halted!"; `c` works.
3. **EmuTOS blitter greyed out** (works under TOS 2.06; HDL path inspected and correct).
4. **Helper port** (AE350 companion firmware port).
5. **Phase 2 of the CPU rework** (operand cycles without IDLE; see item 1 of the older list below).

## Pinned: final stage
- **Remove the ST/STE chipset switch.** The helper's ST/STE option misbehaves because the compile default
  is STE, and David only wants STE. Final stage: remove the helper option and its HDL option/plumbing
  (system_chipset etc.), hardwire STE, and simplify the code. Keep it until then for debugging.

## Older list

1. **URGENT / REQUIRED: WF68K30L bus request handoff rework.** Patch 1 (F65) is done and on
   `main` (`bb9baa2`): prefetch-to-prefetch S5-to-S0, `WF030_FAST_HANDOFF` on. Operand cycles still take IDLE.
   The next bus cycle must start straight after S5 when a
   request is pending, like a real 68030 (cycle-correct; also a speedup). Wanted, not optional.
   - Full handover: [`handoff/HANDOVER_2026-10-09_cpu_rework.md`](../../handoff/HANDOVER_2026-10-09_cpu_rework.md); rollback tag `rollback-2026-10-09-eas`.
   - Patch 1 (branch `f65-handoff`): prefetch-to-prefetch only. `WF030_FAST_HANDOFF` is commented out in `build_st_helper.tcl`. Operand cycles still take IDLE then START_CYCLE.
   - Now: DATA_C1C4 -> IDLE -> START_CYCLE, 2 extra clocks per transfer (hdl/cpu030/wf68k30L_bus_interface.vhd, DATA_C1C4 returns to IDLE). Requests are masked while BUS_BSY (wf68k30L_top.vhd P_BUSREQ); DATA_RDY is strobed on the edge that ends the cycle, so the control unit only issues the next operand afterwards.
   - Expected (notes/RAM_PATH.md, RAM code): reads +32%, writes +37%, copy +22%, dbra loop +33%, ROM code +10-15%.
   - Skipping only IDLE (156 -> 94 ns) gives nothing; the request must reach the bridge within 62.5 ns.
2. **Prefetch queue fetches past taken branches** (2-3 wasted 500 ns words per branch; up to ~35% in tight loops).
3. **Caches** (`ST_030_CACHES`): needs CIIN for I/O/ROM, cache flush on Pexec (TOS does it via CACR), fast RAM.
   The real TF board runs loops from the 256-byte I-cache; this is the largest possible speedup.
4. **Blitter** shows as disabled under TOS 2.06.
5. **Dialog exit-button click loss:** OK/Cancel ignore mouse clicks inside form_do (radio buttons work, Return works).
   Present on F63 too: helper mouse/button injection or IKBD path.
7. **Async reset / PR1014 leftovers:** PR1014 still reported for the clk_osc pad -> DCE hop.
8. **AE350 flash MISO pad constraint (SPI_SDC part 2):** MISO at 20 ns fails in every placement; not in the TNS table.
