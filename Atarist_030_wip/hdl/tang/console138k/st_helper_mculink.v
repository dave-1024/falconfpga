// ===========================================================================
// st_helper_mculink.v - AE350 as the FPGA-Companion MCU (build option ST_HELPER)
//
// On the stock board the BL616 is the "MCU" of the MiSTeryNano / FPGA-
// Companion design: it is the SPI master of misc/mcu_spi.v (MODE1, SS#,
// SCK idle low, data sampled on the falling edge) and watches the core's
// interrupt line (spi_intn, active low). In ST_HELPER the AE350 takes that
// role so the BL616 never has to be reflashed; the BL616's pins are ignored
// (top.sv).
//
// HARDWARE UPDATE (6 Oct 2026): in this Gowin SoC the flash controller's
// registers are not reachable (0xF0B00000 hangs the bus, 0xF0F00000 reads
// all zero), so it cannot run register-mode transfers. The link is now
// bit-banged by the firmware: SS# = GPIO[0], SCK = GPIO[1], MOSI = GPIO[2]
// (top.sv), MISO = mcu_spi dout -> UART2_CTSN (MSR bit 4 CTS = MISO). The
// retiming below is unchanged. The original plan, kept for reference:
//
// The AE350 SoC netlist has no free SPI controller ports, but after the
// boot-time flash handoff (st_helper_ctrl.v) its flash SPI controller (SPI1,
// ATCSPI200) is idle and its CLK/MOSI/MISO are plain fabric nets. So the
// link reuses them:
//   SS#  = AE350 GPIO[0]   frame select, held by firmware across a whole
//                          FPGA-Companion message (mcu_hw_spi_begin/end).
//                          The ATCSPI200's own CS# toggles per transfer and
//                          is ignored here; a stray XIP read of 0x80000000
//                          therefore never reaches the core (SS# stays high).
//   SCK  = SPI1 SCLK       (FLASH_SPI_CLK, a LUT output inside the SoC)
//   MOSI = SPI1 MOSI       (FLASH_SPI_MOSI)
//   MISO = mcu_spi dout -> FLASH_SPI_MISO (top.sv)
//   IRQ# = core spi_intn -> UART2_DCDN (MSR bit 7 DCD = 1 while pending)
//   UP   = link enabled   -> UART2_DSRN (MSR bit 5 DSR = 1 once usable)
//
// Retiming: SCK/MOSI/SS# are re-registered on AHB_CLK (50 MHz) and each
// output changes only after two equal samples (after a 1-flop synchroniser).
// This removes any LUT glitch on the SoC's SCLK net before it is used as the
// mcu_spi clock, and keeps SS#/SCK/MOSI ordered. Cost: about 4 AHB cycles
// (80 ns) of SCK delay, which eats into the MISO return half-period, and SCK
// must stay below ~6 MHz so each level is sampled several times. Firmware
// default: SCLK_DIV = 15, i.e. 50 MHz / 32 = 1.56 MHz if SPI1 runs on the
// 50 MHz AHB clock (3.1 MHz if on a 100 MHz clock). The BL616 runs the same
// link at 13.3 MHz; speeding up is a later step with a measured MISO margin.
//
// Before link_en (flash still owned by the AE350, or the helper failed) the
// outputs are idle: SS# = 1, SCK = 0, MOSI = 0.
// ===========================================================================
module st_helper_mculink (
    input  wire clk_ae,       // AE350 AHB_CLK
    input  wire link_en_a,    // st_helper_ctrl helper_up (clk32, sticky)
    input  wire ae_ss_n_a,    // AE350 GPIO[0]
    input  wire ae_sck_a,     // AE350 GPIO[1] (bit-banged SCK)
    input  wire ae_mosi_a,    // AE350 GPIO[2] (bit-banged MOSI)
    output reg  ss_n,         // to mcu_spi spi_io_ss
    output reg  sck,          // to mcu_spi spi_io_clk
    output reg  mosi          // to mcu_spi spi_io_din
);
    reg [1:0] en_s;
    reg [2:0] ss_s, sck_s, mosi_s;          // [0] synchroniser, [2:1] compared
    initial begin
        en_s = 2'b00; ss_s = 3'b111; sck_s = 3'b000; mosi_s = 3'b000;
        ss_n = 1'b1; sck = 1'b0; mosi = 1'b0;
    end
    always @(posedge clk_ae) begin
        en_s   <= {en_s[0], link_en_a};
        ss_s   <= {ss_s[1:0],   ae_ss_n_a};
        sck_s  <= {sck_s[1:0],  ae_sck_a};
        mosi_s <= {mosi_s[1:0], ae_mosi_a};
        if (!en_s[1]) begin
            ss_n <= 1'b1; sck <= 1'b0; mosi <= 1'b0;
        end else begin
            if (ss_s[2]   == ss_s[1])   ss_n <= ss_s[2];
            if (sck_s[2]  == sck_s[1])  sck  <= sck_s[2];
            if (mosi_s[2] == mosi_s[1]) mosi <= mosi_s[2];
        end
    end
endmodule
