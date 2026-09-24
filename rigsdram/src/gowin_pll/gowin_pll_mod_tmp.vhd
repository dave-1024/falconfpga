--Copyright (C)2014-2026 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.12.03 (64-bit)
--IP Version: 1.0
--Part Number: GW5AST-LV138PG484AC1/I0
--Device: GW5AST-138
--Device Version: C
--Created Time: Mon Aug 31 19:34:31 2026

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component Gowin_PLL_MOD
    port (
        lock: out std_logic;
        clkout0: out std_logic;
        clkout1: out std_logic;
        clkin: in std_logic;
        reset: in std_logic;
        icpsel: in std_logic_vector(5 downto 0);
        lpfres: in std_logic_vector(2 downto 0);
        lpfcap: in std_logic_vector(1 downto 0)
    );
end component;

your_instance_name: Gowin_PLL_MOD
    port map (
        lock => lock,
        clkout0 => clkout0,
        clkout1 => clkout1,
        clkin => clkin,
        reset => reset,
        icpsel => icpsel,
        lpfres => lpfres,
        lpfcap => lpfcap
    );

----------Copy end-------------------
