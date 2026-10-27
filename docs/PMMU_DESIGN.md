# 68030 PMMU design (branch `pmmu`)

## In plain words

A real 68030 has a memory manager built in, the PMMU. It can do three jobs:

1. **Move memory around.** A program sees an address, and the PMMU turns it into a different real address using
   tables in RAM. FreeMiNT uses this to give every program its own protected memory.
2. **Protect memory.** It can stop a program writing somewhere it shouldn't, or stop a user program touching
   system memory. When that happens the CPU gets a "bus error" and the operating system decides what to do.
3. **Say what may be cached.** It can mark areas such as hardware registers as "never cache". TOS 3 and 4 on the TT
   and Falcon, and EmuTOS on any full 68030, set this up as soon as they start.

Until now our CPU core had none of this. Every PMMU instruction jumped to the "unknown instruction" handler, so
software thought it was running on a cheaper 68EC030 that has no PMMU.

We are adding the PMMU in stages, following Motorola's MC68030 User's Manual as the specification, so that it
behaves, and takes the same number of clock cycles, as a real chip as far as we can manage:

- **Stage 1 (done on this branch):** the PMMU's registers, the PMOVE instruction that reads and writes them, and
  the two "transparent" windows (TT0, TT1), which can already mark areas as "never cache". Addresses are not
  changed yet.
- **Stage 2:** the address translation cache (22 entries) and the table walker that reads the tables in RAM.
  From here on, addresses really are translated.
- **Stage 3:** the remaining instructions (PTEST, PLOAD, PFLUSH), PMMU bus errors with the right stack frames,
  the MMU configuration exception, and exact clock counts.

Main stays a known-good build. Nothing here goes into main until it has passed simulation, timing and the board.

What changes for software already with stage 1: TOS 2.06 never uses the PMMU, so it is unaffected. EmuTOS now
detects a full 68030 instead of a 68EC030 and builds its PMMU tables (they map every address to itself, so they
work even before stage 2 translates anything). TTRAM.PRG, BLITFIX, HDDriver and FrontBench do not use PMOVE.

---

## Technical detail

Spec: MC68030UM/AD, *MC68030 Enhanced 32-Bit Microprocessor User's Manual*, 3rd edition (Motorola 1990), downloaded
from bitsavers (`components/motorola/68000/68030/MC68030_Users_Manual_3ed_1990.pdf`). Page numbers below are the
manual's printed page labels (section-page). Box copy: `/workspace/pmmu_ref/um.pdf`, text `/workspace/pmmu_ref/um.txt`.
The PMOVE/PFLUSH/PLOAD/PTEST instruction encodings were cross-checked against GNU as (`-m68030`) and against the
encodings EmuTOS 1.4 hard-codes (`include/asmdefs.h`).

### What software needs

| Software | What it does with the MMU | Needs stage |
|---|---|---|
| TOS 2.06 (main build) | Nothing (no PMOVE in the ROM) | none |
| EmuTOS 1.4 (fallback) | `processor.S`: PMOVE TC,(abs.L) to tell 68030 from 68EC030. `startup.S`: PMOVE (A0),TT0/TT1/TC with zero. With CONF_WITH_68030_PMMU (default 1 in 256K/512K/1M ROMs): builds an identity tree, PMOVE abs.L to CRP, TC, TT0, TT1, then CACR $3919 | 1 (registers); 2 for the tree's CI bits to take effect |
| TOS 3.0x / 4.0x (TT, Falcon) | Sets CRP/TC/TT0/TT1 at boot, early-termination descriptors, I/O cache-inhibited | 2 |
| FreeMiNT with memory protection | Per-process trees (CRP switch with FD=0 on context switch), PFLUSH, PTEST in the bus error handler, page faults with RTE restart | 3 |
| Falcon DSP / later Falcon core | Same as TOS 4 plus cycle-exact bus timing of table walks | 2, 3 |

### Real 68030 behaviour (the spec)

