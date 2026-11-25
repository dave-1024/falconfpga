// falcon_videl_timing.v - FAL_01 VID-SPLIT step 1: native Falcon/Videl beam timing on clk_32
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The ST core's model (gstmcu): the machine's own beam timing drives DE -> MFP TBI,
// HBL (IPL2), VBL (IPL4) and the video address counter; the HDMI side is only a
// reader. Here the HDMI reader stays falcon_scanout at a fixed 640x480@60 (David
// 25 Nov: HDMI 60 Hz only, Hybrid030 way).
//
// Monitor (mon_rgb, = $FF8006 b7:6 01 RGB / 10 VGA, helper option "V"):
//   VGA: 1016 clk32 x 525 lines = 59.95 Hz, 31.5 kHz. Same frame as HDMI VIC 1, so
//        it is GENLOCKED: every HDMI frame start re-seats the native counters
//        (vl=1, hc=LOCK_HC), native line n == HDMI row n-1. The picture window starts
//        at vstart = HDMI vtop, so each native line's DE (and the Timer B ISR's palette
//        write) lands in the HDMI row before that line is decoded (d8e6a1f contract,
//        FrontBench split at native 168) without any HDMI signal reaching the CPU side.
//   RGB: free-running. Lines/frame from Videl VFT (half-lines): >= 576 half-lines ->
//        313 lines x 2048 clk32 (50.08 Hz, 15.625 kHz), else 263 x 2032 (59.87 Hz).
//        Picture starts at VDB/2. Not locked to HDMI (rate differs): until VID-SPLIT
//        step 3 (native-time decode into a frame buffer) raster palette splits will
//        roll in the HDMI picture on RGB 50; interrupt timing is correct.
// DE: one active period per native picture line (only the first monitor line of a
// doubled pair, vdbl = VMODE bit 0), so Timer B counts native lines (200 in ST low).
module falcon_videl_timing (
    input  wire        clk_32,
    input  wire        reset,
    input  wire        mon_rgb,         // 0 = VGA (genlocked), 1 = RGB 50/60
    input  wire [15:0] vft,             // Videl $82A2 (half-lines)
    input  wire [15:0] vdb,             // Videl $82A8 (half-lines)
    input  wire        vdbl,            // Videl VMODE bit 0 (line doubling)
    input  wire [9:0]  height,          // native picture lines (videl_regs)
    input  wire [23:0] fb_base,
    input  wire [11:0] linebytes,
    input  wire [9:0]  hdmi_vtop,       // falcon_scanout picture top row (quasi-static)
    input  wire        hdmi_fs_tgl,     // falcon_scanout frame-start toggle (clk_pixel)
    output reg         de,              // native display enable (MFP TBI = falling edge)
    output reg         hbl,             // level, IPL2
    output reg         vbl,             // level, IPL4
    output reg         frame_start,     // 1-clk pulse at native line 0
    output reg  [23:0] vcount,          // live $FF8205/07/09
    output reg  [9:0]  vl_o,            // native monitor line (debug/sim)
    output reg  [11:0] hc_o
);
    // ---- per-monitor constants ----
    wire        rgb50   = (vft == 16'd0) || (vft >= 16'd576);
    wire [11:0] htot    = !mon_rgb ? 12'd1016 : (rgb50 ? 12'd2048 : 12'd2032);
    wire [9:0]  vtot    = !mon_rgb ? 10'd525  : (rgb50 ? 10'd313  : 10'd263);
    wire [11:0] hde_end = !mon_rgb ? 12'd812  : 12'd1280;  // active length (640 px @25.2 / 320 px @8 MHz)
    wire [11:0] hs0     = !mon_rgb ? 12'd838  : 12'd1650;  // HBL (hsync) start
    wire [11:0] hsw     = !mon_rgb ? 12'd122  : 12'd150;
    wire [9:0]  vs0     = !mon_rgb ? 10'd491  : 10'd0;     // VBL line (VGA: = HDMI vsync rows 490/491)
    localparam [11:0] LOCK_HC = 12'd6;                     // HDMI cx 0 -> clk_32 after the 3-flop sync

    wire [9:0]  nlines  = (height == 10'd0) ? 10'd200 : height;
    wire [9:0]  vdb_l   = vdb[10:1];
    wire [9:0]  vst_rgb = (vdb_l + nlines + 10'd4 > vtot) ? 10'd16 : vdb_l;
    wire [9:0]  vstart  = !mon_rgb ? hdmi_vtop : vst_rgb;
    wire [10:0] span    = vdbl ? {nlines, 1'b0} : {1'b0, nlines};

    reg  [11:0] hc;
    reg  [9:0]  vl;
    reg  [2:0]  fs_s;
    always @(posedge clk_32) fs_s <= {fs_s[1:0], hdmi_fs_tgl};
    wire lock = !mon_rgb && (fs_s[2] != fs_s[1]);

    always @(posedge clk_32) begin
        if (reset) begin hc <= 12'd0; vl <= 10'd0; end
        else if (lock) begin hc <= LOCK_HC; vl <= 10'd1; end
        else if (hc >= htot - 12'd1) begin
            hc <= 12'd0;
            vl <= (vl >= vtot - 10'd1) ? 10'd0 : vl + 10'd1;
        end else hc <= hc + 12'd1;
    end

    // picture line index of this monitor line
    wire [10:0] prow    = {1'b0, vl} - {1'b0, vstart};
    wire        in_pic  = (vl >= vstart) && (prow < span);
    wire        first   = !vdbl || !prow[0];
    wire [9:0]  pline   = vdbl ? prow[10:1] : prow[9:0];
    wire        de_n    = in_pic && first && (hc < hde_end);

    // video counter: base + pline*linebytes + bytes fetched so far in this line
    reg [23:0] line_base;
    reg [11:0] acc;
    reg [11:0] off;
    always @(posedge clk_32) begin
        de          <= de_n;
        vbl         <= (vl == vs0) || (vl == vs0 + 10'd1);
        hbl         <= (hc >= hs0) && (hc < hs0 + hsw) && !((vl == vs0) || (vl == vs0 + 10'd1));
        frame_start <= (hc == 12'd0) && (vl == 10'd0);
        vl_o <= vl; hc_o <= hc;
        if (vl == 10'd0 && hc == 12'd0) line_base <= fb_base;
        if (hc == 12'd0 || (de && !de_n)) begin acc <= 12'd0; off <= 12'd0; end
        else if (de_n) begin
            // off advances linebytes per hde_end clocks (<= 1 byte/clk)
            if (acc + linebytes >= hde_end) begin acc <= acc + linebytes - hde_end; off <= off + 12'd1; end
            else acc <= acc + linebytes;
        end
        if (de && !de_n) line_base <= line_base + {12'd0, linebytes};  // end of a native line
        vcount <= line_base + {12'd0, off[11:1], 1'b0};
    end
endmodule
