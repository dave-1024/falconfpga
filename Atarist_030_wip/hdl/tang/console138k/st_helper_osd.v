// st_helper_osd.v - FalconFPGA ST_HELPER_OSD (FPGA-Companion port, step 5)
//
// The MiSTeryNano OSD (misc/osd_u8g2.v, Till Harbaum: a 128x64 u8g2
// "display" written by the companion over the OSD target) placed on the raw
// ST video in front of the HDMI frame buffer (st_framebuffer.v), so it shows
// on HDMI. Same SPI commands (1 = show/hide, 2 = tile data), same look
// (darkened box, white text, shadow). Differences to osd_u8g2.v, for the raw
// ST timing in the clk32 domain instead of the scan-doubled LCD path:
//  - the pixel scale is per mode, so the menu is 512x256 on the 640x480 HDMI
//    picture in every ST mode: colour (one frame buffer sample per 2 clk32,
//    every ST line doubled) 8 clk32 x 2 lines per OSD pixel, mono (one
//    sample per clk32, 1:1 lines) 4 clk32 x 4 lines;
//  - centred on the measured DE window (not the whole line), so it sits in
//    the middle of the visible picture;
//  - 4 bit colour in and out (the frame buffer stores 4:4:4).
module st_helper_osd (
    input            clk,          // clk32
    input            reset,
    input            data_in_strobe,
    input            data_in_start,
    input      [7:0] data_in,
    input            hs_n,
    input            vs_n,
    input            de,
    input      [3:0] r_in, g_in, b_in,
    output     [3:0] r_out, g_out, b_out
);
    reg enabled = 1'b0;

    // ---- OSD buffer and SPI interface (as osd_u8g2.v) ----
    reg [7:0] buffer [0:1023];
    reg [9:0] data_cnt;
    reg [7:0] command;
    reg       data_addr_state;
    always @(posedge clk) begin
        if (reset) enabled <= 1'b0;
        else if (data_in_strobe) begin
            if (data_in_start) begin
                command <= data_in;
                data_addr_state <= 1'b1;
                data_cnt <= 10'd0;
            end else begin
                data_addr_state <= 1'b0;
                if (command == 8'd1 && data_addr_state) enabled <= data_in[0];
                if (command == 8'd2) begin
                    if (data_addr_state) data_cnt <= { data_in[6:0], 3'b000 };
                    else begin
                        buffer[data_cnt] <= data_in;
                        data_cnt <= data_cnt + 10'd1;
                    end
                end
            end
        end
    end

    reg deD_line = 1'b0;               // DE seen in the current line
    // ---- measure the active window: DE start/length, first/last DE line ----
    reg        hsD, vsD, deD;
    reg [11:0] hcnt = 0, de_start = 0, de_len = 0, de_start_l = 432, de_len_l = 1280, de_s = 0;
    reg [9:0]  vcnt = 0, v_first = 0, v_last = 0, v_first_l = 66, v_last_l = 265;
    reg        seen_de, mono = 1'b0;
    reg [11:0] hlen = 0;
    always @(posedge clk) begin
        hsD <= hs_n; deD <= de;
        if (hs_n && !hsD) deD_line <= 1'b0;
        else if (de) deD_line <= 1'b1;
        if (de && !deD) de_s <= hcnt;
        if (!de && deD) begin de_start <= de_s; de_len <= hcnt - de_s; end
        if (hs_n && !hsD) begin               // end of hsync: new line
            hlen <= hcnt;
            mono <= (hcnt < 12'd1400);
            hcnt <= 12'd0;
            vsD <= vs_n;
            if (!vs_n && vsD) begin            // start of vsync: new frame
                vcnt <= 10'd0;
                v_first_l <= v_first; v_last_l <= v_last;
                de_start_l <= de_start; de_len_l <= de_len;
                seen_de <= 1'b0;
            end else begin
                vcnt <= vcnt + 10'd1;
                if (deD_line) begin
                    if (!seen_de) v_first <= vcnt;
                    v_last <= vcnt;
                    seen_de <= 1'b1;
                end
            end
        end else
            hcnt <= hcnt + 12'd1;
    end

    // ---- geometry ----
    wire [2:0] hsh = mono ? 3'd2 : 3'd3;          // clk32 per OSD pixel: 4 / 8
    wire [2:0] vsh = mono ? 3'd2 : 3'd1;          // lines per OSD pixel: 4 / 2
    wire [11:0] w  = 12'd128 << hsh;              // OSD width in clk32
    wire [9:0]  h  = 10'd64 << vsh;               // OSD height in lines
    wire [11:0] hstart = de_start_l + (de_len_l >> 1) - (w >> 1);
    wire [9:0]  vmid   = (v_first_l + v_last_l) >> 1;
    wire [9:0]  vstart = vmid - (h >> 1);
    wire [11:0] bw = 12'd2 << hsh;                // border: 2 OSD pixels
    wire [9:0]  bh = 10'd2 << vsh;
    wire [11:0] sw = 12'd4 << hsh;                // shadow offset: 4 OSD pixels
    wire [9:0]  sh = 10'd4 << vsh;

    wire hactive  = hcnt >= hstart - bw && hcnt < hstart + w + bw;
    wire vactive  = vcnt >= vstart - bh && vcnt < vstart + h + bh;
    wire thactive = hcnt >= hstart && hcnt < hstart + w;
    wire tvactive = vcnt >= vstart && vcnt < vstart + h;
    wire shactive = hcnt >= hstart - bw + sw && hcnt < hstart + w + bw + sw;
    wire svactive = vcnt >= vstart - bh + sh && vcnt < vstart + h + bh + sh;
    wire active  = hactive && vactive;
    wire tactive = thactive && tvactive;
    wire sactive = shactive && svactive;

    // pixel address one clk32 ahead (buffer read latency)
    wire [11:0] hoff = hcnt + 12'd1 - hstart;
    wire [9:0]  voff = vcnt - vstart;
    wire [6:0]  col  = hoff >> hsh;
    wire [5:0]  row  = voff >> vsh;
    reg  [7:0]  buffer_byte;
    reg  [2:0]  row_bit;
    always @(posedge clk) begin
        buffer_byte <= buffer[{ row[5:3], col }];
        row_bit <= row[2:0];
    end
    wire osd_pix = buffer_byte[row_bit];

    // ---- mixing (osd_u8g2.v colours, on 4 bits) ----
    wire [3:0] osd_r = (tactive && osd_pix) ? 4'hF : sactive ? { 3'b000, r_in[3] } : { 2'b00, r_in[3:2] };
    wire [3:0] osd_g = (tactive && osd_pix) ? 4'hF : sactive ? { 3'b010, g_in[3] } : { 2'b01, g_in[3:2] };
    wire [3:0] osd_b = (tactive && osd_pix) ? 4'hF : sactive ? { 3'b000, b_in[3] } : { 2'b00, b_in[3:2] };
    assign r_out = !enabled ? r_in : active ? osd_r : sactive ? { 1'b0, r_in[3:1] } : r_in;
    assign g_out = !enabled ? g_in : active ? osd_g : sactive ? { 1'b0, g_in[3:1] } : g_in;
    assign b_out = !enabled ? b_in : active ? osd_b : sactive ? { 1'b0, b_in[3:1] } : b_in;
endmodule