- **Registers** (9.7, pp. 9-52 to 9-60): CRP and SRP 64-bit (Figure 9-35: L/U, 15-bit LIMIT, DT in the upper long;
  table address A31-A4 in the lower; bits 3-0 ignored). TC 32-bit (Figure 9-36: E, SRE, FCL, PS, IS, TIA-TID;
  unimplemented bits read 0). TT0/TT1 32-bit (Figure 9-37: base A31-A24, mask, E, CI, R/W, RWM, FC base, FC mask).
  MMUSR 16-bit (Figure 9-38: B L S W I M T N). Transfers: CRP/SRP quad, TC/TTx long, MMUSR word (2.x, p. 2-5).
- **Reset** (9.2.2, p. 9-15): clears E in TC, TT0, TT1; does not flush the ATC.
- **TC consistency** (9.7.2 p. 9-54, 9.7.5.3 p. 9-62): with E=1, PS + IS + TIA.. up to the first zero TIx must be
  32, and PS must not be 0-7; otherwise the register is loaded, E is cleared, and an MMU configuration exception
  (vector 56, offset $E0, 8.1.10 p. 8-21, Table 8-1 p. 8-3) is taken after the instruction. CRP/SRP loaded with DT=0
  load the value and also take it.
- **Transparent translation** (9.3, pp. 9-16/9-17): FC and A31-A24 compared against base/mask; R/W must match unless
  RWM; RMW (RMC) cycles only match with RWM=1; a match is used untranslated with no protection check; CI of
  either matching register asserts CIOUT, which also inhibits the on-chip caches. Independent of TC.E and MMUDIS.
- **ATC** (9.4, pp. 9-17 to 9-20): 22 entries, fully associative, tag = V + FC + 24 address bits (fewer compared for
  bigger pages), data = B, CI, WP, M + 24 physical bits. Replacement: invalid entry first, else pseudo-LRU with a
  history bit. Flushed by PMOVE (FD=0) to CRP/SRP/TC/TT0/TT1, PFLUSHA, PFLUSH, PLOAD of the same address. ATC search
  is fully overlapped (no clocks). A write to an entry with M=0 aborts, walks again to set M, and retries.
- **Descriptors** (9.5.1, pp. 9-20 to 9-28): short (4-byte) and long (8-byte) table, page, early-termination page,
  invalid and indirect descriptors; U set on every descriptor visited; M set in the page descriptor for writes
  unless WP or a supervisor violation was met; S and limit fields only in long format.
- **Table search** (9.5.2 / 9.5.4, pp. 9-28 to 9-43, Figures 9-19, 9-25 to 9-29): root pointer by FC2 and SRE
  (Table 9-2, p. 9-29); optional FC level (FCL); levels A-D by TIA-TID; physical addresses; RMC asserted for the
  whole search so U/M updates are locked read-modify-write; ends with page, invalid, limit violation or bus error.
  Failed searches create an ATC entry with B=1; the bus error is taken on the retry (8.1.2, p. 8-7).
- **Instructions** (9.8, pp. 9-63 to 9-65): PMOVE, PFLUSH(A), PLOAD(R/W), PTEST(R/W) levels 0-7 with optional An;
  all privileged; an unimplemented CpID 0 F-line takes the F-line trap in supervisor mode and a **privilege
  violation in user mode**.
- **Timing** (11.7.2, p. 11-60, no-cache / I-cache case, add EA calculation): PMOVE from CRP/SRP 5/4, to CRP/SRP
  14/12 (invalid 30/28), from TTx 8/8, to TTx 14/12, from MMUSR 5/4, to MMUSR 6/6, from TC 5/4, to TC 40/38 with
  translation enabled (56/58 invalid), 16/14 with translation disabled; PFLUSHA 14/12; PFLUSH 18/16 (FC in SFC/DFC
  22/20); PLOAD 10/8 + table search; PTEST #0 22/22; PTEST #6 88/88 worst case. Table search time: shell script in
  11.7 (pp. 11-51 ff.).

### Stage 1: what is implemented (commits on `pmmu`)

