# Falcon030_rtl

This folder is where the RTL for the **Atari Falcon030** core will live.

The WF68K30L 68030 CPU core is being developed and made cycle-exact against
the MC68030 user's manual inside the Atari ST/STE test bed in
[`Atarist_030_wip/`](../Atarist_030_wip/). The ST bus bridge there is only a test bed.
Once the CPU core is ready, it moves here along with the Falcon-specific hardware
(Falcon bus, VIDEL, DSP 56001, Combel, SDMA/Codec and so on).

Status (24 Nov 2026, branch `falcon`, FAL_01): design note in [docs/DESIGN.md](docs/DESIGN.md).
RTL written and iverilog-clean: bus, IO stubs, NVRAM (`PRESET=0` default, Hybrid stock), YM stub,
VIDEL register file, floppy A:, peripheral sub-bus, TOS loader, SDRAM arbiter (GSTMCU 8-clock
slots, scanout > floppy DMA > loader/CPU; `st_ba` on the shared `sdram.v` for 16 MB), and
`falcon_scanout.v` (port of Hybrid030 `falcon_video.v` onto that arbiter and the ST HDMI path).
OSD entry "TOS ROM" is in `osd/falcon.xml`. `build_falcon.tcl` is the Gowin file list; `falcon_top.sv`
is still NEXT, so there is no bitstream yet. The GHDL bench `sim/run_tos.sh` runs TOS 4.04 on the
shared WF68K30L against a behavioural Falcon bus (VBL fix: past `$E00D60`, VIDEL `$FF82C2` written,
GEMDOS/XBIOS traps). CPU source is shared by path from `../Atarist_030_wip/hdl/cpu030/`. No ROM
images in git: TOS 4.04 comes from the SD card.
