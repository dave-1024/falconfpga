
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

## Control reload test, 17 Oct 2026: oa_039c710 (already on the board, not reflashed)

Script: rl12.sh. Cold boot `c`, then 12 reloads, with the rc of each reload confirmed (an unconfirmed reload is redone). After each round the helper is checked with `hc.sh s`.
- c0 and all 12 reloads: rc=0 on the first attempt, the desktop came up, and the helper reported `link OK` every round. No halt.
- Slow boots: on reload 6 the desktop appeared on grab 3 (2 black grabs), and on reload 7 on grab 5 (4 black grabs, ~45 s after the first grab). The desktop did come up, so neither counts as a halt.
- Comparison with flt_f045aa9 reload 11: there the board stayed black through all 5 grabs and through a cold boot, and the helper serial went silent. That hang was much harder. oa never lost the helper link.
- Conclusion: the hard halt looks build-specific, though this is not proven: it is one event in 11 reloads. Slow but recovering boots happen on oa as well.
