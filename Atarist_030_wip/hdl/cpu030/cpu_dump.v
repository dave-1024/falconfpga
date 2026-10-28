// ===========================================================================
// cpu_dump.v - [F77] DIAG_DUMP: Hatari-style register dump on U15 while the 68030 is halted
// While HALT_OUTn has been low for 1 ms, every ~5 s (and only while top.sv grants U15 with `go`, i.e. the AE350
// UART is idle) it sends:  "DUMP" CRLF, then 32 lines "XX=hhhhhhhh" CRLF:
//   D0..D7, A0..A6, US IS MS (USP/ISP/MSP), PC, SR, VB (VBR), TC, CH CL (CRP), SH SL (SRP), T0 T1, MU (MMUSR),
//   FA (FAULT_ADR), SS (SSW), BA BI (last bridge BERR address / {got, FC2:0, RW, SIZE1:0, bad_space}).
// The CPU is halted, so its registers are static and are read directly (no snapshot flops).
// ===========================================================================
module cpu_dump #(
    parameter integer CLK_HZ = 32_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire         clk,
    input  wire         halt_n,      // synchronised HALT_OUTn
    input  wire [639:0] regs,        // {D7..D0, A0..A6, USP, ISP, MSP, PC, VBR}
    input  wire [15:0]  sr,
    input  wire [287:0] pmmu,        // {TC, CRP, SRP, TT0, TT1, MMUSR, FAULT_ADR, SSW16}
    input  wire [31:0]  berr_adr,
    input  wire [7:0]   berr_info,
    input  wire         go,          // U15 may be taken now
    output reg          own = 1'b0,
    output reg          tx  = 1'b1
);
    localparam integer DIV = CLK_HZ / BAUD;
    reg [31:0] hcnt = 0, rep = 0;
    always @(posedge clk) begin
        if (halt_n) hcnt <= 0; else if (hcnt != 32'hFFFFFFFF) hcnt <= hcnt + 1;
    end
    wire halted = (hcnt >= CLK_HZ / 1000);
    reg pend = 1'b0;
    always @(posedge clk) begin
        if (!halted) begin rep <= 0; pend <= 1'b0; end
        else if (rep == 0) begin pend <= 1'b1; rep <= 5 * CLK_HZ; end
        else if (!own) rep <= rep - 1;
        if (own) pend <= 1'b0;
    end
    function [7:0] hx(input [3:0] v); hx = (v < 10) ? 8'h30 + v : 8'h37 + v; endfunction
    // item k (0..31): label and value
    reg [5:0] k = 0; reg [3:0] pos = 0;   // k = 32: header line "DUMP"
    reg [15:0] lab; reg [31:0] val;
    always @(*) begin
        val = 32'd0; lab = "??";
        case (k)
            6'd0,6'd1,6'd2,6'd3,6'd4,6'd5,6'd6,6'd7: begin lab = {"D", 8'h30 + k[2:0]}; val = regs[384 + 32*k +: 32]; end
            6'd8,6'd9,6'd10,6'd11,6'd12,6'd13,6'd14: begin lab = {"A", 8'h30 + (k - 6'd8)}; val = regs[352 - 32*(k-8) +: 32]; end
            6'd15: begin lab = "US"; val = regs[159:128]; end
            6'd16: begin lab = "IS"; val = regs[127:96]; end
            6'd17: begin lab = "MS"; val = regs[95:64]; end
            6'd18: begin lab = "PC"; val = regs[63:32]; end
            6'd19: begin lab = "SR"; val = {16'd0, sr}; end
            6'd20: begin lab = "VB"; val = regs[31:0]; end
            6'd21: begin lab = "TC"; val = pmmu[287:256]; end
            6'd22: begin lab = "CH"; val = pmmu[255:224]; end
            6'd23: begin lab = "CL"; val = pmmu[223:192]; end
            6'd24: begin lab = "SH"; val = pmmu[191:160]; end
            6'd25: begin lab = "SL"; val = pmmu[159:128]; end
            6'd26: begin lab = "T0"; val = pmmu[127:96]; end
            6'd27: begin lab = "T1"; val = pmmu[95:64]; end
            6'd28: begin lab = "MU"; val = {16'd0, pmmu[63:48]}; end
            6'd29: begin lab = "FA"; val = pmmu[47:16]; end
            6'd30: begin lab = "SS"; val = {16'd0, pmmu[15:0]}; end
            6'd31: begin lab = "BA"; val = berr_adr; end
            6'd32: begin lab = "BI"; val = {24'd0, berr_info}; end
            default: begin lab = "DU"; val = 32'd0; end
        endcase
    end
    // line = lab[0] lab[1] '=' 8 hex CR LF (13 chars); header (k = 33) = "DUMP" CR LF
    reg [7:0] ch;
    always @(*) begin
        if (k == 6'd33) case (pos) 4'd0: ch = "D"; 4'd1: ch = "U"; 4'd2: ch = "M"; 4'd3: ch = "P"; 4'd4: ch = 8'h0D; default: ch = 8'h0A; endcase
        else case (pos)
            4'd0: ch = lab[15:8]; 4'd1: ch = lab[7:0]; 4'd2: ch = "=";
            4'd11: ch = 8'h0D; 4'd12: ch = 8'h0A;
            default: ch = hx(val[31 - 4*(pos-3) -: 4]);
        endcase
    end
    wire [3:0] last = (k == 6'd33) ? 4'd5 : 4'd12;
    reg [15:0] bd = 0; reg [3:0] bi = 0;
    always @(posedge clk) begin
        if (!own) begin
            tx <= 1'b1;
            if (pend && go && halted) begin own <= 1'b1; k <= 6'd33; pos <= 0; bi <= 0; bd <= 0; end
        end else begin
            if (bd == DIV - 1) begin
                bd <= 0;
                if (bi == 4'd9) begin
                    bi <= 0;
                    if (pos == last) begin
                        pos <= 0;
                        if (k == 6'd33) k <= 6'd0;
                        else if (k == 6'd32) own <= 1'b0;
                        else k <= k + 6'd1;
                    end else pos <= pos + 1;
                end else bi <= bi + 1;
            end else bd <= bd + 1;
            if (bd == 0) tx <= (bi == 0) ? 1'b0 : (bi == 9) ? 1'b1 : ch[bi - 1];
        end
    end
endmodule
