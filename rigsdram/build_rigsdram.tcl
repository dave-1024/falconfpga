# FalconFPGA: rigsdram oracle. device_version C (this SOM). Replicate on.
# Run from this directory: gw_sh build_rigsdram.tcl
# File list matches rigsdram.gprj. Do not add src/New folder, bus_trace_pkg.vhd,
# gowin_pll_sim.vhd, or rigtest_sdram.hex.
# Dual-purpose pins stay at the tool default. This design does not use them as GPIO.

set_device GW5AST-LV138PG484AC1/I0 -device_version C

add_file src/pll_init.v
add_file src/bus_trace.vhd
add_file src/gowin_pll/gowin_pll.vhd
add_file src/gowin_pll/gowin_pll_mod.vhd
add_file src/rigguest_sdram_pkg.vhd
add_file src/rigsdram_top.vhd
add_file src/sdram_bus_adapter.vhd
add_file src/sdram_ctrl.vhd
add_file src/wf68k30L_address_registers.vhd
add_file src/wf68k30L_alu.vhd
add_file src/wf68k30L_bus_interface.vhd
add_file src/wf68k30L_control.vhd
add_file src/wf68k30L_data_registers.vhd
add_file src/wf68k30L_exception_handler.vhd
add_file src/wf68k30L_opcode_decoder.vhd
add_file src/wf68k30L_pkg.vhd
add_file src/wf68k30L_top.vhd
add_file src/rigsdram.cst
add_file src/rigsdram.sdc

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name rigsdram
set_option -top_module RIGSDRAM_TOP
set_option -replicate_resources 1
set_option -bit_incl_bsram_init 1

run all
