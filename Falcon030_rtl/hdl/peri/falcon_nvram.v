// falcon_nvram.v - FAL_01: MC146818 RTC/NVRAM for the Falcon030 ($FFFF8961 select, $FFFF8963 data)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Behaviour follows reference/Hybrid030/hybrid_musashi/falcon_m28.c (nvram_*), which
// booted TOS 4.04, and Hatari's nvram.c:
//   regs 0..13 RTC: 0 sec, 2 min, 4 hour (BCD, 24h), 6 weekday, 7 day, 8 month, 9 year,
//   10 reg A ($26, UIP pulses near the end of each second), 11 reg B ($02 24h),
//   12 reg C (reads 0, no interrupts), 13 reg D ($80 = battery good). C and D are read-only.
//   regs 14..63 NVRAM. PRESET = 0 (default): STOCK power-up as Hybrid030 M11h (falcon_m28.c):
//   battery good, user cells zeroed, INVALID checksum, so TOS writes its own defaults like a
//   factory Falcon's first boot (Hybrid030 removed its pre-planted mode for that reason).
//   PRESET = 1: VALID checksum (Hatari: byte 62 = ~sum(14..61), byte 63 = sum) and the video
//   mode word at 28/29 (VMODE_DEFAULT, $001A = VGA | 80 columns | 4 bitplanes). David decides.
// No battery: contents are lost at power-off (later: saved through the helper).
module falcon_nvram #(
    parameter        PRESET = 0,
    parameter [15:0] VMODE_DEFAULT = 16'h001A,
    parameter integer CLK_HZ = 16000000
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       sel_addr,    // byte cycle at $FF8961
    input  wire       sel_data,    // byte cycle at $FF8963
    input  wire       wr,          // write strobe (one clk), with sel_*
    input  wire [7:0] din,
    output reg  [7:0] dout
);
    reg [5:0] idx;
    reg [7:0] mem [0:63];
    // checksum of the default contents (bytes 14..61 are all 0 except the mode word)
    localparam [7:0] SUM = VMODE_DEFAULT[15:8] + VMODE_DEFAULT[7:0];
    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) mem[i] = 8'h00;
        mem[6] = 8'h03; mem[7] = 8'h24; mem[8] = 8'h11; mem[9] = 8'h26;  // Tue 24 Nov 2026 (BCD)
        mem[10] = 8'h26; mem[11] = 8'h02; mem[13] = 8'h80;
        if (PRESET) begin
            mem[28] = VMODE_DEFAULT[15:8]; mem[29] = VMODE_DEFAULT[7:0];
            mem[62] = ~SUM; mem[63] = SUM;
        end
    end
    // seconds tick and the clock (BCD)
    reg [24:0] pre = 0;
    reg [7:0] sec = 8'h00, min = 8'h00, hour = 8'h12;
    wire tick = (pre == CLK_HZ - 1);
    wire uip  = (pre > CLK_HZ - CLK_HZ / 128);
    function [7:0] binc; input [7:0] v; input [7:0] top; begin
        if (v == top) binc = 8'h00;
        else if (v[3:0] == 4'd9) binc = {v[7:4] + 4'd1, 4'd0};
        else binc = v + 8'd1;
    end endfunction
    always @(posedge clk) begin
        if (reset) idx <= 6'd0;
        pre <= tick ? 25'd0 : pre + 25'd1;
        if (tick) begin
            sec <= binc(sec, 8'h59);
            if (sec == 8'h59) begin
                min <= binc(min, 8'h59);
                if (min == 8'h59) hour <= binc(hour, 8'h23);
            end
        end
        if (wr && sel_addr) idx <= din[5:0];
        if (wr && sel_data) begin
            case (idx)
                6'd0: sec <= din; 6'd2: min <= din; 6'd4: hour <= din;
                6'd12, 6'd13: ;
                default: mem[idx] <= din;
            endcase
        end
    end
    always @(*) begin
        if (sel_addr) dout = {2'b00, idx};
        else case (idx)
            6'd0: dout = sec; 6'd2: dout = min; 6'd4: dout = hour;
            6'd10: dout = {uip, 7'h26};
            6'd12: dout = 8'h00;
            default: dout = mem[idx];
        endcase
    end
endmodule
