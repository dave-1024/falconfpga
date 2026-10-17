
## Checkpoint: netlist and Gowin results

- Bitstream: `st_helper_hdn_flt_f045aa9_p3.fs`
- sha256: `f47644b5f327b1f0a980fd98d7d97c0e4160f0d933422b91e9d6a78e915a27e2`
- Fmax: clk_cpu030 22.045 MHz (oa_039c710: 21.725), clk32_core 35.279 MHz (35.255), TNS 0. No constraint changes.
- Unit netlist bench (run_unit.sh): ERRORS=0, all 6 phases.
- Whole-ST bus bench (sim/st/run_bus.sh): completes at 6809234375 ps. Not compared with main: the main netlist resynth produced no .vg.
- Not flashed.
