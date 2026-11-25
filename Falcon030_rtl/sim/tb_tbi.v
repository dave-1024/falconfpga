// tb_tbi.v - FB-1: Timer B event-count split position (FrontBench panel split).
// ST low (4 planes, 200 lines, vdbl). At VBL rise the "program" arms a count of N=168
// on the selected TBI source (falling edges, AER=0); LAT ns after the Nth edge it writes
// ST palette 0 (blue -> grey). Prints the first HDMI row that shows grey at x=8 and x=632.
// Expected (ST): native line 168 = row vtop(40)+336 = 376, no partial row.
//   iverilog -g2012 -DSRC_TB -DLAT=15000 -o /tmp/tbi.vvp hdl/video/falcon_sdp_ram.v \
//     hdl/video/falcon_scanout.v sim/tb_tbi.v && vvp /tmp/tbi.vvp
`timescale 1ns/1ps
module tb_tbi;
`ifndef LAT
 `define LAT 15000
`endif
    reg clk_32 = 0, clk_pixel = 0, reset = 1;
    reg stpal_we = 0; reg [3:0] stpal_wa = 0; reg [11:0] stpal_wd = 0;
    always #15.625 clk_32 = ~clk_32;
    always #19.841 clk_pixel = ~clk_pixel;
    wire ram_req, ram_rd2; wire [23:1] ram_a;
    reg ram_ack = 0;
    always @(posedge clk_32) ram_ack <= ram_req && !ram_ack;
    wire [9:0] cx, cy; wire hsync, vsync, de; wire [7:0] vr, vg, vb;
    wire vbl, hbl, tb_de, underrun; wire [23:0] vcount;
    falcon_scanout dut (
        .clk_32(clk_32), .clk_pixel(clk_pixel), .reset(reset),
        .fb_base(24'h0), .planes(4'd4), .st_shifter(1'b1), .hdbl(1'b1), .vdbl(1'b1),
        .height(10'd200), .linebytes(12'd160),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .fpal_we(1'b0), .fpal_wa(8'd0), .fpal_wd(18'd0),
        .ram_req(ram_req), .ram_rd2(ram_rd2), .ram_a(ram_a),
        .ram_ack(ram_ack), .ram_q(16'd0), .ram_q2(16'd0),
        .cx(cx), .cy(cy), .hsync(hsync), .vsync(vsync), .de(de), .vr(vr), .vg(vg), .vb(vb),
        .vbl(vbl), .hbl(hbl), .tb_de(tb_de), .vcount(vcount), .underrun(underrun));
`ifdef SRC_TB
    wire tbi = tb_de;
`else
    wire tbi = hbl;
`endif
    task wpal(input [11:0] v); begin
        @(posedge clk_32); stpal_we = 1; stpal_wa = 0; stpal_wd = v;
        @(posedge clk_32); stpal_we = 0; end endtask
    reg tbi_d = 0, vbl_d = 0; integer cnt = 0, frames = 0, nev = 0;
    always @(posedge clk_32) begin
        tbi_d <= tbi; vbl_d <= vbl;
        if (vbl && !vbl_d) begin cnt <= 0; frames <= frames + 1; end
        else if (!tbi && tbi_d) begin cnt <= cnt + 1; nev <= nev + 1; end
    end
    always @(posedge clk_32) if (vbl && !vbl_d && frames >= 1)
        $display("frame %0d: TBI falling edges in previous frame = %0d", frames, cnt);
    initial begin
        #200 reset = 0;
        forever begin
            @(posedge vbl); wpal(12'h00F);
            wait (cnt == 168);
            $display("  168th edge at cy=%0d cx=%0d", cy, cx);
            #(`LAT) wpal(12'h888);
            $display("  palette write at cy=%0d cx=%0d", cy, cx);
        end
    end
    reg got_l = 0, got_r = 0;
    always @(posedge clk_pixel) if (frames == 3) begin
        if (cy == 0) begin got_l <= 0; got_r <= 0; end
        if (de && cx == 8   && !got_l && vr != 0) begin got_l <= 1; $display("  first grey row at x=8:   %0d (native %0d)", cy, (cy-40)/2); end
        if (de && cx == 632 && !got_r && vr != 0) begin got_r <= 1; $display("  first grey row at x=632: %0d", cy); end
    end
    always @(posedge clk_pixel) if (frames == 3 && cy >= 372 && cy <= 377 && (cx == 8 || cx == 320 || cx == 632))
        $display("    row %0d x %0d: r=%0d", cy, cx, vr);
    initial begin #(4*16_700_000); $finish; end
endmodule
