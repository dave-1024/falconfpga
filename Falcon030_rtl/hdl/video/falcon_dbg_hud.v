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
// Layout, 8x8 cells, y=0..79 (ten rows), navy background:
//   Rows 0-2: as before (PC, last IO, BERR; VBAS/HHT/VFT/SPSHIFT/SHMODE/CRC;
//             flags, fetch count, planes/linebytes/height, hdbl/vdbl, frame).
//   Row 3 y=24..31
//     cyan 4 hex VCO $FF82C0; lime 8 hex _phystop $42E; yellow 8 hex _frclock
//     $466; white/lime 8 hex XOR of the $700..$7FF PMMU table (lime iff the
//     top 24 bits match the TOS image, $0F0000; U-bit writebacks only touch
//     the low nibble).
//   Row 4 y=32..39
//     teal/orange/purple/magenta 8 hex each: descriptors at $700, $740, $7C0,
//     $7F8 (expected 00000742, 000007C2, 00000001, 00E00001; U sets bit 3).
//   Row 5 y=40..47
//     red 8 hex first program fetch outside $00E0xxxx (0 if still in TOS);
//     orange 8 hex previous $E0 fetch; grey 6 hex last $700..$7FF read
//     address (table walk) + 8 hex data.
//   Rows 6-7 y=48..63  last 8 IO writes, oldest first, four per row:
//     bar + 4 hex addr + 4 hex data.
//   Rows 8-9 y=64..79  last 8 program-fetch addresses, oldest first, four
//     per row, 8 hex each. Frozen after the first fetch outside $E0xxxx.
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
    // Packed post-PMMU debug (see falcon_core.v):
    //  [383:352] d700  [351:320] d740  [319:288] d7c0  [287:256] d7f8
    //  [255:224] tblxor [223:192] phystop [191:160] frclock
    //  [159:144] vco    [143:128] reserved
    //  [127:96]  outpc  [95:64] prevpc
    //  [63:40]   walk_a [39:8] walk_d  [7:0] unused
    input  wire [383:0] cycs,
    input  wire [3:0]   ncyc,          // ncyc[0] = has left $E0 (program space)
    input  wire [255:0] io_ring,       // 8 x {addr[15:0], data[15:0]}, [31:0] oldest
    input  wire [255:0] pc_ring,       // 8 x pc[31:0], [31:0] oldest
    output wire        hit,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);
    localparam [31:0] TOS_CRC_OK = 32'h028B561D;
    localparam [23:0] TBLXOR_HI  = 24'h0F0000; // expected table XOR, ignoring U/M nibble
    wire crc_ok = (tos_crc == TOS_CRC_OK);
    wire left_e0 = ncyc[0];
    wire [31:0] d700    = cycs[383:352];
    wire [31:0] d740    = cycs[351:320];
    wire [31:0] d7c0    = cycs[319:288];
    wire [31:0] d7f8    = cycs[287:256];
    wire [31:0] tblxor  = cycs[255:224];
    wire [31:0] phystop = cycs[223:192];
    wire [31:0] frclock = cycs[191:160];
    wire [15:0] vco     = cycs[159:144];
    wire [31:0] outpc   = cycs[127:96];
    wire [31:0] prevpc  = cycs[95:64];
    wire [23:0] walk_a  = cycs[63:40];
    wire [31:0] walk_d  = cycs[39:8];
    wire tbl_hi_ok = (tblxor[31:8] == TBLXOR_HI);

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

    wire in_hud = (cy < 10'd80) && (cx < 10'd640);
    wire [6:0] col = cx[9:3];          // 0..79
    wire [2:0] px  = cx[2:0];
    wire [2:0] py  = cy[2:0];
    wire [3:0] row = cy[6:3];          // 0..9

    // Which glyph (0-15, 16='=', 17='@', 18=space) at this cell, plus a colour-bar cell.
    reg [4:0]  ch;
    reg        is_bar;
    reg [23:0] bar_rgb;
    reg        is_flag;
    reg        flag_on;
    reg [23:0] flag_rgb;
    integer    k;
    reg [31:0] io_slot, pc_slot;
    always @(*) begin
        ch      = 5'd18;
        is_bar  = 1'b0;
        bar_rgb = 24'h00C0C0;
        is_flag = 1'b0;
        flag_on = 1'b0;
        flag_rgb= 24'h181818;
        io_slot = 32'd0;
        pc_slot = 32'd0;
        if (row == 4'd0) begin
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
        end else if (row == 4'd1) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = 24'h00C000; end
            else if (col >= 7'd1 && col <= 7'd6)
                ch = {1'b0, vbas[4*(6-(col-7'd1))-1 -: 4]};
            else if (col == 7'd8) begin is_bar = 1'b1; bar_rgb = 24'hF08000; end
            else if (col >= 7'd9 && col <= 7'd12)
                ch = {1'b0, hht[4*(4-(col-7'd9))-1 -: 4]};
            else if (col == 7'd14) begin is_bar = 1'b1; bar_rgb = 24'hC000F0; end
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
        end else if (row == 4'd2) begin
            if (col < 7'd16 && col[0] == 1'b0) begin
                is_flag = 1'b1;
                flag_on = flags[col[3:1]];
                case (col[3:1])
                    3'd0: flag_rgb = 24'hC00000; // cpu_reset
                    3'd1: flag_rgb = 24'h800000; // tos_err
                    3'd2: flag_rgb = 24'hF0C000; // reset_out
                    3'd3: flag_rgb = 24'hC000C0; // halted
                    3'd4: flag_rgb = 24'h00C000; // crc_ok
                    3'd5: flag_rgb = 24'h80FF00; // ram_ready
                    3'd6: flag_rgb = 24'h00C0C0; // vbl
                    default: flag_rgb = 24'hF0F0F0; // heartbeat
                endcase
            end
            else if (col == 7'd16) begin is_bar = 1'b1; bar_rgb = 24'h008080; end
            else if (col >= 7'd17 && col <= 7'd20)
                ch = {1'b0, fetch_count[4*(4-(col-7'd17))-1 -: 4]};
            else if (col == 7'd22) begin is_bar = 1'b1; bar_rgb = 24'h0040C0; end
            else if (col == 7'd23)
                ch = {1'b0, planes};
            else if (col >= 7'd24 && col <= 7'd26)
                ch = {1'b0, linebytes[4*(3-(col-7'd24))-1 -: 4]};
            else if (col >= 7'd27 && col <= 7'd29)
                ch = {1'b0, height12[4*(3-(col-7'd27))-1 -: 4]};
            else if (col == 7'd31) begin is_flag = 1'b1; flag_on = hdbl; flag_rgb = 24'hF0C000; end
            else if (col == 7'd33) begin is_flag = 1'b1; flag_on = vdbl; flag_rgb = 24'hF0C000; end
            else if (col == 7'd35) begin is_bar = 1'b1; bar_rgb = 24'h808080; end
            else if (col >= 7'd36 && col <= 7'd37)
                ch = {1'b0, frame[4*(2-(col-7'd36))-1 -: 4]};
        end else if (row == 4'd3) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = 24'h00C0C0; end
            else if (col >= 7'd1 && col <= 7'd4)
                ch = {1'b0, vco[4*(4-(col-7'd1))-1 -: 4]};
            else if (col == 7'd6) begin is_bar = 1'b1; bar_rgb = 24'h80FF00; end
            else if (col >= 7'd7 && col <= 7'd14)
                ch = {1'b0, phystop[4*(8-(col-7'd7))-1 -: 4]};
            else if (col == 7'd16) begin is_bar = 1'b1; bar_rgb = 24'hF0C000; end
            else if (col >= 7'd17 && col <= 7'd24)
                ch = {1'b0, frclock[4*(8-(col-7'd17))-1 -: 4]};
            else if (col == 7'd26) begin is_bar = 1'b1; bar_rgb = tbl_hi_ok ? 24'h80FF00 : 24'hC00000; end
            else if (col >= 7'd27 && col <= 7'd34)
                ch = {1'b0, tblxor[4*(8-(col-7'd27))-1 -: 4]};
        end else if (row == 4'd4) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = 24'h00E0C0; end
            else if (col >= 7'd1 && col <= 7'd8)
                ch = {1'b0, d700[4*(8-(col-7'd1))-1 -: 4]};
            else if (col == 7'd10) begin is_bar = 1'b1; bar_rgb = 24'hF08000; end
            else if (col >= 7'd11 && col <= 7'd18)
                ch = {1'b0, d740[4*(8-(col-7'd11))-1 -: 4]};
            else if (col == 7'd20) begin is_bar = 1'b1; bar_rgb = 24'hC000F0; end
            else if (col >= 7'd21 && col <= 7'd28)
                ch = {1'b0, d7c0[4*(8-(col-7'd21))-1 -: 4]};
            else if (col == 7'd30) begin is_bar = 1'b1; bar_rgb = 24'hC00080; end
            else if (col >= 7'd31 && col <= 7'd38)
                ch = {1'b0, d7f8[4*(8-(col-7'd31))-1 -: 4]};
        end else if (row == 4'd5) begin
            if (col == 7'd0) begin is_bar = 1'b1; bar_rgb = left_e0 ? 24'hC00000 : 24'h00C000; end
            else if (col >= 7'd1 && col <= 7'd8)
                ch = {1'b0, outpc[4*(8-(col-7'd1))-1 -: 4]};
            else if (col == 7'd10) begin is_bar = 1'b1; bar_rgb = 24'hF08000; end
            else if (col >= 7'd11 && col <= 7'd18)
                ch = {1'b0, prevpc[4*(8-(col-7'd11))-1 -: 4]};
            else if (col == 7'd20) begin is_bar = 1'b1; bar_rgb = 24'h808080; end
            else if (col >= 7'd21 && col <= 7'd26)
                ch = {1'b0, walk_a[4*(6-(col-7'd21))-1 -: 4]};
            else if (col >= 7'd28 && col <= 7'd35)
                ch = {1'b0, walk_d[4*(8-(col-7'd28))-1 -: 4]};
        end else if (row == 4'd6 || row == 4'd7) begin
            // Four IO slots per row, 10 cells each (bar + 4 addr + 4 data + gap).
            // row 6: slots 0-3, row 7: slots 4-7. Slot 0 is oldest.
            k = (row == 4'd6) ? (col / 10) : (4 + (col / 10));
            if ((col / 10) < 4) begin
                io_slot = io_ring[32*k +: 32];
                if ((col % 10) == 0) begin
                    is_bar = 1'b1;
                    bar_rgb = (row == 4'd6) ? 24'hF0C000 : 24'hF08000;
                end else if ((col % 10) >= 1 && (col % 10) <= 4)
                    ch = {1'b0, io_slot[16+4*(4-((col%10)-1))-1 -: 4]};
                else if ((col % 10) >= 5 && (col % 10) <= 8)
                    ch = {1'b0, io_slot[4*(4-((col%10)-5))-1 -: 4]};
            end
        end else if (row == 4'd8 || row == 4'd9) begin
            // Four PCs per row, 10 cells (bar + 8 hex + gap). Slot 0 oldest.
            k = (row == 4'd8) ? (col / 10) : (4 + (col / 10));
            if ((col / 10) < 4) begin
                pc_slot = pc_ring[32*k +: 32];
                if ((col % 10) == 0) begin
                    is_bar = 1'b1;
                    bar_rgb = left_e0 ? 24'hC00000 : 24'h00E0C0;
                end else if ((col % 10) >= 1 && (col % 10) <= 8)
                    ch = {1'b0, pc_slot[4*(8-((col%10)-1))-1 -: 4]};
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
