# MOVEM timing: F1 priority encoder, F2 read-ahead (merged on main 18 Oct 2026), F3 writes back to back

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

Rollback order on the board: F3a `st_helper_hdn_f3a_7919eb3_p3.fs` (SHA256
56556195a0eedbee3a4a23b2978d05bbfe7a16ad41cbe6a46dd79168e211d78e), then F2 `st_helper_hdn_f2_c4de2ec_p3.fs`, then
`st_helper_hdn_dc_ff6af03_p3.fs` (SHA256 c9a160b6c34df3c28a97826b73198999a57cbe03be9961f8217cdbae1d41c39e).

## GEMBENCH 6.08 per test (gb608.st, ST Medium, All Tests; time in s, ratio ref/ours)
| Test | dc_ff6af03 (vs STE20608) | F1 d696318 (STE20608 / STFM1048) | F2 c4de2ec (STE20608 / STFM1048) | F3a 7919eb3 (STE20608 / STFM1048) |
|---|---|---|---|---|
| GEM Dialog Box | 24.490 (54%) | 24.385 (53 / 88%) | 24.025 (54 / 89%) | 23.815 (55 / 90%) |
| VDI Text | 33.195 (44%) | 33.125 (44 / 100%) | 32.875 (44 / 100%) | 32.735 (44 / 101%) |
| VDI Text Effects | 43.230 (50%) | 42.815 (50 / 96%) | 42.400 (50 / 97%) | 41.970 (51 / 98%) |
| VDI Small Text | 46.640 (48%) | 46.550 (48 / 98%) | 46.140 (49 / 99%) | 45.910 (49 / 100%) |
| VDI Graphics | 43.415 (64%) | 43.365 (64 / 70%) | 43.180 (64 / 70%) | 43.060 (64 / 70%) |
| GEM Window | 21.215 (47%) | 21.215 (47 / 90%) | 20.395 (49 / 94%) | 20.395 (49 / 94%) |
| Integer Division | 5.135 (613%) | 5.135 (612 / 612%) | 5.135 (612 / 612%) | 5.135 (612 / 612%) |
| RAM Access | 51.135 (71%) | 47.430 (76 / 76%) | 39.685 (91 / 91%) | 35.775 (101 / 101%) |
| ROM Access | 102.580 (73%) | 95.215 (78 / 78%) | 71.570 (104 / 104%) | 71.570 (104 / 104%) |
| Blitting | 22.705 (16%) | 22.700 (15 / 90%) | 22.685 (15 / 90%) | 22.675 (15 / 90%) |
| VDI Scroll | 27.260 (35%) | 27.235 (35 / 97%) | 27.115 (35 / 97%) | 27.045 (35 / 97%) |
| Justified Text | 26.590 (44%) | 26.545 (43 / 99%) | 26.365 (44 / 100%) | 26.265 (44 / 100%) |
| VDI Enquire | 21.155 (98%) | 21.005 (98 / 98%) | 20.625 (100 / 100%) | 20.450 (101 / 101%) |
| Display / CPU / Average | 46 / 147 / 82 | 45 / 154 / 83 and 92 / 154 / 119 | 46 / 180 / 91 and 93 / 180 / 129 | 46 / 186 / 92 and 94 / 186 / 132 |

Float Math and ALT RAM are not run (no FPU, no fast RAM).

Reference machines: STE20608 = Atari STE, 68000 at 8 MHz on the 16-bit ST bus, TOS 2.06, blitter enabled.
STFM1048 = Atari ST(FM), 68000 at 8 MHz on the 16-bit ST bus, TOS 1.04, no blitter. Ours: 68030 core at 16 MHz on the
same 8 MHz 16-bit ST bus, TOS 2.06, caches on (nothing cachable). Other 6.08 sets compared earlier (gb608_compare,
from the set names; their panels were not re-read): PAK030 (PAK68/3 68030 card in an ST), TTNOCACH and TT16MED
(TT030, 68030 at 32 MHz; caches off / ST Medium), FALCON30 (Falcon030, 68030 at 16 MHz, 16-bit bus), MSTEB16 /
MSTEB16C (Mega STE, 68000 at 16 MHz, without / with its cache).

