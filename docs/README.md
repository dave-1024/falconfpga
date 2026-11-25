# Documentation index

**New here?** Start with the top [README](../README.md), then the Falcon core's
[README](https://github.com/dave-1024/falconfpga/blob/falcon/Falcon030_rtl/README.md)
(branch `falcon`) and the step-by-step [BUILD.md](https://github.com/dave-1024/falconfpga/blob/falcon/Falcon030_rtl/BUILD.md). The previous ST-era front page, including its screenshots, is kept as
[README_ST_core_archive.md](README_ST_core_archive.md).

## Using and building
- [HOWTO_BUILD.md](HOWTO_BUILD.md): step-by-step build and flash, in plain words. The live
  core is the Falcon (branch `falcon`); the rest of that guide is still the retired ST core.
- [../Atarist_030_wip/docs/BUILD.md](../Atarist_030_wip/docs/BUILD.md): engineer's ST-era
  build guide (switches, defaults, flash map).
- [TOS_COMPAT.md](TOS_COMPAT.md): which TOS versions work on the retired ST core. The Falcon
  loads TOS 4.04 from the SD card.
- [BUGS.md](BUGS.md): fixed and open bugs on the ST-era 68030 core, in plain English. Open
  items that still apply to the Falcon are also listed on the root README.
- [../Falcon030_rtl/README.md](https://github.com/dave-1024/falconfpga/blob/falcon/Falcon030_rtl/README.md):
  status of the live Falcon core (branch `falcon`).
- [../Atarist_030_wip/README.md](../Atarist_030_wip/README.md): status of the retired ST core.

## Work in progress
- Current Falcon work and the planned list: top [README](../README.md).
- [../Atarist_030_wip/docs/TODO.md](../Atarist_030_wip/docs/TODO.md): ST-era open work, in order
  (historical; the ST core is retired for now).
- [../handoff/CONTEXT.md](../handoff/CONTEXT.md): engineering state and next steps.
- PMMU (done 31 Oct 2026, on the ST test bed): [PMMU_DESIGN.md](PMMU_DESIGN.md), [PMMU_TESTING.md](PMMU_TESTING.md), [PMMU_PROGRESS.md](PMMU_PROGRESS.md).
- [FALCON_LESSONS.md](FALCON_LESSONS.md): lessons from the PMMU/FreeMiNT work (F70, F102-F104, F112, F116, F121).
- [../Atarist_030_wip/docs/HISTORY.md](../Atarist_030_wip/docs/HISTORY.md): change-by-change history of the 030 core.
- [../Atarist_030_wip/docs/FALCON_LESSONS.md](../Atarist_030_wip/docs/FALCON_LESSONS.md): lessons learnt and every bug found.

## Design notes (68030 core)
- Bus and bridge: [PHASE2_DESIGN.md](../Atarist_030_wip/docs/PHASE2_DESIGN.md), [EXACT_HANDOFF.md](../Atarist_030_wip/docs/EXACT_HANDOFF.md),
  [BRIDGE_REVIEW.md](../Atarist_030_wip/docs/BRIDGE_REVIEW.md), [OPTION_A_DESIGN.md](../Atarist_030_wip/docs/OPTION_A_DESIGN.md),
  [PREFETCH_COF.md](../Atarist_030_wip/docs/PREFETCH_COF.md), [MOVEM_TIMING_F1_F2.md](../Atarist_030_wip/docs/MOVEM_TIMING_F1_F2.md),
  [FAULT_FIXES.md](../Atarist_030_wip/docs/FAULT_FIXES.md), [notes/TF536_NOTES.md](../Atarist_030_wip/docs/notes/TF536_NOTES.md), [notes/RAM_PATH.md](../Atarist_030_wip/docs/notes/RAM_PATH.md).
- Caches: [CACHE_PLAN.md](../Atarist_030_wip/docs/CACHE_PLAN.md), [ICACHE_DESIGN.md](../Atarist_030_wip/docs/ICACHE_DESIGN.md), [DCACHE_DESIGN.md](../Atarist_030_wip/docs/DCACHE_DESIGN.md),
  [ttram/CACHE_AUDIT.md](ttram/CACHE_AUDIT.md).
- TT-RAM: [TTRAM_DESIGN.md](../Atarist_030_wip/docs/TTRAM_DESIGN.md), [ttram/](ttram/README.md) (SDRAM headroom, timing map).
- Blitter: [BLITTER_SHARED_DIAG.md](BLITTER_SHARED_DIAG.md).
- Falcon v1 design note (branch `falcon`): [Falcon030_rtl/docs/DESIGN.md](https://github.com/dave-1024/falconfpga/blob/falcon/Falcon030_rtl/docs/DESIGN.md).

## Helper (AE350) and debugging
- [ST_HELPER.md](../Atarist_030_wip/docs/ST_HELPER.md), [../Atarist_030_wip/helper_fw/README.md](../Atarist_030_wip/helper_fw/README.md),
  [notes/SPI_SDC.md](../Atarist_030_wip/docs/notes/SPI_SDC.md).
- The Falcon core keeps its own copy of the helper source in `Falcon030_rtl/helper/` (branch `falcon`). Do not
  build or flash that firmware until the helper cleanup is started.
- [SD_WRITE_DEBUG.md](../Atarist_030_wip/docs/SD_WRITE_DEBUG.md), [DIAG_OVERLAY.md](../Atarist_030_wip/docs/DIAG_OVERLAY.md), [notes/DEBUG2.md](../Atarist_030_wip/docs/notes/DEBUG2.md).

## History and reference
- [README_ST_core_archive.md](README_ST_core_archive.md): archived ST-era front page (25 Nov 2026).
- [history/](history/README.md): retired workflow files, dated handovers, old patches, investigations.
- [../reference/](../reference/README.md): older trees (rigsdram, misterynano_tc138k, Hybrid030).
