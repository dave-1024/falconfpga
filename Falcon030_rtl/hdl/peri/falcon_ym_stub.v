// falcon_ym_stub.v - FAL_01: YM2149 stub for the Falcon030 ($FFFF8800-$FFFF88FF)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// No sound. Register select ($8800) and data ($8802) store all 16 registers and read them
// back like a YM2149 (Hatari psg.c and falcon_m28.c: $8804-$88FF shadow $8800-$8803, the
// odd bytes shadow the even ones), so TOS's read-modify-write of port A (reg 14: floppy
// side/drive select, Falcon speaker and DSP reset bits) and port B (reg 15, printer data)
// see what they wrote. Reads of $8802 return $FF as on the chip; $8800 returns the selected
// register. Real YM (jt49) goes in later.
module falcon_ym_stub (
    input  wire       clk,
    input  wire       reset,
    input  wire       sel,      // byte cycle anywhere in $FF8800-$FF88FF
    input  wire [1:1] a,        // address bit 1: 0 = select/read, 1 = write data
    input  wire       wr,
    input  wire [7:0] din,
    output wire [7:0] dout,
    output wire [7:0] porta     // reg 14 (port A) for the glue: floppy select, DSP reset
);
    reg [3:0] rs;
    reg [7:0] r [0:15];
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            rs <= 4'd0;
            for (i = 0; i < 16; i = i + 1) r[i] <= 8'h00;
            r[14] <= 8'hFF; r[15] <= 8'hFF;
        end else if (sel && wr) begin
            if (!a[1]) rs <= din[3:0];
            else r[rs] <= din;
        end
    end
    assign dout  = a[1] ? 8'hFF : r[rs];
    assign porta = r[14];
endmodule
