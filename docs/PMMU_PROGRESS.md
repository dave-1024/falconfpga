# PMMU progress log (branch `pmmu`)

- 27 Oct 2026 07:40 GMT: branch `pmmu` forked from main 4f9ce7d. Box clone /workspace/pmmu, base worktree /workspace/pmmu_base.
  Manual: /workspace/pmmu_ref/um.pdf (+ um.txt). linserver unreachable from the box today; builds run on the box Gowin.
- 5621114: stage 1 first cut (PMOVE TC/TT0/TT1/MMUSR, TT CI, CpID 0 user privilege).
- WIP: PMOVE CRP/SRP (quad, not with (An)+/-(An) yet); prog_pmmu.s extended; docs/PMMU_DESIGN.md draft.
- Checks: all 31 sim/rtl programs x WS 0/3 byte-identical bus logs old vs new (cmp_full.sh) on 5621114.
  prog_pmmu passes at WS 0 (full run_rtl.sh and netlist prog_bus/prog_tt in progress).
- Found: EmuTOS 1.4 (CONF_WITH_68030_PMMU=1) will now see a full 68030 and PMOVE abs.L to CRP/TC/TT0/TT1;
  that is why CRP/SRP had to be part of stage 1.
