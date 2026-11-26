# Falcon030 v1, Console 138K, Gowin V1.9.12.03 only. device_version C. Replicate on.
# Run from the worktree root: gw_sh Falcon030_rtl/build_falcon.tcl
# Originally based on Atarist_030_wip/build_st_helper.tcl. This folder is self-contained:
# CPU, peripherals, board support and helper HDL are local copies under hdl/.
# No seed sweeps, no relaxed constraints.
# timing_pairs must pass; clk_cpu030 floor 16 MHz. Output: impl/pnr/falcon.fs.
#
# falcon_top.sv + falcon_soc.v are in. HDMI is scanout -> hdmi_640 (own 25.2 MHz
# PLL). Helper SPI/sysctrl/sd_card/HID are in the top; TOS ROM is image 4,
# floppy A: is image 0. MFP/ACIA/IKBD/FDC/falcon_pbus are in falcon_soc.
# SDC: Falcon030_rtl/hdl/top/falcon.sdc (not the ST helper SDC).
# jt49/ and gstmcu/ are local copies for later sound work; they are not in this file list.

set F  "Falcon030_rtl"

set fh [open $F/hdl/tang/console138k/build_sel.vh w]
puts $fh "`define FALCON"
puts $fh "`define ST_HELPER"
puts $fh "`define ST_HELPER_USB"
puts $fh "`define ST_HELPER_OSD"
# no TTRAM (v1), no ST chipset, no 68000, no GSTMCU
close $fh

set_device GW5AST-LV138PG484AC1/I0 -device_version C

# Falcon fabric
add_file $F/hdl/top/falcon_top.sv
add_file $F/hdl/top/falcon_soc.v
add_file $F/hdl/top/falcon_core.v
add_file $F/hdl/top/tos_loader.v
add_file $F/hdl/top/tos_mount_latch.v
add_file $F/hdl/bus/falcon_bus.v
add_file $F/hdl/bus/falcon_pbus.v
add_file $F/hdl/bus/falcon_sdram_fast.v
add_file $F/hdl/video/videl_regs.v
add_file $F/hdl/video/falcon_sdp_ram.v
add_file $F/hdl/video/falcon_scanout.v
add_file $F/hdl/video/falcon_videl_timing.v
add_file $F/hdl/video/falcon_dbg_hud.v
add_file $F/hdl/peri/falcon_io.v
add_file $F/hdl/peri/falcon_nvram.v
add_file $F/hdl/peri/falcon_ym_stub.v
add_file $F/hdl/peri/falcon_fdc.v
add_file $F/hdl/peri/falcon_blitter.v
add_file $F/osd/falcon_xml.hex
# sysctrl.v $readmemh("falcon_xml.hex") searches the gw_sh cwd, not add_file's
# path. 85ca498: WARN EX3988, empty XML ROM, helper config[0]=00.
file copy -force $F/osd/falcon_xml.hex falcon_xml.hex


# WF68K30L (local copy under hdl/cpu030)
add_file $F/hdl/cpu030/wf68k30L_pkg.vhd
add_file $F/hdl/cpu030/wf68k30L_address_registers.vhd
add_file $F/hdl/cpu030/wf68k30L_alu.vhd
add_file $F/hdl/cpu030/wf68k30L_bus_interface.vhd
add_file $F/hdl/cpu030/wf68k30L_control.vhd
add_file $F/hdl/cpu030/wf68k30L_data_registers.vhd
add_file $F/hdl/cpu030/wf68k30L_exception_handler.vhd
add_file $F/hdl/cpu030/wf68k30L_opcode_decoder.vhd
add_file $F/hdl/cpu030/wf68k30L_icache.vhd
add_file $F/hdl/cpu030/wf68k30L_dcache.vhd
add_file $F/hdl/cpu030/wf68k30L_mmu.vhd
add_file $F/hdl/cpu030/wf68k30L_top.vhd

