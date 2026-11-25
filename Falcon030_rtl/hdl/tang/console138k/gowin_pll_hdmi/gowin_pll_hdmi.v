module gowin_pll_hdmi(
    clkin,
    init_clk,
    clkout0,
    lock
);

// FalconFPGA: copied from Hybrid030/hybrid_falcon030/src/gowin_pll_hdmi/.
// Only change: 'lock' (PLL_INIT O_LOCK) is exported as a port, like
// pll_160m does, so the HDMI pixel domain can be held in reset until lock.
// 50 MHz in, VCO 787.5 MHz, clkout0 = 126 MHz (5x 25.2 MHz TMDS clock).


input clkin;
input init_clk;
output clkout0;
output lock;
wire [5:0] icpsel;
wire [2:0] lpfres;
wire pll_lock;
wire pll_rst;


    gowin_pll_hdmi_MOD u_pll(
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
    defparam u_pll_init.MULTI_FAC = 15;


endmodule
