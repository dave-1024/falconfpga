//Timing Constraints -- Tang Console 138K AE350 Falcon Tier C
//= the verified bisection sdc + HDMI clocks + the lane-clock grouping
//taken VERBATIM in form from Gowin's own DDR3_Shared example sdc
//(ae350_shared_ddr3.sdc): ddr3_rw_clk joins the clk50m/ddr3_sysclk
//exclusive group. The two provisional async lines from the bisection
//sdc are RETIRED in favour of the reference grouping.

//--- Board input clock: 50 MHz on CLK (ball V22) ---
create_clock -name clk50m -period 20 -waveform {0 10} [get_ports {CLK}]

//--- AE350 PLL outputs ---
create_clock -name ae350_ddr_clk -period 20 -waveform {0 10} [get_nets {DDR_CLK}]
create_clock -name ae350_ahb_clk -period 20 -waveform {0 10} [get_nets {AHB_CLK}]
create_clock -name ae350_apb_clk -period 20 -waveform {0 10} [get_nets {APB_CLK}]

//--- DDR3 PLL outputs ---
create_clock -name ddr3_clkin      -period 20 -waveform {0 10}  [get_nets {DDR3_CLK_IN}]
create_clock -name ddr3_rw_clk     -period 20 -waveform {0 10}  [get_nets {DDR3_RW_CLK}]
create_clock -name ddr3_memory_clk -period 5  -waveform {0 2.5} [get_nets {DDR3_MEMORY_CLK}]

//--- HDMI clocks (Tier B verified values) ---
create_clock -name hclk5     -period 7.936 [get_nets {hclk5}]
create_clock -name clk_pixel -period 39.68 [get_nets {clk_pixel}]
create_clock -name clk12     -period 83.33 [get_nets {clk12}]

//--- DDR3 controller internal PHY divider clock ---
create_clock -name ddr3_sysclk -period 20 -waveform {0 10} [get_pins {u_RiscV_AE350_SOC_Top/u_RiscV_AE350_SOC/u_riscv_ae350_ddr3_top/u_ddr3_memory_ahb_top/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

//--- Flash SPI clocks ---
create_clock -name flash_sysclk    -period 20 -waveform {0 10} [get_nets  {u_RiscV_AE350_SOC_Top/FLASH_SPI_CLK_in}]
create_clock -name flash_spi_clk_i -period 20 -waveform {0 10} [get_pins  {u_RiscV_AE350_SOC_Top/FLASH_SPI_CLK_iobuf/I}]
create_clock -name flash_spi_clk   -period 20 -waveform {0 10} [get_ports {FLASH_SPI_CLK}]

//--- Clock domain relationships ---
set_clock_groups -exclusive -group [get_clocks {flash_sysclk}] -group [get_clocks {ae350_ahb_clk}] -group [get_clocks {ae350_apb_clk}] -group [get_clocks {ae350_ddr_clk}]
set_clock_groups -asynchronous -group [get_clocks {ddr3_clkin}] -group [get_clocks {ddr3_sysclk}]
set_clock_groups -asynchronous -group [get_clocks {ddr3_sysclk}] -group [get_clocks {ddr3_memory_clk}]
set_clock_groups -exclusive -group [get_clocks {ddr3_memory_clk}] -group [get_clocks {ddr3_clkin}]
//(reference form, per Gowin ae350_shared_ddr3.sdc:)
set_clock_groups -exclusive -group [get_clocks {clk50m}] -group [get_clocks {ddr3_sysclk}] -group [get_clocks {ddr3_rw_clk}]

//--- Ours, not Gowin's (flagged per doctrine): the pixel/serial domain is
//    asynchronous to the lane clock by construction -- the only crossings
//    are the dual-clock line buffers and 2FF toggle synchronisers inside
//    falcon_video.
set_clock_groups -asynchronous -group [get_clocks {clk_pixel hclk5}] -group [get_clocks {ddr3_rw_clk}]

//--- m6: USB clock domain is asynchronous to everything; the only
//    crossings are the gray-pointer FIFOs inside falcon_hid.
set_clock_groups -asynchronous -group [get_clocks {clk12}] -group [get_clocks {ddr3_rw_clk}]
set_clock_groups -asynchronous -group [get_clocks {clk12}] -group [get_clocks {clk_pixel hclk5}]
//--- REV6: the HID ring writer now lives in the AHB_CLK domain (Extended
//    AHB Master port). clk12 -> ae350_ahb_clk is the gray-pointer FIFO
//    crossing inside falcon_hid_ahb; declare it asynchronous.
set_clock_groups -asynchronous -group [get_clocks {clk12}] -group [get_clocks {ae350_ahb_clk}]
