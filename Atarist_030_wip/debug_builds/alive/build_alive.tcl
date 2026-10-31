# gw_sh build_alive.tcl  (run in this dir; PLL=1 in env adds the PLL variant)
set pll [expr {[info exists ::env(PLL)] && $::env(PLL) == 1}]
set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file alive.v
if {$pll} { add_file ../../hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi.v
            add_file ../../hdl/tang/console138k/gowin_pll_hdmi/gowin_pll_hdmi_mod.v
            add_file ../../hdl/tang/console138k/pll_init.v
            set_option -verilog_std sysv2017
            set_option -include_path {.}
            set fh [open defs.vh w]; puts $fh "`define WITH_PLL"; close $fh } else { set fh [open defs.vh w]; close $fh }
add_file alive.cst
add_file alive.sdc
set_option -top_module top
set_option -output_base_name alive
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_jtag_as_gpio 0
set_option -multi_boot 0
run all
