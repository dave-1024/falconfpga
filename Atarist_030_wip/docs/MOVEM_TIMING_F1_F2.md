# MOVEM timing: F1 priority encoder, F2 read-ahead (branch f1-movem-timing)

Goal: GEMBENCH 6.x RAM/ROM Access (back-to-back `MOVEM.L` loops) closer to a 68000 STE, with 68030 behaviour.
Analysis: `gb608_ramrom_analysis` (lab notes): our core left the ST bus idle between MOVEM transfers. RAM catches its
ST slot only when the next cycle starts back to back (GAP 1); ROM pays for every idle clock.

## F1: register-list priority encoder (control unit)
Before: MOVEM walked all 16 list positions, one clock each, including unused ones. A real 68030 costs 8+4n:
only the listed registers. Now `MOVEM_NXT`/`MOVEM_1ST` (priority loops on BIW_1 above/at the index) jump straight
to the next set bit, and `MOVEM_END` (no bit above the index) ends the instruction.
- `-(An)` with one register: the old last-write test (`MOVEM_LAST_WR`) came one clock late with the encoder and
  decremented An twice (found by prog_movemw, fixed with `MOVEM_END` before commit).
- New coverage: `sim/rtl/gen_movemx.py` -> `prog_movemx.s` (2154 cases: empty/full/single/pattern/random masks,
  .W/.L, all R->M and M->R modes, every register as base with -(An)/(An)+, bus error mid-MOVEM on reads, on writes
  crossing $10000, and on reads crossing $10000; the handler records the frame).
- Fmax: clk_cpu030 21.36 MHz (was 22.79), clk32_core 35.80 MHz (was 33.78). TNS none; timing closed.

## F2: MOVEM memory-to-register read-ahead (bus interface)
An A3-style overlap specialised to MOVEM M->R, keeping the one-request bus protocol.
- At S5 of a MOVEM read with more list registers to come (`MOVEM_RA` from the control unit), the bus interface rolls
  into the read of ADR_LATCH+size with the same FC (`RA_GO`, a chain like PF/OP/DP_CHAIN; `RA_LD` steps ADR_LATCH).
- The data or the bus error is handed over only to the matching control request (`RA_MATCH` / held `RA_HELD`
  then `RA_TAKE`). A non-matching request drops it (`RA_DROP`, sim assertion; never seen in any bench).
- Only for cache-inhibited cycles or with the D cache off (`DC_ON='0' or CIIN_LAT='0'`): GEMBENCH runs with
  CACR D=ON, and every ST bus cycle is CIIN, so the read-ahead stays active on the ST.
- While a read-ahead is held, posted-write/op chains and the D-cache hit path wait (no reordering).
- Bus error on a read-ahead: delivered as DATA_VALID=0 on the request, same frame as before (SSW, fault address,
  FC from the latched cycle). The DIB (frame $2C) is frozen from the clock after the faulted read-ahead until
  BUSY_EXH: the prefetches that used to run before the faulted read now run after it and would otherwise land in
  the DIB.
- Remaining frame differences vs ff6af03 (prog_movemx, read faults only): the DIB high word on a .W read (bytes
  not part of the faulted access, left over from an earlier cycle) and the DOB (frame $18, last write data) of a
  read fault. Both are left-over buffer contents, not defined by the 68030 for a read fault, and only change
  because the cycles before the fault come in a different order. All handler-visible fields (SR, PC, format/
  vector, SSW, fault address) and all register/memory results are identical (FILT=5000 SAME).

## F3 (operand-to-operand writes back to back): deferred
MOVEM R->M writes still have a 3-clock register gap (WRITE_DEST WR_RDY -> EXECUTE -> WRITE_DEST). A pure bus chain
can't help: no write request is pending at S5. Gap 1 needs the control unit to present the next write before S5
(a write queue or early posting), which breaks the synchronous write-fault model (WR_FLT = WR_RDY with
DATA_VALID=0). See TODO.md.

## Results (board, 18 Oct 2026; times in s, ratio GEMBENCH convention ref/ours)
| build | Fmax cpu030 / clk32 (MHz) | LUT | 6.08 RAM vs STE20608 | ROM | CPU | Display | Average | 4.03 Average |
|---|---|---|---|---|---|---|---|---|
| dc_ff6af03 (main) | 22.79 / 33.78 | 37,662 | 51.135 71% | 102.580 73% | 147% | 46% | 82% | 133% |
| f1_d696318 | 21.36 / 35.80 | 37,916 | 47.430 76% | 95.215 78% | 154% | 45% | 83% | 133% |
| f2_c4de2ec | 22.33 / 32.44 | 38,034 | 39.685 91% | 71.570 104% | 180% | 46% | 91% | 134% |

vs STFM1048 (ST 68000, no blitter): F1 Display 92 / CPU 154 / Average 119; F2 93 / 180 / 129 (RAM 91%, ROM 104%).
Screenshots (box): /workspace/gembench608_<build>.png and ..._vs_STFM1048.png.

Commits: the board builds were made from local commits d696318 (F1) and c4de2ec (F1+F2). They were pushed to
GitHub as ab1f3ec (HDL) + 890fbea (sim) with the identical tree (`git diff c4de2ec 890fbea` is empty).
Board build `st_helper_hdn_f2_c4de2ec_p3.fs`, sha256 f7d2672c0cd87ee585b1fe9a086436c914d1d70b98979c394a429b3cf7a796fb.
F1 build `st_helper_hdn_f1_d696318_p3.fs`, sha256 2c8154c197b0d31a08f0db46c8140d8fb9925b3c8cd4d1e98c0c0e2c00a64d2b.
