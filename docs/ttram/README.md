# TT-RAM notes

TT-RAM = 16 MB of 68030-side fast RAM at `$01000000-$01FFFFFF`, cachable (everything on the ST side is
cache-inhibited). It sits on the **same single SDRAM module in J9** as ST-RAM; the project stays on one module on
purpose (most people have only one). The SDRAM is 16 bits wide, so each 32-bit TT long is two beats.

## Status (22 Oct 2026)
- Built in by default: `TTRAM` is set in `build_st_helper.tcl` / `build_st_helper_hdn.tcl`; there is no switch to set.
  The I and D caches are on by default too. An on/off option for TT-RAM will be added to the helper later (the HDL
  already has a `TTRAM_ON` / `tt_en` input for it).
- Works with caches on and off since [C10] (71624aa). Release build **tt20** (`build_st_helper_hdn.tcl` + `TTRAM`,
  no debug ring): clk32 33.38 MHz, clk_cpu030 22.42 MHz (rule: at least 17 MHz), worst slack -4.89 ns,
  41127 LUT + 5036 ALU.
- FrontBench prgflags 7 lastcount: **1362** TT-RAM caches on, **1169** TT-RAM caches off, **990** ST-RAM.
- Open: worst path MOVEM_INH_WR -> AR_IN -> ADR_EFF_I; I-only/D-only/TTW/TTE not rerun on tt20; the tt19
  debug-ring build had video dropouts (debug ring is a commented-out `TT_RING` line in `build_st_helper.tcl`).

## Files
- [OVERNIGHT_2026-10-21.md](OVERNIGHT_2026-10-21.md): the overnight test log and results table.
- [T1_TIMING_MAP.md](T1_TIMING_MAP.md): clock-by-clock map of the failing T1 loop.
- Design: [../../Atarist_030_wip/docs/TTRAM_DESIGN.md](../../Atarist_030_wip/docs/TTRAM_DESIGN.md).
- Bugs: [../BUGS.md](../BUGS.md). Lessons: [FALCON_LESSONS.md](../../Atarist_030_wip/docs/FALCON_LESSONS.md) (C10 entry).
