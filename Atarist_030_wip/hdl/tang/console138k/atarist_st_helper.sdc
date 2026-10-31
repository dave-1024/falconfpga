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
// F102: clk_spi / clk_32 are now generated clocks on the pads (see the F102 block at the end).
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
set_clock_groups -asynchronous -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_cpu030 clk_cpu030_n}]
// F66: while TC.E = 1 the bridge samples the 030 pins only on clk_32 edges that are clk_cpu rising edges
// (cpu030_st_bridge.v, slow_ok), >= 62.5 ns after AS. The paths through the MMU's ATC lookup / TT match
// (kept nets XLATE_PIN, BLK_PIN, H_PA in wf68k30L_mmu.vhd) get two clk_32 cycles; with TC.E = 0 those nets
// are constant. Hold stays the single-cycle check.
set_multicycle_path -setup -end 2 -from [get_clocks {clk_cpu030}] -through [get_nets {misterynano/atarist/cpu030/i_wf68k30l/I_MMU/XLATE_PIN misterynano/atarist/cpu030/i_wf68k30l/I_MMU/BLK_PIN misterynano/atarist/cpu030/i_wf68k30l/I_MMU/H_PA*}] -to [get_clocks {clk32_core}]
set_multicycle_path -hold -end 1 -from [get_clocks {clk_cpu030}] -through [get_nets {misterynano/atarist/cpu030/i_wf68k30l/I_MMU/XLATE_PIN misterynano/atarist/cpu030/i_wf68k30l/I_MMU/BLK_PIN misterynano/atarist/cpu030/i_wf68k30l/I_MMU/H_PA*}] -to [get_clocks {clk32_core}]
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
set_clock_groups -asynchronous -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_cpu030 clk_cpu030_n}]

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
set_clock_groups -asynchronous -group [get_clocks {ae350_flash_clk spi_io_clk ddr3_sysclk}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_cpu030 clk_cpu030_n i2s_bclk_d ds2_clk_spi}]
set_clock_groups -asynchronous -group [get_clocks {spi_io_clk}] -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk ddr3_sysclk ae350_flash_clk}]
set_clock_groups -asynchronous -group [get_clocks {i2s_bclk_d ds2_clk_spi}] -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}]

// ---------------------------------------------------------------------------
// clk_g: the 50 MHz board clock after the DCE global buffer in top.sv (fabric
// loads: pll_init FSMs, debouncers). Same clock as clk_osc, delayed.
create_generated_clock -name clk_g -source [get_ports {clk}] -master_clock clk_osc -divide_by 1 [get_pins {u_clk_g/CLKOUT}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_g}] -to_clock [get_clocks {clk_g}]

// ---------------------------------------------------------------------------
// Reset synchronisers (9 Oct 2026, reset_sync.v): por (= !pll_lock, clk_osc)
// enters each fabric domain only through the async PRESET pins of a 3-flop
// async-assert / sync-deassert chain. At release those flops hold a constant
// 1 and the chain absorbs any metastability, so the recovery/removal check
// from por to the chain itself is not a real path. Everything the chains
// reset is timed in-domain.
set_false_path -to [get_pins {u_por32_sync/sync_*_s0/PRESET}]
set_false_path -to [get_pins {u_porfl_sync/sync_*_s0/PRESET}]

// DDR3 PHY (Gowin IP, encrypted): its reset registers (ddr3_clkin) release
// the OSER8/IOLOGIC RESET pins in the ddr3_memory_clk domain, which the IP
// does with the memory clock stopped (DDR3_STOP gates CLKOUT2 of
// gowin_pll_ddr3). Gowin's own reference SDC (ae350_shared_ddr3.sdc, also
// Hybrid030 ae350_stage0.sdc) declares the two clocks exclusive for this.
set_clock_groups -exclusive -group [get_clocks {ddr3_memory_clk}] -group [get_clocks {ddr3_clkin}]

