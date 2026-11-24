// videl_regs.v - FAL_01: VIDEL / ST shifter register file for the Falcon030
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Registers (Hatari videl.c, falcon_m28.c falcon_io_valid):
//   $8200-$820D  screen base hi/mid ($8201/$8203), counter ($8205/7/9, read), base lo ($820D)
//   $820E/$8210  line offset / VWRAP (words per line)
//   $8240-$825F  16 x ST palette (12-bit STe), $8260 ST shift mode, $8264/$8265 hscroll,
//   $8266        Falcon SPSHIFT (bit 8 TC, bit 4 8 planes, bit 10 1 plane, ...)
//   $8280-$82C3  VIDEL timing (HHC..VDE, VCO $82C0, VMODE $82C2), stored and read back
//   $9800-$9BFF  256 x Falcon palette, longword RRRRRRxx GGGGGGxx xxxxxxxx BBBBBBxx
// Outputs are the scanout's geometry, the same fields the Hybrid030 mailbox carried into
// falcon_video.v (fb_base, planes, hdbl, vdbl, native height, linebytes, palettes), so the
// port of falcon_video.v reads them straight from here instead of from DDR3.
module videl_regs (
    input  wire        clk,
    input  wire        reset,
    input  wire        sel,           // IO cycle in $8200-$82C7 or $9800-$9BFF
    input  wire [15:1] a,
    input  wire        uds, lds,
    input  wire        wr,
    input  wire [15:0] din,
    output reg  [15:0] dout,
    input  wire [23:0] vcount,        // live video address counter from the scanout
    // to the scanout
    output wire [23:0] fb_base,
    output reg  [3:0]  planes,        // 0 = true colour (RGB565), 1/2/4/8 = bitplanes
    output reg         hdbl, vdbl,
    output reg  [9:0]  height,        // native visible lines
    output wire [11:0] linebytes,
    output wire [11:0] st_pal_rd,     // ST palette entry st_pal_idx
    input  wire [3:0]  st_pal_idx,
    output reg  [7:0]  fpal_wa,       // Falcon palette write port (to the scanout's palette RAM)
    output reg  [17:0] fpal_wd,
    output reg         fpal_we,
    output reg         stpal_we,
    output reg  [3:0]  stpal_wa,
    output reg  [11:0] stpal_wd
);
    reg [7:0]  base_h, base_m, base_l;
    reg [15:0] lineoff, vwrap, spshift;
    reg [7:0]  shmode;
    reg [15:0] st_pal [0:15];
    reg [15:0] vt [0:35];             // $8280-$82C7 word file
    reg [15:0] fpal_hi [0:255];       // R:G word of each Falcon palette long
    reg [15:0] fpal_rd;
    wire [15:0] o = {a, 1'b0};
    assign fb_base   = {base_h, base_m, base_l[7:1], 1'b0};
    assign linebytes = {vwrap[10:0], 1'b0};
    assign st_pal_rd = st_pal[st_pal_idx][11:0];
    wire [15:0] vmode = vt[(16'h82C2 - 16'h8280) >> 1];
    wire [15:0] vde   = vt[(16'h82AA - 16'h8280) >> 1];
    wire [15:0] vdb   = vt[(16'h82A8 - 16'h8280) >> 1];
    integer i;
    // merge byte lanes into a stored word
    function [15:0] mrg; input [15:0] old; input [15:0] nw; input u; input l; begin
        mrg = {u ? nw[15:8] : old[15:8], l ? nw[7:0] : old[7:0]};
    end endfunction
    always @(posedge clk) begin
        fpal_we <= 1'b0;
        stpal_we <= 1'b0;
        if (reset) begin
            base_h <= 8'h00; base_m <= 8'h00; base_l <= 8'h00; shmode <= 8'h00;
            spshift <= 16'h0000; vwrap <= 16'd40; lineoff <= 16'd0;
            for (i = 0; i < 36; i = i + 1) vt[i] <= 16'h0000;
        end else if (sel && wr) begin
            if (o >= 16'h9800) begin
                if (!o[1]) fpal_hi[o[9:2]] <= mrg(fpal_hi[o[9:2]], din, uds, lds);
                else begin   // low word (blue) completes the entry
                    fpal_wa <= o[9:2];
                    fpal_wd <= {fpal_hi[o[9:2]][15:10], fpal_hi[o[9:2]][7:2], (uds ? din[15:10] : 6'd0)};
                    fpal_we <= 1'b1;
                end
            end else if (o >= 16'h8280) vt[(o - 16'h8280) >> 1] <= mrg(vt[(o - 16'h8280) >> 1], din, uds, lds);
            else if (o >= 16'h8240 && o < 16'h8260) begin
                st_pal[o[4:1]] <= mrg(st_pal[o[4:1]], din, uds, lds);
                stpal_we <= 1'b1;
                stpal_wa <= o[4:1];
                stpal_wd <= mrg(st_pal[o[4:1]], din, uds, lds); // 12-bit port, low 12 of $0RGB
            end
            else case (o)
                16'h8200: if (lds) base_h <= din[7:0];
                16'h8202: if (lds) base_m <= din[7:0];
                16'h820C: if (lds) base_l <= din[7:0];
                16'h820E: lineoff <= mrg(lineoff, din, uds, lds);
                16'h8210: vwrap <= mrg(vwrap, din, uds, lds);
                16'h8260: if (uds) begin shmode <= din[15:8]; spshift <= 16'h0000; end  // ST mode write clears SPSHIFT
                16'h8266: spshift <= mrg(spshift, din, uds, lds);
                default: ;
            endcase
        end
    end
    always @(posedge clk) fpal_rd <= fpal_hi[o[9:2]];
    always @(*) begin
        dout = 16'hFFFF;
        if (o >= 16'h9800) dout = o[1] ? 16'h0000 : fpal_rd;
        else if (o >= 16'h8280) dout = vt[(o - 16'h8280) >> 1];
        else if (o >= 16'h8240 && o < 16'h8260) dout = st_pal[o[4:1]];
        else case (o)
            16'h8200: dout = {8'hFF, base_h};
            16'h8202: dout = {8'hFF, base_m};
            16'h8204: dout = {8'hFF, vcount[23:16]};
            16'h8206: dout = {8'hFF, vcount[15:8]};
            16'h8208: dout = {8'hFF, vcount[7:0]};
            16'h820C: dout = {8'hFF, base_l};
            16'h820E: dout = lineoff;
            16'h8210: dout = vwrap;
            16'h8260: dout = {shmode, 8'hFF};
            16'h8266: dout = spshift;
            default: dout = 16'hFFFF;
        endcase
    end
    // geometry for the scanout (TOS boot modes; refine with Hatari videl.c)
    always @(*) begin
        if (spshift[8])       planes = 4'd0;        // true colour
        else if (spshift[4])  planes = 4'd8;
        else if (spshift[10]) planes = 4'd1;
        else case (shmode[1:0])
            2'd0: planes = 4'd4; 2'd1: planes = 4'd2; default: planes = 4'd1;
        endcase
        hdbl   = (linebytes <= 12'd320) && (planes != 4'd0) ? (linebytes < (planes * 12'd80)) : 1'b0;
        vdbl   = vmode[0];                           // VMODE bit 0: line doubling
        height = (vde > vdb) ? ((vde - vdb) >> (vmode[0] ? 1 : 0)) >> 1 : 10'd480;  // half-lines on VGA
    end
endmodule
