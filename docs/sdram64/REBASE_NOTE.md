# Before continuing: rebase onto the new main

This branch starts at d270586 (tt26rmc2 era, verified: linserver ~/sd64_wt HEAD = d270586). main is now 9fe250b
(PMMU, MiNT/XaAES fixes through F121, F110 sdram.v arbitration fix, flash_unstick). Rebase `sdram64` onto main
before more SDRAM64 work. NOT rebased yet.

Likely conflicts:
- `hdl/tang/mega138kpro/sdram.v`: main's F110 arbitration fix vs this branch's SDRAM64 / SD64_NEGCAP read path
  merge by hand and re-run hdl/cpu030/sim/st/tb_bus.v and hdl/cpu030/sim/ttram/tb_ttram.v.
- `hdl/tang/console138k/top.sv`: pll_sd instance, pll_lock/por (jtagsel fix) vs main's flash_unstick + other top changes.
- `hdl/tang/console138k/atarist_st_helper.sdc`, `build_sel.vh`, `build_st_helper_hdn.tcl` (main moved builds / added defines).
- `hdl/cpu030/*` (bridge, control, bus_interface, alu): this tree carries the older rmc patches; main has newer CPU fixes
  (F97-F121) - prefer main's CPU files and drop the rmc copies if they are already contained.
- `hdl/misterynano.sv`.

Tree notes: committed from linserver ~/sd64_wt as-is, except tb_bus.v and tb_ttram.v taken from box /workspace/sd64
(newer: non-inertial pad-clock delay `always @(clk) clk_pad <= #d clk`, plus an `+sdtrace=` SDRAM trace in tb_bus.v).
build_sel.vh is the linserver copy (has `define SDRAM64`; the box copy lacked it).
