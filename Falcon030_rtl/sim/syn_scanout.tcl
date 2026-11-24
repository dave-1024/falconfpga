# FAL_01: Gowin synthesis-only check of falcon_scanout + falcon_sdp_ram, no pins/PnR.
# Run from an empty scratch dir: gw_sh <path>/syn_scanout.tcl
set W /workspace/falcon_wt
set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file $W/Falcon030_rtl/hdl/video/falcon_sdp_ram.v
add_file $W/Falcon030_rtl/hdl/video/falcon_scanout.v
set_option -synthesis_tool gowinsynthesis
set_option -output_base_name falcon_scanout
set_option -top_module falcon_scanout
set_option -disable_io_insertion 1
run syn
