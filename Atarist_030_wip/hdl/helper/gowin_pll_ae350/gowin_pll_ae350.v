module gowin_pll_ae350(
    clkin,
    init_clk,
    init_rst,
    clkout0,
    clkout1,
    clkout2,
    clkout3,
    clkout4,
    lock
);


input clkin;
input init_clk;
input init_rst;   // [F69] PLL_INIT restart from pll_wdog.v
output clkout0;
output clkout1;
output clkout2;
output clkout3;
output clkout4;
output lock;      // [F69] O_LOCK for pll_wdog.v
wire [5:0] icpsel;
wire [2:0] lpfres;
wire pll_lock;
wire pll_rst;


    gowin_pll_ae350_MOD u_pll(
        .clkout1(clkout1),
        .clkout2(clkout2),
        .clkout3(clkout3),
        .clkout4(clkout4),
        .clkout0(clkout0),
        .lock(pll_lock),
        .clkin(clkin),
        .reset(pll_rst),
        .icpsel(icpsel),
        .lpfres(lpfres),
        .lpfcap(2'b00)
    );


    PLL_INIT u_pll_init(
        .CLKIN(init_clk),
        .I_RST(init_rst),
        .O_RST(pll_rst),
        .PLLLOCK(pll_lock),
        .O_LOCK(lock),
        .ICPSEL(icpsel),
        .LPFRES(lpfres)
    );
    defparam u_pll_init.CLK_PERIOD = 20;
    defparam u_pll_init.MULTI_FAC = 16;


endmodule
