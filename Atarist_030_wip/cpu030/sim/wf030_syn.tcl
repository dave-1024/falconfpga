# Gowin synthesis of the WF68K30L core alone -> post-synthesis Verilog
# netlist for Icarus (the core is VHDL; GHDL cannot convert it to Verilog).
# Run from an empty scratch directory: gw_sh <path>/wf030_syn.tcl
# Output: impl/gwsynthesis/wf030.vg
set here [file dirname [file normalize [info script]]]
set_device GW5AST-LV138PG484AC1/I0 -device_version C
foreach f {pkg address_registers alu bus_interface control data_registers exception_handler opcode_decoder top} {
    add_file $here/../wf68k30L_$f.vhd
}
set_option -synthesis_tool gowinsynthesis
set_option -output_base_name wf030
set_option -top_module WF68K30L_TOP
set_option -disable_io_insertion 1
run syn
