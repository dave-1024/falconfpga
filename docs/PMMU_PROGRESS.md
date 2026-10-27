# PMMU progress log (branch `pmmu`)

- 27 Oct 2026 07:40 GMT: branch `pmmu` forked from main 4f9ce7d. Box clone /workspace/pmmu, base worktree /workspace/pmmu_base.
  Manual: /workspace/pmmu_ref/um.pdf (+ um.txt). linserver unreachable from the box today; builds run on the box Gowin.
- 5621114: stage 1 first cut (PMOVE TC/TT0/TT1/MMUSR, TT CI, CpID 0 user privilege).
- WIP: PMOVE CRP/SRP (quad, not with (An)+/-(An) yet); prog_pmmu.s extended; docs/PMMU_DESIGN.md draft.
- Checks: all 31 sim/rtl programs x WS 0/3 byte-identical bus logs old vs new (cmp_full.sh) on 5621114.
  prog_pmmu passes at WS 0 (full run_rtl.sh and netlist prog_bus/prog_tt in progress).
- Found: EmuTOS 1.4 (CONF_WITH_68030_PMMU=1) will now see a full 68030 and PMOVE abs.L to CRP/TC/TT0/TT1;
  that is why CRP/SRP had to be part of stage 1.

## 2026-10-27 (later)
- PnR of 3ad4633 (debug_builds/build_st_helper_hdn.tcl, box Gowin): all TNS 0 (timing met).
  clk32_core 35.23 MHz (32 req), clk_cpu030 21.51 MHz (16 constrained, >=17 required: OK), hdmi pix 98.9.
  Logic 48051/138240 (35%): 41065 LUT + 5066 ALU; 16340 regs (12%); CLS 45%.
  Reference tt26rmc2: clk32 35.24, cpu030 21.86, 40309 LUT -> PMMU stage 1 costs roughly +750 LUT and -0.35 MHz on cpu030.
- prog_tt.s run in the RTL tb030 (ST=1) old vs new at WS 0-3: full bus logs identical (27k-44k cycles).
  The 2-ST-cycle prog_tt netlist difference (4324 vs 4322) shows up only in the gate-level sim. RTL is identical and so is the
  prog_bus netlist, so it looks like a gate-level ordering artifact. Not proven yet: check it on the board.
- FALCON_LESSONS entry added (e7be193).
- Board not flashed: the user's computer (the board host) is offline.
- Same-script main (4f9ce7d) PnR: clk32 35.24, cpu030 21.86 MHz, 40309 LUT + 5038 ALU, 16119 regs, CLS 44%.
  pmmu 3ad4633 vs main: +756 LUT, +28 ALU, +221 regs, cpu030 -0.35 MHz, clk32 unchanged; BSRAM 171/340, DSP 10.5/298 both.
- Remaining (best guess): ~90k of 138k logic, ~38k of 69k CLS (keep ~20-25% free for routing/Fmax -> ~20-25k LUT
  usable), 169 BSRAM, ~287 DSP. Planned stage 2 (22-entry fully associative ATC + table walker) est. 3-6k LUT + ~1.5k FF.

## 2026-10-27 09:2x board test (linserver)
- Flashed pmmu1 = 3ad4633 bitstream (sha d65d7967..., cable LOC 4817). Serial '?' OK before and after.
  TOS 2.06 boots on its own (memory test 4096 KB, docs/img/pmmu/pmmu1_flash_boot.png).
- Cold boot ('c' + 'key space') with blitfix.st in A and tts.st in B: desktop OK (pmmu1_blitfix_desktop.png).
- tools/pmmutest/: PMMUTEST.PRG (WIP) for stage-1 checks, build.sh. Hatari 2.5 runs to be sorted out.

## 2026-10-27 09:45-10:25 board: PMMUTEST.PRG on pmmu1 (3ad4633)
- tools/pmmutest/PMMUTEST.PRG, run from AUTO on pmt720d.st (TTRAM.PRG first): FAILS=0, DEVS=1
  (results_board_pmmu1.txt, read back from the image; screenshot docs/img/pmmu/pmmutest_stage1_board.png).
  All register masks, the invalid TC (E cleared), and the user-mode privilege violation pass. DEV: no vector 56 yet.