- `wf68k30L_opcode_decoder.vhd`: PMOVE decode ($F000 + EA, one extension word; the field layouts are the ones GNU
  as and EmuTOS emit: `000 PPP R FD 0..0` for TT0 (010) / TT1 (011), `010 PPP R FD 0..0` for TC (000), SRP (010),
  CRP (011), `011 000 R 0 0..0` for MMUSR). Memory alterable EAs: (An), (An)+, -(An), (d16,An), (d8,An,Xn) and the
  full format, (xxx).W, (xxx).L. Privilege: PMOVE and any other CpID 0 F-line in user mode take vector 8.
- `wf68k30L_control.vhd`: PMOVE runs through the existing MOVES operand flow (`MV_RW`/`MV_AN` map the PMOVE R/W bit
  9 onto the MOVES bit 11, An/Dn never used). CRP/SRP read their two longs like a 5-byte bit field (FETCH_OPERAND
  -> CALC_AEFF with ADR_OFFSET + 4) and write them like MOVEP (a second ALU load in INIT_EXEC_WB). Writeback strobe
  `PMMU_WR` with the register select.
- `wf68k30L_top.vhd`: the registers with the manual's masks (TC $83FFFFFF, TTx $FFFF8777, MMUSR $EE47, CRP/SRP
  $FFFF0003_FFFFFFF0); RESET clears only the E bits; TC with E=1 and a bad configuration is stored with E=0.
  TT0/TT1 match on the cycle on the bus (address, FC, R/W, RMC) drives `CIOUTn` and is ORed into the internal CIIN
  path, so the I and D caches do not fill from a CI block (hits of lines already in the caches still hit, 6.1).

### Checklist against the manual

| Manual | Feature | Status | Deviation / reason |
|---|---|---|---|
| 9.7.2 p. 9-54 | TC register, field masks | Done (stage 1) | |
| 9.7.2 / 9.7.5.3 p. 9-62 | TC consistency check, E cleared | Done | Exception itself in stage 3 (vector 56 not yet raised) |
| 9.7.1 p. 9-52 | CRP/SRP 64-bit, masks | Done | Quad PMOVE with (An)+ / -(An) still takes the F-line trap (stage 1c: the 8-byte post-inc/pre-dec step) |
| 9.7.1 p. 9-53 | DT = 0 root pointer: config exception | Register loads; no exception yet | Stage 3 |
| 9.7.3 p. 9-57 | TT0/TT1 fields, E, CI, R/W, RWM, FC base/mask | Done | |
| 9.3 p. 9-16 | TT match rules incl. RMW needs RWM | Done (CI only) | No translation exists yet, so "transparent" only affects CI; MMUSR T bit with PTEST in stage 3 |
| 9.3 p. 9-17 | CIOUT, inhibits on-chip caches | Done | CIOUT is computed from the address the bus unit drives; the bridge does not use the pin |
| 9.7.4 p. 9-59 | MMUSR, PMOVE to/from | Done | Set by PTEST in stage 3 |
| 9.2.2 p. 9-15 | Reset clears E bits only, ATC not flushed | Done | |
| 9.7.5.1 p. 9-61 | FD bit | Decoded | No ATC yet; flush in stage 2 |
| 9.8 p. 9-65 | User mode CpID 0 F-line -> privilege violation | Done | Was F-line before (correctness fix, no switch) |
| 9.8 | PMOVE privileged | Done | |
| 9.4 pp. 9-17-9-20 | ATC, 22 entries, pseudo-LRU, B/CI/WP/M | Stage 2 | |
| 9.5.1 pp. 9-20-9-28 | Short/long table, page, early termination, invalid, indirect descriptors | Stage 2 | |
| 9.5.2, 9.5.4 pp. 9-28-9-43 | Table search, FCL, IS, TIA-TID, limits, U/M with locked RMC | Stage 2 | |
| 9.5.5 pp. 9-43-9-50 | Protection: S, WP, supervisor tree (SRE) | Stage 2 | |
| 9.2.3 p. 9-15 | MMUDIS pin | Tie off | No MMUDIS on our board; treated as negated |
| 9.8, PFLUSH/PFLUSHA | | Stage 3 | Still F-line in supervisor mode |
| 9.8, PLOAD R/W | | Stage 3 | |
| 9.8, 9.7.5.2 | PTEST levels 0-7, An, MMUSR results (Table 9-3 p. 9-60) | Stage 3 | |
| 8.1.2 p. 8-7, 8.2 | Bus error from the ATC/table search, short/long frames, RTE retry | Stage 3 | The existing bus fault frames ($A/$B, FLT1/FLT2, FRM) are reused |
| 8.1.10 p. 8-21 | MMU configuration exception (post-instruction, vector 56) | Stage 3 | |
| 11.7.2 p. 11-60 | PMOVE/PFLUSH/PLOAD/PTEST clocks | Stage 3 | Stage 1 PMOVE runs at the core's MOVES speed; the [T6] padding table gets the 11.7.2 figures in stage 3 |
| 11.7 p. 11-51 | Table search clocks | Stage 2/3 | |

