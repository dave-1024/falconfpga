// st_framebuffer.v - FalconFPGA stage 2: Atari ST video -> 640x480@60
//
// Captures the raw ST video of the core (clk32 domain, before the
// scandoubler/OSD, so no OSD) into an on-chip BSRAM frame buffer and reads
// it back in the 25.2 MHz pixel domain of the 640x480@60 output
// (hdmi_testpattern_640). Single buffer, no frame locking: the ST runs at
// 50/60/71 Hz, the output at 60 Hz, so some tearing is expected.
//
//   st_fb_capture    (clk32)  : ST timing analysis + 640 samples per line
//   st_fb_ram        (2 clks) : 153600 x 12 bit simple dual port BSRAM
//   st_fb_scanout640 (25.2MHz): address generation + pixel formatting
//
// Buffer layout (12 bit words, {r[3:0],g[3:0],b[3:0]}):
//   colour (low/medium res): 240 lines x 640 samples, word = line*640 + x.
//     One sample every second clk32 (16 MHz) during the active line, so a
//     medium res pixel is one sample and a low res pixel two samples.
//     The window is 20 lines of top border + 200 active lines + 20 lines of
//     bottom border (border colour visible there). Horizontally exactly the
//     640 (medium res) pixel active area, i.e. no side borders.
//     Scan-out doubles every line: 240 -> 480 lines (full screen).
//   mono (high res): 400 lines x 80 words, word = line*80 + x/8, 8 pixels
//     per word in bits [7:0] (bit 7 = leftmost). Scan-out 1:1, centred with
//     40 black lines above and below.
//
// Timing of the ST video at the misterynano level (measured by simulating
// gstmcu + gstshifter; h counted in clk32 from the hsync falling edge):
//            line  lines  DE rise  DE len  1st DE line  1st pixel after DE
//   PAL     2048   313     432     1280       66        low +96, mid +91
//   NTSC    2032   263     416     1280       37        low +96, mid +91
//   mono     896   501     160      640       37        +64 (1 px / clk)
// The capture measures the DE position and the first DE line itself every
// frame, so it follows PAL/NTSC/mono automatically; only the pixel latency
// after DE is a parameter (H_OFS_COLOR / H_OFS_MONO).
//
// Mono is detected from the hsync period (< 1400 clk32 = 71 Hz monitor).

// ---------------------------------------------------------------------------
module st_fb_capture #(
    // clk32 cycles from the DE rising edge to the first pixel. 96 is exact
    // for low res; medium res starts at +91, so with 96 the leftmost 2
    // medium res pixels are lost and 2 border pixels appear on the right
    // (use 92 for an exact medium res window, low res then shows one low
    // res pixel of border on the left and loses its last pixel).
    parameter H_OFS_COLOR = 96,
    parameter H_OFS_MONO  = 64,
    // colour: number of border lines captured above the first DE line
    // (the window is always 240 lines: V_BORDER + 200 + (40 - V_BORDER))
    parameter V_BORDER    = 20
) (
    input             clk,        // clk32
    input             hs_n,
    input             vs_n,
    input             de,
    input      [3:0]  r,
    input      [3:0]  g,
    input      [3:0]  b,

    output reg        we = 1'b0,
    output reg [17:0] waddr = 18'd0,
    output reg [11:0] wdata = 12'd0,
    output reg        mono = 1'b0      // current frame is mono (clk32 domain)
);

localparam COLOR_LINES = 240;
localparam MONO_LINES  = 400;

// register the inputs once (all by the same amount, so relative timing is
// unchanged); they come from the core in the same clock domain
reg        s_hs = 1'b1, s_vs = 1'b1, s_de = 1'b0;
reg [11:0] s_rgb = 12'd0;
reg        s_hs_d = 1'b1, s_vs_d = 1'b1, s_de_d = 1'b0;
always @(posedge clk) begin
    s_hs  <= hs_n;  s_vs  <= vs_n;  s_de  <= de;
    s_rgb <= { r, g, b };
    s_hs_d <= s_hs; s_vs_d <= s_vs; s_de_d <= s_de;
end
wire hs_fall = s_hs_d & ~s_hs;
wire vs_fall = s_vs_d & ~s_vs;
wire de_rise = ~s_de_d & s_de;

