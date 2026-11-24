# Falcon030_rtl

This folder is where the RTL for the **Atari Falcon030** core will live.

The WF68K30L 68030 CPU core is being developed and made cycle-exact against
the MC68030 user's manual inside the Atari ST/STE test bed in
[`Atarist_030_wip/`](../Atarist_030_wip/). The ST bus bridge there is only a test bed.
Once the CPU core is ready, it moves here along with the Falcon-specific hardware
(Falcon bus, VIDEL, DSP 56001, Combel, SDMA/Codec and so on).

Status (24 Nov 2026, branch `falcon`, FAL_01): first iteration started. Design note in
[docs/DESIGN.md](docs/DESIGN.md). RTL blocks written and lint-clean (bus decode with async DSACK and
bus errors, IO stubs, NVRAM, YM stub, VIDEL register file, floppy A: wrapper, peripheral sub-bus, TOS loader);
not yet a full top or a bitstream. The GHDL bench `sim/run_tos.sh` runs TOS 4.04 on the shared WF68K30L
against a behavioural Falcon bus. The CPU source is shared by path from `../Atarist_030_wip/hdl/cpu030/`,
so every CPU timing fix lands in both builds. No ROM images in git: TOS 4.04 comes from the SD card.
