module pll_sd64(clkin, init_clk, rst_in, clkout0, clkout1, lock);
input clkin;     // clk32
input init_clk;  // clk_g (50 MHz)
input rst_in;    // hold reset until clk32 is stable (pll_hdmi locked)
output clkout0;  // 64 MHz
output clkout1;  // 64 MHz, 327 deg (pad)
output lock;
wire [5:0] icpsel; wire [2:0] lpfres; wire pll_lock; wire pll_rst;
wire nc2, nc3, nc4, nc5, nc6;
pll_sd64_MOD u_pll(.clkout0(clkout0), .clkout1(clkout1), .clkout2(nc2), .clkout3(nc3), .clkout4(nc4),
    .clkout5(nc5), .clkout6(nc6), .lock(pll_lock), .clkin(clkin), .reset(pll_rst),
    .icpsel(icpsel), .lpfres(lpfres), .lpfcap(2'b00));
PLL_INIT u_pll_init(.CLKIN(init_clk), .I_RST(rst_in), .O_RST(pll_rst), .PLLLOCK(pll_lock),
    .O_LOCK(lock), .ICPSEL(icpsel), .LPFRES(lpfres));
defparam u_pll_init.CLK_PERIOD = 20;
defparam u_pll_init.MULTI_FAC = 30;
endmodule
