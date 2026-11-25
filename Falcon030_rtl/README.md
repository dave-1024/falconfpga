# Falcon030_rtl

RTL for the **Atari Falcon030** core. This folder is self-contained: the WF68K30L
CPU, reused ST peripherals, board support, helper HDL, and a copy of the helper
firmware source all live here. The ST core in [`Atarist_030_wip/`](../Atarist_030_wip/)
is retired for now and is left untouched; if something else is needed from it later,
the module is copied in.

Build: `gw_sh Falcon030_rtl/build_falcon.tcl` from the worktree root, Gowin
V1.9.12.03 only. Constraints are `hdl/top/falcon.sdc`. `timing_pairs` must pass
with `clk_cpu030` at least 16 MHz. No seed sweeps and no relaxed constraints.

Layout:

- `hdl/top`, `hdl/bus`, `hdl/video`, `hdl/peri` — Falcon-native RTL
- `hdl/cpu030` — WF68K30L (local copy)
- `hdl/atarist`, `hdl/fdc1772`, `hdl/ikbd`, `hdl/hdmi`, `hdl/misc`, `hdl/tang`,
  `hdl/helper` — local copies of the modules the Falcon build uses
- `hdl/jt49`, `hdl/gstmcu` — YM2149 and STE DMA sound (copied, not wired yet)
- `osd/falcon.xml`, `osd/falcon_xml.hex` — Falcon OSD menu used by the build
- `helper/` — copy of the AE350 helper firmware source, plus `helper/osd/`
  (the same Falcon XML/hex). Copy only: do not build or flash this firmware
  until David starts the helper cleanup.
- `sim/` — GHDL/iverilog benches; `docs/DESIGN.md` — design note

No ROM images in git: TOS 4.04 comes from the SD card.
