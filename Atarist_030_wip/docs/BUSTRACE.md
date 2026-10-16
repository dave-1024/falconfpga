# DIAG_BUSTRACE: where the display-test time goes (branch `bus-trace`, 16 Oct 2026)

Debug only, default off. `build_st_helper_bt.tcl` = `build_st_helper_hdn.tcl` + `DIAG_BUSTRACE`.
Credits unchanged: the bridge follows Stephen J. Leary's TF534 (GPL-2.0); the counters only observe it.

## Block
- `hdl/cpu030/cpu030_st_bridge.v` (end of file): 128 x 32-bit counters in the clk_32 domain. They read existing
  bridge state only (request/pending, phase, arbitration, DTACK/VPA, en1/en2) and drive nothing back.
- Readout: `hdl/misc/sd_card.v` SDC cmd 9 (the SD_WRITE_DEBUG ring readout) returns the counters instead, so the
  existing helper firmware reads them with `sdwlog 64` (no helper change, no 0x600000 flash):
  line `#i BASE drv 0 old <counter 2i> -> new <counter 2i+1>`. Reading entry 0 freezes the counters, the last byte
  of entry 63 clears and restarts them. Always read all 64 (`docs/bustrace/dump.sh`), then `parse.py`.
- Counter map: comment block above `tc[]` in the bridge, and `parse.py`.
- Simulation: `docs/bustrace/run_bt.sh <wf030.vg> <dir>` (whole-ST bench with the define). Same 10101 ST cycles and
  6807734 ns as without it; the start-wait histogram equals the bench's own "030 AS -> ST S0" histogram (shifted by one).

## Build / board
- 2f2f3be p3 on linserver: clk_cpu030 20.901 MHz, clk32_core 34.912 MHz, TNS 0, recovery min 7.304 ns, removal 0.264 ns.
  `st_helper_bt_2f2f3be_p3.fs` sha256 47ac7824a5738002963ec0926d0b19862ea47ad9bdc80b46c619cadee83e1686.
  Flashed op 53 at 4193 (ends 0x04DE100), cold boot `c`: desktop.

## Results (work in progress)
- Idle (GEMBENCH window, 26.5 s): 70% of clocks no 030 request (EmuTOS idles in STOP), 0.58 M ST cycles/s.
- VDI Graphics (26.105 s, 72%, same as the unmodified build): see analysis below.

## Results (2026-10-16, trace build 2f2f3be, EmuTOS 1.4)

| Test | Time s | GEMBENCH % | ROM share of ST cycles | Prog-fetch share | Cycles vs 68000 max |
|---|---|---|---|---|---|
| VDI Graphics | 26.105 | 72 | 82% | 84% | 1.39x |
| GEM Dialog | 9.995 | 79 | 68% | 72% | 1.31x |
| GEM Window | 4.070 | 80 | 66% | 76% | 1.49x |
| Blitting (software) | 9.635 | 91 | 82% | 87% | 1.21x |
| VDI Text (control) | 14.175 | 99 | 77% | 79% | 1.05x |
| ROM Access | 5.485 | 115 | - | - | 1.03x |

Request-to-slot wait averages 0.01-0.06 clk32; 91% of starts are back-to-back (S6->S0);
0.086 wait states per cycle; no other-master/blitter cycles, no RMC. Busy% exceeds 100% after
idle subtraction because the window includes untimed GEMBENCH overhead: the bus is saturated.

## Analysis vs real STE
A 68000 at 8 MHz needs one 4-clock (500 ns) bus cycle per word fetched. The 030 issues *more*
ST cycles than a 68000 would for the same work (1.2-1.5x on the slow tests): long fetches of
ROM code split into two 16-bit ST cycles, and the prefetch queue overfetches past taken branches.
Each extra fetch costs a full 500 ns slot, so the slow tests are those dominated by ROM-resident,
branchy VDI/AES code. Slot alignment and arbitration are not the problem (<=2%).
Blitter tests could not be run: EmuTOS reports no blitter, so the blitter share is unmeasured.

## Proposed fixes (ranked by expected gain)
1. Fast ROM path / MapROM: serve ROM reads from SDRAM/BRAM at 030 speed (behind a define). VDI Graphics est. 72% -> 150%+.
2. Instruction cache (ST_030_CACHES done properly; needs Fmax margin and flush handling).
3. Stop prefetch past taken branches: 10-30% fewer fetch cycles.
4. RAM slot-alignment / wait-state tweaks: <=2%.
5. Request-to-slot latency: nothing left.
