# Gowin timing reports: F97 interlock builds (black screen) vs f97fw (boots)

Copied as they are from linserver `~/ovn_pnr_<build>/` (the copy of `impl/pnr` saved after each build) and `~/<build>_build.out`, `~/ovn_build_gw_<build>.log`.
All six were built on 29 Oct 2026 from the `~/wf97` tree with `Atarist_030_wip/build_st_helper.tcl` (Gowin, same tcl and SDC). Times are UTC, which is the same as UK time now.

Files in each folder:
- `st_helper_tr_content.html`: the Gowin timing report (max-frequency summary and the explicit report_timing tables from `atarist_st_helper.sdc`)
- `st_helper.timing_paths`: the Gowin path dump (95 paths, node-by-node delays)
- `timing_pairs_output.txt`: `tools/timing/timing_pairs.py` run on that report today (exit 0 = pass for all six)
- `ovn_build_gw_*.log`: the full gw_sh synthesis + PnR log; `*_build.out` is the build wrapper output with start and end times

| Folder | What it is | Commit / tree | Built (UTC) | clk_cpu030 Fmax | clk32_core Fmax | Board |
|---|---|---|---|---|---|---|
| f97n | first F97 interlock in `wf68k30L_control.vhd` FETCH_EXWORD_1 (Dn+An wait, exits on EW_RDY), F94 reverted | the tree that became 0356787 | 14:46–14:59 | 19.900 | 34.896 | **black HDMI** |
| f97p1 | same source as f97n, place_option 1 | same as f97n | 15:19–15:31 | 17.974 | 32.924 | **black** |
| f97B | bisect: wait on the Dn index only (no AR_IN_USE term) | local wf97, not committed | 15:38–15:51 | 21.557 | 33.879 | **black** |
| f97C | control: the same wf97 tree with the original (f93n) control.vhd | local, not committed | 15:54–16:06 | 19.376 | 32.145 | **EmuTOS desktop** |
| f97fx | interlock v2: registered FX_WAIT flag, no EW_RDY exits | local, not committed (reverted by d3ec40d) | 16:15–16:27 | 20.660 | 33.914 | **black** |
| f97fw | forwarding fix (no control.vhd change) | 8c55cb0 | 16:57–17:10 | 20.123 | 32.015 | **EmuTOS desktop, MiNT reaches XaAES** |

Fmax values are read from each report's Max Frequency Summary (constraint 16 MHz for clk_cpu030, 32 MHz for clk32_core).

Missing: the very first F97 build that still had F94 in it (about 14:50, 20.09 MHz / 45,344 LUT in the log) and the F94-only build (22b6c04) have no saved report. `~/ovn_pnr_f97` was overwritten by the f97n run. The f94 log (`~/ovn_build_gw_f94.log`) still exists but has no pnr copy, so it isn't included here.

`paths_excerpt.md` (one level up) lists, for each build, the paths in `st_helper.timing_paths` that pass through FETCH_STATE / NEXT_FETCH_STATE / EW_ACK / DR_IN_USE / STORE_ADR_FORMAT. Caveat: the dump only holds the worst paths per clock pair from the SDC's report_timing commands. Every slack in it is positive, so it shows which paths are near the top, not a failing path. Gowin also renames combinational logic (e.g. `NEXT_FETCH_STATE_16_s7` is a LUT that came from that signal), so a path through logic that was renamed beyond recognition won't be matched.
