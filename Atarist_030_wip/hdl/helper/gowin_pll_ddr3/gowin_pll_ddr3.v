module gowin_pll_ddr3(
    clkin,
    init_clk,
    enclk0,
    enclk1,
    enclk2,
    clkout0,
    clkout1,
    clkout2,
    lock
);


input clkin;
input init_clk;
input enclk0;
input enclk1;
input enclk2;
output clkout0;
output clkout1;
output clkout2;
output lock;
wire [5:0] icpsel;
wire [2:0] lpfres;
wire pll_lock;
wire pll_rst;


    gowin_pll_ddr3_MOD u_pll(
        .enclk0(enclk0),
        .enclk1(enclk1),
        .enclk2(enclk2),
        .clkout1(clkout1),
        .clkout2(clkout2),
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
        .I_RST(1'b0),
        .O_RST(pll_rst),
        .PLLLOCK(pll_lock),
        .O_LOCK(lock),
        .ICPSEL(icpsel),
        .LPFRES(lpfres)
    );
    defparam u_pll_init.CLK_PERIOD = 20;
    defparam u_pll_init.MULTI_FAC = 16;


endmodule
