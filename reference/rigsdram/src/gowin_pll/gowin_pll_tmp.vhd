--Copyright (C)2014-2026 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Part Number: GW5AST-LV138PG484AC1/I0
--Device: GW5AST-138
--Device Version: C


--Change the instance name and port connections to the signal names
----------Copy here to design--------
component Gowin_PLL
    port (
        clkin: in std_logic;
        init_clk: in std_logic;
        clkout0: out std_logic;
        clkout1: out std_logic;
        lock: out std_logic
    );
end component;


your_instance_name: Gowin_PLL
    port map (
        clkin => clkin,
        init_clk => init_clk,
        clkout0 => clkout0,
        clkout1 => clkout1,
        lock => lock
    );


----------Copy end-------------------
