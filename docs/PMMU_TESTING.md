# Testing the 68030 PMMU (falconfpga)

## In short
Every PMMU feature gets three kinds of test:
- **Simulation** (`sim/rtl/prog_pmmu.s`, run by `run_rtl.sh`): fast, exact, and cycle-level.
- **Our own program on the board** (`tools/pmmutest/PMMUTEST.PRG`): checks each feature against the page of
  the Motorola manual (MC68030UM) that defines it.
- **Existing software** that uses the PMMU: shows that real programs work. A test suite made from a real 68030
  (WinUAE's cputester run on David's A1200 + ACA1233) is the best way to get exact reference values.

## 1. PMMUTEST.PRG (tools/pmmutest)
- Build it with `./build.sh` (GNU as, position-independent code, GEMDOS header with no relocations).
- Copy it to a floppy image; putting it in AUTO is easiest. Example:
  `mformat -C -i pmt.st -f 720 :: && mmd -i pmt.st ::AUTO && mcopy -i pmt.st TTRAM.PRG PMMUTEST.PRG ::AUTO/`.
  Upload it with `up2.py`, `mount a` it, then cold boot.
- Each line says PASS, FAIL, DEV (a known, documented deviation of the current stage) or SKIP, with
  "exp=" and "got=" values. The last line gives the FAILS/DEVS totals.
- The same text is written to `PMMUTEST.TXT` in the current directory (the root of A: when run from AUTO). Read it
  back by downloading the image with `get` and opening it with `mtools`.
- Stage 1 tests (manual pages):

| Test | Manual | Expected |
|---|---|---|
| TC write $7FFFFFFF, read back | 9.7.1 p9-52 | $03FFFFFF |
| TT0 / TT1 write $FFFF7FFF | 9.7.3 p9-57 | $FFFF0777 |
| MMUSR write $FFFF | 9.7.4 p9-59 | $EE47 |
| CRP / SRP write all ones | 9.7.2 p9-54 | $FFFF0003 / $FFFFFFF0 |
| Invalid TC (E=1, PS=0) | 9.7.1 p9-53 | stored with E=0 |
| ... and the exception | 9.8 p9-64 | vector 56 (DEV in stage 1: no exception yet) |
| PMOVE in user mode | 9.8 p9-65 | privilege violation, vector 8 |
| TT0/TT1 with CI over a TT-RAM loop | 9.7.3 p9-57 | loop at least 2x slower than cached |
| TT0 with an FC that never matches | 9.7.3 p9-57 | loop speed same as cached |

- On falconfpga only TT-RAM ($01xxxxxx) can be cached, because the bridge asserts CIIN for ST space. So the TT
  timing test copies its loop into a TT-RAM block from `Mxalloc(...,1)`. If there is no TT-RAM (TTRAM.PRG not
  loaded) the test prints SKIP.
- Adding later stages: write a routine `T_xxx` and add it to the `tests` table. Planned:
  - translation with a small table: map a page of TT-RAM to another, check the data, check the U and M bits;
  - ATC: 22 entries (fill 23 pages and time the 23rd), PFLUSH by FC/mask/EA, PFLUSHA;
  - PTEST levels 0..7 and the MMUSR result (B, L, S, W, I, M, T, N), PLOAD;
  - faults: invalid descriptor, write protect, supervisor only, limit; the bus error frame
    (format $A/$B) and the SSW fields;
  - timing: count 200 Hz ticks ($4BA) over 10^6 iterations, or cycle-count loops, and compare them with
    MC68030UM 11.7 (table search clocks p11-60).

## 2. Existing software that uses the 68030 PMMU
| Software | What it uses | Can run here? | Notes |
|---|---|---|---|
| **WinUAE cputester** (Toni Wilen) | Runs every opcode, including PMOVE/PTEST/PFLUSH/PLOAD, on real hardware first, saves the results, then compares on the target. Has 68030 MMU modes. | Generate the reference data on David's **A1200 + ACA1233** (a real 68030). The Amiga side needs porting: a TOS loader for the test data, and a way to keep ST hardware out of the address map. | Best source of exact values from real silicon, including cycle counts if run with cycle counting. |
| **EmuTOS 1.4** (256K/512K/1M, `CONF_WITH_68030_PMMU=1`) | At boot: detects an 030 with `PMOVE TC,abs.L`, then sets up CRP/TC/TT0/TT1 tables (identity map, cache-inhibit regions). | Yes, if an EmuTOS image is flashed (not done this session). | Simple boot check: it must boot with the PMMU registers implemented. With stage 1 only the registers are used (TC.E stored, no translation yet). |
| **FreeMiNT** (with memory protection, `mint030.prg`) | Builds full page tables and turns on TC: separate tables per process, write protection, faults and recovery. | Needs stage 2 (translation + ATC) and stage 3 (faults). | The real end-to-end test. Without memory protection (`MP=NO`) it only uses TT regs. |
| **Outside** (virtual memory for the TT/Falcon) | Paging to disk: page faults, restarting instructions, the U/M bits. | Needs stages 2-3. | A hard test of bus error frames and restarting. |
| **Linux/m68k** (Atari kernel) | Full MMU (030 tables, TT0/TT1), PTEST in fault handling. | Needs stages 2-3, plus enough RAM and a disk image. | Gold standard, but slow to boot. |
| **TOS 3.06** | Its 030 table setup (TT tables, cache inhibit for I/O). | **No: TT only** (TT video, second MFP, SCC). It will not boot on the STE+030 core. | Use it only in Hatari TT mode, as a reference for how Atari builds the tables. |
| **Hatari** (`--cpulevel 3 --mmu on`) | WinUAE CPU core with MMU. | Runs PMMUTEST on the box. Getting it to run from a floppy or GEMDOS drive with TOS 2.06 is still to be sorted out. | Gives the expected results of a reference emulator. It is not cycle exact for the table search. |

