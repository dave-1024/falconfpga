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
//
// 20:1x 24 Nov 2026: sector buffer. sd_card.v (CLK_DIV 0) strobes one byte every 4 clk32, i.e. a
// word every 8 clk32, but an SDRAM arbiter slot is 8 clk32 plus the 4-phase req/ack turnaround and
// a refresh slot every 16: the old one-word register was overwritten before it was written and
// sim/tb_ldrate.v lost 2047 of 4096 words (board: stale SDRAM words inside the TOS copy, while the
// CRC, taken on the SD byte stream, still matched). Each sector now goes into a 256x16 SDP BSRAM,
// is then drained to SDRAM word by word with the full handshake, and only then is the next sector
// requested. The CRC is still over the SD bytes.
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
    reg        drain;           // copying the sector buffer to SDRAM
    reg        sdone;           // one clock: the sector is in SDRAM
    reg [1:0]  dph;
    reg        bufw;            // sector buffer write strobe (odd byte)
    reg [7:0]  bufwa;
    reg [15:0] bufwd;
    reg [15:0] sbuf [0:255] /* synthesis syn_ramstyle = "block_ram" */;
    reg [15:0] sbuf_q;
    always @(posedge clk) if (bufw) sbuf[bufwa] <= bufwd;
    always @(posedge clk) sbuf_q <= sbuf[widx];
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
            drain <= 1'b0; sdone <= 1'b0; bufw <= 1'b0; dph <= 2'd0;
            crc_s <= 32'hFFFFFFFF;
        end else begin
            if (img_mounted) begin
                if (img_size != 32'd524288) err <= 1'b1;
                else begin busy <= 1'b1; err <= 1'b0; cpu_reset <= 1'b1; sect <= 10'd0; sd_lba <= 32'd0; sd_rd <= 1'b1; issued <= 1'b0; crc_s <= 32'hFFFFFFFF; end
            end else if (busy && !issued && !sd_rd && !sd_ack && !got && !ram_req && !drain && !sdone) begin
                // re-issue the first request if sd_ack was already high on the start cycle
                // (last-assignment would have cleared sd_rd) or the pulse was otherwise dropped
                sd_rd <= 1'b1;
            end
            // Only an ack of an outstanding request sets issued. A leftover
            // rbusy after the last byte of a sector must not mark the next
            // request as already issued (that stalled 39bbce6 at sect=1).
            if (sd_ack && sd_rd) begin sd_rd <= 1'b0; issued <= 1'b1; end
            bufw <= 1'b0;
            sdone <= 1'b0;
            if (busy && sd_dout_strobe) begin
                crc_s <= crc8(crc_s, sd_dout);
                if (!sd_buff_addr[0]) hi <= sd_dout;
                else begin bufw <= 1'b1; bufwa <= sd_buff_addr[8:1]; bufwd <= {hi, sd_dout}; end
                if (sect == 10'd0 && sd_buff_addr >= 9'd8 && sd_buff_addr <= 9'd11)
                    base <= {base[23:0], sd_dout};
                if (sd_buff_addr == 9'd511) got <= 1'b1;
            end
            // Drain the sector buffer: widx -> (registered read) sbuf_q -> one 4-phase write each.
            if (got && !drain && !bufw && !sd_dout_strobe) begin
                got <= 1'b0; drain <= 1'b1; widx <= 8'd0; dph <= 2'd0;
            end
            if (drain) case (dph)
                2'd0: dph <= 2'd1;                                  // sbuf_q <= sbuf[widx]
                2'd1: if (!ram_req && !ram_ack) begin ram_wdata <= sbuf_q; ram_req <= 1'b1; dph <= 2'd2; end
                default: if (ram_req && ram_ack) begin
                    ram_req <= 1'b0; dph <= 2'd0;
                    if (widx == 8'd255) begin drain <= 1'b0; sdone <= 1'b1; end
                    else widx <= widx + 8'd1;
                end
            endcase
            if (sdone) begin
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
