// ===========================================================================
// pll_wdog.v - PLL lock watchdog + startup status on U15 (F69, branch pmmu)
//
// After a JTAG reconfigure without a power cycle the board sometimes stayed dead (no byte on U15, black HDMI;
// docs/HELPER_SILENCE.md). Every fabric reset (por = !pll_lock) waits for PLL_INIT's O_LOCK, which only rises in its
// final state; if the ICP/LPF search ends on a setting that does not lock, O_LOCK stays low forever.
// This module runs on the raw 50 MHz board clock (clk_g, no PLL in its path):
//   * per PLL: if its O_LOCK is low for T_WAIT (50 ms; PLL_INIT needs ~7 x 2 ms), pulse that PLL_INIT's I_RST for
//     16 clocks so the search restarts. Retries are counted (saturating at 15) and never stop.
//   * while the main PLL is not locked (por), it owns U15 and sends "P" <hex retries main> <lock bits a,d,m as 0/1>
//     CR LF every ~0.5 s (115200 8N1), so a silent link can be told apart from a dead fabric.
//   * status[7:0] = {retries main[3:0], 1'b0, lock ddr3, lock ae350, lock main} for the mailbox/OSD.
// With all PLLs locking on the first try nothing changes: no I_RST pulse, U15 is the fabric's as before.
// ===========================================================================
module pll_wdog #(
    parameter integer N       = 3,
    parameter [31:0]  T_WAIT  = 32'd2_500_000,   // 50 ms at 50 MHz
    parameter [31:0]  T_MSG   = 32'd25_000_000,  // 0.5 s between status lines
    parameter [8:0]   BAUD_DIV = 9'd433          // 50 MHz / 434 = 115207 baud
)(
    input  wire         clk,          // clk_g, 50 MHz raw
    input  wire [N-1:0] lock_a,       // O_LOCK per PLL (async to clk except the PLL_INIT output, sync anyway)
    output reg  [N-1:0] init_rst = {N{1'b0}},
    output wire         tx,           // status UART, idle high
    output wire [7:0]   status
);
    reg [N-1:0] l_s0 = 0, l_s1 = 0;
    always @(posedge clk) begin l_s0 <= lock_a; l_s1 <= l_s0; end

    reg [3:0] retries [0:N-1];
    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : w
        reg [31:0] cnt = 32'd0;
        reg [4:0]  pulse = 5'd0;
        initial retries[g] = 4'd0;
        always @(posedge clk) begin
            if (pulse != 5'd0) begin
                pulse <= pulse - 5'd1;
                init_rst[g] <= (pulse != 5'd1);
                cnt <= 32'd0;
            end else if (l_s1[g]) begin
                cnt <= 32'd0; init_rst[g] <= 1'b0;
            end else if (cnt >= T_WAIT) begin
                pulse <= 5'd17;
                if (retries[g] != 4'hF) retries[g] <= retries[g] + 4'd1;
            end else
                cnt <= cnt + 32'd1;
        end
    end endgenerate

    assign status = {retries[0], 1'b0, (N > 2) ? l_s1[2] : 1'b0, (N > 1) ? l_s1[1] : 1'b0, l_s1[0]};

    // status line "P" hex 'a' 'd' 'm' CR LF while main (index 0) is not locked
    function [7:0] hexc(input [3:0] v); hexc = (v < 10) ? 8'h30 + v : 8'h37 + v; endfunction
    reg [31:0] mt = 32'd0;
    reg [2:0]  ci = 3'd7;           // 7 = idle
    reg [8:0]  div = 9'd0;
    reg [3:0]  nbit = 4'd0;
    reg [9:0]  sh = 10'h3FF;
    reg        txr = 1'b1;
    assign tx = txr;
    reg [7:0] ch;
    always @(*) case (ci)
        3'd0: ch = 8'h50;                         // P
        3'd1: ch = hexc(retries[0]);
        3'd2: ch = (N > 1 && l_s1[1]) ? 8'h31 : 8'h30;  // ae350 PLL
        3'd3: ch = (N > 2 && l_s1[2]) ? 8'h31 : 8'h30;  // ddr3 PLL
        3'd4: ch = l_s1[0] ? 8'h31 : 8'h30;       // main PLL
        3'd5: ch = 8'h0D;
        default: ch = 8'h0A;
    endcase
    always @(posedge clk) begin
        if (nbit != 4'd0) begin
            if (div != BAUD_DIV) div <= div + 9'd1;
            else begin
                div <= 9'd0; txr <= sh[0]; sh <= {1'b1, sh[9:1]}; nbit <= nbit - 4'd1;
            end
        end else if (ci != 3'd7) begin
            sh <= {1'b1, ch, 1'b0}; nbit <= 4'd10; div <= 9'd0;
            ci <= (ci == 3'd6) ? 3'd7 : ci + 3'd1;
        end else begin
            txr <= 1'b1;
            if (l_s1[0]) mt <= 32'd0;
            else if (mt >= T_MSG) begin mt <= 32'd0; ci <= 3'd0; end
            else mt <= mt + 32'd1;
        end
    end
endmodule
