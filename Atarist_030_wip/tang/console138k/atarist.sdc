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
// The 48 kHz HDMI audio clock (hdmi_tp/clk_audio) is not constrained here: in
// DVI mode (DVI_OUTPUT=1 in top.sv) it is optimised away, and a constraint on
// a missing net is a TA2003 ERROR. In HDMI mode it shows up as an
// auto-derived clock (TA1132 warning), like video2hdmi/clk_audio did.
// the 640x480 HDMI domain is asynchronous to the Atari core (stage 1: only
// the PLL lock, which is double-synchronised; stage 2: see below)
// FalconFPGA stage 2: the ST frame buffer (st_framebuffer.v) writes its BSRAM
// with the core's real 32 MHz clock (pll_hdmi CLKOUT1; the clk_32 clock above
// is only the O_sdram_clk port) and reads it with clk_hdmi640_pix. Name that
// PLL output explicitly (it is otherwise an auto-derived clock that cannot be
// referenced) so it can go into the core's asynchronous group. Only the BSRAM
// and the double-synchronised mono flag cross between the two domains.
create_generated_clock -name clk32_core -source [get_ports {clk}] -master_clock clk_osc -multiply_by 16 -divide_by 25 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}]
// Atarist_030_wip: the WF68K30L 68030 runs from pll_hdmi CLKOUT5 = 8 MHz
// (VCO 800 MHz / 100), the same VCO as clk32_core (800/25), phase 0. It uses
// both clock edges, so its internal falling-edge paths get half a period.
// It is related to clk32_core (every clk_cpu030 edge is a clk32 rising edge):
// the bridge's clk_cpu030 <-> clk32_core paths are timed, not cut.
create_generated_clock -name clk_cpu030 -source [get_ports {clk}] -master_clock clk_osc -multiply_by 4 -divide_by 25 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT5}]
set_clock_groups -asynchronous -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030}]