- TT CI timing, with the loop in TT-RAM (Mxalloc mode 1): cached 178 ticks, TT0 CI 661, TT1 CI 661, TT0 with an
  FC that never matches 177. Note: ST-RAM is never cached on this core (bridge CIIN), so the test must use TT-RAM.
  The first runs looked like TT CI was not working; that was the manual's rule (6.1 p6-3) that a cache hit
  ignores the MMU. The test now clears the caches before each run.
- Found while reading 6.1.2 p6-8: with CIOUT asserted the data cache must also ignore writes (even
  write-allocate). Fixed in wf68k30L_top.vhd (DC_WR_GO gated by a TT CI match on the write address),
  with a prog_pmmu case: a stale hit gives $1111 after a TT CI write of $2222, and $2222 after CD (e68e21f).
  Not on the board yet (needs a rebuild).
- Benchmarks: per David, run only at the end of a stage. FrontBench was started once and then skipped into
  the game by an extra click (my mistake, not a core fault). GEMBENCH not run.
- EmuTOS PMOVE check not done: it needs an EmuTOS ROM flashed at 0x500000, which this test did not include.
- prog_tt 2-ST-cycle netlist difference: can't be seen on the board (125 ns at a BERR); the board behaves
  normally. Still listed as open.
- Full run_rtl.sh on e68e21f (data cache write fix): PASS, including PMMU stage 1 and the new p6-8 case.
  Next: rebuild (pmmu2), check old-vs-new bus logs, board test, then stage 2 (ATC and table walker).

## 2026-10-27: pmmu2 build, board test, EmuTOS, stage 2a/2b

- **pmmu2** (68acd88, TT CI write fix): 41008 LUT / 5065 ALU / 16350 regs, BSRAM 171/340, DSP 10.5/298.
  clk32_core 33.68 MHz (32 req.), clk_cpu030 24.31 MHz (16 req.), TNS 0. Bitstream sha 62c90a56,
  `~/fpga_bitstreams/st_helper_hdn_pmmu2.fs` on linserver.
- Board (TOS 2.06): PMMUTEST FAILS=0 DEVS=1 (DEV = vector 56, not in pmmu2), loop ticks cached 178,
  TT0 CI 661, TT1 CI 661, FC no-match 177 (`docs/img/pmmu/pmmu2_pmmutest.png`).
- **EmuTOS 1.4** (`etos256uk.bin`, via `~/flash_tos_rom.sh`, op 56 at 0x500000) on pmmu2: boot screen shows
  CPU M68030, ST-RAM 4 MB, Alt-RAM 16 MB; no Line-F/exception during its CPU/MMU detection (PMOVE TC/TTx),
  desktop reached (`pmmu2_emutos14_boot.png`, `pmmu2_emutos14_desktop.png`).
- **TOS in flash now: EmuTOS 1.4** (TOS 2.06 backup: `~/fpga_bitstreams/tos206_backup.bin`).
- Stage 2a (MMU configuration exception, vector 56, format $2, 8.1.10 / p9-64): full `run_rtl.sh` PASS;
  61 old programs cycle-identical vs the previous bench.
- Stage 2b: `hdl/cpu030/wf68k30L_mmu.vhd` (22-entry ATC, NRU replacement, table walker FC=5 / RMC locked,
  U/M updates p9-26.., limits, early termination, indirect, WP/S checks, BERR on B-hit) compiles in GHDL;
  not wired into top yet. Next: integration + sim tests, then PFLUSH/PLOAD/PTEST.

## 2026-10-27 11:00-: stage 2b integration (box)
- 3b05d0e: `wf68k30L_mmu.vhd` wired between the bus interface and the pins (top). With TC.E = 0 it is a wire.
  Fixes found in sim: a cycle already on the pins keeps its translation until AS negates (TC enable in the middle of a
  prefetch broke WS >= 3 runs); an ATC entry made by a write's search is marked modified (root-pointer page loop).
