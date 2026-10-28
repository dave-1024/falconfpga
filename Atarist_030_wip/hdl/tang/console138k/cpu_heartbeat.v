// ===========================================================================
// cpu_heartbeat.v - [F72] debug: ST/68030 heartbeat on U15 (only with `define DIAG_HEARTBEAT)
// Once a second, when the AE350's UART has been idle for 10 ms, it borrows U15 for one line:
//   "H" ff c aaaa rrrrr wwww gi bbbbbbbb pppppp nnnn CR LF   (hex)
//   ff    = diag_flags {halted_n, as_n, rom_n, resb, ram_ready, flash_ready, sd_ready, bl616_reset}
//   c     = diag_030 {berr, dsack, req, run}
//   aaaa  = AS# falling edges in the last second (low 16 bits, saturating)
//   rrrrr = last TOS ROM word index fetched (rom_addr[17:1])
//   wwww  = TOS ROM word 0 as last read (expect 602E for TOS 2.06; FFFF = flash read garbage)
//   gi    = bridge first BERR: {got, info FC2:0 RW SIZE1:0 bad_space} (diag_trace[167:160])
//   bbbbbbbb = first BERR address, pppppp = last program fetch A23:0 (diag_trace[159:128], [23:0])
//   nnnn  = line counter
// so "is the 68030 running" can be read on serial without a picture. Default builds do not include it.
// ===========================================================================
module cpu_heartbeat #(
    parameter integer CLK_HZ = 32_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        ae_tx,        // AE350 UART TX (async)
    input  wire [7:0]  flags,
    input  wire [3:0]  c030,
    input  wire [16:0] rom_idx,
    input  wire [15:0] rom_data,
    input  wire [167:0] trace,
    output reg         own = 1'b0,   // 1 while this module drives U15
    output reg         tx  = 1'b1
);
    localparam integer DIV  = CLK_HZ / BAUD;
    localparam integer IDLE = CLK_HZ / 100;      // 10 ms
    reg [2:0]  ae_s = 3'b111;
    reg [31:0] idle = 0, sec = 0;
    reg [1:0]  as_s = 2'b11;
    reg [15:0] as_cnt = 0, as_last = 0, nline = 0;
    reg [7:0]  fl_l; reg [3:0] c_l; reg [16:0] r_l; reg [7:0] g_l; reg [31:0] b_l; reg [23:0] p_l;
    reg        pend = 1'b0;
    reg [15:0] w0 = 16'h0000, w0_l = 16'h0000;
    wire       start;
    always @(posedge clk) begin
        ae_s <= {ae_s[1:0], ae_tx};
        as_s <= {as_s[0], flags[6]};
        if (!ae_s[2]) idle <= 0; else if (idle != 32'hFFFFFFFF) idle <= idle + 1;
        if (as_s == 2'b10 && as_cnt != 16'hFFFF) as_cnt <= as_cnt + 1;
        if (sec == CLK_HZ - 1) begin
            sec <= 0; as_last <= as_cnt; as_cnt <= 0; pend <= 1'b1;
            fl_l <= flags; c_l <= c030; r_l <= rom_idx; w0_l <= w0; g_l <= trace[167:160]; b_l <= trace[159:128]; p_l <= trace[23:0];
        end else sec <= sec + 1;
        if (start) pend <= 1'b0;
        if (rom_idx == 17'd0 && !flags[5]) w0 <= rom_data;
    end
    function [7:0] hx(input [3:0] v); hx = (v < 10) ? 8'h30 + v : 8'h37 + v; endfunction
    // line: 39 chars
    reg [5:0] ci = 0; reg [3:0] bi = 0; reg [15:0] bd = 0;
    assign start = pend && !own && (idle >= IDLE) && !rst;
    reg [7:0] ch;
    wire [143:0] nibs = {fl_l, c_l, as_last, 3'b0, r_l, w0_l, g_l, b_l, p_l, nline};   // 36 hex digits
    always @(*) begin
        if (ci == 6'd0) ch = "H";
        else if (ci <= 6'd36) ch = hx(nibs[143 - 4*(ci-1) -: 4]);
        else if (ci == 6'd37) ch = 8'h0D;
        else ch = 8'h0A;
    end
    always @(posedge clk) begin
        if (rst) begin own <= 1'b0; tx <= 1'b1; end
        else if (start) begin own <= 1'b1; ci <= 0; bi <= 0; bd <= 0; end
        else if (own) begin
            if (bd == DIV - 1) begin
                bd <= 0;
                if (bi == 4'd9) begin
                    bi <= 0;
                    if (ci == 6'd38) begin own <= 1'b0; tx <= 1'b1; nline <= nline + 1; end
                    else begin ci <= ci + 1; end
                end else bi <= bi + 1;
            end else bd <= bd + 1;
            if (bd == 0) tx <= (bi == 0) ? 1'b0 : (bi == 9) ? 1'b1 : ch[bi - 1];
        end
    end
endmodule
