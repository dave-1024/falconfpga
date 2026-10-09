// st_helper_usb.v - FalconFPGA ST_HELPER_USB (FPGA-Companion port, step 4)
//
// USB keyboard/mouse for the AE350 companion. The AE350 has no USB host, so
// two usb_hid_host cores (nand2mario, low-speed HID boot protocol) run on
// the Console's USB-A host ports and the AE350 polls their reports over the
// existing companion link: HID target, command 0x40. The firmware turns the
// reports into boot-protocol packets for FPGA-Companion's hid.c
// (kbd_parse/mouse_parse), which sends key/mouse events back on the HID
// target as on MiSTeryNano. No new clock net: the cores run on clk32 with a
// 3-of-8 clock enable (exactly 12 MHz on average, edges on a 31 ns grid).
//
// Frame: SS# low, 0x01 (HID), 0x40, port (0/1), then 11 reads:
//   0x5A, {conerr, 5'b0, typ}, report count, modifiers, key1..key4,
//   mouse buttons, mouse dx, mouse dy  (dx/dy summed since the last read,
//   saturated to +-127, cleared by the read)
// typ: 0 none, 1 keyboard, 2 mouse, 3 gamepad.
module st_helper_usb (
    input            clk32,
    input            reset,
    inout            usb1_dp, usb1_dn,
    inout            usb2_dp, usb2_dn,
    input            data_in_strobe,
    input            data_in_start,
    input      [7:0] data_in,
    output reg       active,
    output reg [7:0] data_out
);
    reg [2:0] acc = 3'd0;
    reg       ce = 1'b0;
    always @(posedge clk32) { ce, acc } <= { 1'b0, acc } + 4'd3;

    reg [7:0] por = 8'd0;
    always @(posedge clk32) if (ce && !por[7]) por <= por + 8'd1;
    wire rst_n = por[7];

    wire       r [0:1];
    wire       e [0:1];
    wire [1:0] t [0:1];
    wire [7:0] m [0:1], k1 [0:1], k2 [0:1], k3 [0:1], k4 [0:1];
    wire [7:0] mb [0:1], dx [0:1], dy [0:1];

    usb_hid_host u_usb0 (
        .usbclk(clk32), .usbce(ce), .usbrst_n(rst_n),
        .usb_dm(usb1_dn), .usb_dp(usb1_dp),
        .typ(t[0]), .report(r[0]), .conerr(e[0]),
        .key_modifiers(m[0]), .key1(k1[0]), .key2(k2[0]), .key3(k3[0]), .key4(k4[0]),
        .mouse_btn(mb[0]), .mouse_dx(dx[0]), .mouse_dy(dy[0]),
        .game_snes(), .game_l(), .game_r(), .game_u(), .game_d(),
        .game_a(), .game_b(), .game_x(), .game_y(), .game_sel(), .game_sta(),
        .game_lb(), .game_rb(), .dbg_hid_report()
    );
    usb_hid_host u_usb1 (
        .usbclk(clk32), .usbce(ce), .usbrst_n(rst_n),
        .usb_dm(usb2_dn), .usb_dp(usb2_dp),
        .typ(t[1]), .report(r[1]), .conerr(e[1]),
        .key_modifiers(m[1]), .key1(k1[1]), .key2(k2[1]), .key3(k3[1]), .key4(k4[1]),
        .mouse_btn(mb[1]), .mouse_dx(dx[1]), .mouse_dy(dy[1]),
        .game_snes(), .game_l(), .game_r(), .game_u(), .game_d(),
        .game_a(), .game_b(), .game_x(), .game_y(), .game_sel(), .game_sta(),
        .game_lb(), .game_rb(), .dbg_hid_report()
    );

    reg [3:0] state;
    // per-port report latch (everything is in the clk32 domain)
    reg       rd [0:1];
    reg [7:0] cnt [0:1];
    reg [8:0] sx [0:1], sy [0:1];    // signed sums
    // cleared in the same cycle as the snapshot below, so no movement is lost
    wire take = data_in_strobe && !data_in_start && active && state == 4'd0;
    wire clr [0:1];
    assign clr[0] = take && !data_in[0];
    assign clr[1] = take &&  data_in[0];

    function [8:0] sat_add(input [8:0] a, input [7:0] b);
        reg [9:0] s;
        begin
            s = { a[8], a } + { {2{b[7]}}, b };
            if ($signed(s) > 127)       sat_add = 9'd127;
            else if ($signed(s) < -127) sat_add = 9'h181;   // -127
            else                         sat_add = s[8:0];
        end
    endfunction

    integer i;
    always @(posedge clk32) begin
        for (i = 0; i < 2; i = i + 1) begin
            rd[i] <= r[i];
            if (clr[i]) begin
                sx[i] <= 9'd0; sy[i] <= 9'd0;
            end
            if (r[i] && !rd[i]) begin
                cnt[i] <= cnt[i] + 8'd1;
                if (t[i] == 2'd2) begin
                    sx[i] <= sat_add(clr[i] ? 9'd0 : sx[i], dx[i]);
                    sy[i] <= sat_add(clr[i] ? 9'd0 : sy[i], dy[i]);
                end
            end
        end
        if (reset) begin
            cnt[0] <= 8'd0; cnt[1] <= 8'd0;
            sx[0] <= 9'd0; sx[1] <= 9'd0; sy[0] <= 9'd0; sy[1] <= 9'd0;
        end
    end

    // HID target command 0x40
    reg       port;
    reg [7:0] snap [0:9];
    always @(posedge clk32) begin
        if (reset) active <= 1'b0;
        else if (data_in_strobe) begin
            if (data_in_start) begin
                active <= (data_in == 8'h40);
                state <= 4'd0;
            end else if (active) begin
                if (state != 4'd15) state <= state + 4'd1;
                if (state == 4'd0) begin
                    port     <= data_in[0];
                    data_out <= 8'h5A;
                    snap[0]  <= { e[data_in[0]], 5'b00000, t[data_in[0]] };
                    snap[1]  <= cnt[data_in[0]];
                    snap[2]  <= m[data_in[0]];
                    snap[3]  <= k1[data_in[0]];
                    snap[4]  <= k2[data_in[0]];
                    snap[5]  <= k3[data_in[0]];
                    snap[6]  <= k4[data_in[0]];
                    snap[7]  <= mb[data_in[0]];
                    snap[8]  <= sx[data_in[0]][7:0];
                    snap[9]  <= sy[data_in[0]][7:0];
                end else if (state <= 4'd10)
                    data_out <= snap[state - 4'd1];
                else
                    data_out <= 8'h00;
            end
        end
    end
endmodule
