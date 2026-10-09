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
// Atarist_030_wip: the WF68K30L 68030 runs from pll_hdmi CLKOUT5 = 16 MHz
// (VCO 800 MHz / 50), the same VCO as clk32_core (800/25), phase 0. It uses
// both clock edges, so its internal falling-edge paths get half a period.
// It is related to clk32_core (every clk_cpu030 edge is a clk32 rising edge):
// the bridge's clk_cpu030 <-> clk32_core paths are timed, not cut.
create_generated_clock -name clk_cpu030 -source [get_ports {clk}] -master_clock clk_osc -multiply_by 8 -divide_by 25 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT5}]
// F58: the WF68K30L's falling-edge registers (bus interface input/data
// registers DATA_INMUX, DSACK/AVEC/HALT/BERR samples, SLICE_CNT_N, RETRY,
// IRQ filter, STATUSn) are clocked by clk_cpu030_n = CLKOUT6, ODIV 50,
// PE_COARSE 25 = clk_cpu030 at 180 degrees, on a global clock (before, the
// core's inverted CLK was a fabric LUT and those paths were not analysed).
// Related to clk_cpu030 and clk32_core: every edge is a clk32 rising edge.
create_generated_clock -name clk_cpu030_n -source [get_ports {clk}] -master_clock clk_osc -multiply_by 8 -divide_by 25 -invert [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT6}]
set_clock_groups -asynchronous -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030 clk_cpu030_n}]
// F58: explicit reports for the 68030 clock pairs (half-cycle paths between
// clk_cpu030 and clk_cpu030_n, and the bridge's direct clk32 <-> CPU paths)
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030}] -to_clock [get_clocks {clk_cpu030_n}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030_n}] -to_clock [get_clocks {clk_cpu030}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030_n}] -to_clock [get_clocks {clk_cpu030_n}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_cpu030_n}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_cpu030}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030}] -to_clock [get_clocks {clk32_core}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030}] -to_clock [get_clocks {clk_cpu030}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_cpu030_n}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_cpu030}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030}] -to_clock [get_clocks {clk32_core}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk32_core}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030_n}] -to_clock [get_clocks {clk_cpu030}]
// F60: clk_osc hold report (the DDR3 PLL init counter missed hold with placer 0)
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_osc}] -to_clock [get_clocks {clk_osc}]

// AE350 helper clocks. CORE_CLK is the hard 800 MHz core clock and is not timed here.
create_clock -name ae350_ddr_clk -period 20 -waveform {0 10} [get_nets {DDR_CLK}]
create_clock -name ae350_ahb_clk -period 20 -waveform {0 10} [get_nets {AHB_CLK}]
create_clock -name ae350_apb_clk -period 20 -waveform {0 10} [get_nets {APB_CLK}]
create_clock -name ddr3_clkin      -period 20 -waveform {0 10}  [get_nets {DDR3_CLK_IN}]
create_clock -name ddr3_rw_clk     -period 20 -waveform {0 10}  [get_nets {DDR3_RW_CLK}]
create_clock -name ddr3_memory_clk -period 5  -waveform {0 2.5} [get_nets {DDR3_MEMORY_CLK}]

// ---------------------------------------------------------------------------
// ST_HELPER only (atarist_st_helper.sdc, build_st_helper.tcl). The AE350 SoC
// clocks are asynchronous to the ST core: the only crossings are the
// st_helper_ctrl / st_helper_mailbox 2-flop synchronisers (DDR3_INIT, GPIO,
// flash CS#, UART2_TXD), UART2_RXD (sampled by the UART's own oversampler)
// and the static, once-switched flash pad mux. Without this group STA would
// time those crossings as if the 50 MHz and 32 MHz PLL outputs were related.
set_clock_groups -asynchronous -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030 clk_cpu030_n}]

// ---------------------------------------------------------------------------
// Clocks STA found but nobody created (TA1132, 9 Oct 2026). Before this, every
// path in or out of these nets was untimed or timed against a default guess.
// Docs: docs/ST_HELPER.md 7l. Only clock definitions and clock groups; the
// AE350 flash pad I/O delays are not constrained (SCK period not yet known).

