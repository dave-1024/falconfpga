// hdmi_testpattern_640.sv - FalconFPGA stage 1 HDMI bring-up
//
// Standalone 640x480@60 HDMI output (CEA VIC 1, 4:3, 25.2 MHz pixel clock)
// showing colour bars, completely independent of the Atari ST core.
//
//   clk (50 MHz) -> gowin_pll_hdmi -> 126 MHz (TMDS 5x clock, OSER10 FCLK)
//                                  -> CLKDIV /5 -> 25.2 MHz pixel clock
//
// The TMDS encoding uses the MiSTeryNano hdmi/ core (via hdmi_640, with
// HDMI data islands, AVI/SPD/audio InfoFrames and 48 kHz audio), the same
// Gowin OSER10 serializers and the same ELVDS_OBUF output buffers as
// tang/nano20k/video2hdmi.v, so the pins/IO standard are unchanged.
//
// Audio: a quiet 1 kHz test tone, beeping 0.5 s on / 0.5 s off
// (set AUDIO_TONE = 0 for silence). HDMI mode only.
//
// DVI_OUTPUT = 1: plain DVI 1.0 TMDS (video + control periods only, no data
// islands / preambles / guard bands, CTL bits 0), for DVI-only sinks such as
// a monitor on a DVI input via a DVI-to-HDMI cable. No audio in this mode
// (the audio logic is optimised away). DVI_OUTPUT = 0: full HDMI with audio.

module hdmi_testpattern_640 #(
    parameter DVI_OUTPUT = 0,
    parameter AUDIO_TONE = 1
) (
    input        clk,          // 50 MHz board clock

    output       hdmi_lock,    // HDMI PLL locked (for debug/LEDs)

    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

// ------------------------------ clocks ------------------------------
wire clk_pixel_x5;   // 126 MHz
wire clk_pixel;      // 25.2 MHz
wire pll_lock;

gowin_pll_hdmi pll_hdmi640 (
    .clkin    ( clk          ),
    .init_clk ( clk          ),
    .clkout0  ( clk_pixel_x5 ),   // 126 MHz
    .lock     ( pll_lock     )
);

CLKDIV #(.DIV_MODE("5")) clkdiv_hdmi640 (
    .HCLKIN ( clk_pixel_x5 ),
    .RESETN ( 1'b1         ),
    .CALIB  ( 1'b0         ),
    .CLKOUT ( clk_pixel    )
);

assign hdmi_lock = pll_lock;

// pixel-domain reset: synchronise the PLL lock (init_clk domain) and hold
// reset for another 255 pixel clocks after lock
reg [1:0] lock_sync = 2'b00;
reg [7:0] rst_cnt = 8'd0;
always @(posedge clk_pixel) begin
    lock_sync <= { lock_sync[0], pll_lock };
    if (!lock_sync[1])
        rst_cnt <= 8'd0;
    else if (rst_cnt != 8'hff)
        rst_cnt <= rst_cnt + 8'd1;
end
wire pix_rst = (rst_cnt != 8'hff);

// ------------------------- timing + pattern -------------------------
wire [9:0] cx, cy;
wire       hsync_n, vsync_n, de;
wire [7:0] r, g, b;

video_testpattern_640 #(.BORDER(1)) testpattern (
    .clk     ( clk_pixel ),
    .rst     ( pix_rst   ),
    .cx      ( cx        ),
    .cy      ( cy        ),
    .hsync_n ( hsync_n   ),
    .vsync_n ( vsync_n   ),
    .de      ( de        ),
    .r       ( r         ),
    .g       ( g         ),
    .b       ( b         )
);

// ------------------------------ audio -------------------------------
// 48 kHz audio clock: 25.2 MHz / 525 = 48000 Hz exactly
reg [9:0] aclk_cnt = 10'd0;
reg       clk_audio = 1'b0;
always @(posedge clk_pixel) begin
    if (aclk_cnt == 10'd524) aclk_cnt <= 10'd0;
    else                     aclk_cnt <= aclk_cnt + 10'd1;
    clk_audio <= (aclk_cnt < 10'd262);
end

// 1 kHz square wave (toggle every 24 samples), gated 0.5 s on / 0.5 s off,
// amplitude +/-2048 (about -24 dBFS)
reg [4:0]  tone_cnt = 5'd0;
reg        tone_ph  = 1'b0;
reg [15:0] gate_cnt = 16'd0;
reg        gate     = 1'b0;
always @(posedge clk_audio) begin
    if (tone_cnt == 5'd23) begin
        tone_cnt <= 5'd0;
        tone_ph  <= ~tone_ph;
    end else
        tone_cnt <= tone_cnt + 5'd1;

    if (gate_cnt == 16'd23999) begin
        gate_cnt <= 16'd0;
        gate     <= ~gate;
    end else
        gate_cnt <= gate_cnt + 16'd1;
end

wire [15:0] sample = (AUDIO_TONE != 0 && gate) ? (tone_ph ? 16'h0800 : 16'hF800) : 16'h0000;
wire [15:0] audio_word [1:0];
assign audio_word[0] = sample;
assign audio_word[1] = sample;

// ----------------------------- encoder ------------------------------
wire [2:0] tmds;
wire       tmds_clock;

hdmi_640 #(
    .DVI_OUTPUT(DVI_OUTPUT != 0),
    .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME( { "MiSTle", 16'd0} ),
    .PRODUCT_DESCRIPTION( {"TC138K 640x480", 16'd0} )
) hdmi (
    .clk_pixel_x5      ( clk_pixel_x5 ),
    .clk_pixel         ( clk_pixel    ),
    .clk_audio         ( clk_audio    ),
    .reset             ( pix_rst      ),
    .cx                ( cx           ),
    .cy                ( cy           ),
    .hsync             ( hsync_n      ),
    .vsync             ( vsync_n      ),
    .rgb               ( { r, g, b }  ),
    .audio_sample_word ( audio_word   ),
    .tmds              ( tmds         ),
    .tmds_clock        ( tmds_clock   )
);

// differential output, identical to tang/nano20k/video2hdmi.v
ELVDS_OBUF tmds_bufds [3:0] (
    .I  ( { tmds_clock, tmds }     ),
    .O  ( { tmds_clk_p, tmds_d_p } ),
    .OB ( { tmds_clk_n, tmds_d_n } )
);

endmodule
