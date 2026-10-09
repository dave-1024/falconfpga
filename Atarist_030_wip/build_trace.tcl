# FalconFPGA: Console 138K only. device_version C (this SOM). Replicate on.
# Run from this directory: gw_sh build_st_helper.tcl


# ST + AE350 helper image (build option ST_HELPER). Does not change the desktop
# tcl. Same files, pins and dual-purpose options as build_tc138k.tcl, plus:
#   st_helper_ctrl.v     boot-then-release of the SPI flash (AE350 boots first)
#   st_helper_mailbox.v  ST mailbox at $FFFB00, UART2 link to the AE350
#   st_helper_mculink.v  AE350 = FPGA-Companion MCU on mcu_spi (BL616 off)
#   st_helper_cart_rom.v + st_helper_cart.hex  self-test cartridge (ST_HELPER_CART)
#   atarist_st_helper.cst  desktop pins with U15 = AE350 UART, C22 = spi_irqn
#   atarist_st_helper.sdc  desktop constraints + AE350 clocks asynchronous
# Gowin has no -verilog_define, so the macro goes into build_sel.vh (top.sv
# includes it); build_tc138k.tcl writes "// desktop" there again.
# Output: impl/pnr/st_helper.fs. See README "Build option: ST_HELPER".
set fh [open tang/console138k/build_sel.vh w]
puts $fh "`define ST_HELPER"
# Self-test cartridge ROM at $FA0000 (TOS runs it once at boot). Delete the
# next line to build without it.
puts $fh "`define ST_HELPER_CART"
# USB keyboard/mouse on the Console USB-A ports for the AE350 companion
# (st_helper_usb.v, port step 4). Delete the next line to build without it.
puts $fh "`define ST_HELPER_USB"
# Colour monitor (ST low/medium res) instead of mono. Delete the next line
# for ST High (mono), as in the desktop build.
puts $fh "`define ST_COLOUR_MONITOR"
# MiSTeryNano OSD on the HDMI output, drawn by the AE350 companion
# (st_helper_osd.v, port step 5). Delete the next line to build without it.
puts $fh "`define ST_HELPER_OSD"
puts $fh "`define ST_STE"
# diag-trace (debug only): WF68K30L bus/prefetch event ring dumped on HDMI after a trigger
puts $fh "`define WF030_TRACE"
# Experimental WF68K30L instruction/data caches (incomplete: no CIIN, burst
# fill, WA or DMA snoop). Off by default; add the next line to build them in.
# puts $fh "`define ST_030_CACHES"
close $fh

set_device GW5AST-LV138PG484AC1/I0 -device_version C

