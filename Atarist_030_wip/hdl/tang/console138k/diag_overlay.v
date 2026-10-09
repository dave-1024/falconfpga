// diag_overlay.v - FalconFPGA Atarist_030_wip DIAGNOSTIC (DEBUG) build helpers,
// ported from misterynano_tc138k's diag overlay (diag030), extended with
// four bit-bar rows (diag030b: first BERR, screen base, fetch address).
// Only used when `define DIAG_OVERLAY is set in top.sv. Three modules:
//
//   diag_collect  (clk32)    : watches raw core signals, makes per-square
//                              status bits {now, ever} + blink bits + LED bit
//   diag_fake_st  (clk32)    : fake PAL low-res ST timing + test picture for
//                              the frame buffer self-test (FB_SELFTEST, a
//                              separate mode, OFF by default: it replaces the
//                              ST picture in the frame buffer)
//   diag_overlay  (25.2 MHz) : draws the status squares directly on the
//                              640x480 output (after the frame buffer read)
//
// Square colours (normal squares):
//   GREEN  = happening now (seen within the last ~0.13-0.26 s) / level true
//   YELLOW = happened earlier since power-up, but not any more
//   RED    = never seen since power-up
//   S1/S2 blink green/dark green while alive (S1 at ST-VS/32, S2 at HS/16384)
// S20 (bus error) has the colours INVERTED, because seeing it is bad:
//   GREEN  = never seen, YELLOW = seen earlier, RED = happening now
//
// Layout (x,y in output pixels, 48x48 squares, 64 px pitch, 4 px black frame):
//   bit rows a..f (diag030c), y 96..287, 32 px pitch, black band x 8..567:
//                      label square 20x20 at x 16..35, then up to 32 bars
//                      (12 px wide, 20 px tall, 14 px slot, 8 px gap per
//                      group of 4 = one hex digit), MSB left, bars x 48..559.
//                      Bit n (31..0) is in group 7-n/4. White = 1, grey = 0.
//        a  y 102..121 RED label:     first BERR address A31:0
//        b  y 134..153 MAGENTA label: got FC2 FC1 FC0 | RW SIZ1 SIZ0 BAD |
//                                     $FF8201 byte | $FF8203 byte | WH WM
//        c  y 166..185 CYAN label:    A31:0 of the LAST bus cycle STARTED by
//                                     the 030 (raw WF68K30L ADR_OUT at AS)
//        d  y 198..217 GREEN label:   FC2 FC1 FC0 RW | SIZ1 SIZ0 INPROG HUNG |
//                                     T_DSACK T_BERR T_AVEC - |
//                                     IACKs IACKd CPUSP IACKav |
//                                     HALTOUTn RESETOUT RSTINn IPENDn |
//                                     STATUSn IPL2n IPL1n IPL0n |
//                                     ASn DSn DSACK1n DSACK0n |
//                                     BERRn AVECn RMCn RWn  (live pins)
//        e  y 230..249 ORANGE label:  bridge: phase2:0 pending | req s_seen
//                                     c_open term_ok | rAS rUDS rLDS rRWn |
//                                     rDtack rBerr Vpai iStop | s_dsack s_avec
//                                     s_berr s_tag | r_tag addr_oe rVma r_iack |
//                                     arb1:0 BGn can_start | r_res1:0 BRi BgackI
//        f  y 262..281 BLUE label:    bus cycles started mod 256 (8 bits) |
//                                     live last program fetch A23:0
//                      (full key: docs/DIAG_OVERLAY.md)
//   row 0, y 296..343: S17..S20 at x = 8+64*i (i = 0..3)   (030 bridge)
//   row 1, y 360..407: S1..S10  at x = 8+64*i (i = 0..9)
//   row 2, y 424..471: S11..S16 at x = 8+64*i (i = 0..5), then 16 bars
//                      (x 392..635) = first TOS word read (ROM offset 0),
//                      MSB left (white = 1, dark grey = 0, 4 bits per group)
//
// Squares (E = event/activity, L = level):
//   S1  E ST vsync falling edges (blinks at VS/32)        st_video_vs_n
//   S2  E ST hsync falling edges (blinks at HS/16384)     st_video_hs_n
//   S3  E ST DE high                                      st_video_de
//   S4  E non-black RGB while DE                          st_video_r/g/b
//   S5  E ST-side AS falling edges (bridge runs ST cycles) atarist cpu_as_n
//   S6  E TOS ROM selected (E0xxxx/FCxxxx)                rom_n (GSTMCU ROM2_N)
//   S7  E ROM read returned data other than 0000/FFFF     rom_dout @ rom_n rise
//   S8  E frame buffer write enable (ST FB writes)        st_fb_capture we
//   S9  L main PLL locked                                 pll_lock
//   S10 L 68030 out of reset (bridge RESET_INn released)  bridge cpu_rst_n
//   S11 L atarist reset input released                    resb term
//   S12 L SDRAM init done                                 sdram ready
//   S13 E BL616 SPI select seen (MCU talks to the core)   spi_io_ss
//   S14 L BL616 not holding the ST in reset               !system_reset[0]
//   S15 L SD wait done (image or 2 s timeout)             sd_ready
//   S16 L 68030 not halted (no double bus fault)          bridge oHALTEDn
//   S17 E 030 bus cycle started (030 AS seen by bridge)   bridge req toggle
//   S18 L ROM fetch latch (first E/FC-FE cycle, = LED0)   bridge rom_fetch
//   S19 E DSACK returned to the 030                       bridge s_dsack rise
//   S20 E BERR returned to the 030 (colours inverted)     bridge s_berr rise

