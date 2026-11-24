# FAL_01: Gowin synthesis-only check of falcon_core (CPU + bus + IO + NVRAM + YM + VIDEL regs), no pins/PnR.
# Run from an empty scratch dir: gw_sh <path>/syn_core.tcl. Edit W for the worktree path.
set W /workspace/falcon_wt
set_device GW5AST-LV138PG484AC1/I0 -device_version C
foreach f {pkg address_registers alu bus_interface control data_registers exception_handler opcode_decoder icache dcache mmu top} {
    add_file $W/Atarist_030_wip/hdl/cpu030/wf68k30L_$f.vhd
}
foreach f {top/falcon_core.v bus/falcon_bus.v peri/falcon_io.v peri/falcon_nvram.v peri/falcon_ym_stub.v video/videl_regs.v} {
    add_file $W/Falcon030_rtl/hdl/$f
}
set_option -synthesis_tool gowinsynthesis
set_option -output_base_name falcon_core
set_option -top_module falcon_core
set_option -disable_io_insertion 1
set_option -vhdl_std vhd2008
run syn
