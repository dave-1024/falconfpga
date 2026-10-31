# sd64 builds: pll_sd PLL phase settings

From each build's `~/bt_<tag>` copy on linserver, file `hdl/tang/console138k/gowin_pll/pll_sd64_mod.v`
(`CLKOUTn_PE_COARSE` / `CLKOUTn_PE_FINE`). CLKOUT0 = clk_sd64 (internal SDRAM clock), CLKOUT1 = SDRAM pad clock.
The committed tree (this branch) has the base setting (no shift). Shift values and results are from PROGRESS.md.

| Build | CLKOUT0 coarse/fine | CLKOUT1 (pad) coarse/fine | Shift | Extra defines | Result |
|---|---|---|---|---|---|
| base (tree) | 0/0 | 13/5 | none | SDRAM64 | - |
| sd64b | 0/0 (no bt copy; = base) | 13/5 | none | SDRAM64 | PLLs lock, serial OK, HDMI random dots |
| sd64e | 12/0 | 10/5 | -3.125 ns | SDRAM64 | TOS starts, BAD ROM CRC, 2 bombs |
| sd64f | 11/0 | 9/5 | -4.17 ns | SDRAM64 | serial + HDMI dead (wedge, power cycle) |
| sd64g | 11/4 | 10/1 | -3.65 ns | SDRAM64, jtagsel fix | one-way-serial wedge again |
| sd64h | 12/4 | 11/1 | -2.6 ns | SDRAM64, jtagsel fix | memory test OK (4096 KB), BAD ROM CRC E/O, hangs |
| sd64i | 13/0 | 11/5 | -2.08 ns | SDRAM64 | memory test X errors + BAD ROM CRC (worse) |
| sd64j | 13/4 | 12/1 | -1.56 ns | SDRAM64 | built, NOT tested |
| sd64k | 12/4 | 11/1 | -2.6 ns (as h) | SDRAM64 + SD64_NEGCAP | built, NOT tested |

Bitstreams: linserver `~/fpga_bitstreams/st_helper_hdn_sd64{b,e,f,g,h,i,j,k}.fs` (sd64a: do not flash).
