// video_testpattern_640.v - FalconFPGA stage 1 HDMI bring-up
//
// Standalone 640x480@60 (CEA-861 VIC 1) timing generator plus a colour-bar
// test pattern. Runs on the 25.2 MHz pixel clock.
//
//   total 800 x 525
//   H: active 640, front porch 16, sync 96, back porch 48  (sync negative)
//   V: active 480, front porch 10, sync  2, back porch 33  (sync negative)
//
// cx/cy are the coordinates of the pixel whose rgb/hsync_n/vsync_n/de are
// presented on the outputs in the same clock (all derived from the same
// registered counters), which is what hdmi_640 expects.
//
// vsync edges coincide with the hsync leading edge (CEA-861 / HDMI style,
// exactly like MiSTeryNano's hdmi.sv does it): vsync is asserted from
// cx=656 of line 489 to cx=656 of line 491, i.e. exactly 2 lines long,
// with 10 lines of front porch and 33 lines of back porch measured from
// the hsync leading edge.
//
// Pattern: 8 vertical 80 px bars at 75% amplitude (white, yellow, cyan,
// green, magenta, red, blue, black) plus an optional 1 px 100% white
// border around the 640x480 active area (overscan / timing check).

module video_testpattern_640 #(
    parameter BORDER = 1
) (
    input            clk,       // 25.2 MHz pixel clock
    input            rst,       // synchronous reset, active high

    output reg [9:0] cx,        // 0..799
    output reg [9:0] cy,        // 0..524
    output           hsync_n,
    output           vsync_n,
    output           de,
    output     [7:0] r,
    output     [7:0] g,
    output     [7:0] b
);

localparam H_ACT = 640, H_FP = 16, H_SY = 96, H_BP = 48;
localparam V_ACT = 480, V_FP = 10, V_SY = 2,  V_BP = 33;
localparam H_TOT = H_ACT + H_FP + H_SY + H_BP;   // 800
localparam V_TOT = V_ACT + V_FP + V_SY + V_BP;   // 525
localparam H_SS  = H_ACT + H_FP;                 // 656 hsync start
localparam H_SE  = H_ACT + H_FP + H_SY;          // 752 hsync end
localparam V_SS  = V_ACT + V_FP;                 // 490 vsync start line

always @(posedge clk) begin
    if (rst) begin
        cx <= 10'd0;
        cy <= 10'd0;
    end else if (cx == H_TOT-1) begin
        cx <= 10'd0;
        cy <= (cy == V_TOT-1) ? 10'd0 : cy + 10'd1;
    end else
        cx <= cx + 10'd1;
end

wire hs_act = (cx >= H_SS) && (cx < H_SE);
wire vs_act = ((cy == V_SS-1)      && (cx >= H_SS)) ||
              ((cy >= V_SS) && (cy < V_SS+V_SY-1))  ||
              ((cy == V_SS+V_SY-1) && (cx <  H_SS));

assign hsync_n = ~hs_act;
assign vsync_n = ~vs_act;
assign de      = (cx < H_ACT) && (cy < V_ACT);

// ---- pattern ----
localparam [7:0] LV = 8'd192;    // 75% bar level
wire border = (BORDER != 0) &&
              ((cx == 10'd0) || (cx == H_ACT-1) || (cy == 10'd0) || (cy == V_ACT-1));

reg [2:0] bar;   // 0..7
always @(*) begin
    if      (cx <  80) bar = 3'd0;
    else if (cx < 160) bar = 3'd1;
    else if (cx < 240) bar = 3'd2;
    else if (cx < 320) bar = 3'd3;
    else if (cx < 400) bar = 3'd4;
    else if (cx < 480) bar = 3'd5;
    else if (cx < 560) bar = 3'd6;
    else               bar = 3'd7;
end

// bar -> {R,G,B} on/off: white, yellow, cyan, green, magenta, red, blue, black
reg [2:0] rgb_on;
always @(*) begin
    case (bar)
        3'd0: rgb_on = 3'b111;   // white
        3'd1: rgb_on = 3'b110;   // yellow
        3'd2: rgb_on = 3'b011;   // cyan
        3'd3: rgb_on = 3'b010;   // green
        3'd4: rgb_on = 3'b101;   // magenta
        3'd5: rgb_on = 3'b100;   // red
        3'd6: rgb_on = 3'b001;   // blue
        default: rgb_on = 3'b000; // black
    endcase
end

assign r = !de ? 8'd0 : border ? 8'd255 : (rgb_on[2] ? LV : 8'd0);
assign g = !de ? 8'd0 : border ? 8'd255 : (rgb_on[1] ? LV : 8'd0);
assign b = !de ? 8'd0 : border ? 8'd255 : (rgb_on[0] ? LV : 8'd0);

endmodule
