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
