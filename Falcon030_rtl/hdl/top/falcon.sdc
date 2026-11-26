// falcon.sdc - FAL_01: timing constraints for the Falcon030 v1 Console 138K top
//
// Based on the ST helper SDC (atarist_st_helper.sdc).
// Differences: HDMI clocks are on pll_hdmi640 / clkdiv_hdmi640 (not hdmi_tp);
// the ST-bridge MMU multicycle (misterynano/atarist/cpu030/...) is dropped
// (no ST bus bridge). pll_160m is still instanced as pll_hdmi; clk32_core /
// clk_cpu030 are unchanged. i2s_bclk_d is the Gowin name for the clk32/20
// I2S divider (RTL clk_audio); keep the same generated-clock as the ST SDC.
// Gowin V1.9.12.03. timing_pairs must pass; clk_cpu030 floor 16 MHz.

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
create_clock -name clk_hdmi640_x5 -period 7.937 -waveform {0 3.968} [get_nets {clk_hdmi_x5}] -add
create_clock -name clk_hdmi640_pix -period 39.683 -waveform {0 19.841} [get_pins {clkdiv_hdmi640/CLKOUT}] -add
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
// The WF68K30L 68030 runs from pll_hdmi CLKOUT5 = 16 MHz
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
set_clock_groups -asynchronous -group [get_clocks {clk_hdmi640_x5 clk_hdmi640_pix}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_sd80 clk_cpu030 clk_cpu030_n}]
// F66 ST-bridge MMU multicycle is not used: Falcon v1 has no 68000 bus bridge.
// clk_cpu030 <-> clk32_core paths (arbiter/word port) are timed in one cycle.
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
set_clock_groups -asynchronous -group [get_clocks {ae350_ddr_clk ae350_ahb_clk ae350_apb_clk ddr3_clkin ddr3_rw_clk ddr3_memory_clk}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_sd80 clk_cpu030 clk_cpu030_n}]

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
// Gowin names the I2S divider net i2s_bclk_d (RTL: clk_audio, assigned to
// the i2s_bclk port). Omitting this clock left it as a 100 MHz default
// with no async group vs HDMI 126 MHz (TA1132 on the first PnR).
create_generated_clock -name i2s_bclk_d -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 20 [get_nets {i2s_bclk_d}]
create_generated_clock -name ds2_clk_spi -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -master_clock clk32_core -divide_by 252 [get_nets {ds2_p1/clk_spi}]

