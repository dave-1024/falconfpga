# BUILD_REPORT 20261009-1 (F65 fast handoff, 5394948) - 9 Oct 2026

Review: PASS. Both earlier faults fixed (arm at Q_CNT = 0, re-arm CNT <= 2; one PF_CHAIN_GO drives the FSM,
queue re-arm, SIZE_N, ADR_OFFSET, DSACK_MEM, OCS_INH and includes RMC/BUS_FLT/RETRY/HALT/BR/BGACK/miss/dismiss).

RTL bench (run_rtl.sh, GHDL 6.0.0):
- FAST_HANDOFF=1: PASS, prog_loop WS=5 DONE at clk 42764 (limit 45885)
- FAST_HANDOFF=0: PASS, prog_loop WS=5 DONE at clk 44627

Build: WF030_FAST_HANDOFF + BRIDGE_EARLY_AS, place_option 3. TNS 0 on all 48 rows; recovery +5.943 ns,
removal +0.247 ns; clk_cpu030 Fmax 18.900 MHz (16 MHz).
Bitstream st_helper_f65_5394948_p3.fs SHA256 2a940d8b135de3986a5272425701505e1bf9d9a3492a773aef61fc20191f5b70

Flash: op 53, location 289 (cable scan: 289/290). Result: FAIL - cold and warm boot stop after
"-- mailbox test done, TOS continues --", no desktop after > 60 s.
Restored st_helper_eas_d43f5fd_p3.fs (cb7a9632...14eb). NOTE: the restored image also stayed on the same
screen after a reflash (60 s+), so the F65 fail is not conclusive; board/boot environment needs a power cycle
and a re-check by David before F65 is judged.

Correction 2026-10-09 21:34 (David): the no-desktop stop was an SD card fault, now corrected. The restored early-AS image failing the same way fits that. Do not treat the flash as an F65 fail.
