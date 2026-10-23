# Hybrid Falcon030 fabric. Console 138K SOM, device version C.
# Run from this directory (Hybrid030/hybrid_falcon030):
#   C:\Dev\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe build_hybrid.tcl
# Do not use C:\Dev\Gowin\Gowin_V1.9.12_x64. That gw_sh.exe was empty.
#
# Dual-purpose pins: MSPI and CPU only. The six flash balls are the
# AE350 instruction-fetch path. JTAG, SSPI, READY and DONE stay
# dedicated. Do not copy the misterynano "tick all six" set.
#
# Placement is left at Gowin defaults, matching the GUI build that
# produced a picture on this carrier. Bitstream is impl/pnr/Falcon030.fs.
# Flash that at 0x0. This fabric does not use the Tang SDRAM plug-in.

set_device GW5AST-LV138PG484AC1/I0 -device_version C

add_file src/Falcon030_top.v
add_file src/falcon_ahb_mux.v
add_file src/falcon_audio_ahb.v
add_file src/falcon_audio_i2s.v
add_file src/falcon_audio_submux.v
add_file src/falcon_hid_ahb.v
add_file src/falcon_timebase.v
add_file src/falcon_timebase_ahb.v
add_file src/falcon_video.v
add_file src/gowin_pll_ae350/gowin_pll_ae350.v
add_file src/gowin_pll_ae350/gowin_pll_ae350_mod.v
add_file src/gowin_pll_ddr3/gowin_pll_ddr3.v
add_file src/gowin_pll_ddr3/gowin_pll_ddr3_mod.v
add_file src/gowin_pll_hdmi/gowin_pll_hdmi.v
add_file src/gowin_pll_hdmi/gowin_pll_hdmi_mod.v
add_file src/gowin_pll_usb/gowin_pll_usb.v
add_file src/gowin_pll_usb/gowin_pll_usb_mod.v
add_file src/i2s_tx.v
add_file src/key_debounce.v
add_file src/pll_init.v
add_file src/riscv_ae350_soc/riscv_ae350_soc.v
add_file src/tmds_encoder.v
add_file src/usb_hid_host.v
add_file src/tang_console_ae350_stage0.cst
add_file src/ae350_stage0.sdc
add_file src/sine_lut.hex
add_file src/usb_hid_host_rom.hex

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name Falcon030
set_option -top_module falcon_top

# The two checkboxes. 1 = Use as regular IO.
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_jtag_as_gpio 0
set_option -use_sspi_as_gpio 0
set_option -use_ready_as_gpio 0
set_option -use_done_as_gpio 0

run all