- New sim `prog_xlate.s` (WS 0/1/3/7/random, CIMODE 0/1): two-level short tree with early termination, remapped page,
  U/M written back, ATC hit after a table change, PMOVE flush vs PMOVEFD, invalid and WP bus errors with fault
  addresses, 40-page ATC replacement. Stage-1 programs load an identity CRP before their short TC E=1 window.
- 10e493e: PFLUSHA / PFLUSH FC,#MASK[,<ea>] / PLOADR/W / PTEST levels 0-7 (A = 0), MMUSR per Table 9-3. Decoded as an
  F-line LEA (EA computed, no operand access), EA + extension word go to the MMU at writeback; the next instruction
  waits until the MMU is done. New sim `prog_pmop.s`.
- Known deviations: RTE does not rerun a faulted write (DF); PTEST A bit and the Dn FC form take F-line; no 11.7
  clock padding for the MMU instructions or the table search yet (stage 3).
- PMMUTEST.PRG: new T_xlate (identity map of 4 GB with early-termination pages, page A -> B, U/M, PTEST #7, PFLUSHA,
  invalid -> bus error). Hatari 2.5 on the box still double-faults at boot with EmuTOS 256k in STE + 030 MMU mode, so
  the new tests are checked on the board only.
- Regression on 10e493e: full `run_rtl.sh` PASS (incl. prog_xlate, prog_pmop). cmp_full old (cbc2dd6) vs new, all prog_*.s,
  WS 0 and 3, CIMODE 1: 62 runs SAME; only the PMMU programs differ (prog_pmmu, prog_mmucfg, prog_xlate, prog_pmop:
  they turn translation on or use the new instructions). prog_fpbr skipped (needs ASFLAGS).
- **pmmu3** (10e493e, box Gowin, debug_builds/build_st_helper_hdn.tcl): TNS 0 on every clock. clk_cpu030 21.41 MHz,
  clk32_core 32.24 MHz (32 req., little margin). Logic 52074/138240 (38%): 44822 LUT + 5332 ALU; 18174 regs (14%);
  CLS 50%; BSRAM 171/340; DSP 10.5/298; PLL 4/12. vs pmmu2: about +3.8k LUT, +1.8k regs, cpu030 -2.9 MHz.
  Bitstream sha db91c2ff, linserver `~/fpga_bitstreams/st_helper_hdn_pmmu3.fs`.
- Board: flashed pmmu3 (cable LOC 4817), serial OK before and after, boots to the EmuTOS 1.4 desktop
  (pmmu3_boot.png). PMMUTEST stage 2b image pmt3.st uploading.
