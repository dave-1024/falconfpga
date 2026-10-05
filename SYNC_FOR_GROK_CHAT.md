# SYNC FOR GROK CHAT

Catch-up note for Grok chat. Newest entries are at the top. All times are UK time (BST, UTC+1).

## Purpose

Grok chat (David's HDL-writing assistant) is out of tokens until 1 Oct 2026. Until then, David asks
Grok Bot for changes directly, and Grok Bot edits, builds and logs everything here and in
`BUILD_REPORT.md`. **Grok chat: please read this file first when you are back, before assuming any
old state.** While this note is active, Grok Bot may edit HDL at David's request.

## FIX 2026-10-05 18:10: AE350 flash MOSI/MISO were swapped on the serial proof

Cause: the serial proof loan mux routed `FLASH_SPI_MOSI` to `mspi_do` (R22) and
sampled `FLASH_SPI_MISO` from `mspi_di` (P22). The hybrid bring-up that worked uses
the opposite map (`FLASH_SPI_MOSI` = P22 = `mspi_di`, `FLASH_SPI_MISO` = R22 = `mspi_do`).
UART and DDR3 were fine (`PIN` / `D` / `R`); the stub never fetched `ready.bin`.

Fix (serial proof only): AE350 owns MSPI exclusively while the 030 is held; SOC flash
ports connect with the hybrid ball map. Desktop `build_tc138k.tcl` is unchanged (no MSPI
mux). Bitstream for David: `C:\Users\dave_\fpga_caps\ae350_serial_flashfix.fs` (BUILD ONLY,
not flashed). Expect `PIN` then `DR` then `AE350 alive`.

## RESULT 2026-10-05 17:50: proof image printed PIN DR, stub did not run

David SRAM-programmed `d9a3daf` (`build_ae350_serial.tcl`, `ae350_serial.fs`) on cable 417. U15, 115200 8N1. He did not write exFlash. `ready.bin` is at `0x0600000`. He first typed `0x06000004`, then corrected it. The log address is `0x0600000`, not an off-by-four and not `0x6000000`.

Serial text was:

```
PIN
DR
```

No `AE350 alive` after `R`.

- `PIN` is the fabric banner. Lead, U15 and 115200 are good.
- `D` means `ddr3_init_completed` rose. The hybrid DDR3 block trained on this splice.
- `R` means the flash pins had been lent for about 2 ms and the AE350 reset then rose.
- The stub in `helper_fw/ready/ready.c` did not reach `main`. Do not rebuild `ready.bin` for this. It is unchanged.

The remaining fault is the AE350 flash read, not the UART, not DDR3 init, and not the reset. The desktop build is still `build_tc138k.tcl`. Do not mux MSPI back into it. Do not rebuild `d9a3daf`. Do not write exFlash.

## HANDOFF 2026-10-05: AE350 is in the fabric, desktop is a separate build (read this first)

David is building `d9a3daf` now. Do not rebuild it. Do not flash it. Do not write exFlash.
Cable 417 only. TOS slot stays where it is. No patch to apply: this work is already on `main`.

### Two builds, do not mix them

- `build_tc138k.tcl` is the desktop. It is the `c2dea47` path. The 030 is not held. The AE350 is in the fabric, held in reset, and its flash ports are tied off through wires. They are not connected to the ST flash pins. This image boots to the desktop with no delay and no button. It is the known-good image with the helper present but off.
- `build_ae350_serial.tcl` is the AE350 proof only. The 030 stays in reset, so there is no desktop. The bitstream is `ae350_serial.fs`, not `atarist_tc138k.fs`.

Muxing MSPI into the desktop build kills the boot. `5630a36` and `988c846` both did that. Neither booted, and neither printed. Do not put that mux back on `build_tc138k.tcl`.

### What the proof image does

UART is U15, the rigsdram and hybrid `UART2_TXD` pin, 115200 8N1. The proof CST moves `spi_irqn` to C22. The desktop CST does not: U15 stays `spi_irqn`, C22 stays the old BL616 passthrough.

Fabric letters, then the stub:

- `PIN` means the lead, U15 and 115200 are good. Seen on `1e4cc74`. It does not mean the AE350 ran.
- `D` means DDR3 init completed. `X` means it did not, within 8 seconds.
- Flash is lent for about 2 ms, then `R`, then the AE350 reset rises.
- `AE350 alive` is `helper_fw/ready/ready.c`. It does not write GPIO `0xA5`.

`ready.bin` is already at `0x0600000`. Do not rebuild it for `d9a3daf`. Program Without Erasure if it has to be written again. Not `0x6000000`.

The stub is linked with `ae350-ddr.ld`. It cannot reach `main` unless DDR3 trains and that bin is at `0x0600000`. `PIN` then `X` means the CPU was not started.

### Clocks and the DDR3 block

The DDR3 controller is the hybrid SOM DDR3 IP, not the rigsdram plug-in SDRAM. PLL settings match the hybrid: core 800 MHz, AHB and APB 50 MHz, DDR3 memory clock 200 MHz. UART divisor 27 is 50 MHz / (16 × 115200), about 0.5% fast. Rigsdram's old rate was 38400. This stub is 115200. DDR3 init on this splice is not yet proven.

Gowin has no `set_option -verilog_define`. `build_ae350_serial.tcl` writes `` `define AE350_SERIAL `` into `tang/console138k/build_sel.vh` before synthesis. `build_tc138k.tcl` clears that file. `top.sv` includes it.

Inouts cannot be tied to constants (`EX3434`). The desktop image ties the AE350 flash ports off through wires.

### Commits, oldest first

- `c2dea47` desktop restored. AE350 held off. David: boots, no delay.
- `988c846` S1 mux on the desktop image. Did not boot, no UART.
- `154678d` split the proof into `build_ae350_serial.tcl`.
- `e94edae` header macro, after Gowin rejected `-verilog_define`.
- `1e4cc74` the 2 second release was a one-clock pulse. Latched, and added `PIN`. David saw `PIN`.
- `d9a3daf` `D`/`X`, lend flash, `R`, then release. David is building this.

### Next

Wait for David's letters. Do not start a Nano build. Do not write exFlash. SRAM only, cable 417.

## HANDOFF 2026-10-03/04: 68030 build now boots TOS 2.06 and EmuTOS to the desktop (read this first)

State of main (Atarist_030_wip, Tang Console 138K): WF68K30L 68030 core with fixes F55-F59, synchronous
ST bridge, 16 MHz CPU clock. **TOS 2.06 UK (256K) and EmuTOS 192K UK both boot to the GEM desktop** on
the board (location 417), and the CPU keeps running there. The ROM slot (flash 0x500000) currently holds
**TOS 2.06 UK**. The board runs the clean committed build (overlay option off) and shows the TOS 2.06
desktop.

### How we got here (in order)
- **Diag overlay (diag030, 030b, 030c).** A debug overlay on the HDMI picture: status squares plus six
  32-bit bit-bar rows (first bus error, last bus cycle the 030 started, CPU pins, bridge state, last
  program fetch). It let us see from a screen capture whether the CPU was stuck in a bus cycle or had
  stopped by itself. It is now committed as a compile option, off by default (see below).
- **F55 (interrupt mask).** The core could take an interrupt that the new SR mask had just covered (the
  pending request was never re-checked). Fixed in the exception handler. A real 68030-conformance fix,
  but not the cause of the hang at the time.
- **F56 (combinational loops and a latch).** Gowin reported 17 combinational loops and one latch in the
  core. Two loops (BFINS/PACK paths into NEXT_FETCH_STATE) were broken with logically identical
  signals and the BF_NZ latch was removed. Effect: timing analysis now sees the real paths (before,
  the reported fmax didn't match any analysed path because STA cut the loop arcs).
- **F57 (power-up values).** Gowin drops implicit VHDL initial values, so 18 set-type flops powered up
  at 1 while the RTL assumed 0. Explicit initial values added (decoder and ALU).
- **F58 (bridge and clock).** The CPU clock was already phase-locked to clk32 (same PLL), but the
  bridge still used 2-flop synchronisers in both directions. The bridge is now synchronous, the CPU
  runs at 16 MHz (was 8), and the core's falling-edge registers run on a separate PLL output at 180
  degrees (before, they used a fabric inverter that timing analysis did not check). An ST bus access
  went from about 1.6 us to 875 ns (TOS 1.04 Timer B loop in simulation). The rest of the 875 ns
  breaks down roughly like this (an estimate, not measured term by term): the 68000-style ST bus cycle
  itself is about 500 ns (4 clocks at 8 MHz). Waiting for the next 8 MHz bus phase adds up to about
  125 ns. The 030 side (the request seen on clk32, the DSACK sample, the data latch, AS going high)
  and the core's own idle clocks before it starts the next cycle make up the rest.
- **F59 (the desktop fix).** Root cause of the TOS 2.06, TOS 1.04 and EmuTOS freezes: an interrupt
  taken while the core runs a short `move`/`DBcc -4` loop in 68010-style loop mode deadlocked it
  after RTE. Every exception ends with a pipe flush, and an earlier change (F47) made that flush set
  the decoded opcode to ABCD. ABCD counts as a loop-capable instruction. So after RTE into the DBcc,
  the decoder saw "loop about to start" and stopped fetching, while the exception handler was still
  waiting for the third word of its pipe refill. Neither side could move. The fix is two lines in
  `wf68k30L_opcode_decoder.vhd` (the flush sets NOP instead of ABCD). Reproduced and verified in the
  GHDL bench, and confirmed on the board with a temporary debug build (diag030d, not committed) that
  showed exactly the predicted internal state.

### Things to know
- **TOS 1.04 is not 68030-compatible** and isn't a useful target: its supervisor trap dispatchers
  assume the 6-byte 68000 exception frame (the 68010+ pushes 8 bytes or more), so it crashes. Use
  TOS 2.06 or EmuTOS.
- **Upper address bits are not decoded (kept on purpose).** The bridge ignores A31:24, so every
  16 MB block of the 030's 4 GB space mirrors the ST's 24-bit map, and there's no bus error above
  $00FFFFFF. A program that probes 32-bit addresses (for example for TT/Falcon hardware or Fast RAM)
  gets an answer instead of a bus error. **David's decision: keep the mirror for now (no BERR above
  $00FFFFFF).** Reason: on real ST accelerators, fast/TT RAM reduced compatibility because some games
  relied on 24-bit address aliasing (using the top address byte for other data). TOS 2.06 and EmuTOS
  also address the I/O area as $FFxxxxxx here. **If fast RAM is ever added, it must be a build option
  that is off by default.**
- **Speed.** Still slow compared with a real 030 board: every access goes through the 8 MHz ST bus,
  the core has idle clocks after each fetch before the next cycle starts, and the core has no
  instruction or data cache (the 68030 caches and MMU are not implemented in WF68K30L). Ideas: shrink
  the core's gap after fetches; the 68030 instruction/data caches inside the WF68K30L core (David's
  earlier decision: caches go inside the core, real-030 behaviour); Fast RAM outside the ST bus only as
  an off-by-default option (see above).
- **Diag overlay build option.** Uncomment `` `define DIAG_OVERLAY `` in
  `Atarist_030_wip/tang/console138k/top.sv` and rebuild. Off by default (costs fabric and timing,
  covers the screen). The key is in `Atarist_030_wip/docs/DIAG_OVERLAY.md`, and the README explains it.
- **Benches.** `cpu030/sim/rtl/run_rtl.sh` (GHDL, core alone, interrupt mask). `cpu030/sim/run_unit.sh`
  (gate-level netlist + bridge against a behavioural ST bus). The F59 loop/interrupt test program is
  not in the repo yet. It would be worth adding to run_rtl.sh.

### Suggested next steps
1. Test more software under TOS 2.06 and EmuTOS (desktop use, a few programs and games), and keep the
   overlay off unless something freezes.
2. Add the loop-during-interrupt test to `run_rtl.sh` as a regression.
3. Keep the A31:24 mirror (decided). Only if fast RAM is added later: make it a build option, off by
   default.
4. Performance: measure the core's idle clocks between bus cycles, then the 68030 caches inside the
   core.
5. Route ST audio to HDMI and the OSD to the 640x480 output (both still missing on this output).

## diag030 results 2026-10-03 (David's monitor)

Build: diag030 local debug build (key under the 2026-10-03 07:15 entry below; BUILD_REPORT 2026-10-03 08:03).

- **After power-up:** snow over the whole picture. LED U12 blinks, so the 030 is running bus cycles.
- **Squares:**
  - Row 0: S17, S18 and S19 green. S20 yellow (a bus error was seen earlier, not now).
  - Row 1: all green. S1/S2 (vsync/hsync) blink, and S8 (frame-buffer writes) is green.
  - Row 2: S11 and S12 green, S13 yellow, S14-S16 green (030 not halted).
  - The TOS word bars read 0110 0000 0010 1110 = 0x602E, the correct EmuTOS first word.
- **After pressing S0 (AA13):** S17-S19 go yellow→green and S20 goes red→yellow, so a bus error happens on EVERY boot,
  early. S5/S6/S7/S10 go yellow→green, and S11 goes through a reset cycle. The word bars don't change. The picture is
  still snow afterwards, so this is NOT a cold-start problem.
- **Conclusion:** the CPU, ROM fetch, bus handover and DSACK all work. Memory contents or writes are wrong.
- **Requests for Grok chat:**
  1. Check how the bridge splits 32-bit and byte/word writes into 16-bit ST cycles: the order of the halves, the
     second-cycle address (A1), the UDS/LDS byte strobes, and the data lane placement for byte writes at odd and even
     addresses.
  2. Find out which access raises the early BERR. Consider adding a latch of the first BERR address to the diag bars
     in a future patch.
  3. Check that the 030's misaligned and long accesses are handled the way a real 030 with 16-bit dynamic bus sizing
     (DSACK1 only) would handle them.

## Changes since 2026-09-29 (running log, Grok Bot adds entries here, newest first)

- 2026-10-04 12:40: **Diag overlay committed as build option `DIAG_OVERLAY`, OFF by default** (uncomment the
  define in `Atarist_030_wip/tang/console138k/top.sv`; key in `Atarist_030_wip/docs/DIAG_OVERLAY.md`, README
  section added). Clean build (define off): PASS, TNS 0; flashed 417, TOS 2.06 desktop without overlay.
  Handoff section for Grok chat added at the top of this file. See BUILD_REPORT 2026-10-04 12:40.

- 2026-10-04 11:35: **F59 WF68K30L loop-mode deadlock fixed (core, committed)**: an interrupt taken during a
  DBcc loop (`move`/`dbcc -4`) wedged the core after RTE, because the [F47] pipe flush left OP = ABCD
  (loop-capable) so LOOP_ATN blocked the 3rd refill fetch. Flush now sets OP = NOP. Board (F59 + local
  diag030c): **TOS 2.06 UK and EmuTOS 192K UK both reach the GEM desktop**. TOS 2.06 is in the ROM slot.
  See BUILD_REPORT 2026-10-04 11:35.

- 2026-10-03 09:17: **diag030b local DEBUG build, BUILD ONLY (not flashed, HDL not committed)**: diag030 plus four bit-bar
  rows (first BERR address/FC, screen base bytes, last program fetch). PASS: clk32_core 36.304, clk_cpu030 15.705 MHz,
  TNS 0. The patch is at `/workspace/diag030b.patch` on Grok Bot's box (against e502d8f, includes diag030). .fs:
  `C:\Users\dave_\fpga_caps\diag030b.fs` on the laptop. See BUILD_REPORT 2026-10-03 09:17.
  - **diag030b KEY (new rows; S1-S20 and the TOS word bars are unchanged, see the diag030 key below).**
    - Where: four rows above the squares, y 160-287, on a black band from x 8 to 567. Each row has a coloured label
      square (20x20, x 16-35) and then up to 32 bars (12 px wide, 20 px tall, x 48-559). White = 1, dark grey = 0,
      MSB on the left. Bars are in groups of 4 = one hex digit (8 px gap between groups). The 8 group columns are the
      same in every row, so a column is the same bit number in every row (columns 1-8 = bits 31-28 ... 3-0).
    - **Row a, RED label (bars y 166-185): first BERR address A31:0**, 8 hex digits, e.g. `0000 0000 1111 1111 1000
      1010 0000 0000` = $00FF8A00. This is the 030's own address; the bridge ignores A31:24 on the ST bus.
    - **Row b, MAGENTA label (y 198-217):**
      - Group 1: `got FC2 FC1 FC0`. got = 1 means a BERR has been latched since the last reset; if got = 0, rows a/c and
        groups 1-2 of row b are all 0.
      - Group 2: `RW SIZ1 SIZ0 BAD`. RW 1 = read, 0 = write. SIZ (030 SIZE) 01 = byte, 10 = word, 11 = 3 bytes, 00 = long.
        BAD 1 = the bridge itself answered with BERR (a CPU-space cycle that is not an interrupt acknowledge, no ST
        cycle). BAD 0 = the BERR came back from the ST bus.
      - Groups 3-4: the byte written to **$FF8201** (video base high = screen A23:16).
      - Groups 5-6: the byte written to **$FF8203** (video base mid = screen A15:8). These sit under row a's A23:16 and
        A15:8, so the screen base reads directly as $HHMM00, e.g. 4 MB: $3F8000 (3F, 80); 1 MB: $0F8000.
      - Group 7: `WH WM` (2 bars) = $FF8201 / $FF8203 written since the last reset. Group 8 is empty.
      - The bytes are the CPU's D7:0 on an ST-bus byte write (LDS) to that address. A wrong value here with WH/WM = 1
        points at byte-lane placement in the bridge.
    - **Row c, CYAN label (y 230-249): last 030 program fetch A23:0, frozen at the first BERR** ("PC at BERR").
      Columns 1-2 are empty; 6 hex digits sit under row a's A23:0. Program fetch = FC 010 (user) or 110 (supervisor).
      Because of the prefetch it can be a few words ahead of the faulting instruction. If the faulting access is
      itself a program fetch, it shows that fetch.
    - **Row d, BLUE label (y 262-281): live last 030 program fetch A23:0**, same layout as row c. It changes all the
      time while code runs. If it is stuck, the CPU is looping in one place or not fetching.
    - All of these latches clear on the ST reset (power-up, the double cold-start reset, S0). After S0, row a/b/c show
      the first BERR of the new boot.
    - **Probe or real fault?** FC 001 = user data, 010 = user program, 101 = supervisor data, 110 = supervisor program,
      111 = CPU space.
      - FC = 111 (BAD = 1) is a CPU-space cycle. A19:16 is the type: 0000 = breakpoint acknowledge (BKPT), 0010 =
        coprocessor communication (A15:13 = coprocessor ID, 001 = the usual FPU ID, A4:0 = the register; 68020/030 only),
        1111 = interrupt acknowledge (the bridge passes this one to the ST, so BAD = 0). A typical row a is
        $0002_2xxx (CpID 1).
      - A coprocessor cycle (FC 111, A19:16 = 0010) is the **EmuTOS FPU probe** (an F-line instruction with no FPU
        fitted): expected and harmless. A real 030 with no FPU gets the same BERR and takes the F-line exception.
      - An FC 101 data BERR at a known I/O address ($FF8Axx blitter, $FF89xx STE DMA sound, $FF92xx STE joypad,
        $FFFA4x Mega ST FPU, $FFFC2x Mega ST RTC, etc.) is also normally a TOS **hardware probe**.
      - A **real fault** is a BERR at a RAM address (A23:22 = 00, inside the installed RAM), at a garbage/odd-looking
        address, on a program fetch (FC 010/110), or a write (RW = 0) where TOS should not be writing.
- 2026-10-03 07:15: **diag030 local DEBUG build (HDL not committed)**: the misterynano_tc138k status-square overlay was ported to
  Atarist_030_wip, built on the laptop (PASS: clk32_core 34.258, clk_cpu030 15.993 MHz, TNS 0) and flashed to 417. The patch
  is at `/workspace/diag030.patch` on Grok Bot's box (not in the repo). See BUILD_REPORT 2026-10-03 07:15.
  - **diag030 square KEY** (squares 48 px with a black frame, columns at x = 8 + 64*i, read left to right; drawn
    straight on the 640x480 output after the frame buffer, lower-left of the picture).
    - Colour rules. Events: green = happening now (last ~0.13-0.26 s), yellow = happened earlier but not now, red = never
      since power-up. Levels: green = true now, yellow = was true earlier but not now, red = never true. **S20 is inverted:**
      green = never seen, yellow = seen earlier, red = happening now.
    - Row 0 (y 296-343), 030 bridge: **S17** x 8: 030 bus cycle started (bridge saw 030 AS); red = 030 never issues a cycle.
      **S18** x 72: rom_fetch latch (same flag as LED0), set by the first bridge cycle to E0xxxx or FC-FExxxx, cleared by
      reset; yellow = set, then cleared by a reset (e.g. S0) and not set again. **S19** x 136: DSACK returned to the 030
      (ST cycles completing). **S20** x 200: BERR returned to the 030 (inverted colours; includes non-IACK CPU-space cycles,
      which the bridge answers with BERR).
    - Row 1 (y 360-407): **S1** x 8: ST vsync (blinks green/dark green while alive). **S2** x 72: ST hsync (blinks ~1 s).
      **S3** x 136: ST DE seen. **S4** x 200: non-black ST pixels. **S5** x 264: ST-side bus cycles (AS falling edges on the
      68000-style bus the bridge drives); S17 green + S5 red = bridge never gets the ST bus. **S6** x 328: TOS ROM selected
      (ROM2_N). **S7** x 392: ROM read returned data other than 0000/FFFF. **S8** x 456: ST frame-buffer writes.
      **S9** x 520: main PLL locked (level). **S10** x 584: 68030 out of reset, bridge released its reset input (level;
      replaces the original JTAGSEL square, JTAGSEL no longer affects reset).
    - Row 2 (y 424-471): **S11** x 8: atarist reset input released (level). **S12** x 72: SDRAM init done (level).
      **S13** x 136: BL616 has talked to the core over SPI (event). **S14** x 200: BL616 not holding the ST in reset
      (level). **S15** x 264: SD wait done, image found or 2 s timeout (level). **S16** x 328: 68030 not halted (level;
      red/yellow = double bus fault halt).
    - TOS word bars (row 2, x 392-635): 16 bars = first TOS word read from ROM offset 0, MSB left, four groups of four;
      white = 1, dark grey = 0. A TOS image normally starts with BRA, so expect 0110 0000 in the left two groups. All grey =
      never read or read as 0000.
    - LEDs. **LED0** (leds_n[0], G11): unchanged, driven by `~rom_fetch`. **Polarity uncertain:** stock MiSTeryNano drives
      these pins high for "on", which would make G11 lit until the first ROM fetch and dark after; the 20261002-7 report
      assumed pin low = lit. Settle it by comparing LED0 with square S18 once there is a picture. **LED1** (leds_n[1],
      U12): blinks ~2 Hz while the 030 runs bus cycles, steady (on or off) when not; readable with either polarity.
    - **Grok chat: while diag030 is in use, please do not send patches that touch the video overlay area of
      `Atarist_030_wip/tang/console138k/top.sv`** (the leds_n assignment, the misterynano diag ports, the area after
      `assign clk32 = clk_pixel;`, and the hdmi_tp instance). diag030.patch is applied locally on the laptop on top of main
      and would conflict.
- 2026-09-30 10:45: **`Atarist_030_wip/` first 030 test** (commit `3b9afa6`): WF68K30L 68030 replaces fx68k via
  `cpu030/cpu030_st_bridge.v` (`CPU_030` define in atarist.v), CPU 8 MHz from PLL CLKOUT5. Build PASS, pins identical,
  CPU Fmax 16.175 MHz (16 MHz experiment 16.552 MHz), clk32 33.09 MHz. See BUILD_REPORT manual-20260930-a030-first.
- 2026-09-30 09:10: new WIP folder **`Atarist_030_wip/`** (commit `b78df28`, next to
  `misterynano_tc138k/`): a copy of the tracked `misterynano_tc138k` files at `c2d695d` (stage 2, ST
  video via BSRAM frame buffer to 640x480@60 DVI), the starting point for new work. 108 files, no
  path changes needed (only a README note). Test build `manual-20260930-atarist-030-wip` from that
  folder PASS, pins and timing identical to stage 2. `misterynano_tc138k/` stays as the reference.
  David has NOT bench-tested stage 2 yet. Not flashed.
- 2026-09-30 07:55: stage 2 ST video (commit `274f8b0`, build `manual-20260930-stage2-stfb` PASS).
  First, reported by David: stage 1b DVI colour bars (c6b1246) confirmed WORKING on both the DVI
  monitor and the old HDMI TV (2026-09-30). Now the raw ST video (clk32, before scandoubler/OSD, so
  **no OSD**) goes into a 120-block BSRAM frame buffer (`st_framebuffer.v`) and out through the
  640x480@60 DVI path: colour 640x240 (20 border lines top/bottom) line-doubled to 480, mono 640x400
  centred; window follows DE (PAL/NTSC/mono auto), mono detected from the hsync period. Default
  `.ST_VIDEO ( 1 )`, set 0 for colour bars; DVI_OUTPUT still 1. Tuning: ST_H_OFS_COLOR (96),
  ST_V_BORDER (20), MONO_TOP (40). Sim: 3 modes, 0 pixel errors. BSRAM 141/340, pixel Fmax 81.3 MHz,
  clk32 34.07 MHz (+0.35 ns worst), 8/8 primary, pins identical, jtagseln T20. Limits: tearing and
  judder, PAL low-res horizontal offset unverified. Not flashed. No "SRAM Erase" (CT2090).
- 2026-09-29 21:25: stage 1b DVI mode (commit `c6b1246`, build `manual-20260929-stage1b-dvi`
  PASS). Stage 1 HDMI (88a4b08): colour bars and tone WORK on David's TV, but the monitor (DVI input,
  DVI-to-HDMI cable) shows no sync, most likely because it rejects HDMI data islands/guard bands. So
  `hdmi_640.sv` now has `DVI_OUTPUT` (plain DVI 1.0: video + control periods only, CTL bits 0, no
  audio) and **DVI mode is now the default** (`top.sv` `.DVI_OUTPUT ( 1 )`; set 0 for HDMI + tone on
  the TV). Also fixed a 1-pixel offset (column 0 was dropped) in both modes. Pixel clock Fmax
  133.6 MHz, clk32 35.277 MHz (+2.9 ns), pins identical, jtagseln T20, 8/8 primary. Symbol-level sim:
  no island/guard symbols, CTL=00, syncs on ch0. Not flashed. No "SRAM Erase" (CT2090).
