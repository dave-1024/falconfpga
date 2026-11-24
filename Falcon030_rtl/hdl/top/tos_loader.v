// tos_loader.v - FAL_01: copy TOS 4.04 (512K) from an SD image slot into SDRAM $E00000, CPU in reset
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// TOS comes from the SD card, not flash (Hybrid030 HOWTO.md "ROM=", falcon_m28.c M9G/M10
// ROM-from-card). The helper (FPGA-Companion) mounts the OSD entry "TOS ROM" (default
// TOS404.IMG) as an image slot exactly like a floppy; this block reads its sectors 0..1023
// through the same sd_card.v core port the floppy uses (MiSTer sd_lba/sd_rd/sd_ack/byte strobe)
// and writes them as words to SDRAM $E00000-$E7FFFF. Read only: the card is never written.
// cpu_reset stays high until the copy is done and the header looks like a ROM based at
// $E00000 (long at +8 = $00E00000, the TOS base pointer); a bad image keeps the CPU in reset
// and sets err (OSD/LED).
module tos_loader (
    input  wire        clk,             // sd_card / SDRAM port clock
    input  wire        reset,
    input  wire        img_mounted,     // pulse: helper mounted the TOS image
    input  wire [31:0] img_size,
    output reg  [31:0] sd_lba,
    output reg         sd_rd,
    input  wire        sd_ack,
    input  wire [8:0]  sd_buff_addr,
    input  wire [7:0]  sd_dout,
    input  wire        sd_dout_strobe,
    // SDRAM word writes
    output reg         ram_req,
    output wire [23:1] ram_a,
    output reg  [15:0] ram_wdata,
    input  wire        ram_ack,
    output reg         cpu_reset,
    output reg         err,
    output reg         busy,            // 1 while sectors are being copied
    output reg  [9:0]  sect             // 0..1023, sectors written so far (bytes = sect*512)
);
    reg [7:0]  hi;
    reg [8:1]  widx;
    reg [31:0] base;
    reg        got;
    // one-word buffer: sd bytes arrive faster than nothing, slower than SDRAM writes (~8 clk/byte)
    assign ram_a = {5'b11100, sect, widx};   // $E00000 + sect*512 + widx*2
    always @(posedge clk) begin
        if (reset) begin
            cpu_reset <= 1'b1; err <= 1'b0; busy <= 1'b0; sect <= 10'd0; sd_rd <= 1'b0; ram_req <= 1'b0; got <= 1'b0;
        end else begin
            if (img_mounted) begin
                if (img_size != 32'd524288) err <= 1'b1;
                else begin busy <= 1'b1; err <= 1'b0; cpu_reset <= 1'b1; sect <= 10'd0; sd_lba <= 32'd0; sd_rd <= 1'b1; end
            end
            if (sd_ack) sd_rd <= 1'b0;
            if (busy && sd_dout_strobe) begin
                if (!sd_buff_addr[0]) hi <= sd_dout;
                else begin ram_wdata <= {hi, sd_dout}; widx <= sd_buff_addr[8:1]; ram_req <= 1'b1; end
                if (sect == 10'd0 && sd_buff_addr >= 9'd8 && sd_buff_addr <= 9'd11)
                    base <= {base[23:0], sd_dout};
                if (sd_buff_addr == 9'd511) got <= 1'b1;
            end
            if (ram_req && ram_ack) ram_req <= 1'b0;
            if (got && !ram_req && !sd_dout_strobe) begin
                got <= 1'b0;
                if (sect == 10'd1023) begin
                    busy <= 1'b0;
                    if (base == 32'h00E00000) cpu_reset <= 1'b0; else err <= 1'b1;
                end else begin sect <= sect + 10'd1; sd_lba <= sd_lba + 32'd1; sd_rd <= 1'b1; end
            end
        end
    end
endmodule