// Groups for the new clocks. The AE350-side clocks (flash SCK, spi_io_clk,
// ddr3_sysclk) only meet the fabric through the synchronisers / static pad
// mux described above and in the AE350 group line further up; the clk32
// dividers only meet the HDMI 640 domain through the existing frame-buffer
// crossing.
set_clock_groups -asynchronous -group [get_clocks {ae350_flash_clk spi_io_clk ddr3_sysclk}] -group [get_clocks {clk_osc clk_g clk_32 clk_spi sdram_pll_clk st_sck_pll clk32_core clk_sd80 clk_cpu030 clk_cpu030_n i2s_bclk_d ds2_clk_spi}]
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
// SDRAM clock: pll_hdmi CLKOUT2, forwarded to O_sdram_clk (SDR-1: 80 MHz at 306 deg, -1.875 ns vs clk_sd80).
// SDR-1 (26 Nov 2026): the SDRAM runs at 80 MHz. Controller clock clk_sd80 = pll_hdmi CLKOUT0 (VCO 800 / 10), the same
// VCO as clk32_core and clk_cpu030, phase 0: every clk_cpu030 edge is a clk_sd80 edge (ratio 5), every second clk32 edge
// is one (ratio 2.5). Paths between them are timed (falcon_sdram_fast registers every crossing once).
create_generated_clock -name clk_sd80 -source [get_ports {clk}] -master_clock clk_osc -multiply_by 8 -divide_by 5 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT0}]
// SDRAM pad clock: CLKOUT2, 80 MHz at 306 deg (-1.875 ns vs clk_sd80, the same lead in ns as the old 32 MHz 338.4 deg).
create_generated_clock -name sdram_pll_clk -source [get_ports {clk}] -master_clock clk_osc -multiply_by 8 -divide_by 5 -phase 306 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT2}]
create_generated_clock -name clk_32 -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT2}] -master_clock sdram_pll_clk -divide_by 1 [get_ports {O_sdram_clk}] -add
// SDR-1 S4 (David 13:39 UK, 26 Nov 2026): model the real SDRAM clock-pin delay. clk_32 is a generated clock ON THE PORT,
// so Gowin STA gave it zero network latency, while the SDRAM pin registers get the PLL->IOB clock insertion plus the OBUF
// (S2/S3 reports). The pad clock leaves the same PLL through the same kind of clock route and an OBUF, so it gets the same
// delay as source latency, per corner (Gowin: -late used in setup analysis = slow corner, -early in hold = fast corner):
//   late  7.2 = tCL 2.599 + PLL->IOB tNET 2.096 + OBUF 2.528 (slow corner, S3 dq_in_2 / S2 sa_6 paths)
//   early 4.8 = tCL 1.552 + PLL->IOB tNET 0.732 + OBUF 2.482 (fast corner, S3 sd_cmd_2 -> O_sdram_ras_n)
// The -max 6.0 / -min 0.0 output budget and the DQ input delays are unchanged (not a relaxation).
// S5 (David 14:14 UK, option a): Gowin applies source latency per check type, not per corner (S4: setup capture took
// -early 4.8 at the slow corner, hold capture took -late 7.2 at the fast corner, ~2.4 ns cross-corner pessimism each way).
// One value, the FAST-corner 4.8 ns, for both: exact for hold (fast corner), pessimistic for output setup (real slow-corner
// latency 7.2 is larger). Input setup with the slow 7.2 was +3.163 ns in S4 (DQ input regs in the IOB, fixed placement).
set_clock_latency -source 4.8 [get_clocks {clk_32}]
// SDRAM (W9825G6KH-6 class, CL2): tAC <= 6 ns, tOH >= 2.5 ns; tIS 1.5 ns, tIH 0.8 ns. Loose values (board + margin):
// in max 8 / min 0.5, out max 6 / min 0 (also the starting values suggested by the Grok review).
set_input_delay  -clock clk_32 -max 8.0 [get_ports {IO_sdram_dq[*]}]
set_input_delay  -clock clk_32 -min 0.5 [get_ports {IO_sdram_dq[*]}]
// Data for the READ issued at SDRAM edge n is captured by sdram.v on the clk32 edge after SDRAM edge n+CL (STATE_READ):
// the first clk32 edge after an SDRAM edge is 1.88 ns later, the capture edge is the one after that.
// SDR-1: the capture register is falcon_sdram_fast dq_in (clk_sd80), READ+3 as before.
set_multicycle_path -setup -end 2 -from [get_ports {IO_sdram_dq[*]}] -to [get_clocks {clk_sd80}]
set_multicycle_path -hold  -end 1 -from [get_ports {IO_sdram_dq[*]}] -to [get_clocks {clk_sd80}]
set_output_delay -clock clk_32 -max 6.0 [get_ports {O_sdram_addr[*] O_sdram_ba[*] O_sdram_cas_n O_sdram_ras_n O_sdram_wen_n}]
set_output_delay -clock clk_32 -min 0.0 [get_ports {O_sdram_addr[*] O_sdram_ba[*] O_sdram_cas_n O_sdram_ras_n O_sdram_wen_n}]
// SDR-1: DQ (write data) and DQM are registered in falcon_sdram_fast now (launched with the WRITE command), so they get the
// same output timing as the command pins.
set_output_delay -clock clk_32 -max 6.0 [get_ports {IO_sdram_dq[*] O_sdram_dqm[*]}]
// S6 (David 14:40 UK): DQ hold budget = the W9825G6KH datasheet tIH 0.8 ns (min output delay -0.8). S5 missed by 59 ps on the
// DQ output-enable turn-on (IOB OEN path 0.485 ns). Setup budget (-max 6.0) unchanged; DQM keeps -min 0.0.
set_output_delay -clock clk_32 -min -0.8 [get_ports {IO_sdram_dq[*]}]
set_output_delay -clock clk_32 -min 0.0 [get_ports {O_sdram_dqm[*]}]
// Flash SCK: pll_hdmi CLKOUT4, 100 MHz at 22.5 deg, through the AE350/ST pad mux to mspi_clk.
create_generated_clock -name st_sck_pll -source [get_ports {clk}] -master_clock clk_osc -multiply_by 2 -phase 22.5 [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT4}]
create_generated_clock -name clk_spi -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT4}] -master_clock st_sck_pll -divide_by 1 [get_ports {mspi_clk}]
set_clock_groups -exclusive -group [get_clocks {st_sck_pll clk_spi}] -group [get_clocks {ae350_flash_clk}]
// No ST flash_dspi in this build (TOS 4.04 comes from SD, image 4). mspi_di is
// MOSI to the AE350 (Gowin promotes it to an output), so the ST dual-I/O
// set_input_delay / multicycle on {mspi_di mspi_do} does not apply. st_sck_pll
// and clk_spi stay: they are in the clock groups and still describe the pad mux.
// SDRAM DQ/DQM outputs: constrained since SDR-1 (falcon_sdram_fast registers them; the old sdram.v drove them combinationally).
// Flash outputs (command/address phase) are not constrained yet: the sample edge relation needs checking first.
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_32}] -to_clock [get_clocks {clk_sd80}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_32}] -to_clock [get_clocks {clk_sd80}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk_32}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk_32}]
// SDR-1 clock pairs
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk_sd80}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_cpu030}] -to_clock [get_clocks {clk_sd80}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk_cpu030}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_sd80}]
report_timing -setup -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk32_core}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk32_core}] -to_clock [get_clocks {clk_sd80}]
report_timing -hold -max_paths 5 -max_common_paths 1 -from_clock [get_clocks {clk_sd80}] -to_clock [get_clocks {clk32_core}]
