# SDRAM at 64 MHz: where we are (pick-up note, 27 Oct 2026, 07:50 UK time)

## The goal
Make memory faster in the falconfpga STE core (Tang Console 138K). Step 1 is to run the SDRAM
controller and the SDRAM chips at 64 MHz instead of 32 MHz while keeping every memory access at
exactly the same moment as before. Nothing gets faster yet: this step only has to prove that the
chips can run at 64 MHz. After that come burst cache fills for the 68030 and faster TT-RAM.

Benchmarks to compare against (build tt26rmc2):
- GEMBENCH 6.31: average 124% (Display 90, CPU 172, RAM Access 102, Blitting 98, ALT RAM 161,
  Text 55). Setup: TOS 2.06, blitfix.st in drive A (TTRAM.PRG, BLITON, BLITFIX in AUTO), ST Medium.
- FrontBench: steady 1375 (1385 on the first pass). Setup: TOS 2.06, blitfix.st in A, tts.st in B,
  run B:\FRNTBNCH.PRG. It needs TTRAM.PRG from blitfix.st, otherwise it runs from ST-RAM (~990).
- Baseline screenshots are in /workspace/baseline/.

## What we learned about the PLLs (clock generators)
- The 138K's datasheet (DS1239-1.0.3E) allows a VCO of 650-1300 MHz, an input/PFD of at least 19 MHz.
  An older version of the same datasheet says 800-1600. Use only values inside both ranges.
- sd64a set the main PLL (pll_160m) VCO to 1600 MHz. The PLL never locked and the whole board went
  dark. NEVER flash sd64a and never use 1600 MHz again.
- From sd64b on, the main PLL is byte-for-byte the tt26rmc2 one (800 MHz VCO). A second PLL
  (pll_sd64) takes clk32 as its input: 32 MHz in, VCO 960 MHz, two 64 MHz outputs (one for the
  controller, one phase-shifted for the SDRAM clock pin).
- 64 MHz cannot be made with whole dividers from the main PLL at a legal VCO. The 12.5 fractional
  divider exists but its alignment with the other outputs is undocumented, so it was not used.

## The main finding: the two clocks are out of step
The 32 MHz system clock comes from the main PLL, the 64 MHz clock from the second one. Gowin's
timing tool cannot follow a clock through one PLL into another: it treats the second PLL's output as
arriving about 1.6 ns before clk32, when it really arrives later. Telling it the true source
(sd64c) is rejected with "TA2004 Cannot get clock with name clk32_core". So "timing met" is not
true for the hand-over between the two clocks, and on the board the data gets handed over a clock
too early or too late.
Workaround: shift both 64 MHz outputs earlier with the PLL phase setting (1 step = 1.04 ns, fine
step = 0.13 ns). Results:

| Build | Change | Fmax clk32 / sd64 / cpu030 (MHz) | LUTs | Board result | Screenshot |
|---|---|---|---|---|---|
| sd64a | main PLL VCO 1600 | 33.28 / 144.1 / 21.83 | 40318 | board dead (PLL never locks) | - |
| sd64b | 2nd PLL, no shift | 36.28 / 122.9 / 23.66 | 40440 | random dots, TOS never starts | /workspace/sd64b/boot.png |
| sd64c | SDC change only | build failed (TA2004) | - | - | - |
| sd64e | shift -3.1 ns | 36.28 / 122.9 / 23.66 | 40440 | TOS starts, BAD ROM CRC, 2 bombs | (overwritten) |
| sd64f | shift -4.2 ns | same | 40440 | board got stuck (see below) | - |
| sd64g | -3.65 ns + debugger-line change | 34.64 / 112.4 / 23.71 | 40440 | board got stuck | - |
| sd64h | -2.6 ns | 34.64 / 112.4 / 23.71 | 40440 | BEST: memory test 4096 KB OK, then BAD ROM CRC IN CHIP E/O | /workspace/sd64b/sd64h.png |
| sd64i | -2.1 ns | 34.64 / 112.4 / 23.71 | 40440 | memory test with several X errors, BAD ROM CRC | /workspace/sd64b/sd64i_noc.png |
| sd64j | -1.6 ns | 34.64 / 112.4 / 23.71 | 40440 | built, NOT tested | - |
| sd64k | -2.6 ns + read data caught on the falling 64 MHz edge | 34.40 / 91.4 / 23.20 | 40440 | built, NOT tested | - |