### Plan for cycle-correctness

- The core already pads instructions to the chapter 11 no-cache clocks ([T6] counter in the ALU). PMOVE, PFLUSH,
  PLOAD and PTEST get their 11.7.2 entries there (to TC: 16 clocks with translation off, 40 with it on, which is
  the time a real 030 spends flushing and checking).
- The table walker is a bus master inside the bus interface: one long read per descriptor (two for long format),
  RMC held from the first to the last cycle, U/M writes as locked read-modify-write cycles exactly as 9.5.2
  describes. Its bus cycles are the same S0-S5 cycles the bridge already handles, so the ST-side timing of a walk
  is what a real 030 on an ST bus would see.
- ATC lookup is overlapped on a real 030 (9.4 p. 9-17: "no performance penalty"). In the FPGA it has to fit in the
  address phase: 22 x 28-bit compares in parallel, done from the registered logical address one clock before AS,
  so it adds no clocks to a hit.

### Resource and timing risks

- clk_cpu030 must stay at 17 MHz or more (main tt26rmc2: 21.86 MHz). Stage 1 adds two 8-bit/3-bit compares on the
  bus address and about 300 flip-flops; the measured Fmax and LUTs are in the build report below.
- Stage 2 is the risk: 22 fully associative entries are about 22 x (28 + 28) = 1232 flip-flops plus 22 comparators
  and a 22-way mux in front of the bus address. If that path limits clk_cpu030, register the lookup (the 030's own
  pipeline lets the translation start before the bus cycle) rather than slow the clock.
- The table walker adds a second requester inside the bus interface; it must not disturb the RMC, prefetch and
  cache-fill paths that are already timing-critical (see FALCON_LESSONS [RMC1], [PH2-FMAX]).

### Staged plan

1. **Stage 1 (this branch):** registers, PMOVE (all six registers), TT0/TT1 CI, user-mode privilege.
   Remaining small items: quad PMOVE with (An)+/-(An); MMUDIS tie-off note.
2. **Stage 2:** ATC (22 entries, pseudo-LRU, FD flushes), table walker (short/long, early termination, indirect,
   limits, FCL, SRE, U/M locked updates), translated physical address to the bus, page CI to CIOUT, WP/S checks with
   bus error on retry. Sim: identity, offset and multi-level trees; EmuTOS tree; ATC replacement order.
3. **Stage 3:** PFLUSH variants, PLOAD, PTEST with MMUSR per Table 9-3, MMU configuration exception, bus error
   frames from the MMU, 11.7.2 cycle padding, FreeMiNT memory-protection test on the board.

### Simulation (stage 1)

- `Atarist_030_wip/hdl/cpu030/sim/rtl/prog_pmmu.s` + `expect_pmmu.txt`, run by `run_rtl.sh` with 0, 1, 3, 7 and
  random wait states, data cache on: PMOVE to/from every register, masks, TC check, addressing modes (incl. the
  EmuTOS abs.L form), F-line vs privilege violation, TT0 CI (bus reads of $8000/$8010/$8020 = 1/2/1).
- Unchanged-behaviour check: every existing `sim/rtl/prog_*.s` gives a byte-identical bus log (`cmp_full.sh`) on
  the old and new core; the netlist benches prog_bus and prog_tt give identical traces.