// ---------------------------------------------------------------------------
// F102 (30 Oct 2026): I/O timing for the SDRAM and the ST flash reader. Before this, none of these pads had
// input/output delays, so pad<->flop timing moved with every placement unchecked (build-dependent failures,
// f101h read TOS word 0 as $80B8 = $602E << 2: the flash sample slipped one SCK).
// SDRAM clock: pll_hdmi CLKOUT2, 32 MHz at 338.4 deg (-1.88 ns vs clk32_core), forwarded to O_sdram_clk.
create_generated_clock -name sdram_pll_clk -source [get_ports {clk}] -master_clock clk_osc -multiply_by 16 -divide_by 25 -phase 338.4 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT2}]
create_generated_clock -name clk_32 -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT2}] -master_clock sdram_pll_clk -divide_by 1 [get_ports {O_sdram_clk}] -add
// SDRAM (W9825G6KH-6 class, CL2): tAC <= 6 ns, tOH >= 2.5 ns; tIS 1.5 ns, tIH 0.8 ns. Loose values (board + margin):
// in max 8 / min 0.5, out max 6 / min 0 (also the starting values suggested by the Grok review).
set_input_delay  -clock clk_32 -max 8.0 [get_ports {IO_sdram_dq[*]}]
set_input_delay  -clock clk_32 -min 0.5 [get_ports {IO_sdram_dq[*]}]
// Data for the READ issued at SDRAM edge n is captured by sdram.v on the clk32 edge after SDRAM edge n+CL (STATE_READ):
// the first clk32 edge after an SDRAM edge is 1.88 ns later, the capture edge is the one after that.
set_multicycle_path -setup -end 2 -from [get_ports {IO_sdram_dq[*]}] -to [get_clocks {clk32_core}]
set_multicycle_path -hold  -end 1 -from [get_ports {IO_sdram_dq[*]}] -to [get_clocks {clk32_core}]
set_output_delay -clock clk_32 -max 6.0 [get_ports {O_sdram_addr[*] O_sdram_ba[*] O_sdram_cas_n O_sdram_ras_n O_sdram_wen_n}]
set_output_delay -clock clk_32 -min 0.0 [get_ports {O_sdram_addr[*] O_sdram_ba[*] O_sdram_cas_n O_sdram_ras_n O_sdram_wen_n}]
// Flash SCK: pll_hdmi CLKOUT4, 100 MHz at 22.5 deg, through the AE350/ST pad mux to mspi_clk.
create_generated_clock -name st_sck_pll -source [get_ports {clk}] -master_clock clk_osc -multiply_by 2 -phase 22.5 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT4}]
create_generated_clock -name clk_spi -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT4}] -master_clock st_sck_pll -divide_by 1 [get_ports {mspi_clk}]
set_clock_groups -exclusive -group [get_clocks {st_sck_pll clk_spi}] -group [get_clocks {ae350_flash_clk}]
// Flash (W25Q128JV class) dual-I/O read: data changes after SCK falling, tCLQV <= 6 ns, tCLQX >= 1.5 ns (+0.5 ns board).
// flash_dspi.v samples IO0/IO1 (dspi_in_r) on the st_flash_clk rising edge 2 edges after that SCK fall.
set_input_delay -clock clk_spi -clock_fall -max 6.5 [get_ports {mspi_di mspi_do}]
set_input_delay -clock clk_spi -clock_fall -min 1.5 [get_ports {mspi_di mspi_do}]
set_multicycle_path -setup -end 2 -from [get_ports {mspi_di mspi_do}] -to [get_clocks {st_flash_clk}]
set_multicycle_path -hold  -end 1 -from [get_ports {mspi_di mspi_do}] -to [get_clocks {st_flash_clk}]
// SDRAM DQ/DQM outputs are NOT constrained: sdram.v drives them combinationally from the chipset (din, cs/we/ds; f102a
// first build: 16 logic levels from the blitter through the shifter mbus, -11.4 ns against a 1-cycle relation). They are
// set up cycles ahead of the WRITE edge in practice; registering them is the proper fix (F103).
// Flash outputs (command/address phase) are not constrained yet: the sample edge relation needs checking first.
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_32}] -to_clock [get_clocks {clk32_core}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_32}] -to_clock [get_clocks {clk32_core}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_32}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_32}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_spi}] -to_clock [get_clocks {st_flash_clk}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_spi}] -to_clock [get_clocks {st_flash_clk}]
