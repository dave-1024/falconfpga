# Headless build of rigsdram — replicate_resources MUST be on
cd /workspace/repos/falconfpga/reference/rigsdram

if {[catch {open_project /workspace/repos/falconfpga/reference/rigsdram/rigsdram.gprj} err]} {
  puts "open_project failed: $err"
  puts "Falling back to create_project + add_file"
  create_project -name rigsdram -dir /workspace/repos/falconfpga/reference/rigsdram/proj_fallback \
    -pn GW5AST-LV138PG484AC1/I0 -device_version C -force
  foreach f {
    src/pll_init.v
    src/bus_trace.vhd
    src/gowin_pll/gowin_pll.vhd
    src/gowin_pll/gowin_pll_mod.vhd
    src/rigguest_sdram_pkg.vhd
    src/rigsdram_top.vhd
    src/sdram_bus_adapter.vhd
    src/sdram_ctrl.vhd
    src/wf68k30L_address_registers.vhd
    src/wf68k30L_alu.vhd
    src/wf68k30L_bus_interface.vhd
    src/wf68k30L_control.vhd
    src/wf68k30L_data_registers.vhd
    src/wf68k30L_exception_handler.vhd
    src/wf68k30L_opcode_decoder.vhd
    src/wf68k30L_pkg.vhd
    src/wf68k30L_top.vhd
    src/rigsdram.cst
    src/rigsdram.sdc
  } {
    add_file /workspace/repos/falconfpga/reference/rigsdram/$f
  }
  set_device -name GW5AST-138C -device_version C
  # pn already set at create
}

set_option -top_module RIGSDRAM_TOP
set_option -output_base_name rigsdram
set_option -gen_text_timing_rpt 1
set_option -replicate_resources 1
puts "CONFIRM: set_option -replicate_resources 1 applied"

# Echo process config replicate flag if present
foreach cfg [glob -nocomplain impl/*process_config.json proj_fallback/*/impl/*process_config.json] {
  puts "CONFIG_FILE: $cfg"
  catch {puts [exec rg -n Replicate_Resources $cfg]}
}

puts "=== RUN ALL ==="
run all
puts "=== BUILD FINISHED ==="
exit
