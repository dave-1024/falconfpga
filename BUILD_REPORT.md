# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260925-mn1
ACTION: PREPARE
RESULT: PASS
GOWIN_VERSION: NOT_RUN (gw_sh not run, per request)
PROJECT: misterynano_tc138k
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C

UPSTREAM:
  repo:   https://github.com/MiSTle-Dev/MiSTeryNano (primary; fallback not needed)
  commit: c8e4601fbf7264e13f4b18ac2d452444de6b51c5 (2026-08-14 17:50 +0200, "Add rtc support (via NTP for now)")
  gprj:   upstream src/atarist_tc138k.gprj (identical to our misterynano_tc138k/atarist_tc138k.gprj, ignoring line endings)

IMPORT COMMIT: a5d09dbaed81262374f0068e6a51fb2506010987
  "Add misterynano_tc138k Console 138K HDL from upstream"

FILES ADDED: 95
  92 = every <File path> in atarist_tc138k.gprj (91 HDL/cst/sdc + mem/hex; all present upstream, byte-identical copies)
   2 = fx68k/LICENSE, fx68k/fx68k.txt
   1 = UPSTREAM.md (attribution: upstream repo + commit; upstream has no top-level LICENSE)
  Kept unchanged: our atarist_tc138k.gprj, build_tc138k.tcl, README.md, .gitignore, HOW_TO_FILL.md

LAYOUT:
  upstream src/<path> -> misterynano_tc138k/<path> (same relative paths as the gprj).
  No path adjustments. All 92 gprj paths verified present under misterynano_tc138k/ and tracked in git.

CHECK:
  tang/console138k/top.sv       present
  fx68k/fx68k.sv                present
  fx68k/microrom.mem            present
  misterynano.sv                present
  tang/mega138kpro/sdram.v      present
  rigsdram/                     untouched (not in either commit)

MISSING / SKIPPED:
  Missing upstream: none.
  gprj references no *.fs or impl/ files.
  Not copied (per request): other tops (nano20k/primer/mega/console60k), firmware, images, other .gprj/.tcl.
  Note: misc/sysctrl.v also names atarist_t20_xml.hex and ikbd/rom/MCU_BIROM.v names ../src/ikbd/rom/ikbd.hex,
        but only inside non-Gowin `ifdef branches (Efinix / Verilator). Not needed; atarist_t20_xml.hex does not exist upstream anyway.

COPIED PATHS (relative to misterynano_tc138k/):
  UPSTREAM.md
  atarist/acia.v
  atarist/acsi.v
  atarist/atarist.v
  atarist/cubase2_dongle.v
  atarist/cubase3_dongle.v
  atarist/dma.v
  atarist/io_fifo.v
  atarist/mfp.v
  atarist/mfp_hbit16.v
  atarist/mfp_srff16.v
  atarist/mfp_timer.v
  atarist/stBlitter.sv
  atarist/ste_joypad.v
  fdc1772/fdc1772.v
  fdc1772/floppy.v
  fx68k/LICENSE
  fx68k/fx68k.sv
  fx68k/fx68k.txt
  fx68k/fx68kAlu.sv
  fx68k/microrom.mem
  fx68k/nanorom.mem
  fx68k/uaddrPla.sv
  gstmcu/hdl/clockgen.v
  gstmcu/hdl/gstmcu.v
  gstmcu/hdl/gstshifter.v
  gstmcu/hdl/hdegen.v
  gstmcu/hdl/hsyncgen.v
  gstmcu/hdl/latch.v
  gstmcu/hdl/mcucontrol.v
  gstmcu/hdl/modules.v
  gstmcu/hdl/register.v
  gstmcu/hdl/shifter_video.v
  gstmcu/hdl/sndcnt.v
  gstmcu/hdl/vdegen.v
  gstmcu/hdl/vidcnt.v
  gstmcu/hdl/vsyncgen.v
  hdmi/audio_clock_regeneration_packet.sv
  hdmi/audio_info_frame.sv
  hdmi/audio_sample_packet.sv
  hdmi/auxiliary_video_information_info_frame.sv
  hdmi/hdmi.sv
  hdmi/packet_assembler.sv
  hdmi/packet_picker.sv
  hdmi/serializer.sv
  hdmi/source_product_description_info_frame.sv
  hdmi/tmds_channel.sv
  ikbd/hd63701/HD63701.v
  ikbd/hd63701/HD63701_ALU.v
  ikbd/hd63701/HD63701_CORE.v
  ikbd/hd63701/HD63701_EXEC.v
  ikbd/hd63701/HD63701_MCODE.i
  ikbd/hd63701/HD63701_MCROM.v
  ikbd/hd63701/HD63701_SEQ.v
  ikbd/hd63701/HD63701_defs.i
  ikbd/ikbd.sv
  ikbd/rom/MCU_BIROM.v
  ikbd/rom/ikbd.hex
  jt49/filter/jt49_dcrm.v
  jt49/filter/jt49_dcrm2.v
  jt49/filter/jt49_dly.v
  jt49/filter/jt49_mave.v
  jt49/jt49.v
  jt49/jt49_bus.v
  jt49/jt49_cen.v
  jt49/jt49_div.v
  jt49/jt49_eg.v
  jt49/jt49_exp.v
  jt49/jt49_noise.v
  misc/atarist_keymap.v
  misc/atarist_xml.hex
  misc/dualshock2.v
  misc/hid.v
  misc/mcu_spi.v
  misc/osd_u8g2.v
  misc/scandoubler.v
  misc/sd_card.v
  misc/sd_rw.v
  misc/sdcmd_ctrl.v
  misc/sysctrl.v
  misc/video_analyzer.v
  misterynano.sv
  tang/console138k/atarist.cst
  tang/console138k/atarist.sdc
  tang/console138k/gowin_pll/pll_160m.v
  tang/console138k/gowin_pll/pll_160m_mod.v
  tang/console138k/pll_init.v
  tang/console138k/top.sv
  tang/console60k/flash_dspi.v
  tang/mega138kpro/gowin_dpb/fdc_dpram.v
  tang/mega138kpro/gowin_dpb/sector_dpram.v
  tang/mega138kpro/sdram.v
  tang/nano20k/video.v
  tang/nano20k/video2hdmi.v
  tang/nano20k/ws2812.v
```
