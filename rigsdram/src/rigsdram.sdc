// =====================================================================
// rigsdram.sdc -- TIMING constraints only.  Never IO_LOC lines here.
//
// ONE COMMAND PER LINE.  Gowin's SDC reader is not full Tcl and does
// not accept a backslash line continuation: it truncates the command
// at the backslash and then complains the remaining options are
// missing.
// =====================================================================

// ---------------------------------------------------------------------
// CLOCKS  [F43]
//
// The 50 MHz board clock enters on pin CLK.  A PLL (Gowin_PLL, instance
// u_pll in rigsdram_top.vhd) divides it into two outputs:
//     clkout0 -> clk50    50   MHz  (SDRAM controller, adapter, UART)
//     clkout1 -> core_clk 12.5 MHz  (the CPU)
//
// This REPLACED a fabric /4 counter that made core_clk a logic net the
// timing tool modelled as a clock edge at t=0 while clocking its own
// flop 2.68 ns later -- a real hold violation on the divider feedback,
// plus two more where the controller ran on the raw pin, phase
// unrelated to core_clk.  See the P&R path tables from the pre-PLL
// build.
//
// ONLY the input clock is declared here.  A Gowin PLL AUTO-DERIVES its
// output clocks from the primitive's divider parameters and propagates
// them through -- declaring generated clocks on the PLL outputs by hand
// fought the tool (TA2003 "can't set constraint", TA2004 "cannot get
// clock").  An earlier attempt with get_pins {u_pll/clkout0} also
// failed because the generated wrapper nests the primitive deeper than
// that path (u_pll/u_pll/PLL_inst).
//
// Gowin auto-derives the two PLL output clocks and names them after the
// primitive output pins (confirmed from this build's synthesis report):
//     u_pll/u_pll/PLL_inst/CLKOUT0.default_gen_clk   20 ns / 50   MHz
//     u_pll/u_pll/PLL_inst/CLKOUT1.default_gen_clk   80 ns / 12.5 MHz
// The double u_pll/u_pll is the instance in the top (u_pll) plus the
// same name reused inside the generated wrapper.  The multicycle lines
// below reference these exact names.  CLKOUT0 = clk50, CLKOUT1 = core_clk.
create_clock -name clk_ref -period 20 -waveform {0 10} [get_ports {CLK}]

// [F43] Name the PLL output clocks OURSELVES.  The tool AUTO-derives
// them too (as ...PLL_inst/CLKOUTn.default_gen_clk) but those names do
// not exist yet when the SDC is PARSED, so get_clocks cannot reference
// them -- every attempt returned TA2004.  Declaring them here with
// create_generated_clock on the PLL output NETS makes the names exist
// at parse time, and the multicycle lines below can use them.
//
// The nets are the top-level signals u_pll drives: clk50 (clkout0, the
// 50 MHz output) and core_clk (clkout1, /4 = 12.5 MHz).  These names
// resolve because get_nets matches top-level signal names at parse time,
// unlike the derived-clock names which do not exist yet.
create_generated_clock -name clk50    -source [get_ports {CLK}] -master_clock clk_ref -divide_by 1 [get_nets {clk50}]
create_generated_clock -name core_clk -source [get_ports {CLK}] -master_clock clk_ref -divide_by 4 [get_nets {core_clk}]

// ---------------------------------------------------------------------
// MULTICYCLE: 68030 bus signals into the adapter.  core_clk -> clk50.
// (Rationale unchanged: the address is held the whole bus cycle, ~240
// ns, and the adapter cannot capture until ASn is low, so two clk50
// periods is what the protocol already guarantees.)
set_multicycle_path 2 -setup -from [get_clocks {core_clk}] -to [get_clocks {clk50}]
set_multicycle_path 1 -hold  -from [get_clocks {core_clk}] -to [get_clocks {clk50}]

// NO set_clock_groups -asynchronous, DELIBERATELY.  The adapter crosses
// both ways -- it samples ASn/ADR/RWn/SIZE launched on core_clk and
// drives DSACKn/DATA_IN back for the CPU to capture on core_clk's
// FALLING edge -- and both clocks come from one PLL, so they are phase
// locked, not asynchronous.  Declaring them async would stop the tool
// analysing exactly the paths that matter.

// ---------------------------------------------------------------------
// AFTER P&R, CHECK THESE FOUR THINGS
//
// 1. Clock Summary names BOTH clk50 and core_clk.  If either is absent
//    its paths were never analysed, whatever the summary says.
//
// 2. Do NOT trust "Total Negative Slack Summary".  In the pre-PLL build
//    it read 0.000 across all rows with 0 endpoints while the path
//    tables held negative paths -- every one CROSS-CLOCK, which TNS
//    here does not cover.
//
// 3. Read the Setup and Hold path tables directly.  The three hold
//    violations F43 targets (the divider feedback at -0.415, and wdata
//    /we into the adapter at -0.134 and -0.121) must be GONE.
//
// 4. Timing Constraints Report lists BOTH multicycle exceptions as
//    Actived.  If a core_clk -> clk50 path still shows Relation 20.000,
//    the exception did not take.

// [H48-3] first lock CDC flop. pll_lock is made on clk_ref / pll_init.
// One command per line. Do not false-path the whole clk_ref domain.
set_false_path -from [get_pins {u_pll/u_pll_init/state_1_s0/Q}] -to [get_pins {u_lock_meta/D}]
set_false_path -from [get_pins {u_pll/u_pll_init/state_1_s0/Q}] -to [get_pins {lock_meta_s0/RESET}]
