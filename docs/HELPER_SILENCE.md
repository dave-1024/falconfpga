# Helper silent after an FPGA reconfigure (analysis, 28 Oct 2026, no board)

## What we know
| when | action | after |
|---|---|---|
| 27 Oct, 28 Oct 06:5x | op 53 (flash) + op 1 of pmmu8exc / f66 / f68 / pmmu8 | helper silent until a physical replug |
| 28 Oct 07:22 | op 2 (SRAM) f68 | link OK after 10 s, HDMI fine, pmt5 + MiNT ran |
| 28 Oct 08:01 | op 2 (SRAM) f68ovl (timing clean) | **no byte at all on ttyUSB1** (not even after CR), HDMI black |
| 08:05 / 08:09 | op 2 f68 again, then op 1 (pmmu8 from flash) | still silent, HDMI black |

The FT2232 stays enumerated and `/dev/ttyUSB1` comes back after `modprobe ftdi_sio`. A replug (board power + USB) always recovers.
Flash contents are not the cause (pmmu8 at 0 verified, and SRAM loads fail too).

## Boot chain (st_helper_ctrl.v, top.sv)
config → `pll_lock` (pll_hdmi; `PLL_INIT` soft FSMs on clk_g) → `por`/`por32` released → fabric prints **"STH"** on U15
→ DDR3 trains ('D', or 'X' after 4 s) → AE350 POR released ('R') → firmware copies 0x600000 → DDR and shows 0xA5
(otherwise 'T' after 2 s) → flash goes to the ST → TOS boots. **Every fallback still boots TOS with video.**

## Hypotheses, checked against the data
1. **A PLL does not lock after a warm reconfigure** (por stuck): no fabric letters, no ST, no video. This fits everything
   (no byte at all, black HDMI, depends on the build, replug fixes it). `PLL_INIT` is a fabric FSM; F60 already saw its
   hold margin depend on placement (u_gowin_pll_ddr3/u_pll_init). Note that pll_hdmi's lock drives `por` for the whole design.
2. **DDR3 does not train on a warm reconfigure** (the DDR3 chip is not power-cycled; `ddr3_rstn` is only a 20 ms debounce after config).
   That should give 'X' and then TOS **with video**, so on its own it does not explain the black HDMI. Still a likely
   cause of "helper prints boot lines then stops answering", seen once on 27 Oct.
3. **The FT2232 UART channel is left unusable by programmer_cli** (driver unbind, MPSSE state): the serial would be dead with the board fine.
   This does not fit a black HDMI either, unless the capture also lost sync. A host-side USB reset of the FT2232 (`usbreset 0403:6010`) would test it without the board.
4. **AE350 hard core state across reconfigure**: POR_RSTN comes from fabric `ae_run` (0 from config), so it is reset. It would
   show 'T'/'C' and still boot TOS. Unlikely.

## Cheap diagnostics (next board session)
- Start a raw serial logger on ttyUSB1 **before** every op 2 / op 1 (`stty raw; cat > log &`) and keep it running across the
  programmer's driver unbind/rebind (restart it right after `modprobe ftdi_sio`). "STH", then D/X/R/T/C, tell 1 from 2 from 4 at once.
- Grab HDMI right after the load: black = fabric/ST not running (1); TOS screen = helper-only problem (2/3/4).
- After a silent load, try `usbreset` on the FT2232 before anything else (3).

## Robustness options (design)
A. **PLL lock watchdog** on the raw 50 MHz pad clock (not behind any PLL): if pll_hdmi / ae350 / ddr3 PLLs are not all
   locked within ~10 ms of config, pulse their RESET and retry (up to N times), then light an LED. A pure-fabric counter on clk.
B. **Re-time PLL_INIT**: keep it on clk_g (already a DCE) and add a hold-margin check for clk_g to `timing_pairs.py`
   (fail the flash rule on any clk_g/clk_osc hold < 0.1 ns).
C. **DDR3 retry**: on 'X', drive DDR3_RESET_N low ≥ 200 µs (via the controller reset), retrain up to 3 times before the TOS-only fallback.
D. **Helper heartbeat watchdog**: firmware toggles a GPIO bit (say GPIO[8]) every 100 ms; if it stops for 2 s, the fabric resets
   the AE350. The flash is already the ST's (sticky), so the firmware must keep its image in DDR and have a tiny reset
   stub re-enter it (or the boot loader must accept "image already in DDR" through a GPIO strap). This needs a firmware change.
E. **Fabric status over U15 after boot**: a mailbox command or a fixed status byte every second while the AE350 is in reset,
   so a silent link can always be classified.
F. **Process**: use only SRAM loads for tests; flash only known-good images. Use the logger from the diagnostics list on every load.

Recommended order: diagnostics first (zero risk), then A + E (fabric only, small), then C, then D (firmware).

## Result (a), 28 Oct 08:25 GMT: USB reset does not bring it back
`usbreset 0403:6010` on linserver: "ok". Both FT2232 channels rebound (the UART is now /dev/ttyUSB0 = by-id if01).
Raw logger on the UART before and after: **0 bytes**. `hc.py s`: no answer (3 tries). HDMI frame still black (all 0).
So hypothesis 3 (host/FTDI state) is **ruled out**: the board side is dead (fabric or ST not running), which fits hypothesis 1.
Note: hc.py/up2.py pick the port by-id, so the tty renumbering does not matter.
## F69: fixes 1 + 2 built (28 Oct 2026, 08:41 GMT) - NOT loaded (waits for David's replug)
- `hdl/tang/console138k/pll_wdog.v`, wired in top.sv:
  - runs on clk_g (raw 50 MHz). For each PLL (main pll_160m, ae350, ddr3), if its O_LOCK is low for 50 ms it pulses that PLL_INIT's
    `I_RST` (new `init_rst` port on the three PLL wrappers) and the ICP/LPF search restarts; it retries for ever and counts the retries.
  - while `por` (main PLL not locked) it owns U15 and sends `P<retries hex><ae350 lock><ddr3 lock><main lock>` CR LF every 0.5 s
    at 115200. Seeing nothing at all means the board/clock is dead; `P0000` repeating means no PLL locks.
- Sim: `hdl/tang/console138k/sim/tb_pll_wdog.v` (iverilog). PLL 0 locks after 2 restarts, PLL 1 at once, PLL 2 never. Result: exactly 2 restarts,
  continuous restarts of PLL 2, status line `P1100` decoded, status byte ok. **PASS.**
- Fix 3: `timing_pairs.py` now fails any hold pair on clk_g/clk_osc below 0.1 ns.
- Build `st_helper_hdn_f69_be0ae8f.fs` (sha256 14f22cad569b7152…): `timing_pairs.py` **all ok** (worst setup 1.224 ns clk32, clk_g hold 0.248 ns).
  pll_wdog is in the netlist. Gowin warns that the reg initialiser on `init_rst` is ignored (GSR clears it to 0 anyway).
- Test plan after the replug: SRAM-load f69 (op 2) with a serial logger running, check "STH" / boot, then repeat op 2 loads a few times.
