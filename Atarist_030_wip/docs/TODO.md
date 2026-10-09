# TODO (in priority order)

1. **URGENT / REQUIRED: WF68K30L bus request handoff rework.** The next bus cycle must start straight after S5 when a
   request is pending, like a real 68030 (cycle-correct; also a speedup). Wanted, not optional.
   - Full handover: [`handoff/HANDOVER_2026-10-09_cpu_rework.md`](../../handoff/HANDOVER_2026-10-09_cpu_rework.md); rollback tag `rollback-2026-10-09-eas`.
   - Now: DATA_C1C4 -> IDLE -> START_CYCLE, 2 extra clocks per transfer (hdl/cpu030/wf68k30L_bus_interface.vhd:530-568,
     back to IDLE at :565-566). Requests are masked while BUS_BSY (wf68k30L_top.vhd:744-764); DATA_RDY is strobed on the
     edge that ends the cycle (bus_interface.vhd:908-923, BUS_CYC_RDY at S5 :1018-1020), so the control unit only
     issues the next request afterwards. START_CYCLE-keyed logic: :455 SIZE_N, :622 AERR_I, :645 PF_START, :692 queue flush.
   - Expected (notes/RAM_PATH.md, RAM code): reads +32%, writes +37%, copy +22%, dbra loop +33%, ROM code +10-15%.
   - Skipping only IDLE (156 -> 94 ns) gives nothing; the request must reach the bridge within 62.5 ns.
2. **Prefetch queue fetches past taken branches** (2-3 wasted 500 ns words per branch; up to ~35% in tight loops).
3. **Caches** (`ST_030_CACHES`): needs CIIN for I/O/ROM, cache flush on Pexec (TOS does it via CACR), fast RAM.
   The real TF board runs loops from the 256-byte I-cache; this is the largest possible speedup.
4. **Blitter** shows as disabled under TOS 2.06.
5. **Dialog exit-button click loss:** OK/Cancel ignore mouse clicks inside form_do (radio buttons work, Return works).
   Present on F63 too: helper mouse/button injection or IKBD path.
6. **Helper SD write timeout** ("SDC: write timeout", core sd_card state 13); `ST_SD_WRITE_FIX` does not cure it.
7. **Async reset / PR1014 leftovers:** PR1014 still reported for the clk_osc pad -> DCE hop.
8. **AE350 flash MISO pad constraint (SPI_SDC part 2):** MISO at 20 ns fails in every placement; not in the TNS table.
