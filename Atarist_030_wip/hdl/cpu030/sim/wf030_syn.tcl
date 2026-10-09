# Gowin synthesis of the WF68K30L core alone -> post-synthesis Verilog
# netlist for Icarus (the core is VHDL; GHDL cannot convert it to Verilog).
# Run from an empty scratch directory: gw_sh <path>/wf030_syn.tcl
# Output: impl/gwsynthesis/wf030.vg
set here [file dirname [file normalize [info script]]]
set_device GW5AST-LV138PG484AC1/I0 -device_version C
foreach f {pkg address_registers alu bus_interface control data_registers exception_handler opcode_decoder} {
    add_file $here/../wf68k30L_$f.vhd
}
# F58: synthesise with CLK_N_EXT = 1 like cpu030_st_bridge.v (falling-edge
# registers on the CLK_N port). The generic default is rewritten in a copy.
set fh [open $here/../wf68k30L_top.vhd r]; set t [read $fh]; close $fh
if {![regsub {(CLK_N_EXT +: integer := )0([;)])} $t {\11\2} t]} { error "CLK_N_EXT generic not found" }
set fh [open wf68k30L_top_clkn.vhd w]; puts -nonewline $fh $t; close $fh
add_file [file normalize wf68k30L_top_clkn.vhd]
set_option -synthesis_tool gowinsynthesis
set_option -output_base_name wf030
set_option -top_module WF68K30L_TOP
set_option -disable_io_insertion 1
run syn