// line / frame counters
reg [11:0] hcnt = 12'd0;          // clk32 since hsync fall
reg  [9:0] vcnt = 10'd0;          // lines since vsync fall
reg        mono_line = 1'b0;      // last line was short (mono)

// per frame measurement (current frame) and latched values (used)
reg        de_seen = 1'b0;
reg [11:0] de_h_cur = 12'd432;
reg  [9:0] de_v_cur = 10'd66;
reg [11:0] de_h = 12'd432;        // DE rising edge position in the line
reg  [9:0] win_v = 10'd46;        // first captured line
reg [11:0] start_h = 12'd528;     // hcnt of the first sample

// capture state
reg        cap = 1'b0;            // capturing a line
reg        ph = 1'b0;             // colour: sample phase (every 2nd clk)
reg  [9:0] xcnt = 10'd0;          // samples (colour) / words (mono) done
reg  [2:0] bcnt = 3'd0;           // mono bit counter
reg  [7:0] sreg = 8'd0;           // mono shift register
reg  [9:0] lcnt = 10'd0;          // lines captured this frame
reg [17:0] line_base = 18'd0;
reg [17:0] addr = 18'd0;

always @(posedge clk) begin
    we <= 1'b0;

    // ---- counters ----
    if (hs_fall) begin
        hcnt      <= 12'd0;
        vcnt      <= vcnt + 10'd1;
        mono_line <= (hcnt < 12'd1400);
    end else if (hcnt != 12'hfff)
        hcnt <= hcnt + 12'd1;

    if (de_rise) begin
        de_h_cur <= hcnt;
        if (!de_seen) begin
            de_seen  <= 1'b1;
            de_v_cur <= vcnt;
        end
    end

    // ---- new frame ----
    if (vs_fall) begin
        vcnt      <= 10'd0;
        lcnt      <= 10'd0;
        line_base <= 18'd0;
        cap       <= 1'b0;
        de_seen   <= 1'b0;
        mono      <= mono_line;
        if (de_seen) begin    // keep the previous values if DE was absent
            de_h    <= de_h_cur;
            start_h <= de_h_cur + (mono_line ? H_OFS_MONO : H_OFS_COLOR);
            if (mono_line)
                win_v <= de_v_cur;
            else
                win_v <= (de_v_cur >= V_BORDER) ? de_v_cur - V_BORDER : 10'd0;
        end
    end else if (!cap) begin
        // ---- start of a captured line ----
        if (hcnt == start_h && vcnt >= win_v &&
            lcnt < (mono ? MONO_LINES : COLOR_LINES)) begin
            cap  <= 1'b1;
            addr <= line_base;
            xcnt <= 10'd0;
            bcnt <= 3'd0;
            // first sample is taken in this very clock
            if (mono) begin
                sreg <= { 7'd0, s_rgb[11] };
                bcnt <= 3'd1;
                ph   <= 1'b0;
            end else begin
                we    <= 1'b1;
                waddr <= line_base;
                wdata <= s_rgb;
                addr  <= line_base + 18'd1;
                xcnt  <= 10'd1;
                ph    <= 1'b1;
            end
        end
    end else begin
        // ---- capturing ----
        if (mono) begin
            sreg <= { sreg[6:0], s_rgb[11] };
            bcnt <= bcnt + 3'd1;
            if (bcnt == 3'd7) begin
                we    <= 1'b1;
                waddr <= addr;
                wdata <= { 4'd0, sreg[6:0], s_rgb[11] };
                addr  <= addr + 18'd1;
                xcnt  <= xcnt + 10'd1;
                if (xcnt == 10'd79) begin
                    cap       <= 1'b0;
                    lcnt      <= lcnt + 10'd1;
                    line_base <= line_base + 18'd80;
                end
            end
        end else begin
            ph <= ~ph;
            if (!ph) begin
                we    <= 1'b1;
                waddr <= addr;
                wdata <= s_rgb;
                addr  <= addr + 18'd1;
                xcnt  <= xcnt + 10'd1;
                if (xcnt == 10'd639) begin
                    cap       <= 1'b0;
                    lcnt      <= lcnt + 10'd1;
                    line_base <= line_base + 18'd640;
                end
            end
        end
    end
end

endmodule

// ---------------------------------------------------------------------------
// simple dual port RAM, independent write and read clocks, registered read.
// Written so that Gowin synthesis infers BSRAM (SDPB).
module st_fb_ram #(
    parameter DEPTH = 153600,
    parameter AW    = 18,
    parameter DW    = 12
) (
    input               wclk,
    input               we,
    input      [AW-1:0] waddr,
    input      [DW-1:0] wdata,
    input               rclk,
    input      [AW-1:0] raddr,
    output reg [DW-1:0] rdata
);

reg [DW-1:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle = "block_ram" */;

always @(posedge wclk)
    if (we) mem[waddr] <= wdata;

always @(posedge rclk)
    rdata <= mem[raddr];

endmodule

// ---------------------------------------------------------------------------
// 25.2 MHz side: address generation from the 640x480 timing (cx/cy), 2 clock
// latency (address register + RAM output register). cx/cy/syncs are delayed
// by the same 2 clocks so they stay aligned with the pixel data.
module st_fb_scanout640 #(
    parameter MONO_TOP = 40           // first output line of the mono image
) (
    input             clk,            // 25.2 MHz
    input             mono_async,     // from the clk32 domain

    input       [9:0] cx_in,
    input       [9:0] cy_in,
    input             hs_in,
    input             vs_in,

    output reg [17:0] raddr = 18'd0,
    input      [11:0] rdata,

    output reg  [9:0] cx = 10'd0,
    output reg  [9:0] cy = 10'd0,
    output reg        hs = 1'b1,
    output reg        vs = 1'b1,
    output      [7:0] r,
    output      [7:0] g,
    output      [7:0] b
);

// synchronise the mode flag (changes only at ST frame boundaries)
(* ASYNC_REG = "TRUE" *) reg [1:0] mono_sync = 2'b00;
always @(posedge clk) mono_sync <= { mono_sync[0], mono_async };
wire mono = mono_sync[1];

// stage 0 -> 1: address
wire [9:0] my   = cy_in - MONO_TOP;
wire [8:0] line = cy_in[9:1];
wire [17:0] caddr = { line, 9'd0 } + { 2'd0, line, 7'd0 } + { 8'd0, cx_in };
wire [17:0] maddr = { 3'd0, my[8:0], 6'd0 } + { 5'd0, my[8:0], 4'd0 } + { 11'd0, cx_in[9:3] };
wire in_act  = (cx_in < 10'd640) && (cy_in < 10'd480);
wire in_mono = in_act && (cy_in >= MONO_TOP) && (cy_in < MONO_TOP + 400);

reg        mono1 = 1'b0, mono2 = 1'b0;
reg        vis1 = 1'b0,  vis2 = 1'b0;
reg  [2:0] bit1 = 3'd0,  bit2 = 3'd0;
reg  [9:0] cx1 = 10'd0,  cy1 = 10'd0;
reg        hs1 = 1'b1,   vs1 = 1'b1;

always @(posedge clk) begin
    // stage 1
    raddr <= mono ? maddr : caddr;
    mono1 <= mono;
    vis1  <= mono ? in_mono : in_act;
    bit1  <= cx_in[2:0];
    cx1 <= cx_in;  cy1 <= cy_in;  hs1 <= hs_in;  vs1 <= vs_in;
    // stage 2 (rdata valid)
    mono2 <= mono1;
    vis2  <= vis1;
    bit2  <= bit1;
    cx <= cx1;  cy <= cy1;  hs <= hs1;  vs <= vs1;
end

wire       mpix = rdata[3'd7 - bit2];
wire [3:0] r4 = !vis2 ? 4'd0 : mono2 ? {4{mpix}} : rdata[11:8];
wire [3:0] g4 = !vis2 ? 4'd0 : mono2 ? {4{mpix}} : rdata[7:4];
wire [3:0] b4 = !vis2 ? 4'd0 : mono2 ? {4{mpix}} : rdata[3:0];
assign r = { r4, r4 };
assign g = { g4, g4 };
assign b = { b4, b4 };

endmodule
