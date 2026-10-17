
## Checkpoint: netlist and Gowin results

- Bitstream: `st_helper_hdn_flt_f045aa9_p3.fs`
- sha256: `f47644b5f327b1f0a980fd98d7d97c0e4160f0d933422b91e9d6a78e915a27e2`
- Fmax: clk_cpu030 22.045 MHz (oa_039c710: 21.725), clk32_core 35.279 MHz (35.255), TNS 0. No constraint changes.
- Unit netlist bench (run_unit.sh): ERRORS=0, all 6 phases.
- Whole-ST bus bench (sim/st/run_bus.sh): completes at 6809234375 ps. Not compared with main: the main netlist resynth produced no .vg.
- Not flashed.

## Board test, 17 Oct 2026 (flt_f045aa9_p3): HALT, rolled back

- Flashed st_helper_hdn_flt_f045aa9_p3.fs (sha256 verified on linserver) with op 53 --fsFile at location 4193, after a cable rescan. core rc=0, reload rc=0.
- Cold boot `c`: desktop on the first grab.
- rl.sh reloads 1-10: desktop on every one. Reload 3's ssh call printed no `reload rc=`, so that reload is not confirmed, and I ran an 11th by hand.
- Reload 11: black on 5/5 grabs (~50 s). `hc.sh s` printed menu/SYS output once, then nothing. After a cold boot `c`: still black 5/5, and the helper is silent. This counts as a halt.
- Warm resets and GEMBENCH: not run.
- Rollback: reflashed st_helper_hdn_oa_039c710_p3.fs (sha f543ebe4...3ba6) the same way. Link OK, and the desktop comes up on the first grab after `c`.
- Open question: is the halt from the core or from the reload/helper path (see the helper-serial item 7)? The helper serial went silent along with the video. Before the fault-fixes build goes on the board again, oa_039c710 should get the same 11+ reload test, to see whether it also halts.
