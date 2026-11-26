// tb_scanout_arb.v - FAL_01 (BLI-9): 4-plane fetch against a falcon_sdram_arb-style LEVEL ack
// (ack held until req drops, 8-clock slots, burst-2). Group 0 = p0..p2 $FFFF, p3 $0000 = pixel 7 (grey);
// expects pal[7] on x=0..15. Before the fix the scanout re-took the stale ack and showed pixel 15.
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 4-plane 16-colour group 0: palette index 1 = $0F00, plane-0 word 16'h8000.
// Expects pixel 0 = 24'hFF0000 and pixels 1..15 black on the second frame
// (line 0 is prefetched at cx==0 of cy==524). Run:
//   iverilog -g2012 -o /tmp/tb_scanout.vvp hdl/video/falcon_sdp_ram.v \
//     hdl/video/falcon_scanout.v sim/tb_scanout.v && vvp /tmp/tb_scanout.vvp

`timescale 1ns/1ps
module tb_scanout_arb;
    reg clk_32 = 0, clk_pixel = 0, reset = 1;
    reg stpal_we = 0;
    reg [3:0] stpal_wa = 0;
    reg [11:0] stpal_wd = 0;
    always #15.625 clk_32 = ~clk_32;     // 32 MHz
    always #19.841 clk_pixel = ~clk_pixel; // 25.2 MHz

    // 4 plane words for native line 0, group 0: index = bit 15..0 of each plane
    // pw0 = 16'h8000 -> pixel 0 index 1, rest 0; others 0 => pixels: 1,0,0,...
    reg [15:0] mem [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) mem[i] = 16'd0;
        mem[0] = 16'hFFFF; mem[1] = 16'hFFFF; mem[2] = 16'hFFFF; mem[3] = 16'h0000;
        // line 1 at word 160 (linebytes=320)
        mem[160] = 16'h4000; // pixel 1 index 1
        mem[161] = 16'd0; mem[162] = 16'd0; mem[163] = 16'd0;
    end

    wire ram_req, ram_rd2;
    wire [23:1] ram_a;
    reg ram_ack = 0;
    reg [15:0] ram_q = 0, ram_q2 = 0;
    reg [2:0] ph = 0; reg busy = 0; reg [23:1] la;
    always @(posedge clk_32) begin
        ph <= ph + 3'd1;
        if (ram_ack && !ram_req) ram_ack <= 1'b0;
        if (ph == 3'd7) begin busy <= ram_req && !ram_ack; la <= ram_a; end
        if (ph == 3'd6 && busy) begin
            ram_q <= mem[la]; ram_q2 <= mem[la + 23'd1]; ram_ack <= 1'b1; busy <= 1'b0;
        end
    end

    wire [9:0] cx, cy;
    wire hsync, vsync, de;
    wire [7:0] vr, vg, vb;
    wire vbl, hbl, underrun;
    wire [23:0] vcount;

    falcon_scanout dut (
        .clk_32(clk_32), .clk_pixel(clk_pixel), .reset(reset),
        .fb_base(24'h000000), .planes(4'd4), .st_shifter(1'b1), .hdbl(1'b0), .vdbl(1'b0),
        .height(10'd480), .linebytes(12'd320),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .fpal_we(1'b0), .fpal_wa(8'd0), .fpal_wd(18'd0),
        .ram_req(ram_req), .ram_rd2(ram_rd2), .ram_a(ram_a),
        .ram_ack(ram_ack), .ram_q(ram_q), .ram_q2(ram_q2),
        .cx(cx), .cy(cy), .hsync(hsync), .vsync(vsync), .de(de),
        .vr(vr), .vg(vg), .vb(vb),
        .vbl(vbl), .hbl(hbl), .vcount(vcount), .underrun(underrun)
    );

    // ST palette index 1 = 0x0F00 (red nibble) after we poke it via force after reset
    initial begin
        #200 reset = 0;
        // write pal[1] = 12'hF00 through the port: generate a we pulse in clk_32
    end

    // palette programmed after reset
    initial begin
        wait (reset == 0);
        @(posedge clk_32);
        stpal_we = 1'b1; stpal_wa = 4'd7; stpal_wd = 12'h0F0;
        @(posedge clk_32);
        stpal_we = 1'b0;
    end

    integer saw_red, saw_black, errors;
    initial begin
        saw_red = 0; saw_black = 0; errors = 0;
        // run 2 frames worth
        wait (reset == 0);
        wait (cy == 10'd0 && cx == 10'd1);
        wait (cy == 10'd2); // after line 0 and 1 have been displayed at least once? line 0 fetched at cy=524
        // actually after reset we start cy=0; first frame line 0 may be blank. Wait until second frame.
        wait (cy == 10'd524);
        wait (cy == 10'd0);
        wait (cx == 10'd0);
        // now line 0 should be in the buffer; sample during this line
        wait (cx == 10'd4);
        $display("cy=%0d cx=%0d rgb=%02x%02x%02x de=%0d underrun=%0d", cy, cx, vr, vg, vb, de, underrun);
        // pixel 0 should be red FF0000 (F nibble replicated), pixels 1+ black
        // but 2-cycle pipeline + hdmi contract: at cx=0 q2 is pixel 0
        // sample a few pixels by recording at each cx
    end

    reg [23:0] pixmem [0:15];
    integer k;
    initial begin
        wait (reset == 0);
        // wait second frame line 0
        wait (cy == 10'd524);
        wait (cy == 10'd0);
        for (k = 0; k < 16; k = k + 1) begin
            wait (cx == k[9:0]);
            @(posedge clk_pixel);
            pixmem[k] = {vr, vg, vb};
        end
        $display("pixels:");
        for (k = 0; k < 16; k = k + 1)
            $display("  x=%0d rgb=%06x", k, pixmem[k]);
        if (pixmem[0] != 24'h00FF00) begin
            $display("FAIL pixel0 expected 00FF00 (pal 7) got %06x", pixmem[0]);
            errors = errors + 1;
        end
        for (k = 1; k < 16; k = k + 1) begin
            if (pixmem[k] != 24'h00FF00) begin
                $display("FAIL pixel%0d expected 00FF00 got %06x", k, pixmem[k]);
                errors = errors + 1;
            end
        end
        if (underrun) begin
            $display("FAIL underrun set");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS 4-plane group 0");
        else $display("FAIL %0d errors", errors);
        $finish;
    end

    initial begin
        #20000000;
        $display("TIMEOUT cy=%0d cx=%0d", cy, cx);
        $finish;
    end
endmodule
