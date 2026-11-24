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
    output reg  [9:0]  sect,            // 0..1023, sectors written so far (bytes = sect*512)
    output wire [31:0] crc              // IEEE CRC32 of bytes written so far (TOS404.IMG = 32'h028B561D)
);
    reg [7:0]  hi;
    reg [8:1]  widx;
    reg [31:0] base;
    reg        got;
    reg        issued;          // 1 once the current sector request has been acked
    // IEEE CRC32 (poly 0xEDB88320) of the image bytes in file order. TOS404.IMG is 028b561d.
    reg [31:0] crc_s;
    function [31:0] crc8;
        input [31:0] c_in;
        input [7:0]  d;
        integer k;
        reg [31:0] c;
        begin
            c = c_in ^ {24'd0, d};
            for (k = 0; k < 8; k = k + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            crc8 = c;
        end
    endfunction
    assign crc = ~crc_s;
    // one-word buffer: sd bytes arrive faster than nothing, slower than SDRAM writes (~8 clk/byte)
    assign ram_a = {5'b11100, sect, widx};   // $E00000 + sect*512 + widx*2
    always @(posedge clk) begin
        if (reset) begin
            cpu_reset <= 1'b1; err <= 1'b0; busy <= 1'b0; sect <= 10'd0; sd_rd <= 1'b0; ram_req <= 1'b0; got <= 1'b0; issued <= 1'b0;
            crc_s <= 32'hFFFFFFFF;
        end else begin
            if (img_mounted) begin
                if (img_size != 32'd524288) err <= 1'b1;
                else begin busy <= 1'b1; err <= 1'b0; cpu_reset <= 1'b1; sect <= 10'd0; sd_lba <= 32'd0; sd_rd <= 1'b1; issued <= 1'b0; crc_s <= 32'hFFFFFFFF; end
            end else if (busy && !issued && !sd_rd && !sd_ack && !got && !ram_req) begin
                // re-issue the first request if sd_ack was already high on the start cycle
                // (last-assignment would have cleared sd_rd) or the pulse was otherwise dropped
                sd_rd <= 1'b1;
            end
            // Only an ack of an outstanding request sets issued. A leftover
            // rbusy after the last byte of a sector must not mark the next
            // request as already issued (that stalled 39bbce6 at sect=1).
            if (sd_ack && sd_rd) begin sd_rd <= 1'b0; issued <= 1'b1; end
            if (busy && sd_dout_strobe) begin
                crc_s <= crc8(crc_s, sd_dout);
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
                end else begin
                    // Board 39bbce6 tray: mount/size/go/busy/rd/ack/strobe/ram_ack
                    // all on, but sect stuck at 1. rbusy (sd_ack) is still high
                    // when sector 0's last RAM write completes, so "sd_rd<=1;
                    // issued<=0" was then cancelled by "if (sd_ack) sd_rd<=0;
                    // issued<=1" in the same cycle. Wait for ack to fall;
                    // the re-issue clause raises sd_rd once !sd_ack.
                    sect <= sect + 10'd1;
                    sd_lba <= sd_lba + 32'd1;
                    issued <= 1'b0;
                end
            end
        end
    end
endmodule
