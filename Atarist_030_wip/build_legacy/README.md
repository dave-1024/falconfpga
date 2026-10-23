# build_legacy/

Retired or superseded build scripts, kept for reference. Each `cd`s to `Atarist_030_wip/` itself:
`gw_sh build_legacy/<name>.tcl`. Use `../build_st_helper.tcl` (main) or `../debug_builds/` instead.

| script | what it was for |
|---|---|
| `build_ae350_serial.tcl` | AE350 serial proof image (helper bring-up) |
| `build_st_helper_nocart.tcl` | main build without the self-test cart (cart is now opt-in in the main build) |
| `build_st_helper_sdlog.tcl`, `build_st_helper_mch.tcl` | `SD_WRITE_DEBUG` (SD request ring) for the SD write / media-change hunt; mch also without `ST_FLOPPY_MEDIACH` |
| `build_st_helper_dmaw.tcl`, `_excw.tcl`, `_gdt.tcl`, `_hiwatch.tcl`, `_hiv6.tcl`, `_wrw.tcl` | `DIAG_OVERLAY` on-screen watches from earlier bug hunts (DMA/exception/GEMDOS trace/hi-address/write watches) |

All of these predate TT-RAM, the 030 caches and SD hardening being default (they lack `TTRAM`, `ST_030_CACHES`, `ST_SD_HARDEN`); add those defines if you revive one.
