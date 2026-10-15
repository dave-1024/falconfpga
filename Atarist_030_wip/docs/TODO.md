# TODO (in priority order)

## Next fixes, in order (set by David, 15 Oct 2026)

1. **SD state-13 hardening** (branch `sd-harden`, define `ST_SD_HARDEN`, test variant, not flashed).
   Four items, see [`SD_WRITE_DEBUG.md`](SD_WRITE_DEBUG.md): check the data-response token and retry a
   rejected block; after the retries report an error and re-init the card instead of a silent done; bound
   the read-timeout / CMD17 retries with a re-init; latch the FDC sector at request time. Simulated in
   `hdl/misc/sim/tb_sd_harden.v` (rejected tokens, dead CMD24, dead reads). Still to do: board test, and
   pass the error to the FDC (record-not-found / CRC status) instead of only counting it.
2. ~~**FNOP frame fault** (bad format word, RTE takes exception 14).~~ **RESOLVED 15 Oct 2026: not a CPU
   fault.** The probe was wrong: FNOP3.PRG's handler restores A2 and then does `move.l a2,2(a2)`, so it
   patches the code at skip+2 instead of the stacked PC at 2(SP). RTE returns to the FNOP, and the patched
   code later bus-errors, which led to the exception 14. Its format-nibble print (`asl #4` then `and #15`)
   always gives 0. FNOP3.PRG read from the corrupt gb403.st is byte-intact (no INF text), so the disk did
   not cause it. The new probe `sw/fnop_probe/fnop4.s` (source in the repo) on the mch build, EmuTOS 256K,
   3 runs: Line-F, vector offset $2C, format 0, stacked PC = the FNOP, RTE to the patched PC. Correct
   68030 behaviour. The GEMBENCH Float Math failure was the corrupt AUTOFPU.BIN (FLOAT_PANIC.md); it passes
   on a clean image.
3. **$FFFF bus-error writeback bug** (BERR Dn writeback, see `docs/float_panic/FLOAT_PANIC.md`).
4. **Warm-reset halt** (`$482`): after `w` the 030 build stops at "System halted!"; `c` works.
5. **EmuTOS blitter greyed out** (works under TOS 2.06; HDL path inspected and correct).
6. **Helper port** (AE350 companion firmware port).
7. **Phase 2 of the CPU rework** (operand cycles without IDLE; see item 1 of the older list below).

## Older list

1. **URGENT / REQUIRED: WF68K30L bus request handoff rework.** Patch 1 (F65) is done and on
   `main` (`bb9baa2`): prefetch-to-prefetch S5-to-S0, `WF030_FAST_HANDOFF` on. The open fault is the
   FNOP frame, handed back in [`handoff/HANDOFF_2026-10-12_fnop_format.md`](../../handoff/HANDOFF_2026-10-12_fnop_format.md).
   On the board `FNOP` takes a bus error whose format word is not `A` or `B`, so `RTE` takes exception 14.
   The core is correct in simulation. Operand cycles still take IDLE. (FNOP: RESOLVED 15 Oct 2026, a probe bug; see Next fixes item 2.)
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
6. **Helper SD write timeout / runtime-mount errors: DIAGNOSED 15 Oct 2026** (`docs/SD_WRITE_DEBUG.md`).
   - **State 13 jam:** fixed by `ST_SD_WRITE_FIX` (7e3d5dd). It did not recur in stress tests: runtime
     mounts, 2x 737 KB uploads, desktop saves fired mid-upload. Max 580 clocks in CMD24, 0 errors.
     Remaining weaknesses are next-fix item 1.
   - **Corrupted images (gb403) and GEMDOS -35 / "not readable" after runtime mounts:** TOS never saw a
     media change on a runtime image swap, so it wrote the previous disk's FAT/directory/DESKTOP.INF into
     the new image. Reproduced, and fixed by `ST_FLOPPY_MEDIACH` (now on in build_st_helper.tcl). Board
     retest: the swapped image keeps its own directory, and GEMBENCH loads from a runtime-mounted disk.
7. **Async reset / PR1014 leftovers:** PR1014 still reported for the clk_osc pad -> DCE hop.
8. **AE350 flash MISO pad constraint (SPI_SDC part 2):** MISO at 20 ns fails in every placement; not in the TNS table.
