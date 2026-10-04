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
//
// Stage 2: ST_VIDEO = 1 (default) shows the Atari ST video through a BSRAM
// frame buffer (st_framebuffer.v: capture in the clk32 domain, scan-out at
// 25.2 MHz, 2 clocks of pipeline delay compensated here). ST_VIDEO = 0 shows
// the colour bars as in stage 1 (the st_* inputs are then unused).

module hdmi_testpattern_640 #(
    parameter DVI_OUTPUT = 0,
    parameter AUDIO_TONE = 1,
    parameter ST_VIDEO   = 1,     // 1 = ST frame buffer, 0 = colour bars
    // ST capture window tuning (see st_framebuffer.v)
    parameter ST_H_OFS_COLOR = 96,  // clk32 from DE rise to 1st colour sample
    parameter ST_H_OFS_MONO  = 64,  // clk32 from DE rise to 1st mono pixel
    parameter ST_V_BORDER    = 20,  // colour border lines above the picture
    // FalconFPGA DIAG build (top.sv `define DIAG_OVERLAY), both 0 = normal:
    parameter DIAG_OVERLAY   = 0,   // 1 = draw diag_overlay status squares
    parameter FB_SELFTEST    = 0    // 1 = frame buffer fed by diag_fake_st
) (
    input        clk,          // 50 MHz board clock

    // raw ST video from the core (clk32 domain), used if ST_VIDEO = 1
    input        clk32,
    input        st_hs_n,
    input        st_vs_n,
    input        st_de,
    input  [3:0] st_r,
    input  [3:0] st_g,
    input  [3:0] st_b,

    output       hdmi_lock,    // HDMI PLL locked (for debug/LEDs)

    // DIAG build only (tie to 0 / leave open otherwise), see diag_overlay.v
    input [19:0] diag_now,     // per square "now" (clk32 domain, slow)
    input [19:0] diag_ever,    // per square "ever" (clk32 domain, slow)
    input        diag_vs_blink,
    input        diag_hs_blink,
    input [15:0] diag_word,    // first TOS word
    input [191:0] diag_rows,   // diag030c: 6 bit-bar rows a..f, 32 bits each (slow)
    output       diag_fb_we,   // frame buffer write enable (clk32 domain)

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

// ------------------------ ST frame buffer ---------------------------
// v_* = what goes to the encoder: either the colour bars directly or the
// frame buffer output with cx/cy/syncs delayed to match the RAM latency
wire [9:0] v_cx, v_cy;
wire       v_hsync_n, v_vsync_n;
wire [7:0] v_r, v_g, v_b;

generate if (ST_VIDEO != 0) begin : g_stfb
    wire        fb_we;
    wire [17:0] fb_waddr, fb_raddr;
    wire [11:0] fb_wdata, fb_rdata;
    wire        fb_mono;

    // DIAG FB_SELFTEST: replace the real ST video at the capture input by a
    // locally generated fake ST picture (clk32). Shows if buffer + read work.
    wire        c_hs_n, c_vs_n, c_de;
    wire [11:0] c_rgb;
    if (FB_SELFTEST != 0) begin : g_selftest
        diag_fake_st fake ( .clk(clk32), .hs_n(c_hs_n), .vs_n(c_vs_n),
                            .de(c_de), .rgb(c_rgb) );
    end else begin : g_realst
        assign c_hs_n = st_hs_n;  assign c_vs_n = st_vs_n;
        assign c_de   = st_de;    assign c_rgb  = { st_r, st_g, st_b };
    end
    assign diag_fb_we = fb_we;

    st_fb_capture #(
        .H_OFS_COLOR ( ST_H_OFS_COLOR ),
        .H_OFS_MONO  ( ST_H_OFS_MONO  ),
        .V_BORDER    ( ST_V_BORDER    )
    ) capture (
        .clk   ( clk32    ),
        .hs_n  ( c_hs_n   ),
        .vs_n  ( c_vs_n   ),
        .de    ( c_de     ),
        .r     ( c_rgb[11:8] ),
        .g     ( c_rgb[7:4]  ),
        .b     ( c_rgb[3:0]  ),
        .we    ( fb_we    ),
        .waddr ( fb_waddr ),
        .wdata ( fb_wdata ),
        .mono  ( fb_mono  )
    );

    st_fb_ram fbram (
        .wclk  ( clk32     ),
        .we    ( fb_we     ),
        .waddr ( fb_waddr  ),
        .wdata ( fb_wdata  ),
        .rclk  ( clk_pixel ),
        .raddr ( fb_raddr  ),
        .rdata ( fb_rdata  )
    );

    st_fb_scanout640 scanout (
        .clk        ( clk_pixel ),
        .mono_async ( fb_mono   ),
        .cx_in      ( cx        ),
        .cy_in      ( cy        ),
        .hs_in      ( hsync_n   ),
        .vs_in      ( vsync_n   ),
        .raddr      ( fb_raddr  ),
        .rdata      ( fb_rdata  ),
        .cx         ( v_cx      ),
        .cy         ( v_cy      ),
        .hs         ( v_hsync_n ),
        .vs         ( v_vsync_n ),
        .r          ( v_r       ),
        .g          ( v_g       ),
        .b          ( v_b       )
    );
end else begin : g_bars
    assign v_cx = cx;           assign v_cy = cy;
    assign v_hsync_n = hsync_n; assign v_vsync_n = vsync_n;
    assign v_r = r;             assign v_g = g;   assign v_b = b;
    assign diag_fb_we = 1'b0;
end endgenerate

// ----------------- DIAG status overlay (after the buffer) ----------------
wire [7:0] o_r, o_g, o_b;
generate if (DIAG_OVERLAY != 0) begin : g_diag
    diag_overlay overlay (
        .clk            ( clk_pixel     ),
        .cx             ( v_cx          ),
        .cy             ( v_cy          ),
        .r_in           ( v_r           ),
        .g_in           ( v_g           ),
        .b_in           ( v_b           ),
        .now_async      ( diag_now      ),
        .ever_async     ( diag_ever     ),
        .vs_blink_async ( diag_vs_blink ),
        .hs_blink_async ( diag_hs_blink ),
        .word_async     ( diag_word     ),
        .rows_async     ( diag_rows     ),
        .r              ( o_r           ),
        .g              ( o_g           ),
        .b              ( o_b           )
    );
end else begin : g_nodiag
    assign o_r = v_r;  assign o_g = v_g;  assign o_b = v_b;
end endgenerate

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
    .cx                ( v_cx         ),
    .cy                ( v_cy         ),
    .hsync             ( v_hsync_n    ),
    .vsync             ( v_vsync_n    ),
    .rgb               ( { o_r, o_g, o_b } ),
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
