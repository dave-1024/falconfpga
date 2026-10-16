# TODO (in priority order)

## Next fixes, in order (set by David, 15 Oct 2026)

Done items move to the "Bugs found" list in [`FALCON_LESSONS.md`](FALCON_LESSONS.md) (SD hardening + FDC error status,
FNOP probe, disk-change corruption, Float Math/gb403, BERR writeback F66: all closed 15 Oct 2026).

1. **Warm-reset halt**: PINNED, see "Pinned: warm-reset halt" below (no work on it for now).
2. **EmuTOS blitter greyed out** (works under TOS 2.06; HDL path inspected and correct).
3. **Helper port** (AE350 companion firmware port).
4. **Phase 2 of the CPU rework** (operand cycles without IDLE; see item 1 of the older list below).

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
