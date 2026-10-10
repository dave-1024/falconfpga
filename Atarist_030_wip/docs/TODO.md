# TODO (in priority order)

1. **URGENT / REQUIRED: WF68K30L bus request handoff rework.** The next bus cycle must start straight after S5 when a
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
6. **Helper SD write timeout, and the floppy errors that follow it.** A write ends with
   "SDC: write timeout" and `hdl/misc/sd_card.v` sticks in state 13. Only a core reload clears it.
   `ST_SD_WRITE_FIX` does not cure it. Under TOS 2.06 the next floppy read then fails: that is the
   read error after a write, not a separate floppy bug and not the ROM. TOS error #35 (GEMDOS -35,
   no free file handle) on launching GEMBENCH is the same family: it happens on a runtime mount, or
   after a write has jammed the card. It does not happen when the image is mounted from `atarist.ini`
   on an FPGA power cycle. Seen again on EmuTOS 256K, 2026-10-10; first EmuTOS boot since the JSR
   SP fix. Not the JSR bug (that crashed or executed the filename; this is a clean GEMDOS alert).
7. **Async reset / PR1014 leftovers:** PR1014 still reported for the clk_osc pad -> DCE hop.
8. **AE350 flash MISO pad constraint (SPI_SDC part 2):** MISO at 20 ns fails in every placement; not in the TNS table.
