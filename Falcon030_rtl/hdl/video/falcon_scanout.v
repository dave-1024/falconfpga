// falcon_scanout.v - FAL_01: port of Hybrid030 falcon_video.v onto the SDRAM arbiter + ST HDMI
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decode-on-fetch line buffer from Hybrid030 falcon_video.v v6.2: the clk_32
// side fetches one native line through falcon_sdram_arb.v, then decodes it
// into a 640-wide RGB888 ping-pong buffer; the clk_pixel side is a linear
// reader at 640x480@60 (CEA VIC 1). Mailbox parse and DDR3 lane-5 bursts are
// dropped; geometry comes from videl_regs.v (the same fields the mailbox
// carried: fb_base, planes, hdbl, vdbl, height, linebytes, palettes).
//
// Guard: linebytes == 0 or > 640 yields black (Hybrid030 M11d / v6 header).
// v1 needs the TOS boot modes (640x480 4-plane VGA, ST modes doubled).
// A 640x480 4-plane line is 160 words = 40 us at one word/250 ns; the HDMI
// line is 31.8 us, so that mode underruns until a burst path is added.
module falcon_scanout (
    input  wire        clk_32,
    input  wire        clk_pixel,
    input  wire        reset,
    // geometry (videl_regs, clk_cpu / treated as false-path or loosely timed)
    input  wire [23:0] fb_base,
    input  wire [3:0]  planes,          // 0 = RGB565, 1/2/4/8 = bitplanes
    input  wire        hdbl, vdbl,
    input  wire [9:0]  height,          // native visible lines
    input  wire [11:0] linebytes,
    // ST palette write (from videl_regs, clk_cpu; sampled in clk_32)
    input  wire        stpal_we,
    input  wire [3:0]  stpal_wa,
    input  wire [11:0] stpal_wd,
    // Falcon palette write
    input  wire        fpal_we,
    input  wire [7:0]  fpal_wa,
    input  wire [17:0] fpal_wd,
    // SDRAM arbiter word port (clk_32)
    output reg         ram_req,
    output reg  [23:1] ram_a,
    input  wire        ram_ack,
    input  wire [15:0] ram_q,
    // HDMI 640x480 (clk_pixel)
    output reg  [9:0]  cx, cy,
    output wire        hsync, vsync, de,
    output wire [7:0]  vr, vg, vb,
    // interrupts / VIDEL counter (levels in clk_32, synced from pixel timing)
    output reg         vbl, hbl,
    output reg  [23:0] vcount,
    output reg         underrun
);
    // CEA VIC 1: 640x480@60, 25.2 MHz, negative syncs
    localparam [9:0] H_ACT = 10'd640, H_FP = 10'd16, H_SYNC = 10'd96, H_BP = 10'd48;
    localparam [9:0] H_TOT = 10'd800;
    localparam [9:0] V_ACT = 10'd480, V_FP = 10'd10, V_SYNC = 10'd2,  V_BP = 10'd33;
    localparam [9:0] V_TOT = 10'd525;

    // --------------- pixel timing ---------------
    wire hs_l = (cx >= (H_ACT+H_FP)) && (cx < (H_ACT+H_FP+H_SYNC));
    wire vs_l = (cy >= (V_ACT+V_FP)) && (cy < (V_ACT+V_FP+V_SYNC));
    assign hsync = ~hs_l;               // negative polarity
    assign vsync = ~vs_l;
    assign de    = (cx < H_ACT) && (cy < V_ACT);

    always @(posedge clk_pixel) begin
        if (reset) begin cx <= 10'd0; cy <= 10'd0; end
        else if (cx == H_TOT-10'd1) begin
            cx <= 10'd0;
            cy <= (cy == V_TOT-10'd1) ? 10'd0 : cy + 10'd1;
        end else cx <= cx + 10'd1;
    end

    // native line for this display row, centred in 480 if height*vdbl < 480
    wire [9:0] nlines = (height == 10'd0) ? 10'd480 : height;
    wire [9:0] disp_h = vdbl ? {nlines[8:0], 1'b0} : nlines;
    wire [9:0] vtop   = (disp_h >= V_ACT) ? 10'd0 : ((V_ACT - disp_h) >> 1);
    wire [9:0] vbot   = vtop + (disp_h >= V_ACT ? V_ACT : disp_h);
    wire       in_pic = (cy >= vtop) && (cy < vbot);
    wire [9:0] drow   = in_pic ? (cy - vtop) : 10'd0;
    wire [9:0] nline  = vdbl ? {1'b0, drow[9:1]} : drow;
    wire       need_fetch = in_pic && (!vdbl || !drow[0]);  // first of a doubled pair

    // request a native line: toggle in the pixel domain at the start of the
    // display row (a few pixels into HBLANK of the previous line so fetch
    // can run during the previous display line + blanking)
    reg        fetch_tgl;
    reg [9:0]  fetch_line;
    reg        fetch_odd;               // display-row parity -> rgbbuf select
    always @(posedge clk_pixel) begin
        if (reset) fetch_tgl <= 1'b0;
        else if (cx == (H_TOT-10'd8) && need_fetch) begin
            fetch_line <= (cy == V_TOT-10'd1) ? 10'd0 : (in_pic ? nline : 10'd0);
            // next row's parity: the row that starts after this HBLANK
            fetch_odd  <= (cy == V_TOT-10'd1) ? 1'b0 : (cy + 10'd1 - vtop); // 1-bit: row parity
            fetch_tgl  <= ~fetch_tgl;
        end
    end

    // --------------- clk_32: palettes, fetch, decode ---------------
    reg [11:0] pal [0:15];
    reg [17:0] fpal [0:255];
    integer pi;
    always @(posedge clk_32) begin
        if (reset) begin
            for (pi = 0; pi < 16; pi = pi + 1) pal[pi] <= 12'd0;
        end else if (stpal_we) pal[stpal_wa] <= stpal_wd;
    end
    always @(posedge clk_32) begin
        if (fpal_we) fpal[fpal_wa] <= fpal_wd;
    end

    reg [15:0] rawbuf [0:639];
    reg [23:0] rgbbuf0 [0:639];
    reg [23:0] rgbbuf1 [0:639];

    // CDC of the fetch toggle
    reg [2:0] tgl_s;
    always @(posedge clk_32) tgl_s <= {tgl_s[1:0], fetch_tgl};
    wire fetch_go = tgl_s[1] != tgl_s[2];

    // latched geometry for this line (guard insane transients)
    reg [23:0] base_l;
    reg [3:0]  planes_l;
    reg        hdbl_l, vdbl_l, odd_l, ok_l;
    reg [11:0] lb_l;
    reg [9:0]  nline_l;
    wire [11:0] lb_now = linebytes;
    wire        lb_ok  = (lb_now != 12'd0) && (lb_now <= 12'd640);

    localparam S_IDLE=0, S_FETCH=1, S_DEC=2, S_DEC2=3;
    reg [1:0]  st;
    reg [9:0]  widx, wmax, dcol, dcol_w;
    reg [23:1] line_a;
    reg        wrbuf;
    reg        busy_line;

    // decode helpers (same as falcon_video.v, but rawbuf is 16-bit BE words)
    wire [1:0] pshift = planes_l[3] ? 2'd3 : planes_l[2] ? 2'd2 :
                        (planes_l == 4'd2) ? 2'd1 : 2'd0;
    wire [9:0] dx     = hdbl_l ? {1'b0, dcol[9:1]} : dcol;
    wire [8:0] grp    = {4'd0, dx[9:4]};
    wire [3:0] pk     = dx[3:0];
    wire [8:0] wbase  = grp << pshift;
    wire [15:0] pw0   = rawbuf[wbase + 9'd0];
    wire [15:0] pw1   = rawbuf[wbase + 9'd1];
    wire [15:0] pw2   = rawbuf[wbase + 9'd2];
    wire [15:0] pw3   = rawbuf[wbase + 9'd3];
    wire [15:0] pw4   = rawbuf[wbase + 9'd4];
    wire [15:0] pw5   = rawbuf[wbase + 9'd5];
    wire [15:0] pw6   = rawbuf[wbase + 9'd6];
    wire [15:0] pw7   = rawbuf[wbase + 9'd7];
    wire [7:0] idx8   = { (planes_l>4'd7) ? pw7[15-pk] : 1'b0,
                          (planes_l>4'd6) ? pw6[15-pk] : 1'b0,
                          (planes_l>4'd5) ? pw5[15-pk] : 1'b0,
                          (planes_l>4'd4) ? pw4[15-pk] : 1'b0,
                          (planes_l>4'd3) ? pw3[15-pk] : 1'b0,
                          (planes_l>4'd2) ? pw2[15-pk] : 1'b0,
                          (planes_l>4'd1) ? pw1[15-pk] : 1'b0,
                          (planes_l>4'd0) ? pw0[15-pk] : 1'b0 };
    wire [15:0] tcw   = rawbuf[dx];
    wire [23:0] c565  = { tcw[15:11], tcw[15:13], tcw[10:5], tcw[10:9], tcw[4:0], tcw[4:2] };
    wire [11:0] p12   = pal[idx8[3:0]];
    wire [23:0] cpal  = { p12[11:8], p12[11:8], p12[7:4], p12[7:4], p12[3:0], p12[3:0] };
    reg  [17:0] fpal_q;
    reg  [23:0] rgb_np;
    wire [23:0] f_rgb = { fpal_q[17:12], fpal_q[17:16],
                          fpal_q[11:6],  fpal_q[11:10],
                          fpal_q[5:0],   fpal_q[5:4] };
    wire [23:0] rgb_final = (planes_l == 4'd8) ? f_rgb : rgb_np;

    always @(posedge clk_32) begin
        if (reset) begin
            st <= S_IDLE; ram_req <= 1'b0; underrun <= 1'b0; busy_line <= 1'b0;
        end else begin
            case (st)
                S_IDLE: if (fetch_go) begin
                    if (busy_line) underrun <= 1'b1;
                    base_l <= fb_base; planes_l <= planes; hdbl_l <= hdbl; vdbl_l <= vdbl;
                    lb_l <= lb_now; nline_l <= fetch_line; odd_l <= fetch_odd;
                    ok_l <= lb_ok;
                    wrbuf <= fetch_odd;
                    if (!lb_ok) begin
                        dcol <= 10'd0; st <= S_DEC;      // fill black
                    end else begin
                        line_a <= fb_base[23:1] + nline * (lb_now >> 1); // word addr; nline from pixel domain
                        // use latched nline after this edge: compute from fetch_line
                        line_a <= fb_base[23:1] + fetch_line * (lb_now >> 1);
                        widx <= 10'd0;
                        wmax <= lb_now[11:1];            // words in the line
                        ram_a <= fb_base[23:1] + fetch_line * (lb_now >> 1);
                        ram_req <= 1'b1;
                        busy_line <= 1'b1;
                        st <= S_FETCH;
                    end
                end
                S_FETCH: if (ram_req && ram_ack) begin
                    rawbuf[widx] <= ram_q;
                    ram_req <= 1'b0;
                    if (widx + 10'd1 >= wmax) begin
                        dcol <= 10'd0; st <= S_DEC;
                    end else begin
                        widx <= widx + 10'd1;
                        ram_a <= ram_a + 23'd1;
                        ram_req <= 1'b1;
                    end
                end else if (!ram_req) ram_req <= 1'b1;
                S_DEC: begin
                    // stage A: gather + ST pal / TC; issue Falcon pal read
                    rgb_np  <= (planes_l == 4'd0) ? c565 : cpal;
                    fpal_q  <= fpal[idx8];
                    dcol_w  <= dcol;
                    dcol    <= dcol + 10'd1;
                    st      <= S_DEC2;
                end
                S_DEC2: begin
                    if (ok_l) begin
                        if (wrbuf) rgbbuf1[dcol_w] <= rgb_final;
                        else       rgbbuf0[dcol_w] <= rgb_final;
                    end else begin
                        if (wrbuf) rgbbuf1[dcol_w] <= 24'd0;
                        else       rgbbuf0[dcol_w] <= 24'd0;
                    end
                    if (dcol_w == 10'd639) begin
                        busy_line <= 1'b0; st <= S_IDLE;
                    end else st <= S_DEC;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    // video address counter (approx: base + native line * linebytes)
    // TOS reads $FF8205/7/9; a line-granularity value is enough for v1.
    always @(posedge clk_32) begin
        vcount <= base_l + {14'd0, nline_l} * {12'd0, lb_l};
    end

    // VBL/HBL in clk_32, synced from pixel timing
    reg [2:0] vs_s, hs_s;
    always @(posedge clk_32) begin
        vs_s <= {vs_s[1:0], vs_l};
        hs_s <= {hs_s[1:0], hs_l};
        vbl  <= vs_s[2];
        hbl  <= hs_s[2] && !vs_s[2];
    end

    // --------------- pixel read (2-cycle like Hybrid, +2 ahead) ---------------
    wire [9:0] hfetch = (cx >= H_TOT-10'd2) ? (cx - (H_TOT-10'd2)) : (cx + 10'd2);
    wire [9:0] yfetch = (cx >= H_TOT-10'd2) ? ((cy == V_TOT-10'd1) ? 10'd0 : cy + 10'd1) : cy;
    wire [9:0] drow_f = (yfetch >= vtop) && (yfetch < vbot) ? (yfetch - vtop) : 10'd0;
    wire       rsel   = drow_f[0];
    wire       in_f   = (yfetch >= vtop) && (yfetch < vbot) && (hfetch < H_ACT);
    reg [23:0] q1, q2;
    always @(posedge clk_pixel) begin
        q1 <= rsel ? rgbbuf1[hfetch] : rgbbuf0[hfetch];
        q2 <= q1;
    end
    wire [23:0] pix = in_f ? q2 : 24'd0;
    assign vr = pix[23:16];
    assign vg = pix[15:8];
    assign vb = pix[7:0];
endmodule
