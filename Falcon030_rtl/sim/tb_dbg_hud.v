// tb_dbg_hud.v - iverilog check of the always-on hex overlay glyphs
`timescale 1ns/1ps
module tb_dbg_hud;
    reg  [9:0]  cx, cy;
    wire        hit;
    wire [7:0]  r, g, b;

    falcon_dbg_hud uut (
        .cx(cx), .cy(cy),
        .pc(32'h00E00030), .io_a(16'h82C2), .io_d(16'h0008),
        .berr_count(16'h0002), .berr_addr(32'h00FF8E09),
        .vbas(24'h000000), .hht(16'h001A), .vft(16'h020B),
        .spshift(16'h0000), .shmode(8'h00),
        .tos_crc(32'h028B561D),
        .flags(8'b1011_0000), // hb, vbl, ram_ready, crc_ok
        .fetch_count(16'h00AB),
        .planes(4'd4), .linebytes(12'h140), .height(10'd480),
        .hdbl(1'b0), .vdbl(1'b0), .frame(8'h3C),
        .cycs(384'h0), .ncyc(4'd0),
        .io_ring(256'h0), .pc_ring(256'h0),
        .hit(hit), .r(r), .g(g), .b(b)
    );

    integer errors, x, y, lit;
    initial begin
        errors = 0;
        // outside the strip
        cx = 10'd0; cy = 10'd80; #1;
        if (hit !== 1'b0) begin $display("FAIL: hit at y=80"); errors = errors+1; end
        // navy background of a space cell (row 0, col 9 = x=72, between PC and IO)
        cx = 10'd72; cy = 10'd3; #1;
        if (hit !== 1'b1) begin $display("FAIL: miss in strip"); errors = errors+1; end
        if (r !== 8'h10 || g !== 8'h20 || b !== 8'h40) begin
            $display("FAIL: bg got %02x%02x%02x", r, g, b); errors = errors+1;
        end
        // cyan PC bar at x=0..7, y=0..7
        cx = 10'd3; cy = 10'd3; #1;
        if (r !== 8'h00 || g !== 8'hC0 || b !== 8'hC0) begin
            $display("FAIL: PC bar %02x%02x%02x", r, g, b); errors = errors+1;
        end
        // CRC bar must be lime because crc == 028B561D (x=240, y=8)
        cx = 10'd243; cy = 10'd10; #1;
        if (r !== 8'h80 || g !== 8'hFF || b !== 8'h00) begin
            $display("FAIL: CRC bar %02x%02x%02x (want lime)", r, g, b); errors = errors+1;
        end
        // First hex of PC is 0 (x=8..15). Glyph '0' has a hole in the middle.
        cx = 10'd12; cy = 10'd3; #1; // cell x=8, px=4, row 3: '0' bits = 10001, px 4 is bits[1] = 0
        if (r !== 8'h10) begin $display("FAIL: '0' hole %02x", r); errors = errors+1; end
        // left wall of '0' at px=1, row 1: bits[4]=1
        cx = 10'd9; cy = 10'd1; #1;
        if (r !== 8'hF0) begin $display("FAIL: '0' wall %02x", r); errors = errors+1; end
        // last nibble of PC is 0 too (32'h00E00030 ends with 0). Check '3' at x=64..71.
        // '3' row 0 is 01110, px=3 (cx=67) is bits[2]=1
        cx = 10'd67; cy = 10'd0; #1;
        if (r !== 8'hF0) begin $display("FAIL: '3' top %02x", r); errors = errors+1; end
        // flag 4 (crc_ok) at x=64..79, y=16, should be green (flags[4]=1)
        cx = 10'd70; cy = 10'd18; #1;
        if (r !== 8'h00 || g !== 8'hC0) begin
            $display("FAIL: crc_ok flag %02x%02x%02x", r, g, b); errors = errors+1;
        end
        // flag 0 cpu_reset is 0 -> dark
        cx = 10'd4; cy = 10'd18; #1;
        if (r !== 8'h18) begin $display("FAIL: reset flag dark %02x", r); errors = errors+1; end
        if (errors == 0) $display("ALL PASS");
        else $display("FAILED %0d", errors);
        $finish;
    end
endmodule
