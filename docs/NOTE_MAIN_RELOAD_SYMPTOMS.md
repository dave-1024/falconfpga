# Note for main users: black screen / silent serial after reflashing (28 Oct 2026)

**Symptoms (seen on main and on pmmu):** after flashing or reloading the FPGA without unplugging the board you get a black screen, LEDs
yellow + purple, no text from the helper serial port, and possibly a TOS error.

**Likely cause:** main's ST flash reader (`hdl/tang/console60k/flash_dspi.v`, identical on main and pmmu) leaves the SPI flash in dual-I/O
*continuous read* mode. A JTAG reload resets the FPGA, not the flash, so on the next start the AE350 helper's boot loader is misread
and the helper never comes up. Since the helper also owns the OSD and the companion link, the board looks dead. A power cycle resets the flash.
(Proven on the pmmu board, 28 Oct: alive tests, then verify-then-load. See docs/HELPER_SILENCE.md.)

**Workaround (no code change):** after programming, do one read-only flash operation before the design starts, for example a verify:
`programmer_cli -d GW5AST-138C --location <loc> --run 66 --fsFile <the .fs you just flashed>`, then `--run 2 --fsFile <same .fs>`
(SRAM load), or just unplug and replug the board. Do not bulk-erase. TOS (0x500000) and the helper firmware (0x600000) do not need rewriting.

**Fix:** F70 on branch pmmu (`flash_unstick.v`). Before the AE350 is released, the fabric sends the mode-bit exit and 0x66/0x99 to the flash.
It goes to main only after David's review.

**Other notes from the comparison (main vs pmmu, no change made):**
- `jtagseln = !(!pll_lock || spi_ext || bl616_jtagsel)` and `bl616_rx = 0` are the same on both. `por` no longer includes bl616_jtagsel (earlier fix).
  With `use_jtag_as_gpio 1`, the JTAG pins are GPIO once the PLL locks, unless the BL616 pulls `bl616_jtagsel` low. If the USB device keeps
  deregistering, the BL616 is re-enumerating. Unplugging the USB is the reliable reset for that; the FPGA design does not drive the BL616's USB.
- **PR1014 "generic routing for clock clk_d":** there is no `clk_d` net in main's HDL. It is very likely the known PR1014 for the 50 MHz pad -> DCE
  hop (`clk_g`, documented in ST_HELPER.md / TODO.md item 7), so it is benign. Worth confirming in the friend's log which net it names.
- **TOS 256K error:** main's flash layout expects TOS at 0x500000. A 256K image is fine for TOS 2.06; an error right after a reload is consistent
  with the flash-mode problem above (the reader sees garbage) and should go away with the verify-then-load workaround or a replug.