## 3. Where results go
`docs/PMMU_PROGRESS.md`, plus screenshots in `docs/img/pmmu/`.

## 4. FreeMiNT with memory protection (tools/minttest)
Recipe and test: `tools/minttest/README.md` (`mkimg.sh` downloads the pinned FreeMiNT 1.19 snapshot, builds
MPTEST.PRG and a 720 KB floppy; no hard disk needed).

Hard disks on this setup (for later): the helper mounts ACSI images with `mount h0|h1 <file>` (targets 0 and 1
only, `hdl/atarist/acsi.v`), raw `.hd`/`.img` files anywhere on the FAT32 SD card (`sdc.c` accepts `.ST`/`.HD`;
contiguous files are direct-mapped). TOS 2.06 has no ACSI driver of its own, so an HD image needs a boot
driver (AHDI/HDDRIVER/...) in its root sector; that is why the MiNT test uses a floppy.

Findings so far (27 Oct 2026):
- MiNT's default memory protection is not strict: a `Pexec(100)` child is forked from its parent and keeps
  the parent's regions mapped (`k_exec.c`, `exec_region`: they are only marked invalid with MPF_STRICT). With
  `KERN_MPFLAGS=1` (MPF_STRICT, a normal mint.cnf option) the child's write gets "memory violation".
- Hatari 2.5 (STE, TOS 2.06 UK, 030 + MMU, 4 MB): MPTEST FAILS=0 (MP on, child V killed by SIGBUS, parent
  memory unchanged, three W children exit 0). Without strict mode the child's write goes through (FAILS=2).
  Hatari with 1 MB does not get to MPTEST (no BOOT.LOG), with 14 MB it does.
- Board (pmmu8, TOS 2.06, 4 MB): AUTO is reached (STAGE0.TXT), but MiNT never opens BOOT.LOG and MPTEST never
  runs, with memory protection on **and off**. So the stop is before MiNT's file system init and is not caused
  by MiNT's page tables (with MEM_PROT=NO MiNT does not set TC.E). Cause not found yet; see PMMU_PROGRESS.

### Status 27 Oct 21:30 UTC (MiNT on the board)
- Last on-screen text, MP on (mint_scr.st, WRITE_BOOT=NO): FAT/VFAT banner `(c) 2000-2010 by Frank Naumann.`
  (img/pmmu/mint_board_stop.png). With DIAG_OVERLAY (img/pmmu/mint_mpon_overlay_halt.png) the CPU is halted
  (double bus fault) right after mint030 set_mmu does `pmove 12(sp),tc` (TC $80D04447, CRP table $BC000);
  last bus cycle = a table-search read at $BC186.
- Theory: a PMMU/table-search fault seen only on the board (bridge/bus side): the same state replayed on the
  RTL core (tools/minttest/sim) translates correctly. Next: whole-ST bench or DIAG_EXCWATCH.
- MP off (mint_nomp.st) is separate: CPU keeps running past `Installing BIOS keyboard table`, no BOOT.LOG yet.

## Morning summary (27 Oct 2026, written ~23:00 GMT)

**Where FreeMiNT stops (MP on, pmmu8):** the last on-screen text is the FAT/VFAT 1.27 banner (docs/img/pmmu/mint_board_stop.png). The DIAG_OVERLAY build shows the CPU **halted** (double fault). The last fetch was $5CE9A, just after `pmove 12(sp),tc; rts` in MiNT's set_mmu. The last cycle was an FC5 table-search read at $BC186 (docs/img/pmmu/mint_mpon_overlay_halt.png). With MP off the CPU does not halt (a separate, open issue).

