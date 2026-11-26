// falcon_fdc.v - FAL_01: Falcon030 floppy, drive A: only: ST dma.v + fdc1772.v + the DMA address
//                counter and RAM master the GSTMCU provided in the ST core
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Falcon has ONE floppy drive and no second floppy port (Hybrid030 HOWTO.md "Floppy B":
// TOS 4.04 only knows one floppy; falcon_m28.c M11i: B: commands pend with no drive select).
// So fdc1772 is built with FD_NUM = 1, the drive select is YM port A bit 1 only (active low,
// bit 2 / drive B is ignored), side = port A bit 0, and only helper image slot 0 is used.
// Registers: $FF8604/6 dma.v (FDC/sector count, mode/status), $FF8609/B/D DMA address
// (this file; in the ST it lived in the GSTMCU), $FF860E density (falcon_io.v latch; fdc1772
// takes HD from the image size, so the latch is read back only for now).
// RAM side: dma.v asks with rdy_o (ram_br) when cpu_sel is low; each completed word is a rising
// edge on rdy_i. Words go through the SDRAM arbiter port below.
// Clock: clk_32 with the 8 MHz enable, as in atarist.v.
module falcon_fdc (
    input  wire        clk_32,
    input  wire        clk8_en,
    input  wire        reset,
    // CPU (byte/word IO cycle, synchronised into clk_32 by the caller)
    input  wire        sel_dma,          // $FF8604-$FF8607
    input  wire        sel_addr,         // $FF8608-$FF860D
    input  wire [3:1]  a,
    input  wire        rw,
    input  wire        wr_stb,
    input  wire [15:0] din,
    output wire [15:0] dout,
    output wire        irq,              // FDC INTRQ -> MFP GPIP5 (active high here)
    input  wire [7:0]  ym_porta,
    // SDRAM arbiter word port
    output reg         ram_req,
    output wire        ram_we,
    output wire [23:1] ram_a,
    output wire [15:0] ram_wdata,
    input  wire        ram_ack,
    input  wire [15:0] ram_rdata,
    // helper / sd_card (image slot 0 only)
    input  wire        img_mounted,
    input  wire [31:0] img_size,
    input  wire        img_wp,
    output wire [31:0] sd_lba,
    output wire        sd_rd,
    output wire        sd_wr,
    input  wire        sd_ack,
    input  wire        sd_err,
    input  wire [8:0]  sd_buff_addr,
    input  wire [7:0]  sd_dout,
    output wire [7:0]  sd_din,
    input  wire        sd_dout_strobe
);
    wire fdc_drq, fdc_sel, fdc_rw; wire [1:0] fdc_addr; wire [7:0] fdc_din, fdc_dout;
    wire rdy_o; reg rdy_i = 1'b1;
    wire [15:0] dma_dout;
    reg  [23:1] dma_a;
    reg  [15:0] ram_q;
    reg         dir_out;                  // 1: RAM -> FDC (disk write), dma.v dma_direction_out
    always @(posedge clk_32) begin
        if (reset) dir_out <= 1'b0;
        else if (sel_dma && wr_stb && a[1]) dir_out <= din[8];   // $FF8606 mode bit 8
    end
    dma dma (
        .clk(clk_32), .clk_en(clk8_en), .reset(reset),
        .cpu_din(din), .cpu_sel(sel_dma), .cpu_a1(a[1]), .cpu_rw(rw), .cpu_dout(dma_dout),
        .img_mounted(2'b00), .img_size(64'd0), .acsi_rd_req(), .acsi_wr_req(), .acsi_lba(),
        .sd_busy(1'b0), .sd_done(1'b0), .sd_rd_byte_strobe(1'b0), .sd_rd_byte(8'd0), .sd_wr_byte(),
        .sd_byte_addr(9'd0), .acsi_irq(),
        .fdc_drq(fdc_drq), .fdc_addr(fdc_addr), .fdc_sel(fdc_sel), .fdc_rw(fdc_rw),
        .fdc_din(fdc_din), .fdc_dout(fdc_dout),
        .rdy_i(rdy_i), .rdy_o(rdy_o), .ram_din(ram_q), .hdd_leds());
    // DMA address counter $FF8609 (hi) / $860B (mid) / $860D (lo), word aligned
    always @(posedge clk_32) begin
        if (reset) dma_a <= 23'd0;
        else if (sel_addr && wr_stb) case (a)
            3'd4: dma_a[23:16] <= din[7:0];
            3'd5: dma_a[15:8]  <= din[7:0];
            3'd6: dma_a[7:1]   <= din[7:1];
            default: ;
        endcase
        else if (ram_req && ram_ack) dma_a <= dma_a + 23'd1;
    end
    // RAM master: one word per dma.v request, rdy_i rises when it is done
    wire br = rdy_o && !sel_dma;
    always @(posedge clk_32) begin
        if (reset) begin ram_req <= 1'b0; rdy_i <= 1'b0; end
        else begin
            rdy_i <= 1'b0;
            if (!ram_req && br && !rdy_i) ram_req <= 1'b1;
            else if (ram_req && ram_ack) begin ram_req <= 1'b0; ram_q <= ram_rdata; rdy_i <= 1'b1; end
        end
    end
    assign ram_we    = !dir_out;          // disk read: FIFO -> RAM
    assign ram_a     = dma_a;
    assign ram_wdata = dma_dout;
    assign dout = sel_addr ? (a == 3'd4 ? {8'hFF, dma_a[23:16]} : a == 3'd5 ? {8'hFF, dma_a[15:8]} :
                              a == 3'd6 ? {8'hFF, dma_a[7:1], 1'b0} : 16'hFFFF) : dma_dout;
    // drive A only: select active low on port A bit 1; bit 2 (B) ignored
    fdc1772 #(.FD_NUM(1)) fdc1772 (
        .clkcpu(clk_32), .clk8m_en(clk8_en),
        .floppy_drive(ym_porta[1]), .floppy_side(ym_porta[0]), .floppy_reset(~reset),
        .floppy_step(), .floppy_motor(1'b0), .floppy_ready(),
        .irq(irq), .drq(fdc_drq),
        .cpu_addr(fdc_addr), .cpu_sel(fdc_sel), .cpu_rw(fdc_rw), .cpu_din(fdc_din), .cpu_dout(fdc_dout),
        .img_type(3'd1), .img_mounted(img_mounted), .img_wp(img_wp), .img_ds(1'b0), .img_size(img_size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack), .sd_err(sd_err),
        .sd_buff_addr(sd_buff_addr), .sd_dout(sd_dout), .sd_din(sd_din), .sd_dout_strobe(sd_dout_strobe));
endmodule
