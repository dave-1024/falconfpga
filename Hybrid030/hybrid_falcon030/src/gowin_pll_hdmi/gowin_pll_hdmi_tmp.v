//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Part Number: GW5AST-LV138PG484AC1/I0
//Device: GW5AST-138
//Device Version: C


//Change the instance name and port connections to the signal names
//--------Copy here to design--------
    gowin_pll_hdmi your_instance_name(
        .clkin(CLK), //input  clkin
        .init_clk(CLK), //input  init_clk
        .clkout0(hclk5) //output  clkout0
);


//--------Copy end-------------------