add_file tang/console138k/top.sv
add_file atarist/acia.v
add_file atarist/acsi.v
add_file atarist/atarist.v
add_file atarist/cubase2_dongle.v
add_file atarist/cubase3_dongle.v
add_file atarist/dma.v
add_file atarist/io_fifo.v
add_file atarist/mfp.v
add_file atarist/mfp_hbit16.v
add_file atarist/mfp_srff16.v
add_file atarist/mfp_timer.v
add_file atarist/stBlitter.sv
add_file atarist/ste_joypad.v
add_file cpu030/wf68k30L_pkg.vhd
add_file cpu030/wf68k30L_address_registers.vhd
add_file cpu030/wf68k30L_alu.vhd
add_file cpu030/wf68k30L_bus_interface.vhd
add_file cpu030/wf68k30L_control.vhd
add_file cpu030/wf68k30L_data_registers.vhd
add_file cpu030/wf68k30L_exception_handler.vhd
add_file cpu030/wf68k30L_opcode_decoder.vhd
add_file cpu030/wf68k30L_icache.vhd
add_file cpu030/wf68k30L_dcache.vhd
add_file cpu030/wf68k30L_top.vhd
add_file cpu030/cpu030_st_bridge.v
add_file cpu030/trace/wf030_trace_cap.v
add_file cpu030/trace/wf030_trace_view.v
add_file fdc1772/fdc1772.v
add_file fdc1772/floppy.v
add_file fx68k/fx68k.sv
add_file fx68k/fx68kAlu.sv
add_file fx68k/uaddrPla.sv
add_file gstmcu/hdl/clockgen.v
add_file gstmcu/hdl/gstmcu.v
add_file gstmcu/hdl/gstshifter.v
add_file gstmcu/hdl/hdegen.v
add_file gstmcu/hdl/hsyncgen.v
add_file gstmcu/hdl/latch.v
add_file gstmcu/hdl/mcucontrol.v
add_file gstmcu/hdl/modules.v
add_file gstmcu/hdl/register.v
add_file gstmcu/hdl/shifter_video.v
add_file gstmcu/hdl/sndcnt.v
add_file gstmcu/hdl/vdegen.v
add_file gstmcu/hdl/vidcnt.v
add_file gstmcu/hdl/vsyncgen.v
add_file hdmi/audio_clock_regeneration_packet.sv
add_file hdmi/audio_info_frame.sv
add_file hdmi/audio_sample_packet.sv
add_file hdmi/auxiliary_video_information_info_frame.sv
add_file hdmi/hdmi.sv
add_file hdmi/packet_assembler.sv
add_file hdmi/packet_picker.sv
add_file hdmi/serializer.sv
add_file hdmi/source_product_description_info_frame.sv
add_file hdmi/tmds_channel.sv
add_file ikbd/hd63701/HD63701.v
add_file ikbd/hd63701/HD63701_ALU.v
add_file ikbd/hd63701/HD63701_CORE.v
add_file ikbd/hd63701/HD63701_EXEC.v
add_file ikbd/hd63701/HD63701_MCODE.i
add_file ikbd/hd63701/HD63701_MCROM.v
add_file ikbd/hd63701/HD63701_SEQ.v
add_file ikbd/hd63701/HD63701_defs.i
add_file ikbd/ikbd.sv
add_file ikbd/rom/MCU_BIROM.v
add_file jt49/filter/jt49_dcrm.v
add_file jt49/filter/jt49_dcrm2.v
add_file jt49/filter/jt49_dly.v
add_file jt49/filter/jt49_mave.v
add_file jt49/jt49.v
add_file jt49/jt49_bus.v
add_file jt49/jt49_cen.v
add_file jt49/jt49_div.v
add_file jt49/jt49_eg.v
add_file jt49/jt49_exp.v
add_file jt49/jt49_noise.v
add_file misc/hid.v
add_file misc/mcu_spi.v
add_file misc/osd_u8g2.v
add_file misc/scandoubler.v
add_file misc/sd_card.v
add_file misc/sd_rw.v
add_file misc/sdcmd_ctrl.v
add_file misc/sysctrl.v
add_file misc/video_analyzer.v
add_file misc/atarist_keymap.v
add_file misc/dualshock2.v
add_file misterynano.sv
add_file tang/console60k/flash_dspi.v
add_file tang/mega138kpro/sdram.v
add_file tang/nano20k/video.v
add_file tang/nano20k/video2hdmi.v
add_file tang/nano20k/ws2812.v
add_file tang/mega138kpro/gowin_dpb/fdc_dpram.v
add_file tang/mega138kpro/gowin_dpb/sector_dpram.v
add_file tang/console138k/gowin_pll/pll_160m.v
add_file tang/console138k/gowin_pll/pll_160m_mod.v
add_file tang/console138k/pll_init.v
add_file helper/key_debounce.v
add_file helper/gowin_pll_ae350/gowin_pll_ae350.v
add_file helper/gowin_pll_ae350/gowin_pll_ae350_mod.v
add_file helper/gowin_pll_ddr3/gowin_pll_ddr3.v
add_file helper/gowin_pll_ddr3/gowin_pll_ddr3_mod.v
add_file helper/riscv_ae350_soc/riscv_ae350_soc.v
add_file tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi.v
add_file tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi_mod.v
add_file tang/console138k/video_testpattern_640.v
add_file tang/console138k/hdmi_640.sv
add_file tang/console138k/hdmi_testpattern_640.sv
add_file tang/console138k/st_framebuffer.v
add_file tang/console138k/diag_overlay.v
add_file tang/console138k/st_helper_ctrl.v
add_file tang/console138k/st_helper_mailbox.v
add_file tang/console138k/st_helper_mculink.v
add_file tang/console138k/st_helper_cart_rom.v
add_file tang/console138k/st_helper_cart.hex
add_file tang/console138k/st_helper_usb.v
add_file tang/console138k/st_helper_osd.v
add_file tang/console138k/usb_hid_host.v
add_file tang/console138k/usb_hid_host_rom.hex
add_file tang/console138k/atarist_st_helper.cst
add_file tang/console138k/atarist_st_helper.sdc
add_file fx68k/microrom.mem
add_file fx68k/nanorom.mem
add_file ikbd/rom/ikbd.hex
add_file misc/atarist_xml.hex

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name st_helper
set_option -verilog_std sysv2017
set_option -top_module top
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_jtag_as_gpio 1
set_option -use_mode_as_gpio 0
set_option -use_i2c_as_gpio 0
set_option -print_all_synthesis_warning 0
set_option -show_all_warn 1
set_option -rw_check_on_ram 0
set_option -user_code 00000002
set_option -bit_compress 0
set_option -multi_boot 0
set_option -mspi_jump 0
set_option -turn_off_bg 0
set_option -vccx 1.8
set_option -vcc 0.9
set_option -power_on_reset_monitor 1
set_option -timing_driven 1
set_option -cst_warn_to_error 1
set_option -rpt_auto_place_io_info 1
set_option -convert_sdp32_36_to_sdp16_18 1
set_option -correct_hold_violation 1
# F60 build: with the default placer (0) the AE350 DDR3 PLL init counter
# (u_gowin_pll_ddr3/u_pll_init/waitcnt, clk_osc) missed hold by up to 0.131 ns
# (clk_osc hold TNS -0.371, 4 endpoints; clock skew -0.75 ns). Placer 1 is
# clean on every clock (clk_cpu030 17.65 MHz, clk32_core 32.11 MHz).
set_option -place_option 1
set_option -loading_rate 70.000
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1
set_option -bit_crc_check 1
set_option -bit_security 1
set_option -bit_incl_bsram_init 1
set_option -bg_programming off
set_option -hotboot 0
set_option -program_done_bypass 0
set_option -wakeup_mode 0
set_option -serdesRetiming 0
set_option -enable_dsrm 0
set_option -disable_io_insertion 0
set_option -looplimit 2000
set_option -co-place_io_registers 0
set_option -replicate_resources 1
set_option -show_init_in_vo 0

run all
