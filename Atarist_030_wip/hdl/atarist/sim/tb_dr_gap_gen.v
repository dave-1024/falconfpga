`timescale 1ns/1ps
module tb;
reg clk_32=0, clk_cpu=0; always #15.6 clk_32=~clk_32; always @(posedge clk_32) clk_cpu<=~clk_cpu;
reg porb=0, resb=0;
reg reset; reg peripheral_reset; reg mcu_reset_n=1; reg [6:0] reset_cnt=7'h7f; reg cpu_reset_n_d;
wire ext_reset=!resb; wire cpu_reset_n_o=1'b1;
// FalconFPGA: double reset on cold start, same scheme as rigsdram's AUTO_WARM
// broker (rigsdram_top.vhd AW_FREE_RUN/AW_PULSE). After power-up, once the
// first ST reset has ended, let the CPU run DR_GAP clk_32 cycles, then reload
// reset_cnt once (= one ST reset-button press). Re-armed only by porb.
// 1536 = 512 (bridge RESET_HOLD, 128 clk_cpu) + 1024 (~256 clk_cpu free run).
// ST_DR_PRECPU (2026-10-15, warm-reset F67/F68 test): the second pulse comes 64 clk_32
// after the first release, inside the bridge's CPU hold (2 sync + RESET_HOLD 128 clk_cpu
// = ~260 clk_32), so the chipset/GSTMCU/SDRAM path is still reset twice but the 030 is
// released only once and never sees a reset in the middle of EmuTOS's start-up (with F67
// it would honour it; see docs/RESET_PATHS.md). Undefined: the original rigsdram timing.
`ifdef ST_DR_PRECPU
localparam [10:0] DR_GAP = 11'd64;
`else
localparam [10:0] DR_GAP = 11'd1536;
`endif
reg   [1:0] dr_st  = 2'd0;   // 0 = wait first release, 1 = free run, 2 = done
reg  [10:0] dr_cnt = 11'd0;


always @(posedge clk_32) begin

    cpu_reset_n_d <= cpu_reset_n_o;

	reset <= reset_cnt != 0;

	if (reset_cnt != 0) reset_cnt <= reset_cnt - 1'd1;
	if (ext_reset) reset_cnt <= 7'h7f;

	if (!porb) begin
		dr_st  <= 2'd0;
		dr_cnt <= 11'd0;
	end else if (dr_st == 2'd0) begin
		if (reset_cnt == 0) dr_st <= 2'd1;
	end else if (dr_st == 2'd1) begin
		if (reset_cnt != 0) dr_cnt <= 11'd0;          // reset again meanwhile: restart gap
		else if (dr_cnt == DR_GAP) begin
			reset_cnt <= 7'h7f;                        // second reset pulse
			dr_st     <= 2'd2;
		end else dr_cnt <= dr_cnt + 11'd1;
	end

	peripheral_reset <= reset | ~cpu_reset_n_o;

	// don't keep the GSTMCU in reset, because its signals are needed for the SDRAM controller
	if (reset_cnt == 10) mcu_reset_n <= 0;
	else if (reset_cnt < 8) mcu_reset_n <= 1;
	if (~cpu_reset_n_o & cpu_reset_n_d) mcu_reset_n <= 0;
end

localparam integer RESET_HOLD=128;
wire extReset=reset, pwrUp=!porb;
    localparam [7:0] RHOLD = RESET_HOLD;
    (* syn_preserve = 1 *) reg [1:0] rst_sync = 2'b11;
    reg [7:0]  rst_cnt   = 8'd0;
    reg        cpu_rst_n = 1'b0;
    wire       st_rst    = extReset | pwrUp;

    always @(posedge clk_cpu) begin
        rst_sync <= {rst_sync[0], st_rst};
        if (rst_sync[1]) begin
            rst_cnt   <= 8'd0;
            cpu_rst_n <= 1'b0;
        end else if (rst_cnt != RHOLD) begin
            rst_cnt   <= rst_cnt + 8'd1;
            cpu_rst_n <= 1'b0;
        end else begin
            cpu_rst_n <= 1'b1;
        end
    end


integer rel=0, t0=0; reg prev=0;
always @(posedge clk_32) begin
  prev<=cpu_rst_n;
  if (cpu_rst_n && !prev) begin rel=rel+1; $display("%0t ns CPU released #%0d", $time, rel); end
  if (!cpu_rst_n && prev) $display("%0t ns CPU reset asserted again (CPU had been running)", $time);
end
reg rp=0; always @(posedge clk_32) begin rp<=reset; if(reset!=rp) $display("%0t ns ST reset=%0d", $time, reset); end
initial begin #200 porb=1; #3000 resb=1; #400000 $display("DONE releases=%0d", rel); $finish; end
endmodule