// ---------------------------------------------------------------------------
module diag_collect #(
    parameter WIN_BITS = 22           // activity window 2^22 clk32 = 131 ms
) (
    input             clk,            // clk32
    // ST video (raw, clk32)
    input             st_hs_n,
    input             st_vs_n,
    input             st_de,
    input      [11:0] st_rgb,
    // CPU / ROM (clk32)
    input             cpu_as_n,       // ST-side AS (driven by the bridge)
    input             cpu_halted_n,   // 030 HALT_OUTn (synced in the bridge)
    input             rom_n,
    input      [16:0] rom_idx,        // rom_addr[17:1]
    input      [15:0] rom_data,
    // 030 bridge (clk32 unless noted)
    input             c030_run_async, // bridge cpu_rst_n (clk_cpu030 domain)
    input             c030_req,       // bridge req_now (toggles per 030 AS)
    input             c030_rom_fetch, // bridge rom_fetch latch
    input             c030_dsack,     // bridge s_dsack
    input             c030_berr,      // bridge s_berr
    // system (clk32)
    input             st_resb,        // reset input of the atarist core
    input             ram_ready,
    input             sd_ready,
    input             mcu_reset,      // system_reset[0] from the BL616
    input             mcu_ss_async,   // BL616 SPI select (async)
    input             pll_lock_async, // main PLL lock (async)
    input             fb_we,          // frame buffer write enable (clk32)
    // results
    output     [19:0] now,
    output reg [19:0] ever = 20'd0,
    output            vs_blink,
    output            hs_blink,
    output reg [15:0] rom_word0 = 16'h0000,
    output            led_030         // blinks ~1 Hz while 030 bus cycles run
);

