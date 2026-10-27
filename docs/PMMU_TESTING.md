# Testing the 68030 PMMU (falconfpga)

## In short
Every PMMU feature gets three kinds of test:
- **Simulation** (`sim/rtl/prog_pmmu.s`, run by `run_rtl.sh`): fast, exact, and cycle-level.
- **Our own program on the board** (`tools/pmmutest/PMMUTEST.PRG`): checks each feature against the page of
  the Motorola manual (MC68030UM) that defines it.
- **Existing software** that uses the PMMU: shows that real programs work. A test suite made from a real 68030
  (WinUAE's cputester run on David's A1200 + ACA1233) is the best way to get exact reference values.

## 1. PMMUTEST.PRG (tools/pmmutest)
- Build it with `./build.sh` (GNU as, position-independent code, GEMDOS header with no relocations).
- Copy it to a floppy image; putting it in AUTO is easiest. Example:
  `mformat -C -i pmt.st -f 720 :: && mmd -i pmt.st ::AUTO && mcopy -i pmt.st TTRAM.PRG PMMUTEST.PRG ::AUTO/`.
  Upload it with `up2.py`, `mount a` it, then cold boot.
- Each line says PASS, FAIL, DEV (a known, documented deviation of the current stage) or SKIP, with
  "exp=" and "got=" values. The last line gives the FAILS/DEVS totals.
- The same text is written to `PMMUTEST.TXT` in the current directory (the root of A: when run from AUTO). Read it
  back by downloading the image with `get` and opening it with `mtools`.
- Stage 1 tests (manual pages):

| Test | Manual | Expected |
|---|---|---|
| TC write $7FFFFFFF, read back | 9.7.1 p9-52 | $03FFFFFF |
| TT0 / TT1 write $FFFF7FFF | 9.7.3 p9-57 | $FFFF0777 |
| MMUSR write $FFFF | 9.7.4 p9-59 | $EE47 |
| CRP / SRP write all ones | 9.7.2 p9-54 | $FFFF0003 / $FFFFFFF0 |
| Invalid TC (E=1, PS=0) | 9.7.1 p9-53 | stored with E=0 |
| ... and the exception | 9.8 p9-64 | vector 56 (DEV in stage 1: no exception yet) |
| PMOVE in user mode | 9.8 p9-65 | privilege violation, vector 8 |
| TT0/TT1 with CI over a TT-RAM loop | 9.7.3 p9-57 | loop at least 2x slower than cached |
| TT0 with an FC that never matches | 9.7.3 p9-57 | loop speed same as cached |

- On falconfpga only TT-RAM ($01xxxxxx) can be cached, because the bridge asserts CIIN for ST space. So the TT
  timing test copies its loop into a TT-RAM block from `Mxalloc(...,1)`. If there is no TT-RAM (TTRAM.PRG not
  loaded) the test prints SKIP.
- Adding later stages: write a routine `T_xxx` and add it to the `tests` table. Planned:
  - translation with a small table: map a page of TT-RAM to another, check the data, check the U and M bits;
  - ATC: 22 entries (fill 23 pages and time the 23rd), PFLUSH by FC/mask/EA, PFLUSHA;
  - PTEST levels 0..7 and the MMUSR result (B, L, S, W, I, M, T, N), PLOAD;
  - faults: invalid descriptor, write protect, supervisor only, limit; the bus error frame
    (format $A/$B) and the SSW fields;
  - timing: count 200 Hz ticks ($4BA) over 10^6 iterations, or cycle-count loops, and compare them with
    MC68030UM 11.7 (table search clocks p11-60).

## 2. Existing software that uses the 68030 PMMU
| Software | What it uses | Can run here? | Notes |
|---|---|---|---|
| **WinUAE cputester** (Toni Wilen) | Runs every opcode, including PMOVE/PTEST/PFLUSH/PLOAD, on real hardware first, saves the results, then compares on the target. Has 68030 MMU modes. | Generate the reference data on David's **A1200 + ACA1233** (a real 68030). The Amiga side needs porting: a TOS loader for the test data, and a way to keep ST hardware out of the address map. | Best source of exact values from real silicon, including cycle counts if run with cycle counting. |
| **EmuTOS 1.4** (256K/512K/1M, `CONF_WITH_68030_PMMU=1`) | At boot: detects an 030 with `PMOVE TC,abs.L`, then sets up CRP/TC/TT0/TT1 tables (identity map, cache-inhibit regions). | Yes, if an EmuTOS image is flashed (not done this session). | Simple boot check: it must boot with the PMMU registers implemented. With stage 1 only the registers are used (TC.E stored, no translation yet). |
| **FreeMiNT** (with memory protection, `mint030.prg`) | Builds full page tables and turns on TC: separate tables per process, write protection, faults and recovery. | Needs stage 2 (translation + ATC) and stage 3 (faults). | The real end-to-end test. Without memory protection (`MP=NO`) it only uses TT regs. |
| **Outside** (virtual memory for the TT/Falcon) | Paging to disk: page faults, restarting instructions, the U/M bits. | Needs stages 2-3. | A hard test of bus error frames and restarting. |
| **Linux/m68k** (Atari kernel) | Full MMU (030 tables, TT0/TT1), PTEST in fault handling. | Needs stages 2-3, plus enough RAM and a disk image. | Gold standard, but slow to boot. |
| **TOS 3.06** | Its 030 table setup (TT tables, cache inhibit for I/O). | **No: TT only** (TT video, second MFP, SCC). It will not boot on the STE+030 core. | Use it only in Hatari TT mode, as a reference for how Atari builds the tables. |
| **Hatari** (`--cpulevel 3 --mmu on`) | WinUAE CPU core with MMU. | Runs PMMUTEST on the box. Getting it to run from a floppy or GEMDOS drive with TOS 2.06 is still to be sorted out. | Gives the expected results of a reference emulator. It is not cycle exact for the table search. |

## 3. Where results go
`docs/PMMU_PROGRESS.md`, plus screenshots in `docs/img/pmmu/`.