- PMMUTEST on pmmu3 (EmuTOS 1.4, AUTO on pmt3.st): it **does run from AUTO under EmuTOS**. Stage 1 all PASS, vector 56
  now PASS (no DEV). First run: xlate SKIP (no Mshrink, so no free ST-RAM; fixed). Second run: translation works on
  the board (write through page A lands in page B, U+M set, PFLUSHA + PTEST #0 gives I, invalid page -> bus error),
  but 2 FAILs: d5/d4 overwritten by the PTEST EA ($00029000), a core bug (see FALCON_LESSONS). Fixed in 2951ec9;
  pmmu4 build running. Screenshots `pmmu3_pmmutest.png`, `pmmu3_pmmutest2.png` (in /workspace/pmmu_out/shots).
- 2951ec9: full run_rtl.sh PASS; cmp_full 62 SAME (only PMMU programs differ). **pmmu4** build: TNS 0, clk_cpu030 21.99 MHz,
  clk32_core 33.11 MHz, 44823 LUT + 5328 ALU (logic 52071, 38%), 18174 regs, CLS 50%, BSRAM 171/340, DSP 10.5/298.
  sha 8ff8f360, linserver `~/fpga_bitstreams/st_helper_hdn_pmmu4.fs`. (One Gowin run failed on "License verification
  failed, server not responding"; the rerun was fine.)
- pmmu4 flashed (LOC 4817, rc 0), serial OK before/after, desktop (pmmu4_boot.png).
- PMMUTEST stage 2b on pmmu4 (EmuTOS 1.4, AUTO): **FAILS=0 DEVS=0**, all stage 1 and stage 2b tests pass:
  page A -> B translation, write to physical B, U+M set, PTEST #7 = $0202, PFLUSHA + PTEST #0 = I, invalid -> bus error
  (`docs/img/pmmu/pmmu4_pmmutest.png`). Loop ticks: cached 178, TT0/TT1 CI 661, FC no-match 178.
- Board left on pmmu4, EmuTOS 1.4 in flash, pmt3.st in drive A (not saved to atarist.ini).
- Not done yet: GEMBENCH/FrontBench (at the end of stage 2), long-format/indirect/S/SRE/limit sim programs, PTEST An,
  Dn FC form, RTE write rerun, 11.7 clocks (stage 3).

## Stage 2c (27 Oct 2026, GMT)
- 71472d5 + 6560e85: full run_rtl.sh PASS (prog_xlate2: long tables, limits, long indirect, S page, SRE). cmp_full 62 SAME,
  only PMMU programs differ.
- **pmmu5** (71472d5): TNS 0 on every clock. clk_cpu030 21.60 MHz, clk32_core 35.79 MHz. Logic 52076/138240 (38%):
  44827 LUT + 5329 ALU; 18174 regs; CLS 49%; BSRAM 171/340; DSP 10.5/298. sha 01aa01e4, linserver
  `~/fpga_bitstreams/st_helper_hdn_pmmu5.fs`.
- Flashed pmmu5 (LOC 4817, rc 0), serial OK before/after. PMMUTEST stage 2 (pmt4.st, EmuTOS 1.4): **FAILS=0 DEVS=0**
  incl. long+indirect A->B, PTEST user FC on S page ($2002), PTEST limit ($4401), indirect N=3, limit -> bus error
  (`docs/img/pmmu/pmmu5_pmmutest.png`).
- FrontBench flags 7 (tts.st, EmuTOS 1.4, TT-RAM, caches on, 920 s): **1382 lastcount, 213 frames** (baseline 1375)
  (`docs/img/pmmu/pmmu5_frontbench.png`).
- GEMBENCH: flashed TOS 2.06 (tos206_backup.bin) + pmmu5 core (LOC 4817, rc 0). Booted to the 2.06 desktop; GB608 refused low
  res. While switching to medium in Options > Set Preferences the desktop stopped taking clicks (pointer still moves, OK/Cancel
  and the buttons ignored; `pmmu5_tos206_prefs_hang.png`). Not yet known if this is the core or the helper's click
  injection. Per the board rules no cold boot: fell back to pmmu2 at once.
- Fallback to pmmu2 (sha 62c90a56, LOC 4817, rc 0, ALLDONE) with TOS 2.06 in flash: the helper serial never answered (echo only)
  and HDMI showed no picture, even after a usbreset of the capture. So **pmmu2 is not a safe fallback with TOS 2.06 in flash**.
- Reflashed pmmu5 (LOC 4817, rc 0): serial OK, TOS 2.06 desktop (`pmmu5_tos206_desktop.png`). Board left there.
- GEMBENCH not run: the Set Preferences stall on pmmu5 is still open (it may be the core, or the helper's click injection).

## Stage 3 (pmmu6, 456ef73 + pmmutest 7f215ac)

- Done: FC operand in Dn (p. 9-64), PTEST A=1 (p. 9-63), short indirect DT 2 sim (prog_xlate3; fixed indirect address bit 2 being read as WP), RTE rerun of a faulted write from a format $A frame (DF, p. 8-12; prog_df). Format $B frames still restart.
- run_rtl.sh: PASS (all steps incl. short indirect and write rerun). cmpall: non-PMMU programs cycle-identical except prog_frame (3538 -> 3547 clk at WS0) — deliberate: RTE of a $A frame now reads the SSW.
- Timing: TNS 0, clk_cpu030 20.84 MHz, clk32_core 32.08 MHz (thin). Logic 52199 (38%): 44958 LUT + 5321 ALU, 18275 regs, BSRAM 171/340.
- Board (TOS 2.06 in flash): PMMUTEST stage 3 FAILS=0 DEVS=0, all T_s3 cases PASS (img/pmmu/pmmu6_pmmutest.png).
- Pending: 11.7 clock padding for MMU instructions / table search (table-search formula not yet sourced).
