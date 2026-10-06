# DIAG_OVERLAY: on-screen diagnostic overlay (debug build option)

The diagnostic overlay draws the core's internal state straight onto the HDMI/DVI
picture, so a frozen or misbehaving 68030 can be examined with nothing more than a
monitor (or an HDMI capture stick). It was used to find the F58 bridge timing
problem and the F59 loop-mode deadlock.

**It is OFF by default.** To enable it, uncomment `` `define DIAG_OVERLAY `` near
the top of `tang/console138k/top.sv` and rebuild. It needs `HDMI_TESTPATTERN`
and `ST_VIDEO = 1` (both are the defaults). With the define commented out the
debug wiring has no load and synthesis removes it, so the normal build is
unaffected.

Why it is off: it uses extra fabric (registers and the drawing logic), reduces
the timing margin a little, and covers part of the screen. It is for debugging
only, not for normal use.

When enabled, `leds_n[1]` blinks (about 2 Hz) while the 68030 starts bus cycles
and stays steady when it stops; `leds_n[0]` is still the ROM-fetch latch.

`DIAG_FB_SELFTEST` (in `top.sv`, only with `DIAG_OVERLAY`): 1 fills the frame
buffer from a locally generated test picture instead of the ST video, to check
the frame buffer on its own. Keep it 0.

## Layout

All coordinates are in 640x480 output pixels. From top to bottom:
six bit-bar rows (a to f), then three rows of 48x48 status squares
(S17-S20, S1-S10, S11-S16), and on the last row 16 bars with the first TOS
word read from the ROM (offset 0, MSB left).

## Bit-bar rows

Six bit-bar rows above the squares, y 96-287 (640x480 coords), black band x 8-567, 32 px pitch.
Each row: coloured label square (x 16-35), then up to 32 bars, 12 px wide, MSB left, groups of 4
(= one hex digit, 8 px gap). White = 1, dark grey = 0, missing bar = unused. Column n = same bit in every row.

| row | label | bars y (640x480) | content |
|---|---|---|---|
| a | RED | 102-121 | first BERR address A31:0 (unchanged from diag030b) |
| b | MAGENTA | 134-153 | bits 31-24: got FC2 FC1 FC0, RW SIZ1 SIZ0 BAD; bits 23-8: last word read from cmdload $482; bits 7-0: EmuTOS boot-path flags (diag030w, see below) |
| c | CYAN | 166-185 | A31:0 of the LAST bus cycle STARTED by the 030 (raw WF68K30L ADR_OUT on the clk_cpu edge where AS is first seen low) |
| d | GREEN | 198-217 | see below |
| e | ORANGE | 230-249 | bridge (68000 side, clk_32) state, see below |
| f | BLUE | 262-281 | G1-G2: bus cycles started mod 256; G3-G8: live last program fetch A23:0 (raw ADR_OUT, FC=x10) |

Row d (GREEN), bits 31..0, groups G1..G8:
- G1: FC2 FC1 FC0 RW of the last started cycle (RW 1 = read)
- G2: SIZ1 SIZ0 (01 byte, 10 word, 11 3-byte, 00 long), INPROG (that cycle not yet terminated AND AS still low), HUNG (sticky: some cycle stayed open > 8192 clk_cpu = ~1.02 ms at 8 MHz)
- G3: last termination one-hot T_DSACK T_BERR T_AVEC (as seen at the 030 pins), 4th bar unused
- G4: IACKs (sticky: IACK cycle started, FC=111 & A19:16=F), IACKd (sticky: IACK terminated), CPUSP (sticky: any FC=111 cycle), IACKav (sticky: IACK terminated with AVEC)
- G5: HALT_OUTn, RESET_OUT, RESET_INn (bridge cpu_rst_n), IPENDn  (live)
- G6: STATUSn, IPL2n IPL1n IPL0n as fed to the CPU (active low: 111 = no interrupt)  (live)
- G7: ASn, DSn, DSACK1n, DSACK0n at the 030 (live; DSACK = 01 when bridge acks)
- G8: BERRn, AVECn, RMCn, RWn at the 030 (live)
Rows c, d and f are cleared while the 030 is held in reset.

Row b (MAGENTA) bits 7-0, diag030w EmuTOS 1.4 boot-path flags (sticky, cleared by
the ST reset; set by a PROGRAM-space ST bus cycle at a fixed address in the tail of
biosmain(), 256K image E0xxxx / 192K image FCxxxx; atarist.v):
- bit 7 CMD: cmdload path, Pexec("COMMAND.PRG") (E016A6 / FC0E7C)
- bit 6 EXEC: exec_os path, Pexec(PE_BASEPAGE) for the AES (E016C4 / FC0E9A)
- bit 5 P1RET: that first Pexec returned (E016E2 / FC0EB8)
- bit 4 AES: exec_os entry gm_init fetched (E1EAA8 / FD79A8)
- bit 3 HALT: biosmain's "System halted!" call reached (E01714 / FC0EE4)
- bit 2 FCROM / bit 1 E0ROM: a program fetch from FC0000-FEFFFF / E00000-E3FFFF was seen
- bit 0 CMDRD: $482 was read (bits 23-8 then hold the last word read)
The icache can hide a fetch from the bus only if that line was already cached,
which does not happen for this once-per-boot code. These addresses are only valid
for the EmuTOS 1.4 UK 192K/256K images.

Row e (ORANGE), bridge state, live:
- G1: phase2:0 (0 IDLE, 1 S0, 2 S2, 3 S4 = waiting for DTACK/VPA/BERR, 4 S6), pending (030 request not yet accepted)
- G2: req_now, s_seen, c_open (030 request open, clk_cpu), term_ok (termination tag matches)
- G3: rAS rUDS rLDS rRWn (ST-side strobes, active low)
- G4: rDtack rBerr (sampled DTACKn/BERRn), Vpai (sampled VPAn), iStop
- G5: s_dsack s_avec s_berr s_tag (answer to the 030)
- G6: r_tag addr_oe rVma r_iack
- G7: arb1:0 (0 idle, 1 grant, 2 busy), BGn, can_start
- G8: r_res1:0 (0 DSACK, 1 AVEC, 2 BERR), BRi, BgackI

Reading: hung bus cycle = row d INPROG=1/HUNG=1, row c = that cycle, row e phase shows where the bridge waits.
CPU-internal wedge = INPROG=0, ASn=1, row f count and PC frozen, bridge IDLE, pending=0.

## Status squares

Colours: GREEN = happening now (seen within the last ~0.13-0.26 s) or level
true; YELLOW = happened earlier since power-up but not any more; RED = never
seen since power-up. S1/S2 blink green/dark green while alive. S20 (bus error)
has the colours inverted, because seeing it is bad: GREEN = never seen,
YELLOW = seen earlier, RED = happening now.

Rows: S17-S20 at y 296-343, S1-S10 at y 360-407, S11-S16 at y 424-471
(x = 8 + 64*i).

```
Squares (E = event/activity, L = level):
  S1  E ST vsync falling edges (blinks at VS/32)        st_video_vs_n
  S2  E ST hsync falling edges (blinks at HS/16384)     st_video_hs_n
  S3  E ST DE high                                      st_video_de
  S4  E non-black RGB while DE                          st_video_r/g/b
  S5  E ST-side AS falling edges (bridge runs ST cycles) atarist cpu_as_n
  S6  E TOS ROM selected (E0xxxx/FCxxxx)                rom_n (GSTMCU ROM2_N)
  S7  E ROM read returned data other than 0000/FFFF     rom_dout @ rom_n rise
  S8  E frame buffer write enable (ST FB writes)        st_fb_capture we
  S9  L main PLL locked                                 pll_lock
  S10 L 68030 out of reset (bridge RESET_INn released)  bridge cpu_rst_n
  S11 L atarist reset input released                    resb term
  S12 L SDRAM init done                                 sdram ready
  S13 E BL616 SPI select seen (MCU talks to the core)   spi_io_ss
  S14 L BL616 not holding the ST in reset               !system_reset[0]
  S15 L SD wait done (image or 2 s timeout)             sd_ready
  S16 L 68030 not halted (no double bus fault)          bridge oHALTEDn
  S17 E 030 bus cycle started (030 AS seen by bridge)   bridge req toggle
  S18 L ROM fetch latch (first E/FC-FE cycle, = LED0)   bridge rom_fetch
  S19 E DSACK returned to the 030                       bridge s_dsack rise
  S20 E BERR returned to the 030 (colours inverted)     bridge s_berr rise
```

## Reading a capture

- A hung bus cycle: row d INPROG = 1 or HUNG = 1, row c is that cycle, row e
  shows where the bridge is waiting.
- A CPU-internal stop: INPROG = 0, ASn = 1, the row f count and fetch address
  frozen, bridge IDLE with pending = 0.
- Normal running: rows c and f change from frame to frame (they show as
  flickering bars on a capture).
