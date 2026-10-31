// ===========================================================================
// flash_unstick.v - [F70] bring the SPI NOR back to plain SPI mode before the AE350 boots from it
//
// flash_dspi.v (the ST's TOS reader) runs the flash in dual-I/O 0xBB *continuous read* (mode bits M5:4 = 10): the flash then
// takes the next CS# cycle as "address + mode bits" with no command byte. A JTAG reconfigure resets the FPGA but not the flash, so
// after any reload the AE350 boot loader's read command was misread, the helper image came out garbage and the helper stayed
// silent (docs/HELPER_SILENCE.md). Power-up and the programmer's flash ops reset the flash, which is why a replug or a verify fixed it.
// After por, while the AE350 is still in reset and the fabric owns the flash pads, this module sends:
//   1. CS# low, 16 SCK with IO0 = IO1 = 1 driven, CS# high   (mode-bit reset: M5:4 = 11 ends continuous read; harmless otherwise)
//   2. 0x66 (reset enable), 0x99 (reset) in plain SPI on IO0, each its own CS# cycle
//   3. 40 us wait (tRST)
// then done = 1 (sticky). SCK = clk / 8 (4 MHz at 32 MHz), CS# high >= 1 us between cycles.
// ===========================================================================
module flash_unstick #(parameter integer DIV = 4, parameter integer T_GAP = 64, parameter integer T_RST = 1280) (
    input  wire clk, input wire rst,
    output reg  busy = 1'b0, output reg done = 1'b0,
    output reg  csn = 1'b1, output reg sck = 1'b0,
    output reg  io0 = 1'b1, output reg io1_oe = 1'b0      // io1 driven 1 when io1_oe
);
    localparam S_IDLE = 0, S_GAP = 1, S_CYC = 2, S_END = 3, S_WAIT = 4, S_DONE = 5;
    reg [2:0]  st = S_IDLE;
    reg [1:0]  cyc = 0;            // 0: mode-bit exit, 1: 0x66, 2: 0x99
    reg [4:0]  nb = 0;             // bits left in this cycle
    reg [7:0]  sh = 0;
    reg [15:0] t = 0;
    reg [7:0]  d = 0;              // SCK half-period divider
    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; busy <= 1'b1; done <= 1'b0; csn <= 1'b1; sck <= 1'b0; io0 <= 1'b1; io1_oe <= 1'b0;
            cyc <= 0; t <= 0; d <= 0;
        end else case (st)
            S_IDLE: begin busy <= 1'b1; st <= S_GAP; t <= 0; end
            S_GAP: if (t == T_GAP) begin
                    csn <= 1'b0; t <= 0; d <= 0; sck <= 1'b0; st <= S_CYC;
                    if (cyc == 0) begin nb <= 16; io0 <= 1'b1; io1_oe <= 1'b1; sh <= 8'hFF; end
                    else begin nb <= 8; sh <= (cyc == 1) ? 8'h66 : 8'h99; io0 <= (cyc == 1) ? 1'b0 : 1'b1; io1_oe <= 1'b0; end
                end else t <= t + 1;
            S_CYC: if (d == DIV - 1) begin
                    d <= 0;
                    if (!sck) sck <= 1'b1;                                   // flash samples on the rising edge
                    else begin
                        sck <= 1'b0;
                        if (nb == 1) st <= S_END;
                        else begin nb <= nb - 1; if (cyc != 0) begin sh <= {sh[6:0], 1'b1}; io0 <= sh[6]; end end
                    end
                end else d <= d + 1;
            S_END: begin
                    if (d == DIV - 1) begin csn <= 1'b1; io1_oe <= 1'b0; io0 <= 1'b1; d <= 0; t <= 0;
                        if (cyc == 2) st <= S_WAIT; else begin cyc <= cyc + 1; st <= S_GAP; end
                    end else d <= d + 1;
                end
            S_WAIT: if (t == T_RST) st <= S_DONE; else t <= t + 1;
            default: begin busy <= 1'b0; done <= 1'b1; end
        endcase
    end
endmodule