**Ruled out:**
- RTL replay of the Hatari snapshot at that exact PC (TOS ROM, wait states 0/1/3/random, IRQ sweep): no failure.
- MTREE.PRG (MiNT's exact TC and long-descriptor tree, translated with IRQs, under TOS) PASSES on the board.
- PROBE/PROBE2: every TOS call MiNT makes before this point completes on the board.

So the tree format and TC are not the cause. The failure depends on MiNT's real RAM/stack state or timing through the bridge and caches.

**Tonight's attempt:** I built pmmu (d7663f8) with DIAG_OVERLAY + DIAG_EXCWATCH as `st_helper_hdn_pmmu8exc_d7663f8.fs` (clk_cpu030 20.15 MHz, clk32_core 32.49 MHz, 45678 LUT + 5308 ALU, 19335 regs). With it flashed, the helper serial stopped answering (no `s` reply), and after a cold boot of mint_scr.st the screen showed only orange/blue stripes. Reflashing pmmu8 brought serial back once; after a second excwatch try it did not.

**Board state now — needs attention:** pmmu8 is flashed (programmer rc=0). The helper on /dev/ttyUSB1 prints its boot lines and then stops answering commands, even after waiting more than a minute. Per the rules I stopped board work: pmt5.st was **not** remounted or re-verified. Please power-cycle/replug the board, then `mount a pmt5.st`, `c`, and check PMMUTEST.TXT FAILS=0.

**Next:** find out why the DIAG_EXCWATCH build kills the helper link (likely the debug mux on the companion link, or timing; 43 endpoints failing, worst -13.7 ns, against 44 / -12.9 ns for the overlay-only build). Then capture the exception trail before the halt.

## Flash rule: no negative slack on any clock pair (27 Oct 2026, 22:50 GMT)

**Do not flash a build with negative setup or hold slack in any explicit `report_timing` clock-pair table.** That includes pmmu8exc (worst −13.7 ns) and pmmu8ovl (worst −12.9 ns).

Check with `python3 tools/timing/timing_pairs.py <impl/pnr>` (exit 1 means do not flash). The Gowin "Total Negative Slack" table showed **0** for every clock on these builds and on pmmu8, so TNS alone is not enough.

Correction: in my previous note, "43" and "44" were the logic depth of the worst path (number of nodes), not a count of failing endpoints.

**Finding:** pmmu8 itself (the build where MiNT stops, bitstream md5 ced52e19) fails `clk_cpu030 -> clk32_core` by **−7.0 ns**. The path is:

DC_OA → FILL_WADR (+1 incrementer) → ADR_OUT_I → MMU ATC lookup (XLATE/HIT_OK → BLK) → P_ASn → bridge live request → r_adr/r_dout CE.

The MMU gates AS combinationally with the ATC result, so this path exists only while **translation is on**. It is the bridge's half-cycle (31.25 ns) path. When it is too slow, the bridge can see AS low with a still-settling (logical, untranslated) address and start an ST cycle with it. That matches a failure right after `pmove tc` that RTL simulation cannot reproduce.

The plain builds before the data cache work passed this pair (pmmu_b2: +3.76 ns).

## Overnight status (27 Oct 2026, 23:35 GMT, sim only, board untouched)
- **Likely cause found (timing):** on pmmu8, clk_cpu030 -> clk32_core fails by −7.0 ns on the MMU's AS/address path. With TC.E = 1 the ATC lookup gates AS in the same clock, and the ST bridge samples it 31.25 ns later. See FALCON_LESSONS "Bridge sampled translated 030 pins…".
- **Fix (pushed, not flashed):**
  - F65: DC_OA+4 is now registered.
  - F66: with MMU_ON, the bridge takes requests only on clk_32 edges aligned to clk_cpu rising edges. The SDC gives the paths through BLK_PIN/XLATE_PIN/H_PA two clk_32 cycles.
- **Checks so far:**
  - CPU bench cmp_full old vs new: SAME on every program tried. prog_df differs only in report-line numbers.
  - Whole-ST bench prog_bus with MMU off: results and traces are byte-identical to the old bridge.
  - MMU-on bench run (`ASFLAGS="--defsym MMU=1"`): in progress.
- **Build f66 (first version):** cpu030->clk32 now passes (+4.25 ns), but clk_cpu030_n -> clk_cpu030 fails by −9.5 ns. syn_keep on HIT_OK/XLATE deepened the BLK -> DSACK core path. I moved the keeps to pin-side copies; build f66b is running.
- 23:55: the MMU-on whole-ST bench gives the same results as the old bridge (R1000/R1100/R1200 equal). Translated ST cycles start later: AS->S0 is mostly 5×31.25 ns instead of 2, and the bench runs 9.69 ms instead of 8.37 ms (about 16% slower with translation on; no change with it off).
- f66b timing: cpu030->clk32 is +3.2 ns (fixed), but clk_cpu030_n -> clk_cpu030 is −5.2 ns. That path is SLICE_CNT_N -> RMC_PIN (T_SLICE term) -> MMU WP check/TT RWM -> CIIN -> core. F67 gives the MMU/TT an RMC signal without the T_SLICE term (equal while AS is low). Build f67 is running.
