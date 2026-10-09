# FalconFPGA: Console 138K only. device_version C (this SOM). Replicate on.
# Run from this directory: gw_sh build_tc138k.tcl


# Desktop image. Clears the proof macro if a serial build ran last.
set fh [open hdl/tang/console138k/build_sel.vh w]
puts $fh "// desktop"
close $fh

set_device GW5AST-LV138PG484AC1/I0 -device_version C

add_file hdl/tang/console138k/top.sv
add_file hdl/atarist/acia.v
add_file hdl/atarist/acsi.v
add_file hdl/atarist/atarist.v
add_file hdl/atarist/cubase2_dongle.v
add_file hdl/atarist/cubase3_dongle.v
add_file hdl/atarist/dma.v
add_file hdl/atarist/io_fifo.v
add_file hdl/atarist/mfp.v
add_file hdl/atarist/mfp_hbit16.v
add_file hdl/atarist/mfp_srff16.v
add_file hdl/atarist/mfp_timer.v
add_file hdl/atarist/stBlitter.sv
add_file hdl/atarist/ste_joypad.v
add_file hdl/cpu030/wf68k30L_pkg.vhd
add_file hdl/cpu030/wf68k30L_address_registers.vhd
add_file hdl/cpu030/wf68k30L_alu.vhd
add_file hdl/cpu030/wf68k30L_bus_interface.vhd
add_file hdl/cpu030/wf68k30L_control.vhd
add_file hdl/cpu030/wf68k30L_data_registers.vhd
add_file hdl/cpu030/wf68k30L_exception_handler.vhd
add_file hdl/cpu030/wf68k30L_opcode_decoder.vhd
add_file hdl/cpu030/wf68k30L_icache.vhd
add_file hdl/cpu030/wf68k30L_dcache.vhd
add_file hdl/cpu030/wf68k30L_top.vhd
add_file hdl/cpu030/cpu030_st_bridge.v
add_file hdl/fdc1772/fdc1772.v
add_file hdl/fdc1772/floppy.v
add_file hdl/fx68k/fx68k.sv
add_file hdl/fx68k/fx68kAlu.sv
add_file hdl/fx68k/uaddrPla.sv
add_file hdl/gstmcu/hdl/clockgen.v
add_file hdl/gstmcu/hdl/gstmcu.v
add_file hdl/gstmcu/hdl/gstshifter.v
add_file hdl/gstmcu/hdl/hdegen.v
add_file hdl/gstmcu/hdl/hsyncgen.v
add_file hdl/gstmcu/hdl/latch.v
add_file hdl/gstmcu/hdl/mcucontrol.v
add_file hdl/gstmcu/hdl/modules.v
add_file hdl/gstmcu/hdl/register.v
add_file hdl/gstmcu/hdl/shifter_video.v
add_file hdl/gstmcu/hdl/sndcnt.v
add_file hdl/gstmcu/hdl/vdegen.v
add_file hdl/gstmcu/hdl/vidcnt.v
add_file hdl/gstmcu/hdl/vsyncgen.v
add_file hdl/hdmi/audio_clock_regeneration_packet.sv
add_file hdl/hdmi/audio_info_frame.sv
add_file hdl/hdmi/audio_sample_packet.sv
add_file hdl/hdmi/auxiliary_video_information_info_frame.sv
add_file hdl/hdmi/hdmi.sv
add_file hdl/hdmi/packet_assembler.sv
add_file hdl/hdmi/packet_picker.sv
add_file hdl/hdmi/serializer.sv
add_file hdl/hdmi/source_product_description_info_frame.sv
add_file hdl/hdmi/tmds_channel.sv
add_file hdl/ikbd/hd63701/HD63701.v
add_file hdl/ikbd/hd63701/HD63701_ALU.v
add_file hdl/ikbd/hd63701/HD63701_CORE.v
add_file hdl/ikbd/hd63701/HD63701_EXEC.v
add_file hdl/ikbd/hd63701/HD63701_MCODE.i
add_file hdl/ikbd/hd63701/HD63701_MCROM.v
add_file hdl/ikbd/hd63701/HD63701_SEQ.v
add_file hdl/ikbd/hd63701/HD63701_defs.i
add_file hdl/ikbd/ikbd.sv
add_file hdl/ikbd/rom/MCU_BIROM.v
add_file hdl/jt49/filter/jt49_dcrm.v
add_file hdl/jt49/filter/jt49_dcrm2.v
add_file hdl/jt49/filter/jt49_dly.v
add_file hdl/jt49/filter/jt49_mave.v
add_file hdl/jt49/jt49.v
add_file hdl/jt49/jt49_bus.v
add_file hdl/jt49/jt49_cen.v
add_file hdl/jt49/jt49_div.v
add_file hdl/jt49/jt49_eg.v
add_file hdl/jt49/jt49_exp.v
add_file hdl/jt49/jt49_noise.v
add_file hdl/misc/hid.v
add_file hdl/misc/mcu_spi.v
add_file hdl/misc/osd_u8g2.v
add_file hdl/misc/scandoubler.v
add_file hdl/misc/sd_card.v
add_file hdl/misc/sd_rw.v
add_file hdl/misc/sdcmd_ctrl.v
add_file hdl/misc/sysctrl.v
add_file hdl/misc/video_analyzer.v
add_file hdl/misc/atarist_keymap.v
add_file hdl/misc/dualshock2.v
add_file hdl/misterynano.sv
add_file hdl/tang/console60k/flash_dspi.v
add_file hdl/tang/mega138kpro/sdram.v
add_file hdl/tang/nano20k/video.v
add_file hdl/tang/nano20k/video2hdmi.v
add_file hdl/tang/nano20k/ws2812.v
add_file hdl/tang/mega138kpro/gowin_dpb/fdc_dpram.v
add_file hdl/tang/mega138kpro/gowin_dpb/sector_dpram.v
add_file hdl/tang/console138k/gowin_pll/pll_160m.v
add_file hdl/tang/console138k/gowin_pll/pll_160m_mod.v
add_file hdl/tang/console138k/pll_init.v
add_file hdl/helper/key_debounce.v
add_file hdl/helper/gowin_pll_ae350/gowin_pll_ae350.v
add_file hdl/helper/gowin_pll_ae350/gowin_pll_ae350_mod.v
add_file hdl/helper/gowin_pll_ddr3/gowin_pll_ddr3.v
add_file hdl/helper/gowin_pll_ddr3/gowin_pll_ddr3_mod.v
add_file hdl/helper/riscv_ae350_soc/riscv_ae350_soc.v
add_file hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi.v
add_file hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi_mod.v
add_file hdl/tang/console138k/video_testpattern_640.v
add_file hdl/tang/console138k/hdmi_640.sv
add_file hdl/tang/console138k/hdmi_testpattern_640.sv
add_file hdl/tang/console138k/st_framebuffer.v
add_file hdl/tang/console138k/diag_overlay.v
add_file hdl/tang/console138k/atarist.cst
add_file hdl/tang/console138k/atarist.sdc
add_file hdl/fx68k/microrom.mem
add_file hdl/fx68k/nanorom.mem
add_file hdl/ikbd/rom/ikbd.hex
add_file hdl/misc/atarist_xml.hex

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name atarist_tc138k
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
