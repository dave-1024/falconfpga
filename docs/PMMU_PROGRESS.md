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