- 2026-09-29 20:36: stage 1 video-out sanity check (commit `88a4b08`, build
  `manual-20260929-stage1-colourbars` PASS). TV test of the pll32 build first (reported by David):
  flashed, the Console gives "invalid format" on the old TV while the 20K is OK there; the main monitor
  shows no sync on both. So `top.sv` now has `` `define HDMI_TESTPATTERN ``: the core stays running but
  its video is off HDMI, and a standalone 640x480@60 (VIC 1, 4:3) picture is sent instead: 8 colour
  bars with a 1 px white border plus a quiet 1 kHz beeping tone. It uses its own PLL
  (`gowin_pll_hdmi`, from Hybrid030, 126 MHz) with CLKDIV/5 = 25.2 MHz and MiSTeryNano's `hdmi/` core
  (`hdmi_640.sv`). Pixel clock Fmax 104.4 MHz (+30.1 ns); clk32 margin now only ~0.11 ns
  (32.117 MHz). TMDS pins identical, jtagseln on T20, primary clocks 8/8 (ds2 SPI clock moved to LW).
  To switch back: comment out the define AND edit `atarist.sdc` (re-enable clk_hdmi, comment out the
  stage 1 block). Not flashed. No "SRAM Erase" (CT2090). Details in `BUILD_REPORT.md`.
- 2026-09-29 13:35: exact 32 MHz PLL for the Console (commit `6fe62b8`, build `manual-20260929-pll32`
  PASS). `pll_160m_mod.v` now MDIV 16, VCO 800 MHz, ODIV 5/25/25/8/8: 160 MHz TMDS, 32.000 MHz pixel
  (was 31.667 MHz, ~1.2% slow), 32 MHz SDRAM clock at 338.4 deg (was 337.5), 100 MHz flash/mspi (was 95).
  `pll_160m.v` MULTI_FAC 16, `top.sv` PIXEL_CLOCK 32_000_000, `atarist.sdc` clk_32 31.25 ns.
  `atarist.cst` now pins `jtagseln` to T20 (it had been auto-placed on H17, USB-C D+). Pixel clock Fmax
  33.923 MHz, `.fs` 37047546 bytes. Not flashed yet. Do not use Gowin Programmer "SRAM Erase" (CT2090).
  TOS still at 0x500000. Details in `BUILD_REPORT.md`.
- 2026-09-29 12:47: this note created. No HDL changed.

## Current goal

Get the Console 138K version (`misterynano_tc138k`) showing a picture on David's very old HDMI TV,
starting from the rolled-back known-good tree (`66f57bb`).

## Nano 20K bench result (reported by David)

Stock MiSTeryNano on David's Tang Nano 20K gave a picture on his very old HDMI TV. This proves the TV
works with MiSTeryNano's stock HDMI output.

## TOS flash address (verified from the HDL)

- On this Console build, TOS goes at byte offset **0x500000**. The `08dc9cc` claim of 0x100000 was wrong.
- `misterynano.sv` lines ~149-159 pass the word address `{3'b001, slot, ste, rom_addr[17:1]}`.
- `tang/console60k/flash_dspi.v` (the flash module this project uses) forces byte bit A22=1 via
  `(state==6'd8)?{2'b01}`, which adds 0x400000, and shifts the word address to a byte address.
- So: ST TOS at 0x500000, STE at 0x540000, secondary slots at 0x580000 and 0x5C0000.
- 0x100000 is the Tang Nano 20K layout. On the Console it would land inside the bitstream.
- This matches the upstream MiSTeryNano Console 60K table.

## 2026-09-28 21:49 - build `manual-20260928-rollback` of `66f57bb`: PASS

- The `.fs` is 36538618 bytes, identical to mn3/mn4.
- Pixel clock CLKOUT1 reaches 33.313 MHz against a 31.667 MHz target.
- `-co-place_io_registers 0` was accepted by Gowin 1.9.12.03, so the `d10de5b` claim that it is
  unknown was wrong.
- No HDMI pin errors. The only negative slack is on cross-clock paths from auto-detected clocks
  (`ds2_p1/clk_spi` into IKBD setup at -19.7 ns, and `video2hdmi/clk_audio` hold at -2.1 ns),
  unchanged from before.
- Report commit: `bca98e9`.

## 2026-09-28 21:43 - rollback

`misterynano_tc138k/` was rolled back to `687446a` (the last good mn3/mn4 build tree) in commit
`66f57bb`, at David's request. It undoes 14 commits, `ea085ff`..`f492d96`:

- the HDMI pin sim files `sim/tb_hdmi_pins.sv` and `sim/run_hdmi_sim.sh` (deleted)
- the `d10de5b` tcl co-place change
- the stray empty file `git`
- the `00ebf80` `atarist.cst` separate HDMI P/N constraint (G16 tmds_clk_n)
- the `08dc9cc` README TOS address change
- all LED blink and Timer C probe work in `top.sv` and `atarist/mfp.v`
  (`9fb57be`, `3d2b7e7`, `1191ff6`, `4c85fb0`, `5c809f7`, `bafd9d3`, `6e72415`, `f492d96`)

The history is kept, so any of it can be restored.

## Open notes

- The old CONTEXT.md base64 handoff (2026-09-28-2, CHANGED 1) was not decoded because ACTION was
  NO_BUILD. It is retained as historical context only; the retired BUILD_REQUEST/CONTEXT watcher is
  superseded by the Patch handoff.
- `BUILD_REQUEST.md` and `CONTEXT.md` were not edited when this note was created.
- 2026-09-30 11:06: Atarist_030_wip README purpose/rules + LICENSE-NOTES.md added (docs only). Caches are to go INSIDE the WF68K30L core (David's decision), real-030 behaviour, no compatibility patches.
- 2026-09-30 11:11: LICENSE-NOTES.md notes the TF-style bridge is ST test bench only, not carried to the Falcon build.
- 2026-09-30 11:18: LICENSE-NOTES.md wording: repo is public (source only); no ST bitstream will be shared.
- 2026-09-30 11:45: Atarist_030_wip README now opens with credits/thanks to Stephen J. Leary (TerribleFire TF534).
- 2026-09-30 11:47: main README now urges readers to read Credits; credits expanded (Leary, Tejada, Puri).
- 2026-09-30 12:50: both MiSTeryNano READMEs now explain the HDMI/DVI switch and why the HDMI work was done (docs only).
- 2026-09-30 14:05: cpu030_st_bridge.v comments now credit Stephen J. Leary first and at each TF534-derived block (no logic change).
- 2026-10-01 11:22: misterynano_tc138k top.sv reset fix: `wire por = !pll_lock;` (dropped `|| bl616_jtagsel`; stock BL616 firmware never drives it low, so the V14 pull-up held the ST in reset = DVI sync, black screen). Build PASS (clk32 35.0 MHz, pix 86.4 MHz), not flashed, awaiting David's hardware test.
- 2026-10-01 19:36: Atarist_030_wip top.sv gets the same reset fix as 8adecde (`wire por = !pll_lock;`). Build PASS (cpu030 17.18 MHz, clk32 32.002 MHz met with near-zero margin), not flashed. David confirmed 19:25 BST that 8adecde boots misterynano_tc138k to the TOS desktop on the Console with stock BL616 firmware.
- 2026-10-01 21:50: Atarist_030_wip atarist.v: double reset on cold start (rigsdram AUTO_WARM scheme): ~48 us after the first ST reset ends, one extra reset_cnt reload (ST reset-button-equivalent); re-armed only by porb; both CPU paths.

## Catch-up 2026-10-01/02 (from Grok Bot)

- **Console black screen / “invalid signal” root cause:** Tang Console `top.sv` had `por = !pll_lock || bl616_jtagsel`. The BL616 is running stock Sipeed firmware (FPGA-Companion has never been installed), so it never drives that pin low and the ST stayed in reset. The Nano 20K uses `!pll_lock` only. Fixed in `8adecde` (`misterynano_tc138k`) and `a89f293` (`Atarist_030_wip`). The standard core now boots TOS 1.04 to the desktop on the Console.
- Upstream `top.sv` ties off the S0 (AA13) and S1 (AB13) buttons. Re-enabling S0 as a CPU reset is parked as a future debug aid.
- `c967a5e` added a double cold-start reset to `Atarist_030_wip/atarist/atarist.v`, porting rigsdram’s `AUTO_WARM` scheme. It is outside the `CPU_030` ifdef, so it also applies to the 68000 build. The rigsdram README says `AUTO_WARM` is a board workaround, not a product feature; this may be reverted.
- **Important correction:** David’s “C1-2 USB3 Video” HDMI capture device was faulty and has been returned. Screen captures are suspended until a new capture device arrives. Earlier capture results (030 “black screen”; 68000 build of the 030 tree “two bombs / bus error”) are therefore **unreliable**. On 2026-10-02, checking a real monitor showed the 68000 build of `Atarist_030_wip` ( `CPU_030` commented out, with the `misterynano_tc138k` SDC, hence no `clk_cpu030` `create_generated_clock` or clock-group entry) boots EmuTOS 1.4 to the desktop. Those were local laptop edits and are not committed.
- A read-only diff found `Atarist_030_wip` effectively identical to `misterynano_tc138k` outside the 030 files, apart from clock plumbing: PLL `CLKOUT5` at 8 MHz, `clk_cpu030` in the SDC, and the `clk_cpu` port.
- **Current board state:** the 030 build from main `9b0718d` (including the double reset) is flashed. Timing passed: `clk32_core` 32.069 MHz against 32 (almost no margin), `clk_cpu030` 17.6 MHz, TNS 0. EmuTOS 1.4 UK is in the TOS slot at `0x500000`. David will check the monitor when he is back; the result is pending.
- **TOS swapping (only when requested):** images are in `C:\tosimg` on David’s laptop: `tos104.bin` and `emutos-192uk-1.4.img`, both 192K padded with `FF` to 256K. Flash with `programmer_cli` op 56 using `--mcuFile` at `--spiaddr 0x500000` on cable location **417** (never 418), then reflash the core `.fs` with op 53.
- **Timing note:** detailed reports show negative-slack paths from `ds2_p1/clk_spi` (a Gowin-derived clock) into `clk32_core` (ikbd), while TNS remains 0. This looks like an unconstrained clock-domain crossing and is worth checking against the standard core.
- **Next steps:** get the monitor result for the 030 build. If it is black, try EmuTOS for a crash dump and consider adding margin to `clk32_core`.
- **Patch handoff (from 2026-10-02):** to hand code changes to Grok Bot, commit one `handoff/<YYYYMMDD-HHMM>-<short-name>.patch` (unified diff that `git apply`s on main) plus a matching `.md` (REQUEST_ID, ACTION, WORKDIR, BUILD_CMD, TOS, description). David tells Grok Bot when one is waiting. Full rules in `AGENT_PROTOCOL.md`, template in `handoff/README.md`.

## 2026-10-03 ~18:00 BST: diag030b capture readout (local-only diag, EmuTOS 1.4 UK 192K)
- First BERR: addr $FFFF8C80, FC=101 (supervisor data), read, byte, from ST bus. EmuTOS SCC probe ($FF8C8x), expected/harmless.
- PC at first BERR: shows $E00C4C, matches $FC0C4C (jsr $FC772E) in the 192K image.
- Screen base: $FF8201=$3F, $FF8203=$80 (both written) -> $3F8000, correct for 4 MB.
- Live last program fetch: shows $E13CA6, matches $FD3CA6, the extension word of `move #$2700,sr` at $FD3CA4. Frozen for ~20 s of frames: CPU is stopped there, not looping (a loop would show changing fetches).
- Note: both PC rows show A20..A18 as 0 ($E0/$E1 vs $FC/$FD) while the BERR row shows them set; probably a diag latch wiring quirk, worth checking.
- Next suspect: the bus cycle right after this fetch never completes (no DSACK/BERR) or the core halts on the move-to-SR / following read of $20CA.

## 2026-10-03 ~19:10 BST: diag030c readout (local-only diag, patch kept on Grok Bot's box; timing 36.0/16.45 MHz, flashed 417)
- No hung bus cycle: last 030 cycle started = $00E13CA6, FC=110, read, word, ended by DSACK; in-progress=0, hung=0; bridge IDLE, all strobes released.
- Bus-cycle start counter changes every frame, so the core is not fully dead; snapshots almost always show the fetch at $FD3CA6 (`move #$2700,sr` at $FD3CA4).
- IACK cycles happen (autovectored). IPL shows level 2 (HBL) pending, never 4, so VBLs are being taken and the mask is still 3: the `move #$2700,sr` never takes effect.
- Likely loop: stall in MOVE_TO_SR -> VBL -> handler -> RTE -> stall again. Suspect wf68k30L_control.vhd SLEEP state: MOVE_TO_SR waits for NEXT_EXEC_WB_STATE=IDLE (~line 2422) before START_OP / IPIPE_FLUSH (~line 1063).
- A20..A18 is NOT a diag bug: the core's raw ADR_OUT drives $E1xxxx for program fetches that should be $FDxxxx (even after jsr $FC772E). Hidden because $E00000 is the ROM alias. Suspect PC_I / PC_L = PC + PC_ADR_OFFSET in wf68k30L_top.vhd, or synthesis. Separate bug.
- Next: small GHDL bench of WF68K30L alone (move #$2300,sr / move #$2700,sr with IPL=2 held; jsr $00FC772E with ADR_OUT trace).

## 2026-10-05 ~19:10 BST: AE350 serial flash-fetch v2 (hybrid dual-purpose)

- 6702eaf MOSI/MISO fix was necessary but not sufficient: board still `PIN`/`DR`, no alive.
- Root cause vs hybrid: dual-purpose must be **MSPI+CPU only** (not all six). Also need true inout IOBUFs on CS/CLK and hybrid-style ~20 ms debounce of DDR3_INIT before AE350 reset.
- Serial-only fix committed; desktop stays mux-free / full six dual-purpose as before.
- Bitstream `ae350_serial_flash_v2.fs` flashed op 53 @ 417. Leave ready.bin at 0x0600000 and TOS alone.
- Next letters: `PIN` `DR` then hopefully `AE350 alive`. If still PINDR only, next suspects are SPI mode/clock vs hybrid IP defaults or ready.bin XIP map — not desktop mux.
