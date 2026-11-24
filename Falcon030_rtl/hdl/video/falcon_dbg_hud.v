// falcon_dbg_hud.v - FAL_01: always-on hex overlay on the 640x480 HDMI scanout
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drawn in clk_pixel over the picture (and over the loader colour bars).
// Independent of VIDEL: a black framebuffer or a misprogrammed mode still
// shows this strip, so one HDMI grab tells us whether TOS is running, hung,
// or running with a video-register / scanout problem.
//
// Layout, 8x8 cells, y=0..55 (seven rows), navy background:
//   Row 0 y=0..7
//     x=0..7     cyan bar            PC (last instruction-fetch address)
//     x=8..71    8 hex  pc[31:0]
//     x=80..87   yellow bar          last IO write
//     x=88..119  4 hex  io_a
//     x=120..127 '='
//     x=128..159 4 hex  io_d
//     x=168..175 red bar             bus errors
//     x=176..207 4 hex  berr count
//     x=208..215 '@'
//     x=216..279 8 hex  berr address
//   Row 1 y=8..15
//     x=0..7     green bar           VBAS
//     x=8..55    6 hex  vbas[23:0]
//     x=64..71   orange bar          HHT $FF8282
//     x=72..103  4 hex  hht
//     x=112..119 purple bar          VFT $FF82A2
//     x=120..151 4 hex  vft
//     x=160..167 white bar           SPSHIFT $FF8266
//     x=168..199 4 hex  spshift
//     x=208..215 grey bar            ST shift $FF8260
//     x=216..231 2 hex  shmode
//     x=240..247 lime/red bar        TOS CRC32 (lime iff == 32'h028B561D)
//     x=248..311 8 hex  crc
//   Row 2 y=16..23  (16 px flag blocks, lit = on)
//     0 red      cpu_reset (loader still holding)
//     1 maroon   tos_err
//     2 yellow   CPU RESET_OUT
//     3 magenta  CPU halted
//     4 green    crc matches TOS404.IMG
//     5 lime     ram_ready
//     6 cyan     VBL (live)
//     7 white    heartbeat (frame counter lsb)
//     then x=128..135 teal bar + 4 hex fetch count,
//          x=176..183 blue bar + 1 hex planes + 3 hex linebytes + 3 hex height,
//          x=248..255 hdbl (white/dark), x=264..271 vdbl,
//          x=280..287 grey bar + 2 hex frame counter.
//   Rows 3..6 y=24..55  first 8 bus cycles, two per row (0,1 / 2,3 / 4,5 / 6,7):
//     each cycle: teal/orange bar, 6 hex addr, 4 hex data, 2 hex flags
//     flags = {berr, ack_early, rw, siz[1:0], fc[2:0]}. Blank if i >= ncyc.
module falcon_dbg_hud (
    input  wire [9:0]  cx,
    input  wire [9:0]  cy,
    input  wire [31:0] pc,
    input  wire [15:0] io_a,
    input  wire [15:0] io_d,
    input  wire [15:0] berr_count,
    input  wire [31:0] berr_addr,
    input  wire [23:0] vbas,
    input  wire [15:0] hht,
    input  wire [15:0] vft,
    input  wire [15:0] spshift,
    input  wire [7:0]  shmode,
    input  wire [31:0] tos_crc,
    input  wire [7:0]  flags,          // {hb, vbl, ram_ready, crc_ok, halted, reset_out, tos_err, cpu_reset}
    input  wire [15:0] fetch_count,
    input  wire [3:0]  planes,
    input  wire [11:0] linebytes,
    input  wire [9:0]  height,
    input  wire        hdbl,
    input  wire        vdbl,
    input  wire [7:0]  frame,
    input  wire [383:0] cycs,          // 8 x 48: {addr[23:0], data[15:0], flags[7:0]}
    input  wire [3:0]   ncyc,
    output wire        hit,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);
    localparam [31:0] TOS_CRC_OK = 32'h028B561D;
    wire crc_ok = (tos_crc == TOS_CRC_OK);

    // 5x7 hex (and '=' '@') in an 8x8 cell, rows 0..6, columns 1..5 of the cell.
    function [4:0] hexrow;
        input [4:0] ch;      // 0-15 hex, 16='=', 17='@', 18=space
        input [2:0] row;
        begin
            hexrow = 5'b00000;
            if (ch == 5'd16) begin
                if (row == 3'd2 || row == 3'd4) hexrow = 5'b11111;
            end else if (ch == 5'd17) begin
                case (row)
                    3'd0: hexrow = 5'b01110;
                    3'd1: hexrow = 5'b10001;
                    3'd2: hexrow = 5'b10101;
                    3'd3: hexrow = 5'b10101;
                    3'd4: hexrow = 5'b10010;
                    3'd5: hexrow = 5'b10000;
                    3'd6: hexrow = 5'b01110;
                    default: hexrow = 5'b00000;
                endcase
            end else if (ch <= 5'd15) begin
                case (ch[3:0])
                    4'h0: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b10001; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h1: case (row)
                        3'd0: hexrow = 5'b00100; 3'd1: hexrow = 5'b01100; 3'd2: hexrow = 5'b00100;
                        3'd3: hexrow = 5'b00100; 3'd4: hexrow = 5'b00100; 3'd5: hexrow = 5'b00100;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h2: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b00001;
                        3'd3: hexrow = 5'b00110; 3'd4: hexrow = 5'b01000; 3'd5: hexrow = 5'b10000;
                        default: hexrow = 5'b11111;
                    endcase
                    4'h3: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b00001;
                        3'd3: hexrow = 5'b01110; 3'd4: hexrow = 5'b00001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h4: case (row)
                        3'd0: hexrow = 5'b00010; 3'd1: hexrow = 5'b00110; 3'd2: hexrow = 5'b01010;
                        3'd3: hexrow = 5'b10010; 3'd4: hexrow = 5'b11111; 3'd5: hexrow = 5'b00010;
                        default: hexrow = 5'b00010;
                    endcase
                    4'h5: case (row)
                        3'd0: hexrow = 5'b11111; 3'd1: hexrow = 5'b10000; 3'd2: hexrow = 5'b11110;
                        3'd3: hexrow = 5'b00001; 3'd4: hexrow = 5'b00001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h6: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10000; 3'd2: hexrow = 5'b11110;
                        3'd3: hexrow = 5'b10001; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h7: case (row)
                        3'd0: hexrow = 5'b11111; 3'd1: hexrow = 5'b00001; 3'd2: hexrow = 5'b00010;
                        3'd3: hexrow = 5'b00100; 3'd4: hexrow = 5'b01000; 3'd5: hexrow = 5'b01000;
                        default: hexrow = 5'b01000;
                    endcase
                    4'h8: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b01110; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'h9: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b10001; 3'd4: hexrow = 5'b01111; 3'd5: hexrow = 5'b00001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'hA: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b11111; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b10001;
                    endcase
                    4'hB: case (row)
                        3'd0: hexrow = 5'b11110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b11110; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b11110;
                    endcase
                    4'hC: case (row)
                        3'd0: hexrow = 5'b01110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10000;
                        3'd3: hexrow = 5'b10000; 3'd4: hexrow = 5'b10000; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b01110;
                    endcase
                    4'hD: case (row)
                        3'd0: hexrow = 5'b11110; 3'd1: hexrow = 5'b10001; 3'd2: hexrow = 5'b10001;
                        3'd3: hexrow = 5'b10001; 3'd4: hexrow = 5'b10001; 3'd5: hexrow = 5'b10001;
                        default: hexrow = 5'b11110;
                    endcase
                    4'hE: case (row)
                        3'd0: hexrow = 5'b11111; 3'd1: hexrow = 5'b10000; 3'd2: hexrow = 5'b10000;
                        3'd3: hexrow = 5'b11110; 3'd4: hexrow = 5'b10000; 3'd5: hexrow = 5'b10000;
                        default: hexrow = 5'b11111;
                    endcase
                    default: case (row) // F
                        3'd0: hexrow = 5'b11111; 3'd1: hexrow = 5'b10000; 3'd2: hexrow = 5'b10000;
                        3'd3: hexrow = 5'b11110; 3'd4: hexrow = 5'b10000; 3'd5: hexrow = 5'b10000;
                        default: hexrow = 5'b10000;
                    endcase
                endcase
            end
        end
    endfunction

    wire [11:0] height12 = {2'b00, height};

    wire in_hud = (cy < 10'd56) && (cx < 10'd640);
    wire [6:0] col = cx[9:3];          // 0..79
    wire [2:0] px  = cx[2:0];
    wire [2:0] py  = cy[2:0];
    wire [2:0] row = cy[5:3];

    wire [2:0]  cyc_ri   = row - 3'd3;
    wire        cyc_right = (col >= 7'd40);
    wire [3:0]  cyc_i    = {1'b0, cyc_ri, cyc_right};
    wire [47:0] cyc_w    = cycs[48*cyc_i +: 48];
    wire [23:0] cyc_a    = cyc_w[47:24];
    wire [15:0] cyc_d    = cyc_w[23:8];
    wire [7:0]  cyc_f    = cyc_w[7:0];
    wire [6:0]  cyc_bcol = cyc_right ? (col - 7'd40) : col;

    // Which glyph (0-15, 16='=', 17='@', 18=space) at this cell, plus a colour-bar cell.
    reg [4:0]  ch;
    reg        is_bar;
    reg [23:0] bar_rgb;
    reg        is_flag;
    reg        flag_on;
    reg [23:0] flag_rgb;
    always @(*) begin
        ch      = 5'd18;
        is_bar  = 1'b0;
        bar_rgb = 24'h00C0C0;
        is_flag = 1'b0;
        flag_on = 1'b0;
        flag_rgb= 24'h181818;
        if (row == 3'd0) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = 24'h00C0C0; end
            else if (col >= 7'd1 && col <= 7'd8)
                ch = {1'b0, pc[4*(8-(col-7'd1))-1 -: 4]};
            else if (col == 7'd10) begin is_bar = 1'b1; bar_rgb = 24'hF0C000; end
            else if (col >= 7'd11 && col <= 7'd14)
                ch = {1'b0, io_a[4*(4-(col-7'd11))-1 -: 4]};
            else if (col == 7'd15) ch = 5'd16; // '='
            else if (col >= 7'd16 && col <= 7'd19)
                ch = {1'b0, io_d[4*(4-(col-7'd16))-1 -: 4]};
            else if (col == 7'd21) begin is_bar = 1'b1; bar_rgb = 24'hC00000; end
            else if (col >= 7'd22 && col <= 7'd25)
                ch = {1'b0, berr_count[4*(4-(col-7'd22))-1 -: 4]};
            else if (col == 7'd26) ch = 5'd17; // '@'
            else if (col >= 7'd27 && col <= 7'd34)
                ch = {1'b0, berr_addr[4*(8-(col-7'd27))-1 -: 4]};
        end else if (row == 3'd1) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = 24'h00C000; end
            else if (col >= 7'd1 && col <= 7'd6)
                ch = {1'b0, vbas[4*(6-(col-7'd1))-1 -: 4]};
            else if (col == 7'd8) begin is_bar = 1'b1; bar_rgb = 24'hF08000; end
            else if (col >= 7'd9 && col <= 7'd12)
                ch = {1'b0, hht[4*(4-(col-7'd9))-1 -: 4]};
            else if (col == 7'd14) begin is_bar = 1'b1; bar_rgb = 24'hC000C0; end
            else if (col >= 7'd15 && col <= 7'd18)
                ch = {1'b0, vft[4*(4-(col-7'd15))-1 -: 4]};
            else if (col == 7'd20) begin is_bar = 1'b1; bar_rgb = 24'hF0F0F0; end
            else if (col >= 7'd21 && col <= 7'd24)
                ch = {1'b0, spshift[4*(4-(col-7'd21))-1 -: 4]};
            else if (col == 7'd26) begin is_bar = 1'b1; bar_rgb = 24'h808080; end
            else if (col >= 7'd27 && col <= 7'd28)
                ch = {1'b0, shmode[4*(2-(col-7'd27))-1 -: 4]};
            else if (col == 7'd30) begin is_bar = 1'b1; bar_rgb = crc_ok ? 24'h80FF00 : 24'hC00000; end
            else if (col >= 7'd31 && col <= 7'd38)
                ch = {1'b0, tos_crc[4*(8-(col-7'd31))-1 -: 4]};
        end else if (row == 3'd2) begin
            // flags 0..7 at x=0..127 (16 px = 2 cells each)
            if (cx < 10'd128) begin
                is_flag = 1'b1;
                flag_on = flags[cx[6:4]];
                case (cx[6:4])
                    3'd0: flag_rgb = 24'hFF2020;
                    3'd1: flag_rgb = 24'h800000;
                    3'd2: flag_rgb = 24'hF0C000;
                    3'd3: flag_rgb = 24'hC000C0;
                    3'd4: flag_rgb = 24'h00C000;
                    3'd5: flag_rgb = 24'h80FF00;
                    3'd6: flag_rgb = 24'h00C0C0;
                    default: flag_rgb = 24'hF0F0F0;
                endcase
            end else if (col == 7'd16) begin is_bar = 1'b1; bar_rgb = 24'h00E0C0; end
            else if (col >= 7'd17 && col <= 7'd20)
                ch = {1'b0, fetch_count[4*(4-(col-7'd17))-1 -: 4]};
            else if (col == 7'd22) begin is_bar = 1'b1; bar_rgb = 24'h3060FF; end
            else if (col == 7'd23)
                ch = {1'b0, planes};
            else if (col >= 7'd24 && col <= 7'd26)
                ch = {1'b0, linebytes[4*(3-(col-7'd24))-1 -: 4]};
            else if (col >= 7'd27 && col <= 7'd29)
                ch = {1'b0, height12[4*(3-(col-7'd27))-1 -: 4]};
            else if (col == 7'd31) begin is_flag = 1'b1; flag_on = hdbl; flag_rgb = 24'hF0F0F0; end
            else if (col == 7'd33) begin is_flag = 1'b1; flag_on = vdbl; flag_rgb = 24'hF0C000; end
            else if (col == 7'd35) begin is_bar = 1'b1; bar_rgb = 24'h808080; end
            else if (col >= 7'd36 && col <= 7'd37)
                ch = {1'b0, frame[4*(2-(col-7'd36))-1 -: 4]};
        end else if (row >= 3'd3 && row <= 3'd6) begin
            // Two cycles per row, 40 cells (320 px) each.
            // cycle i at col base 0 or 40: bar + 6 addr + 4 data + 2 flags.
            if (cyc_i < {1'b0, ncyc}) begin
                if (cyc_bcol == 7'd0) begin
                    is_bar = 1'b1;
                    bar_rgb = cyc_f[7] ? 24'hC00000 : cyc_f[6] ? 24'hC000C0 : (cyc_right ? 24'hF08000 : 24'h00E0C0);
                end else if (cyc_bcol >= 7'd1 && cyc_bcol <= 7'd6)
                    ch = {1'b0, cyc_a[4*(6-(cyc_bcol-7'd1))-1 -: 4]};
                else if (cyc_bcol >= 7'd8 && cyc_bcol <= 7'd11)
                    ch = {1'b0, cyc_d[4*(4-(cyc_bcol-7'd8))-1 -: 4]};
                else if (cyc_bcol >= 7'd13 && cyc_bcol <= 7'd14)
                    ch = {1'b0, cyc_f[4*(2-(cyc_bcol-7'd13))-1 -: 4]};
            end
        end
    end

    wire [4:0] bits = hexrow(ch, py);
    wire       in_col = (px >= 3'd1) && (px <= 3'd5) && (py <= 3'd6);
    wire       gp = in_col && bits[5'd5 - {2'b00, px}];

    wire [7:0] bg_r = 8'h10, bg_g = 8'h20, bg_b = 8'h40;
    assign hit = in_hud;
    assign r = !in_hud ? 8'd0 :
               is_bar  ? bar_rgb[23:16] :
               is_flag ? (flag_on ? flag_rgb[23:16] : 8'h18) :
               gp      ? 8'hF0 : bg_r;
    assign g = !in_hud ? 8'd0 :
               is_bar  ? bar_rgb[15:8] :
               is_flag ? (flag_on ? flag_rgb[15:8]  : 8'h18) :
               gp      ? 8'hF0 : bg_g;
    assign b = !in_hud ? 8'd0 :
               is_bar  ? bar_rgb[7:0] :
               is_flag ? (flag_on ? flag_rgb[7:0]   : 8'h18) :
               gp      ? 8'hF0 : bg_b;
endmodule
