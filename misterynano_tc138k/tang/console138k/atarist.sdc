//Copyright (C)2014-2024 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9 
//Created Time: 2024-02-23 19:02:18
// FalconFPGA stage 1: video2hdmi is not instantiated while HDMI_TESTPATTERN is
// defined in top.sv, and Gowin treats a constraint on a missing net as an ERROR
// (TA2003). To go back to the core video path, re-enable this line and comment
// out the "stage 1" block at the end of this file.
// create_clock -name clk_hdmi -period 6.25 -waveform {0 3.125} [get_nets {video2hdmi/clk_pixel_x5}] -add
// create_clock -name clk_flash -period 10 -waveform {0 5} [get_nets {flash_clk}]
create_clock -name clk_spi -period 10 -waveform {0 5} [get_ports {mspi_clk}] -add
create_clock -name clk_32 -period 31.25 -waveform {0 15.625} [get_ports {O_sdram_clk}] -add
create_clock -name clk_osc -period 20 -waveform {0 10} [get_ports {clk}] -add

// FalconFPGA stage 1 (HDMI_TESTPATTERN in top.sv): standalone 640x480@60 HDMI.
// gowin_pll_hdmi: 50 MHz -> 126 MHz TMDS serial clock, CLKDIV/5 -> 25.2 MHz pixel clock.
create_clock -name clk_hdmi640_x5 -period 7.937 -waveform {0 3.968} [get_nets {hdmi_tp/clk_pixel_x5}] -add
create_clock -name clk_hdmi640_pix -period 39.683 -waveform {0 19.841} [get_pins {hdmi_tp/clkdiv_hdmi640/CLKOUT}] -add
// 48 kHz HDMI audio clock (25.2 MHz / 525, fabric generated)
create_clock -name clk_hdmi640_audio -period 20833.333 -waveform {0 10396.825} [get_nets {hdmi_tp/clk_audio}] -add
// nothing crosses between the test-pattern HDMI domain and the Atari core
// (only the PLL lock, which is double-synchronised); audio -> pixel uses the
// hdmi core's own toggle synchronisers
set_clock_groups -asynchronous -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}] -group [get_clocks {clk_hdmi640_audio}] -group [get_clocks {clk_osc clk_32 clk_spi}]
