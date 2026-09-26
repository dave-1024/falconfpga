# Clean rigsdram tree

Matches the Gowin Design panel of the 2026-09-24 DONE P build, minus the two disabled files (red X) and minus binaries.

**Needs the Tang SDRAM module in J9.** This is an HDL build. The hybrid (`Hybrid030/`) does not use that module; this tree does. Do not flash with the socket empty.

Do not add: `src/New folder/`, `bus_trace_pkg.vhd`, `gowin_pll_sim.vhd`, `rigtest_sdram.hex`, `impl/`, `*.fs`.

```
rigsdram.gprj
rigsdram.gprj.user
src/pll_init.v
src/bus_trace.vhd
src/gowin_pll/gowin_pll.vhd
src/gowin_pll/gowin_pll_mod.vhd
src/gowin_pll/gowin_pll.ipc
src/gowin_pll/gowin_pll.mod
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
```
