// Behavioural 16-bit SDRAM (W9825G6KH-like, 4 banks x 8K rows x 512 cols), CL2, BL1,
// sampled on the controller clock edge after the command register (as sdram.v sees it).
// Checks: bank state for ACT/RD/WR, tRC, auto-refresh with all banks idle, read DQM
// (must be 00 at the READ edge and the next), data-bus contention with the controller.
module sdram_model (input clk, input [2:0] cmd, input [12:0] a, input [1:0] ba, input [1:0] dqm,
                    inout [15:0] dq, input ctl_oe, output reg [31:0] errors = 0);
    localparam ACT=3'b011, RD=3'b101, WR=3'b100, PRE=3'b010, REF=3'b001, MRS=3'b000;
    reg [15:0] mem [0:(1<<24)-1];        // {ba, row[12:0], col[8:0]} = 24 bits
    reg        act [0:3]; reg [12:0] row [0:3]; integer act_t [0:3]; integer free_t [0:3];
    integer t = 0, i;
    reg [15:0] q; reg qen = 0;
    reg [23:0] p1a; reg p1 = 0, p2 = 0; reg [23:0] p2a;
    assign dq = qen ? q : 16'bz;
    initial for (i = 0; i < (1<<24); i = i + 1) mem[i] = 16'h0000;
    initial for (i = 0; i < 4; i = i + 1) begin act[i] = 0; act_t[i] = -100; free_t[i] = 0; end
    always @(posedge clk) begin
        t = t + 1;
        // read pipeline: READ seen at t -> data driven t+1..t+2 (captured by sdram.v at t+2)
        if (qen) qen <= 0;
        if (p1) begin q <= mem[p1a]; qen <= 1; end
        p1 <= 0;
        if (qen === 1'b1 && ctl_oe) begin errors = errors + 1; $display("%t SDRAM ERR bus contention", $time); end
        case (cmd)
        ACT: begin
            if (act[ba]) begin errors = errors + 1; $display("%t SDRAM ERR ACT on open bank %0d", $time, ba); end
            if (t - act_t[ba] < 2 || t < free_t[ba]) begin errors = errors + 1; $display("%t SDRAM ERR tRC/tRP bank %0d", $time, ba); end
            act[ba] = 1; row[ba] = a; act_t[ba] = t; end
        RD, WR: begin
            if (!act[ba]) begin errors = errors + 1; $display("%t SDRAM ERR %s on idle bank %0d", $time, cmd==RD?"RD":"WR", ba); end
            if (cmd == RD) begin
                if (dqm != 2'b00) begin errors = errors + 1; $display("%t SDRAM ERR read DQM", $time); end
                p1 <= 1; p1a <= {ba, row[ba], a[8:0]};
            end else begin
                if (!dqm[1]) mem[{ba, row[ba], a[8:0]}][15:8] = dq[15:8];
                if (!dqm[0]) mem[{ba, row[ba], a[8:0]}][7:0]  = dq[7:0];
                if (^dq === 1'bx && dqm != 2'b11) begin errors = errors + 1; $display("%t SDRAM ERR write data X", $time); end
            end
            if (a[10]) begin act[ba] = 0; free_t[ba] = t + (cmd == WR ? 3 : 2); end
            end
        PRE: for (i = 0; i < 4; i = i + 1) if (a[10] || i == ba) begin act[i] = 0; free_t[i] = t + 1; end
        REF: for (i = 0; i < 4; i = i + 1) if (act[i] || t < free_t[i]) begin errors = errors + 1; $display("%t SDRAM ERR REFRESH with bank %0d busy", $time, i); end
        default: ;
        endcase
        if (cmd == RD) ; // dqm on the following edge is checked below
    end
    reg rd_d = 0;
    always @(posedge clk) begin
        if (rd_d && dqm != 2'b00) begin errors = errors + 1; $display("%t SDRAM ERR read DQM (+1)", $time); end
        rd_d <= (cmd == RD);
    end
endmodule