**Blitter finding:** GEMBENCH 6 shows "BLiTTER NP" for our system. Against the blitter STE the Display group is 46%
(Blitting 15%); against the blitter-less STFM1048 it is 93% (Blitting 90%). The Display gap to STE20608 is mostly the
blitter, not the CPU (TODO.md status). RAM/ROM are the same against both sets: both are 68000s at 8 MHz on the ST bus.

## F3: MOVEM register-to-memory writes back to back (18 Oct 2026, branch f3-write-queue)
Measured on F2 (p608w loop, `movem.l` of 13 registers to -(An), WS5, VCD): within a long the two word portions are
back to back, between registers AS stays high for 2 clocks (GAP 3): DATA_RDY of the last portion (S4/S5 clock) ->
the control unit loads the next register (ALU_INIT) -> EXECUTE -> WRITE_DEST, request from IDLE (PW_GO). RAM misses
its ST slot on every register.

The 68030 sequencer has the next MOVEM operand ready while the current one is on the bus. In our bus interface a
posted write's outcome is final in the S3 clock of its last portion: `WP_GO` (DSACK seen, no BERR, no retry, no
halt) is what already raises the posted DATA_RDY one clock later. F3 uses that clock:
- control: `F3_EARLY` = WP_GO (`WR_EARLY`) while EXEC_WB is in WRITE_DEST for MOVEM register-to-memory, FETCH is in
  INIT_EXEC_WB with a further register (MOVEM_COND), no write fault pending. It releases `ALU_BSY_M` and acknowledges
  the ALU, so the next register is loaded (ALU_INIT, the -(An) step, list pointer, offset) exactly as at DATA_RDY,
  one clock earlier, and only when nothing can undo it. EXEC_WB stays in WRITE_DEST for the next register.
- bus interface: `WR_TAKE` suppresses that write's DATA_RDY (the control unit already consumed it); `WW_GO` rolls the
  S5 edge of the write into the next write (OP_WR live, same start actions as OP_CHAIN/PW_GO: WP_BUFFER, SSW, size,
  address latch), under the hold conditions of every other chain. A waiting prefetch (DP_CHAIN) yields to it.
- data/address: in the S4/S5 clock the ALU result register still holds the previous register, so `DATA_FROM_CORE`
  takes the freshly loaded operand (`RESULT_MV`, the ALU's combinational MOVEM path) for that one clock (`F3_BYP`);
  `ADR_FAST` loads ADR_WB in the take clock instead of after the one-clock calculation delay (ADR_EFF_I already holds
  the next address there in all MOVEM modes).
- faults: nothing is set up before the running write is final, so a bus error can only hit the next write, which
  is handled as before (WR_FLT = WR_RDY and DATA_VALID=0). No queue, no undo. If the chain conditions fail at S5
  (arbitration, halt, retry) the write starts from IDLE as before.

Sim (old = F2 tree): run_rtl PASS. p608w WS5: all register gaps GAP 1 (were GAP 3). 13-program compare at WS 0/1/3/7:
identical except frame $2C (DIB, sampled bus, undefined for write faults) and $0E (stage B, a stale BIW_2 that
moves with prefetch timing; separate item in TODO.md); FILT=5000 (everything the handlers record, register dumps)
identical for prog_fault, prog_wpberr, prog_movemx at all wait states. prog_movemx -9.5% clocks.

Board (f3a_7919eb3): Fmax clk_cpu030 20.94 MHz (38 levels; F2 22.33), clk32_core 34.02 MHz, TNS 0; LUT 37,870,
regs 15,663. Two cold boots clean. 6.08 RAM 39.685 -> 35.775 s (91 -> 101%), CPU 180 -> 186%, Average 91 -> 92%
(STE20608), 129 -> 132% (STFM1048); ROM unchanged (reads). 4.03 134 -> 135%.
Commits: board build from local 7919eb3; on GitHub b33c140 + 304b885 (same HDL; the connector re-encoded two
comment lines and the ALU file's line ends).
