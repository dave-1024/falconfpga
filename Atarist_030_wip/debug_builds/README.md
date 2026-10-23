# debug_builds/

Current, still-useful build variants. The main build is `../build_st_helper.tcl`.
Retired scripts are in `../build_legacy/`.

Every script here `cd`s to `Atarist_030_wip/` itself, so run it from there:

    gw_sh debug_builds/<name>.tcl

| script | what it is for |
|---|---|
| `build_st_helper_hdn.tcl` | Main build + `SD_WRITE_DEBUG` (SD request ring), `place_option 3`. The board/release builds tt20-tt26 were made with it. |
| `build_st_68000.tcl` | Same ST + helper image with the original fx68k 68000 (`ST_CPU_68000`), STE chipset: reference for 030 comparisons. |
| `build_st_68000_st.tcl` | As above with the plain ST chipset (no `ST_STE`). |
| `build_tc138k.tcl` | Old desktop image without the AE350 helper (BL616 MCU). Writes `// desktop` into `build_sel.vh`. |