// register all inputs once (same clock domain, only for timing)
// (power-up values are the "bad" state so that no level square latches a
// false "ever" in the first clock)
reg        hs = 1'b1, vs = 1'b1, de = 1'b0, as = 1'b1, halt_n = 1'b0, rn = 1'b1;
reg        hs_d = 1'b1, vs_d = 1'b1, as_d = 1'b1, rn_d = 1'b1;
reg        rgb_nz = 1'b0, resb = 1'b0, rrdy = 1'b0, srdy = 1'b0, mrst = 1'b1, we = 1'b0;
reg        rq = 1'b0, rq_d = 1'b0, rf = 1'b0, ds = 1'b0, ds_d = 1'b0, be = 1'b0, be_d = 1'b0;
reg [16:0] ridx = 17'd0;
reg [15:0] rdat = 16'd0;
(* ASYNC_REG = "TRUE" *) reg [2:0] ss_s = 3'b111;   // 2-FF sync + edge
(* ASYNC_REG = "TRUE" *) reg [1:0] lk_s = 2'b00;    // 2-FF sync
(* ASYNC_REG = "TRUE" *) reg [1:0] rn_s = 2'b00;    // 2-FF sync (030 run)
always @(posedge clk) begin
    hs <= st_hs_n;  vs <= st_vs_n;  de <= st_de;
    as <= cpu_as_n; halt_n <= cpu_halted_n; rn <= rom_n;
    rgb_nz <= st_de && (st_rgb != 12'd0);
    resb <= st_resb; rrdy <= ram_ready; srdy <= sd_ready; mrst <= mcu_reset;
    we <= fb_we;
    rq <= c030_req; rf <= c030_rom_fetch; ds <= c030_dsack; be <= c030_berr;
    ridx <= rom_idx; rdat <= rom_data;
    hs_d <= hs; vs_d <= vs; as_d <= as; rn_d <= rn;
    rq_d <= rq; ds_d <= ds; be_d <= be;
    ss_s <= { ss_s[1:0], mcu_ss_async };
    lk_s <= { lk_s[0], pll_lock_async };
    rn_s <= { rn_s[0], c030_run_async };
end

wire vs_fall  = vs_d & ~vs;
wire hs_fall  = hs_d & ~hs;
wire as_fall  = as_d & ~as;
wire rom_end  = ~rn_d & rn;          // end of a ROM cycle (data valid)
wire rom_ok   = rom_end && (rdat != 16'h0000) && (rdat != 16'hffff);
wire ss_fall  = ss_s[2] & ~ss_s[1];
wire req_tg   = rq ^ rq_d;           // one 030 AS cycle accepted by the front end
wire ds_rise  = ds & ~ds_d;
wire be_rise  = be & ~be_d;

// first TOS word (ROM offset 0) as seen at the end of the ROM cycle
always @(posedge clk)
    if (rom_end && ridx == 17'd0) rom_word0 <= rdat;

// blink counters
reg [4:0]  vs_cnt = 5'd0;
reg [13:0] hs_cnt = 14'd0;
always @(posedge clk) begin
    if (vs_fall) vs_cnt <= vs_cnt + 5'd1;
    if (hs_fall) hs_cnt <= hs_cnt + 14'd1;
end
assign vs_blink = vs_cnt[4];          // toggles every 16 VS -> period VS/32
assign hs_blink = hs_cnt[13];         // period HS/16384 (~1 s colour)

// index (= square number - 1):
//   event squares (activity): 0 VS, 1 HS, 2 DE, 3 RGB, 4 ST AS, 5 ROM,
//                             6 ROM data ok, 7 FB WE, 12 MCU SPI,
//                             16 030 AS, 18 DSACK, 19 BERR
//   level squares:            8 PLL lock, 9 030 out of reset, 10 RESB,
//                             11 SDRAM ready, 13 MCU not holding reset,
//                             14 SD ready, 15 030 not halted, 17 ROM fetch
wire [19:0] ev  = { be_rise, ds_rise, 1'b0, req_tg,
                    3'b000, ss_fall, 4'b0000,
                    we, rom_ok, ~rn, as_fall, rgb_nz, de, hs_fall, vs_fall };
wire [19:0] lvl = { 2'b00, rf, 1'b0,
                    halt_n, srdy, ~mrst, 1'b0, rrdy, resb, rn_s[1], lk_s[1], 8'd0 };
localparam [19:0] IS_LVL = 20'b0010_1110_1111_0000_0000;

// window counter, 2 extra bits for a ~2 Hz LED blink
reg [WIN_BITS+1:0] win = 0;
reg [19:0] cur = 20'd0, prev = 20'd0;
always @(posedge clk) begin
    win <= win + 1'd1;
    if (win[WIN_BITS-1:0] == 0) begin
        prev <= cur | ev;
        cur  <= 20'd0;
    end else
        cur  <= cur | ev;
    ever <= ever | ev | lvl;
end
assign now = (IS_LVL & lvl) | (~IS_LVL & (cur | prev));

assign led_030 = win[WIN_BITS+1] & now[16];

endmodule

// ---------------------------------------------------------------------------
// Fake ST video at clk32 for the frame buffer self-test. Same timing as the
// real core in PAL low res (measured, see st_framebuffer.v): line 2048 clk32,
// 313 lines, hsync low 150 clk, DE 432..1711 on lines 66..265, pixels start
// 96 clk after DE (like the real shifter). Picture, 640x200 "medium res"
// samples (x 0..639, y 0..199):
//   1 px white frame around the whole picture,
//   top half   (y <  100): 10 vertical colour bars, 64 samples wide:
//              white yellow cyan green magenta red blue black grey orange
//   lower part (y 100..149): 16-step grey ramp (40 samples per step)
//   bottom     (y >= 150): 8x8 black/white checkerboard
//   border (outside the picture): dark blue
module diag_fake_st (
    input             clk,            // clk32
    output reg        hs_n = 1'b1,
    output reg        vs_n = 1'b1,
    output reg        de   = 1'b0,
    output reg [11:0] rgb  = 12'd0
);
localparam LINE = 2048, LINES = 313, DE_H = 432, DE_V = 66, DE_N = 200;
localparam PX_H = DE_H + 96;          // first pixel
localparam VS_H = 416;

reg [10:0] gh = 11'd0;
reg  [8:0] gv = 9'd0;
always @(posedge clk) begin
    if (gh == LINE-1) begin
        gh <= 11'd0;
        gv <= (gv == LINES-1) ? 9'd0 : gv + 9'd1;
    end else
        gh <= gh + 11'd1;
end

wire [10:0] px  = gh - PX_H;          // valid while in the picture
wire  [9:0] x   = px[10:1];           // 0..639 (2 clk32 per sample)
wire  [8:0] y   = gv - DE_V;          // 0..199
wire        pic = (gv >= DE_V) && (gv < DE_V + DE_N) &&
                  (gh >= PX_H) && (gh < PX_H + 1280);
wire        brd = (gh >= 320) && (gh < 2000) &&
                  (gv >= DE_V - 40) && (gv < DE_V + DE_N + 40);

reg [11:0] bar;
always @(*) begin
    case (x[9:6])
        4'd0: bar = 12'hfff;  4'd1: bar = 12'hff0;  4'd2: bar = 12'h0ff;
        4'd3: bar = 12'h0f0;  4'd4: bar = 12'hf0f;  4'd5: bar = 12'hf00;
        4'd6: bar = 12'h00f;  4'd7: bar = 12'h000;  4'd8: bar = 12'h888;
        default: bar = 12'hf80;
    endcase
end

// grey ramp: step = x / 40 (0..15)
reg [3:0] step;
always @(*) begin
    step = 4'd15;
    if      (x <  40) step = 4'd0;   else if (x <  80) step = 4'd1;
    else if (x < 120) step = 4'd2;   else if (x < 160) step = 4'd3;
    else if (x < 200) step = 4'd4;   else if (x < 240) step = 4'd5;
    else if (x < 280) step = 4'd6;   else if (x < 320) step = 4'd7;
    else if (x < 360) step = 4'd8;   else if (x < 400) step = 4'd9;
    else if (x < 440) step = 4'd10;  else if (x < 480) step = 4'd11;
    else if (x < 520) step = 4'd12;  else if (x < 560) step = 4'd13;
    else if (x < 600) step = 4'd14;
end

wire frame = (x == 10'd0) || (x == 10'd639) || (y == 9'd0) || (y == 9'd199);

always @(posedge clk) begin
    hs_n <= !(gh < 150);
    vs_n <= !((gv == 0 && gh >= VS_H) || gv == 1 || gv == 2 || (gv == 3 && gh < VS_H));
    de   <= (gv >= DE_V) && (gv < DE_V + DE_N) && (gh >= DE_H) && (gh < DE_H + 1280);
    if (pic)
        rgb <= frame      ? 12'hfff :
               (y < 100)  ? bar :
               (y < 150)  ? {3{step}} :
               (x[3] ^ y[3]) ? 12'hfff : 12'h000;
    else if (brd)
        rgb <= 12'h004;
    else
        rgb <= 12'h000;
end

endmodule

// ---------------------------------------------------------------------------
// Pixel side: overlay the status squares on the 640x480 picture. Purely
// combinational on cx/cy/rgb (cx/cy are already aligned with rgb), all
// status inputs are 2-FF synchronised here (they are slow / stretched).
module diag_overlay (
    input             clk,            // 25.2 MHz pixel clock
    input       [9:0] cx,
    input       [9:0] cy,
    input       [7:0] r_in,
    input       [7:0] g_in,
    input       [7:0] b_in,
    input      [19:0] now_async,
    input      [19:0] ever_async,
    input             vs_blink_async,
    input             hs_blink_async,
    input      [15:0] word_async,
    input     [191:0] rows_async,     // diag030c rows a..f (a = [191:160])
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);

(* ASYNC_REG = "TRUE" *) reg [57:0] s1 = 58'd0;
(* ASYNC_REG = "TRUE" *) reg [57:0] s2 = 58'd0;
always @(posedge clk) begin
    s1 <= { word_async, hs_blink_async, vs_blink_async, ever_async, now_async };
    s2 <= s1;
end
wire [19:0] now   = s2[19:0];
wire [19:0] ever  = s2[39:20];
wire        vsb   = s2[40];
wire        hsb   = s2[41];
wire [15:0] word  = s2[57:42];

(* ASYNC_REG = "TRUE" *) reg [191:0] t1 = 192'd0;
(* ASYNC_REG = "TRUE" *) reg [191:0] t2 = 192'd0;
always @(posedge clk) begin
    t1 <= rows_async;
    t2 <= t1;
end

localparam R0_Y = 10'd296, R1_Y = 10'd360, R2_Y = 10'd424, SQ = 6'd48;

// cell geometry: 64 px cells, square at local x/y 8..55, black frame 4..59
wire [5:0] lx  = cx[5:0];
wire [3:0] col = cx[9:6];
wire in_r0  = (cy >= R0_Y - 4) && (cy < R0_Y + SQ + 4);
wire in_r1  = (cy >= R1_Y - 4) && (cy < R1_Y + SQ + 4);
wire in_r2  = (cy >= R2_Y - 4) && (cy < R2_Y + SQ + 4);
wire sq_y0  = (cy >= R0_Y) && (cy < R0_Y + SQ);
wire sq_y1  = (cy >= R1_Y) && (cy < R1_Y + SQ);
wire sq_y2  = (cy >= R2_Y) && (cy < R2_Y + SQ);
wire sq_x   = (lx >= 6'd8) && (lx < 6'd56);
wire fr_x   = (lx >= 6'd4) && (lx < 6'd60);
wire act    = (cx < 10'd640) && (cy < 10'd480);

// row 0: squares 16..19 (col 0..3); row 1: squares 0..9 (col 0..9);
// row 2: squares 10..15 (col 0..5)
wire r0_cell = act && in_r0 && (col < 4'd4);
wire r1_cell = act && in_r1 && (col < 4'd10);
wire r2_cell = act && in_r2 && (col < 4'd6);
wire [4:0] idx = in_r0 ? { 1'b1, col } :
                 in_r1 ? { 1'b0, col } : { 1'b0, col } + 5'd10;

// 16 bit word bars, row 2, x 392..635: per bit 12 px bar in a 14 px slot,
// 8 px extra gap between groups of 4 -> group = 4*14+8 = 64 px
wire [9:0] wx   = cx - 10'd392;
wire [1:0] grp  = wx[7:6];
wire [5:0] gx   = wx[5:0];
reg  [1:0] bsel; reg bon;
always @(*) begin
    bon = 1'b1; bsel = 2'd0;
    if      (gx < 6'd12)                bsel = 2'd0;
    else if (gx >= 6'd14 && gx < 6'd26) bsel = 2'd1;
    else if (gx >= 6'd28 && gx < 6'd40) bsel = 2'd2;
    else if (gx >= 6'd42 && gx < 6'd54) bsel = 2'd3;
    else bon = 1'b0;
end
wire in_wx   = act && (cx >= 10'd388) && (cx < 10'd640);
wire bar_on  = act && (cx >= 10'd392) && (cx < 10'd648) && bon && sq_y2;
wire [3:0] bitn = 4'd15 - { grp, bsel };
wire bitv    = word[bitn];

// ---- diag030c bit rows a..f (y 96..287, 32 px pitch) ----
wire [9:0] ry     = cy - 10'd96;
wire [2:0] rsel   = ry[7:5];
wire [4:0] rly    = ry[4:0];
wire in_rows      = act && (cy >= 10'd96) && (cy < 10'd288) &&
                    (cx >= 10'd8) && (cx < 10'd568);
wire rbar_y       = (rly >= 5'd6) && (rly < 5'd26);
wire rlab_on      = in_rows && rbar_y && (cx >= 10'd16) && (cx < 10'd36);
wire [9:0] bx     = cx - 10'd48;
wire [2:0] rgrp   = bx[8:6];
wire [5:0] rgx    = bx[5:0];
reg  [1:0] rbsel; reg rbon;
always @(*) begin
    rbon = 1'b1; rbsel = 2'd0;
    if      (rgx < 6'd12)                 rbsel = 2'd0;
    else if (rgx >= 6'd14 && rgx < 6'd26) rbsel = 2'd1;
    else if (rgx >= 6'd28 && rgx < 6'd40) rbsel = 2'd2;
    else if (rgx >= 6'd42 && rgx < 6'd54) rbsel = 2'd3;
    else rbon = 1'b0;
end
wire [4:0] rbit   = 5'd31 - { rgrp, rbsel };
reg [31:0] rvec, rmask; reg [23:0] rlab;
always @(*) begin
    case (rsel)
        3'd0: begin rvec = t2[191:160]; rmask = 32'hffffffff; rlab = 24'hff0000; end // a red
        3'd1: begin rvec = t2[159:128]; rmask = 32'hffffffc0; rlab = 24'hff00ff; end // b magenta
        3'd2: begin rvec = t2[127:96];  rmask = 32'hffffffff; rlab = 24'h00ffff; end // c cyan
        3'd3: begin rvec = t2[95:64];   rmask = 32'hffefffff; rlab = 24'h00ff00; end // d green
        3'd4: begin rvec = t2[63:32];   rmask = 32'hffffffff; rlab = 24'hff8000; end // e orange
        default: begin rvec = t2[31:0]; rmask = 32'hffffffff; rlab = 24'h3070ff; end // f blue
    endcase
end
wire rbar_on = in_rows && rbar_y && (cx >= 10'd48) && (cx < 10'd560) && rbon && rmask[rbit];
wire rbitv   = rvec[rbit];

// S20 (index 19, bus error) has inverted colours
wire inv = (idx == 5'd19);
reg [23:0] sq_col;
always @(*) begin
    if (now[idx])
        sq_col = inv ? 24'hff0000 :
                 (idx == 5'd0 && !vsb) || (idx == 5'd1 && !hsb) ? 24'h006000 : 24'h00ff00;
    else if (ever[idx])
        sq_col = 24'hffff00;
    else
        sq_col = inv ? 24'h00ff00 : 24'hff0000;
end

always @(*) begin
    { r, g, b } = { r_in, g_in, b_in };
    if ((r0_cell || r1_cell || r2_cell) && fr_x)
        { r, g, b } = 24'h000000;                       // black frame
    if ((r0_cell && sq_y0 || r1_cell && sq_y1 || r2_cell && sq_y2) && sq_x)
        { r, g, b } = sq_col;                           // status square
    if (in_wx && in_r2)
        { r, g, b } = 24'h000000;                       // word background
    if (bar_on)
        { r, g, b } = bitv ? 24'hffffff : 24'h404040;   // word bits
    if (in_rows)
        { r, g, b } = 24'h000000;                       // diag030b band
    if (rlab_on)
        { r, g, b } = rlab;                             // row label
    if (rbar_on)
        { r, g, b } = rbitv ? 24'hffffff : 24'h404040;  // row bits
end

endmodule
