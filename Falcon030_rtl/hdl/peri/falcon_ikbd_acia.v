// falcon_ikbd_acia.v - FAL_01: Hybrid030-style keyboard ACIA + IKBD stub
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Falcon-side only: does not modify the shared ST acia.v / ikbd HD63701.
// Behaviour copied from Hybrid030 falcon_m28.c M5 (and io_read8/io_write8):
//   $FFFC00 status: bit 1 TDRE is always 1; bit 0 RDRF + bit 7 IRQ when a
//                   queued IKBD byte has been delivered to RDR
//   $FFFC02 data:   read returns RDR and clears RDRF+IRQ
//   write $FFFC00:  bits [1:0]==2'b11 is a master reset (SR=0x02)
//   write $FFFC02:  IKBD command bytes, with the Hybrid length table so
//                   multi-byte commands consume their operands
//     $80 $01 reset: flush the FIFO and reply with the self-test / version
//                    byte. Hybrid030 sent $F0; the real IKBD and Hatari send
//                    $F1, and EmuTOS/TOS 4.04 accept any $Fx (ikbd_reset:
//                    (version & 0xF0) == 0xF0). We send $F1.
//     $1C read clock: $FC + six BCD bytes (same dummy date as Hybrid030)
//     $08/$0B/$11 mouse on, $12/$13 mouse off: accepted, no reply
//   MIDI is not in this module (the existing acia.v instance stays).
//
// pbus holds acia_cs for one E period; side effects fire on the rising edge
// of sel so RDR is popped once per CPU cycle.
module falcon_ikbd_acia (
    input  wire       clk,
    input  wire       reset,
    input  wire       sel,
    input  wire       rs,      // 0 = status/control ($FFFC00), 1 = data ($FFFC02)
    input  wire       rw,      // 1 = read (same polarity as ST acia.v)
    input  wire [7:0] din,
    output wire [7:0] dout,
    output wire       irq
);
    localparam [7:0] IKBD_VERSION = 8'hF1;

    reg [7:0] fifo [0:15];
    reg [3:0] rd_ptr, wr_ptr;
    wire      empty = (rd_ptr == wr_ptr);
    wire [3:0] wr_nxt = wr_ptr + 4'd1;
    wire      full  = (wr_nxt == rd_ptr);

    reg [7:0] rdr;
    reg [7:0] sr;               // [7] IRQ, [1] TDRE, [0] RDRF
    assign irq  = sr[7];
    assign dout = rs ? rdr : sr;

    reg sel_d;
    wire strobe = sel & ~sel_d;

    reg [7:0] cmd0, cmd1;
    reg [2:0] cmdpos, cmdlen;

    function [2:0] ikbd_cmd_len;
        input [7:0] op;
        begin
            case (op)
                8'h80: ikbd_cmd_len = 3'd2;
                8'h07: ikbd_cmd_len = 3'd2;
                8'h09: ikbd_cmd_len = 3'd5;
                8'h0A: ikbd_cmd_len = 3'd3;
                8'h0B: ikbd_cmd_len = 3'd3;
                8'h0C: ikbd_cmd_len = 3'd3;
                8'h0E: ikbd_cmd_len = 3'd6;
                8'h17: ikbd_cmd_len = 3'd2;
                8'h19: ikbd_cmd_len = 3'd7;
                8'h1B: ikbd_cmd_len = 3'd7;
                8'h20: ikbd_cmd_len = 3'd4;
                8'h21: ikbd_cmd_len = 3'd3;
                8'h22: ikbd_cmd_len = 3'd3;
                default: ikbd_cmd_len = 3'd1;
            endcase
        end
    endfunction

    // one-cycle request to push N bytes from push_dat[0..]
    reg        do_reset_reply;
    reg        do_clock_reply;

    always @(posedge clk) begin
        if (reset) begin
            sel_d          <= 1'b0;
            rd_ptr         <= 4'd0;
            wr_ptr         <= 4'd0;
            rdr            <= 8'h00;
            sr             <= 8'h02;
            cmdpos         <= 3'd0;
            cmdlen         <= 3'd1;
            cmd0           <= 8'h00;
            cmd1           <= 8'h00;
            do_reset_reply <= 1'b0;
            do_clock_reply <= 1'b0;
        end else begin
            sel_d          <= sel;
            do_reset_reply <= 1'b0;
            do_clock_reply <= 1'b0;
            sr[1]          <= 1'b1;     // TDRE always

            // ACIA access (one shot per pbus cycle)
            if (strobe) begin
                if (rw) begin
                    if (rs) begin
                        sr[0] <= 1'b0;
                        sr[7] <= 1'b0;
                    end
                end else if (!rs) begin
                    if (din[1:0] == 2'b11)
                        sr <= 8'h02;    // master reset
                end else begin
                    // IKBD command byte
                    if (cmdpos == 3'd0) begin
                        cmd0   <= din;
                        cmdlen <= ikbd_cmd_len(din);
                    end
                    cmd1 <= din;
                    if (cmdpos + 3'd1 >= (cmdpos == 3'd0 ? ikbd_cmd_len(din) : cmdlen)) begin
                        cmdpos <= 3'd0;
                        if ((cmdpos == 3'd0 ? din : cmd0) == 8'h80 && din == 8'h01)
                            do_reset_reply <= 1'b1;
                        else if ((cmdpos == 3'd0 ? din : cmd0) == 8'h1C)
                            do_clock_reply <= 1'b1;
                    end else
                        cmdpos <= cmdpos + 3'd1;
                end
            end

            // FIFO replies (next cycle after the command completes)
            if (do_reset_reply) begin
                fifo[0] <= IKBD_VERSION;
                rd_ptr  <= 4'd0;
                wr_ptr  <= 4'd1;
            end else if (do_clock_reply) begin
                fifo[0] <= 8'hFC;
                fifo[1] <= 8'h99;
                fifo[2] <= 8'h12;
                fifo[3] <= 8'h31;
                fifo[4] <= 8'h23;
                fifo[5] <= 8'h59;
                fifo[6] <= 8'h00;
                rd_ptr  <= 4'd0;
                wr_ptr  <= 4'd7;
            end else if (!sel && !sr[0] && !empty) begin
                // Deliver only while the pbus cycle is idle. pbus samples
                // acia_d at the end of a full E period, so RDR must stay
                // stable for the whole sel pulse.
                rdr    <= fifo[rd_ptr];
                rd_ptr <= rd_ptr + 4'd1;
                sr[0]  <= 1'b1;
                sr[7]  <= 1'b1;
            end
        end
    end
endmodule
