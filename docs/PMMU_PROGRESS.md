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