// (1) AE350 flash SPI SCLK: FLASH_SPI_CLK = a LUT in the encrypted SoC
// (u_gwspiflash/u_spi_spiif/n250_s0), also the clock of the SoC's MISO capture
// flops. 20 ns and exclusive to the SoC's AHB/APB/DDR clocks, as in Gowin's
// own AE350 reference SDC (flash_sysclk).
create_clock -name ae350_flash_clk -period 20 -waveform {0 10} [get_nets {ae350_flash_clk}]
set_clock_groups -exclusive -group [get_clocks {ae350_flash_clk}] -group [get_clocks {ae350_ahb_clk}] -group [get_clocks {ae350_apb_clk}] -group [get_clocks {ae350_ddr_clk}]
// The ST flash controller (flash_clk = pll_hdmi CLKOUT3, 100 MHz) owns the same
// balls only after the one-time sth_flash_to_st switch: never both at once.
create_generated_clock -name st_flash_clk -source [get_ports {clk}] -master_clock clk_osc -multiply_by 2 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT3}]
set_clock_groups -exclusive -group [get_clocks {st_flash_clk}] -group [get_clocks {ae350_flash_clk}]

// (2) spi_io_clk: st_helper_mculink's re-registered SCK (an AHB_CLK flop; the
// AE350 bit-bangs it, a level passes after two equal AHB samples, so a half
// period is >= 3 x 20 ns -> 120 ns minimum period) clocks misc/mcu_spi.v.
// Asynchronous to the fabric (mcu_spi -> clk32: toggle flag + 2-flop
// synchroniser) and to the AE350 clocks (MOSI/SS# come from the same retiming
// flops and are stable >= 2 AHB cycles around each SCK edge). The internal
// mcu_spi shift-register paths are timed at 120 ns.
create_clock -name spi_io_clk -period 120 -waveform {0 60} [get_nets {spi_io_clk}]

// (3) DDR3 PHY divider (fclkdiv CLKOUT): ddr3_sysclk 20 ns with the relations
// of Gowin's reference (ae350_shared_ddr3.sdc): asynchronous to ddr3_clkin and
// to ddr3_memory_clk (the PHY's own CDC handles those crossings).
create_clock -name ddr3_sysclk -period 20 -waveform {0 10} [get_pins {u_RiscV_AE350_SOC_Top/u_RiscV_AE350_SOC/u_riscv_ae350_ddr3_top/u_ddr3_memory_ahb_top/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {ddr3_clkin}] -group [get_clocks {ddr3_sysclk}]
set_clock_groups -asynchronous -group [get_clocks {ddr3_sysclk}] -group [get_clocks {ddr3_memory_clk}]

// (4) Fabric dividers of clk32 (MiSTeryNano upstream): i2s bit clock
// (clk32 / 20) and DualShock2 SPI clock (clk32 / 252). Generated from
// clk32_core so the paths into and out of them are timed with the true
// relation instead of as unrelated clocks.
create_generated_clock -name i2s_bclk_d -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 20 [get_nets {i2s_bclk_d}]
create_generated_clock -name ds2_clk_spi -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 252 [get_nets {ds2_p1/clk_spi}]

// Groups for the new clocks. The AE350-side clocks (flash SCK, spi_io_clk,
// ddr3_sysclk) only meet the fabric through the synchronisers / static pad
// mux described above and in the AE350 group line further up; the clk32
// dividers only meet the HDMI 640 domain through the existing frame-buffer
// crossing.
set_clock_groups -asynchronous -group [get_clocks {ae350_flash_clk spi_io_clk ddr3_sysclk}] -group [get_clocks {clk_osc clk_32 clk_spi clk32_core clk_cpu030 clk_cpu030_n i2s_bclk_d ds2_clk_spi}]
set_clock_groups -asynchronous -group [get_clocks {spi_io_clk}] -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk ddr3_sysclk ae350_flash_clk}]
set_clock_groups -asynchronous -group [get_clocks {i2s_bclk_d ds2_clk_spi}] -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}]
