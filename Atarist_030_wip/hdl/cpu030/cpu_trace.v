// ===========================================================================
// cpu_trace.v - [F78] DIAG_TRACE: full-speed per-clk_cpu trace of the 68030 pins in BRAM
// Writes one 144-bit entry on every clk_cpu rising edge from CPU release (rst_n rising) into a
// DEPTH-entry ring. When HALT_OUTn goes low it records POST more entries and freezes. While frozen it
// sends over U15 (clk_32, only while `go`): "TRACE" CRLF, then DEPTH lines of 36 hex digits, oldest first:
//   [143:136] {ipl2:0, avecn, rmcn, 3'b0}
//   [135:120] cnt  = clk_cpu cycles since release (saturates at FFFF)
//   [119:104] ctl  = {asn, dsn, dsack1n, dsack0n, berrn, haltn, rstn, rwn, fc2:0, siz1:0, statusn, ipendn, exc}
//   [103:96]  vec  = exception vector number (DBG_EXC, valid with exc)
//   [95:64] adr, [63:32] data (DATA_IN if RW, else DATA_OUT), [31:0] PC
// repeated every ~20 s while frozen. Rearmed by the next CPU reset. Observation only.
// ===========================================================================
module cpu_trace #(
    parameter integer AW     = 10,           // 1024 entries
    parameter integer POST   = 64,
    parameter integer CLK_HZ = 32_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire         clk_cpu,
    input  wire         rst_n,          // cpu_rst_n (clk_cpu)
    input  wire         halt_n,         // HALT_OUTn (clk_cpu)
    input  wire [143:0] ent,            // entry, minus cnt (bits 135:120 ignored)
    input  wire         clk,            // clk_32
    input  wire         go,
    output wire         want,           // frozen and waiting for U15
    output reg          own = 1'b0,
    output reg          tx  = 1'b1
);
    localparam integer DIV = CLK_HZ / BAUD;
    localparam integer N = 1 << AW;
    (* syn_ramstyle = "block_ram" *) reg [143:0] mem [0:N-1];
    // ---- capture (clk_cpu) ----
    reg [AW-1:0] wp = 0; reg [15:0] cnt = 0; reg [7:0] post = 0;
    reg run = 1'b0, frz = 1'b0, wrapped = 1'b0, rst_d = 1'b0;
    always @(posedge clk_cpu) begin
        rst_d <= rst_n;
        if (!rst_n) begin run <= 1'b0; frz <= 1'b0; end
        else if (!rst_d) begin run <= 1'b1; frz <= 1'b0; wp <= 0; cnt <= 0; post <= 0; wrapped <= 1'b0; end
        else if (run) begin
            mem[wp] <= {ent[143:136], cnt, ent[119:0]};
            wp <= wp + 1'b1; if (&wp) wrapped <= 1'b1;
            if (cnt != 16'hFFFF) cnt <= cnt + 1'b1;
            if (!halt_n || post != 0) begin
                post <= post + 1'b1;
                if (post == POST - 1) begin run <= 1'b0; frz <= 1'b1; end
            end
        end
    end
    // ---- dump (clk_32); wp/wrapped are static while frz ----
    reg [2:0] fs = 0; always @(posedge clk) fs <= {fs[1:0], frz};
    wire frozen = fs[2];
    reg [31:0] rep = 0; reg pend = 1'b0;
    always @(posedge clk) begin
        if (!frozen) begin rep <= 0; pend <= 1'b0; end
        else if (rep == 0) begin pend <= 1'b1; rep <= 20 * CLK_HZ; end
        else if (!own) rep <= rep - 1;
        if (own) pend <= 1'b0;
    end
    assign want = pend & frozen;
    reg [AW-1:0] ra = 0; reg [143:0] rd = 0;
    always @(posedge clk) rd <= mem[ra];
    reg [AW:0] k = 0; reg [5:0] pos = 0; reg hdr = 1'b0;
    function [7:0] hx(input [3:0] v); hx = (v < 10) ? 8'h30 + v : 8'h37 + v; endfunction
    reg [7:0] ch;
    always @(*) begin
        if (hdr) case (pos) 6'd0: ch = "T"; 6'd1: ch = "R"; 6'd2: ch = "A"; 6'd3: ch = "C"; 6'd4: ch = "E"; 6'd5: ch = 8'h0D; default: ch = 8'h0A; endcase
        else if (pos < 6'd36) ch = hx(rd[143 - 4*pos -: 4]);
        else if (pos == 6'd36) ch = 8'h0D;
        else ch = 8'h0A;
    end
    wire [5:0] last = hdr ? 6'd6 : 6'd37;
    wire [AW:0] cnt_e = wrapped ? N : {1'b0, wp};
    reg [15:0] bd = 0; reg [3:0] bi = 0;
    always @(posedge clk) begin
        if (!own) begin
            tx <= 1'b1;
            if (want && go) begin own <= 1'b1; hdr <= 1'b1; k <= 0; pos <= 0; bi <= 0; bd <= 0; ra <= wrapped ? wp : 0; end
        end else begin
            if (bd == DIV - 1) begin
                bd <= 0;
                if (bi == 4'd9) begin
                    bi <= 0;
                    if (pos == last) begin
                        pos <= 0;
                        if (hdr) hdr <= 1'b0;
                        else begin
                            k <= k + 1'b1; ra <= ra + 1'b1;
                            if (k + 1'b1 == cnt_e) own <= 1'b0;
                        end
                    end else pos <= pos + 1'b1;
                end else bi <= bi + 1'b1;
            end else bd <= bd + 1'b1;
            if (bd == 0) tx <= (bi == 0) ? 1'b0 : (bi == 9) ? 1'b1 : ch[bi - 1];
        end
    end
endmodule
