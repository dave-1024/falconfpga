// falcon_scanout.v - FAL_01: port of Hybrid030 falcon_video.v onto the SDRAM arbiter + ST HDMI
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decode-on-fetch from Hybrid030 falcon_video.v v6.2, but the line memories
// are explicit SDP BSRAM (falcon_sdp_ram, syn_ramstyle = "block_ram", the
// same style as st_fb_ram). The first v1 coding (a 640x16 rawbuf with eight
// combinational ports, plus dual-clock 640x24 rgbbuf0/1 without the
// attribute) synthesised as 62136 LUT / 16586 FF / 5 BSRAM and made the
// first full build fail PR0004 at 88% CLS.
//
// clk_32 fetches one native 16-pixel group (1/2/4/8 words, or one RGB565
// word) through falcon_sdram_arb.v, holds the plane words in eight
// registers, and writes finished RGB888 into a 1024x24 ping-pong BSRAM
// (bank in addr[9]). The clk_pixel side is a linear reader at 640x480@60
// (CEA VIC 1), two-cycle latency like Hybrid. The 256x18 Falcon palette is
// also SDP BSRAM with a synchronous read; the 16-entry ST palette stays as
// registers. Geometry comes from videl_regs.v.
//
// Prefetch: at cx==0 of display line cy, request the NEXT row's native line
// into bank ndrow[0]. That is a full HDMI line (31.8 us, ~1016 clk32) and
// is the correct bank/line for TOS 640x480 (vdbl=0). The earlier trigger
// (H_TOT-8, current nline into the next-row bank) was an off-by-one.
//
// Guard: linebytes == 0 or > 640 yields black (Hybrid030 M11d / v6 header).
// v1 needs the TOS boot modes (640x480 4-plane VGA, ST modes doubled).
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
    output reg         ram_rd2,         // request a burst-2 word pair
    output reg  [23:1] ram_a,
    input  wire        ram_ack,
    input  wire [15:0] ram_q,
    input  wire [15:0] ram_q2,
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

    // At cx==0 of line cy, prefetch the NEXT display row into its bank.
    wire [9:0] next_cy = (cy == V_TOT-10'd1) ? 10'd0 : (cy + 10'd1);
    wire       nin_pic = (next_cy >= vtop) && (next_cy < vbot);
    wire [9:0] ndrow   = nin_pic ? (next_cy - vtop) : 10'd0;
    wire [9:0] nnline  = vdbl ? {1'b0, ndrow[9:1]} : ndrow;
    wire       nfetch  = nin_pic && (!vdbl || !ndrow[0]);

    reg        fetch_tgl;
    reg [9:0]  fetch_line;
    reg        fetch_odd;
    always @(posedge clk_pixel) begin
        if (reset) fetch_tgl <= 1'b0;
        else if (cx == 10'd0 && nfetch) begin
            fetch_line <= nnline;
            fetch_odd  <= ndrow[0];
            fetch_tgl  <= ~fetch_tgl;
        end
    end

    // --------------- clk_32: palettes, fetch, decode ---------------
    reg [11:0] pal [0:15];
    integer pi;
    always @(posedge clk_32) begin
        if (reset) begin
            for (pi = 0; pi < 16; pi = pi + 1) pal[pi] <= 12'd0;
        end else if (stpal_we) pal[stpal_wa] <= stpal_wd;
    end

    // Falcon palette: SDP BSRAM, both ports on clk_32, registered read
    wire [17:0] fpal_q;
    reg  [7:0]  fpal_ra;
    falcon_sdp_ram #(.DEPTH(256), .AW(8), .DW(18)) u_fpal (
        .wclk(clk_32), .we(fpal_we), .waddr(fpal_wa), .wdata(fpal_wd),
        .rclk(clk_32), .raddr(fpal_ra), .rdata(fpal_q)
    );

    // Ping-pong RGB line buffer: 1024x24 SDP, bank in addr[9], dual clock
    reg         rgb_we;
    reg  [9:0]  rgb_wa;
    reg  [23:0] rgb_wd;
    wire [9:0]  rgb_ra;
    wire [23:0] rgb_rd;
    falcon_sdp_ram #(.DEPTH(1024), .AW(10), .DW(24)) u_rgb (
        .wclk(clk_32), .we(rgb_we), .waddr(rgb_wa), .wdata(rgb_wd),
        .rclk(clk_pixel), .raddr(rgb_ra), .rdata(rgb_rd)
    );

    // CDC of the fetch toggle
    reg [2:0] tgl_s;
    always @(posedge clk_32) tgl_s <= {tgl_s[1:0], fetch_tgl};
    wire fetch_go = tgl_s[1] != tgl_s[2];

    // latched geometry for this line
    reg [23:0] base_l;
    reg [3:0]  planes_l;
    reg        hdbl_l, vdbl_l, odd_l, ok_l;
    reg [11:0] lb_l;
    reg [9:0]  nline_l;
    wire [11:0] lb_now = linebytes;
    wire        lb_ok  = (lb_now != 12'd0) && (lb_now <= 12'd640);

    localparam S_IDLE=3'd0, S_START=3'd1, S_WAIT=3'd2, S_PRIME=3'd3, S_PIX=3'd4, S_FILL=3'd5;
    reg [2:0]  st;
    reg [9:0]  dcol, dcol_w;
    reg [23:1] line_a;
    reg        wrbuf;
    reg        busy_line;
    reg [3:0]  wneed, wgot;
    reg [15:0] pw [0:7];
    reg [23:0] rgb_np;

    // words in one 16-pixel native group (TC is one word per native pixel)
    wire [3:0] words_per_grp = (planes_l == 4'd0) ? 4'd1 :
                               planes_l[3]        ? 4'd8 :
                               planes_l[2]        ? 4'd4 :
                               (planes_l == 4'd2) ? 4'd2 : 4'd1;

    // decode of the CURRENT compute column (dcol) from the latched plane words
    wire [9:0] nat_x  = hdbl_l ? {1'b0, dcol[9:1]} : dcol;
    wire [3:0] pk     = nat_x[3:0];
    wire [7:0] idx8   = { (planes_l>4'd7) ? pw[7][15-pk] : 1'b0,
                          (planes_l>4'd6) ? pw[6][15-pk] : 1'b0,
                          (planes_l>4'd5) ? pw[5][15-pk] : 1'b0,
                          (planes_l>4'd4) ? pw[4][15-pk] : 1'b0,
                          (planes_l>4'd3) ? pw[3][15-pk] : 1'b0,
                          (planes_l>4'd2) ? pw[2][15-pk] : 1'b0,
                          (planes_l>4'd1) ? pw[1][15-pk] : 1'b0,
                          (planes_l>4'd0) ? pw[0][15-pk] : 1'b0 };
    wire [15:0] tcw   = pw[0];
    wire [23:0] c565  = { tcw[15:11], tcw[15:13], tcw[10:5], tcw[10:9], tcw[4:0], tcw[4:2] };
    wire [11:0] p12   = pal[idx8[3:0]];
    wire [23:0] cpal  = { p12[11:8], p12[11:8], p12[7:4], p12[7:4], p12[3:0], p12[3:0] };
    wire [23:0] f_rgb = { fpal_q[17:12], fpal_q[17:16],
                          fpal_q[11:6],  fpal_q[11:10],
                          fpal_q[5:0],   fpal_q[5:4] };
    wire [23:0] rgb_final = (planes_l == 4'd8) ? f_rgb : rgb_np;

    // last display column of this group (the column being written, dcol_w)
    wire last_in_grp = (planes_l == 4'd0) ? (hdbl_l ? dcol_w[0] : 1'b1) :
                       (hdbl_l ? (dcol_w[4:0] == 5'd31) : (dcol_w[3:0] == 4'd15));

    always @(posedge clk_32) begin
        if (reset) begin
            st <= S_IDLE; ram_req <= 1'b0; ram_rd2 <= 1'b0;
            underrun <= 1'b0; busy_line <= 1'b0;
            rgb_we <= 1'b0; fpal_ra <= 8'd0;
        end else begin
            rgb_we <= 1'b0;
            case (st)
                S_IDLE: if (fetch_go) begin
                    if (busy_line) underrun <= 1'b1;
                    base_l   <= fb_base;
                    planes_l <= planes;
                    hdbl_l   <= hdbl;
                    vdbl_l   <= vdbl;
                    lb_l     <= lb_now;
                    nline_l  <= fetch_line;
                    odd_l    <= fetch_odd;
                    ok_l     <= lb_ok;
                    wrbuf    <= fetch_odd;
                    dcol     <= 10'd0;
                    if (!lb_ok) begin
                        busy_line <= 1'b1;
                        st <= S_FILL;
                    end else begin
                        line_a    <= fb_base[23:1] + (fetch_line * lb_now[11:1]);
                        ram_a     <= fb_base[23:1] + (fetch_line * lb_now[11:1]);
                        busy_line <= 1'b1;
                        wgot      <= 4'd0;
                        st        <= S_START;
                    end
                end
                S_START: begin
                    wneed   <= words_per_grp;
                    wgot    <= 4'd0;
                    ram_a   <= line_a;
                    ram_rd2 <= (words_per_grp >= 4'd2) && ((line_a & 23'h1FF) != 23'h1FF);
                    ram_req <= 1'b1;
                    st      <= S_WAIT;
                end
                S_WAIT: if (ram_req && ram_ack) begin
                    pw[wgot] <= ram_q;
                    if (ram_rd2) pw[wgot + 4'd1] <= ram_q2;
                    ram_req <= 1'b0;
                    ram_rd2 <= 1'b0;
                    begin : nxt
                        reg [3:0] ni;
                        ni = wgot + (ram_rd2 ? 4'd2 : 4'd1);
                        line_a <= line_a + (ram_rd2 ? 23'd2 : 23'd1);
                        if (ni >= wneed) begin
                            wgot <= ni;
                            st   <= S_PRIME;        // pw settles this edge; use next cycle
                        end else begin
                            wgot    <= ni;
                            ram_a   <= line_a + (ram_rd2 ? 23'd2 : 23'd1);
                            ram_rd2 <= ((wneed - ni) >= 4'd2) &&
                                       (((line_a + (ram_rd2 ? 23'd2 : 23'd1)) & 23'h1FF) != 23'h1FF);
                            ram_req <= 1'b1;
                        end
                    end
                end else if (!ram_req) ram_req <= 1'b1;
                // stage A for dcol: latch ST/TC colour, issue Falcon palette read
                S_PRIME: begin
                    rgb_np  <= (planes_l == 4'd0) ? c565 : cpal;
                    fpal_ra <= idx8;
                    dcol_w  <= dcol;
                    dcol    <= dcol + 10'd1;
                    st      <= S_PIX;
                end
                // stage B: write dcol_w; if the group continues, also stage A for dcol
                S_PIX: begin
                    rgb_we <= 1'b1;
                    rgb_wa <= {wrbuf, dcol_w};
                    rgb_wd <= rgb_final;
                    if (dcol_w == 10'd639) begin
                        busy_line <= 1'b0;
                        st        <= S_IDLE;
                    end else if (last_in_grp) begin
                        // dcol already points at the first column of the next group
                        st <= S_START;
                    end else begin
                        rgb_np  <= (planes_l == 4'd0) ? c565 : cpal;
                        fpal_ra <= idx8;
                        dcol_w  <= dcol;
                        dcol    <= dcol + 10'd1;
                    end
                end
                S_FILL: begin
                    rgb_we <= 1'b1;
                    rgb_wa <= {wrbuf, dcol};
                    rgb_wd <= 24'd0;
                    if (dcol == 10'd639) begin
                        busy_line <= 1'b0;
                        dcol      <= 10'd0;
                        st        <= S_IDLE;
                    end else dcol <= dcol + 10'd1;
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
    // falcon_sdp_ram already registers rdata (1 cycle); q2 is the second.
    wire [9:0] hfetch = (cx >= H_TOT-10'd2) ? (cx - (H_TOT-10'd2)) : (cx + 10'd2);
    wire [9:0] yfetch = (cx >= H_TOT-10'd2) ? ((cy == V_TOT-10'd1) ? 10'd0 : cy + 10'd1) : cy;
    wire [9:0] drow_f = (yfetch >= vtop) && (yfetch < vbot) ? (yfetch - vtop) : 10'd0;
    wire       rsel   = drow_f[0];
    assign     rgb_ra = {rsel, hfetch};
    // Address is +2 ahead; rdata is registered in the SDP, q2 is the second
    // stage, so q2 at cx is the pixel for this cx (Hybrid / hdmi_640 contract:
    // cx and rgb refer to the same pixel in the same clock). Blank from the
    // current counters, not from the ahead in_f.
    reg [23:0] q2;
    always @(posedge clk_pixel) q2 <= rgb_rd;
    wire [23:0] pix = ((cx < H_ACT) && (cy >= vtop) && (cy < vbot)) ? q2 : 24'd0;
    assign vr = pix[23:16];
    assign vg = pix[15:8];
    assign vb = pix[7:0];
endmodule