# Peripherals (local copies, originally from the ST core)
add_file $F/hdl/atarist/acia.v
add_file $F/hdl/atarist/stBlitter.sv
add_file $F/hdl/atarist/acsi.v
add_file $F/hdl/atarist/dma.v
add_file $F/hdl/atarist/io_fifo.v
add_file $F/hdl/atarist/mfp.v
add_file $F/hdl/atarist/mfp_hbit16.v
add_file $F/hdl/atarist/mfp_srff16.v
add_file $F/hdl/atarist/mfp_timer.v
add_file $F/hdl/fdc1772/fdc1772.v
add_file $F/hdl/fdc1772/floppy.v
add_file $F/hdl/ikbd/hd63701/HD63701.v
add_file $F/hdl/ikbd/hd63701/HD63701_ALU.v
add_file $F/hdl/ikbd/hd63701/HD63701_CORE.v
add_file $F/hdl/ikbd/hd63701/HD63701_EXEC.v
add_file $F/hdl/ikbd/hd63701/HD63701_MCODE.i
add_file $F/hdl/ikbd/hd63701/HD63701_MCROM.v
add_file $F/hdl/ikbd/hd63701/HD63701_SEQ.v
add_file $F/hdl/ikbd/hd63701/HD63701_defs.i
add_file $F/hdl/ikbd/ikbd.sv
add_file $F/hdl/ikbd/rom/MCU_BIROM.v
add_file $F/hdl/ikbd/rom/ikbd.hex
# MCU_BIROM.v $readmemh("ikbd.hex"): earlier builds found it next to MCU_BIROM.v (no EX3988),
# but copy it into the gw_sh cwd too, as for falcon_xml.hex, so the HD63701 ROM is never empty.
file copy -force $F/hdl/ikbd/rom/ikbd.hex ikbd.hex

# HDMI, SDRAM, helper HDL, PLL, SD (local copies; same board pins as the ST helper image)
add_file $F/hdl/hdmi/audio_clock_regeneration_packet.sv
add_file $F/hdl/hdmi/audio_info_frame.sv
add_file $F/hdl/hdmi/audio_sample_packet.sv
add_file $F/hdl/hdmi/auxiliary_video_information_info_frame.sv
add_file $F/hdl/hdmi/hdmi.sv
add_file $F/hdl/hdmi/packet_assembler.sv
add_file $F/hdl/hdmi/packet_picker.sv
add_file $F/hdl/hdmi/serializer.sv
add_file $F/hdl/hdmi/source_product_description_info_frame.sv
add_file $F/hdl/hdmi/tmds_channel.sv
add_file $F/hdl/misc/dualshock2.v
add_file $F/hdl/misc/hid.v
add_file $F/hdl/misc/mcu_spi.v
add_file $F/hdl/misc/osd_u8g2.v
add_file $F/hdl/misc/sd_card.v
add_file $F/hdl/misc/sd_rw.v
add_file $F/hdl/misc/sdcmd_ctrl.v
add_file $F/hdl/misc/sysctrl.v
add_file $F/hdl/misc/atarist_keymap.v
# SDR-1: sdram.v (32 MHz) replaced by hdl/bus/falcon_sdram_fast.v (80 MHz)
add_file $F/hdl/tang/mega138kpro/gowin_dpb/fdc_dpram.v
add_file $F/hdl/tang/mega138kpro/gowin_dpb/sector_dpram.v
add_file $F/hdl/tang/console138k/gowin_pll/pll_160m.v
add_file $F/hdl/tang/console138k/gowin_pll/pll_160m_mod.v
add_file $F/hdl/tang/console138k/pll_init.v
add_file $F/hdl/tang/console138k/pll_wdog.v
add_file $F/hdl/tang/console138k/flash_unstick.v
add_file $F/hdl/tang/console138k/reset_sync.v
add_file $F/hdl/helper/key_debounce.v
add_file $F/hdl/helper/gowin_pll_ae350/gowin_pll_ae350.v
add_file $F/hdl/helper/gowin_pll_ae350/gowin_pll_ae350_mod.v
add_file $F/hdl/helper/gowin_pll_ddr3/gowin_pll_ddr3.v
add_file $F/hdl/helper/gowin_pll_ddr3/gowin_pll_ddr3_mod.v
add_file $F/hdl/helper/riscv_ae350_soc/riscv_ae350_soc.v
add_file $F/hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi.v
add_file $F/hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi_mod.v
add_file $F/hdl/tang/console138k/hdmi_640.sv
add_file $F/hdl/tang/console138k/st_helper_ctrl.v
add_file $F/hdl/tang/console138k/st_helper_mailbox.v
add_file $F/hdl/tang/console138k/st_helper_mculink.v
add_file $F/hdl/tang/console138k/st_helper_usb.v
add_file $F/hdl/tang/console138k/st_helper_osd.v
add_file $F/hdl/tang/console138k/usb_hid_host.v
add_file $F/hdl/tang/console138k/usb_hid_host_rom.hex
add_file $F/hdl/tang/console138k/atarist_st_helper.cst
add_file $F/hdl/top/falcon.sdc

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name falcon
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
set_option -place_option 3
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

# Linserver V1.9.12.03 board build (timing_pairs must pass).
run all