All of them pass timing (no negative slack) and keep clk_cpu030 well above 17 MHz.
The TOS ROM comes from flash, not SDRAM, so "BAD ROM CRC" most likely means occasional RAM bit errors
during the check (the quick memory test does not catch them). Around -2.6 ns is the best so far; both
sides of it are worse, so the working range is narrow, which hints that the read-data capture point
is also marginal. That is why sd64k exists.
Simulation (prog_bus and prog_tt, whole ST bench) matches the 32 MHz build for sd64b..k, apart from
two start-up commands (precharge, load mode) one clock earlier before the RAM is ready.

## The stuck-board problem
Symptoms: after flashing, the helper still prints its start-up text over serial, but ignores every
command (no answer to "?"), and HDMI stays black. Reflashing tt26rmc2, USB resets of the debugger and
the capture, and a remote power cycle do NOT fix it; only David physically re-plugging the board does.
It happened after sd64a, sd64f and sd64g, each time around a cold boot ("c") of a build whose ST side
was misbehaving. Tying the debugger line (jtagseln) to the main PLL only (done in sd64g) did not help,
so that was ruled out. Rule: on a test build, do not send "c"; the core starts TOS by itself after
flashing (seen with sd64i). Check the serial still answers "?" (it can take ~50 s) before anything else.
If it gets stuck: reflash tt26rmc2 once, stop and ask David to re-plug.

## Cable location
The debugger's USB location changes after every replug (4593, 4641, 4689, 4817 so far). All flash
scripts rescan first; never hard-code it.

## Scripts (box /workspace/sdram64 unless noted)
- try2.sh <tag>: flash ~/fpga_bitstreams/st_helper_hdn_<tag>.fs, check serial, HDMI grab, NO cold boot.
  Screenshot: /workspace/sd64b/<tag>_noc.png. (try.sh does the same but sends "c" - avoid on test builds.)
- linserver ~/flash_fs.sh <fs>: rescan cable, flash core, reload. ~/flash_rmc2.sh: put tt26rmc2 back
  (checks its sha). Both run with sudo.
- linserver ~/bv.sh <tag> c0coarse c0fine padcoarse padfine [extra define]: copies ~/sd64_wt to
  ~/bt_<tag>, sets the second PLL's phases, builds, copies the bitstream to ~/fpga_bitstreams and the
  reports to ~/<tag>_pnr. Run it with nohup (about 25 minutes, two at a time is fine).
- sta.sh <pnr dir>: Fmax, slack and LUTs from a report.
- /workspace/lg2.sh out.png: HDMI grab. If black: sudo usbreset 345f:2130 on linserver, wait 10 s.
- /workspace/hcx.sh "cmd" ...: helper serial commands (/dev/ttyUSB0 or 1, 115200).

## Where things are (nothing committed to git)
- Work trees: linserver ~/sd64_wt (base tt26rmc2 tree d270586 + rmc patches + sd64 changes),
  box /workspace/sd64 (same files); original copy /workspace/sd64_orig.
- Changed files: gowin_pll/pll_sd64.v + pll_sd64_mod.v (new), top.sv, misterynano.sv,
  mega138kpro/sdram.v (SDRAM64, SD64_NEGCAP), atarist_st_helper.sdc, build_st_helper_hdn.tcl, tb_bus.v.
  The phase shift of each build lives only in its ~/bt_<tag> copy (the base tree has no shift).
- Bitstreams: ~/fpga_bitstreams/st_helper_hdn_sd64{b,e,f,g,h,i,j,k}.fs (sd64a: do not flash).
- Log of every step: /workspace/sdram64/PROGRESS.md.

## Next steps, in order
1. Test sd64k (-2.6 ns + falling-edge capture) with try2.sh. If cleaner, try sd64j too.
2. Fine-tune around the best one in 0.13 ns steps (e.g. -2.35, -2.85 ns), with and without
   falling-edge capture.
3. Better fix for the clock hand-over so it does not depend on a hand-tuned phase: put the
   SDRAM read/write data hand-over on the 64 MHz edge half way between clk32 edges, or move clk32
   and the 68030 clocks onto the same PLL as the 64 MHz clock (needs care with the 100 MHz flash clock).
4. When a build reaches the desktop cleanly: run GEMBENCH and FrontBench against the baselines.
5. Then the real speed-ups: 68030 burst cache fills (STERM/CBREQ/CBACK, not supported by the core yet)
   and faster TT-RAM using the extra 64 MHz slots.
6. Housekeeping: refresh CONTEXT.md, fix tools/up2.py and the cable location in flash_etos.sh.
