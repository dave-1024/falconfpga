# ST_HELPER: the AE350 RISC-V helper alongside the 030 ST desktop

Build: `gw_sh build_st_helper.tcl` (writes `` `define ST_HELPER `` into
`tang/console138k/build_sel.vh`). Bitstream: `impl/pnr/st_helper.fs`.
Firmware: `helper_fw/mailbox/` (`helper_mailbox.bin`, flash at `0x0600000`).
The desktop build `build_tc138k.tcl` is unchanged: every ST_HELPER change is
inside `` `ifdef ST_HELPER ``. With the define off, synthesis removes it.

**End goal.** The AE350 replaces the BL616 as the core's helper MCU, so that
the FPGA-Companion firmware (keyboard, mouse, OSD, floppy and hard disk
emulation) runs on the AE350 and the BL616 never has to be reflashed. This
first build gives the AE350 the same core-side interface as the BL616 and
tests it. FPGA-Companion itself is not ported yet (see "Port plan" below).

## 1. Boot-then-release of the SPI flash

One SPI NOR holds the core (0x000000), TOS (0x500000) and the helper image
(0x600000). Both the ST and the AE350 need it, but never at the same time:

| Phase | Flash owner | 030 / ST | AE350 | U15 shows |
|---|---|---|---|---|
| power-up | AE350 (in reset) | reset | reset | `STH` |
| DDR3 trained, +20 ms | AE350 | reset | running, boot loader copies `ready`-style image from 0x600000 into DDR3 | `D`, `R`, then the helper's own text |
| firmware writes GPIO[7:0] = 0xA5 ("done with flash"), runs from DDR3 | AE350, CS# idle | reset | running | helper text |
| CS# high for 8 us: **one-way switch** (`flash_to_st`, sticky) | ST | reset, its flash controller reinitialises | running, flash disconnected (MISO = 1) | |
| +2 us | ST | **released, TOS 2.06 boots** | running, companion link up | |

`st_helper_ctrl.v` is the state machine (clk32). Fallback, so the desktop
always boots: if DDR3 does not train in 4 s (`X`), the firmware does not
signal 0xA5 within 2 s (`T`), its CS# is not idle within 1 ms (`C`), or S1 is
held (`K`), the AE350 is put back into reset, the flash goes to the ST after
1 ms and the 030 is released; the letter is printed on U15 and BOOT
($FFFB11) says why.

**Why this is safe when the 988c846 runtime mux was not.** 988c846 muxed the
flash between ST and AE350 at run time and left an always-driven assign on
`mspi_do` (IO1). The ST flash controller (`tang/console60k/flash_dspi.v`)
reads in dual-I/O mode (0xBB, 100 MHz), so IO0/IO1 must turn around; the
assign fought the flash on every read and TOS never loaded. Here:

- the switch happens **once**, while the 030 is in reset and before the ST
  flash controller has left reset, with both CS# lines high, so no
  transaction is cut and nothing on the ST side ever sees the AE350;
- after the switch IO0/IO1 are real tristate pads driven by the ST
  controller's **own output enables** (`mspi_io_oe`, new ST_HELPER ports on
  `flash_dspi.v`), exactly the desktop's bidirectional behaviour;
- the switch is sticky (no way back until power-off or reconfiguration), so
  the AE350 can never touch the flash again. If its firmware ever tried, it
  would read 0xFF and the ST would not notice.

The flash controller's reset (`flash_reinit`) is released two `flash_clk`
cycles after the switch, so its 16-ones mode-exit sequence runs on the ST's
pads (this also clears any read mode the AE350 boot loader left behind).

## 2. AE350 = the companion MCU (replaces the BL616)

The stock core talks to its helper MCU through `misc/mcu_spi.v`: an SPI slave
(MODE1: SCK idle low, data sampled on the falling edge), plus an active-low
interrupt line from `sysctrl.v`. On the Tang Console the BL616 drives it on
the JTAG dual-purpose pins. In ST_HELPER:

| FPGA-Companion signal | BL616 (desktop) | AE350 (ST_HELPER) |
|---|---|---|
| SS# | `spi_csn` (TMS) | AE350 **GPIO[0]**, held by firmware for a whole message |
| SCK | `spi_sclk` (TCK) | AE350 flash SPI controller (SPI1) SCLK, after the handoff |
| MOSI | `spi_dat` (TDI) | SPI1 MOSI |
| MISO | `spi_dir` (TDO) | SPI1 MISO (`FLASH_SPI_MISO`) |
| IRQ# | `spi_irqn` (U15) | UART2 **DCD#** (MSR bit 7 reads 1 while an IRQ is pending) |
| link up | (n/a) | UART2 **DSR#** (MSR bit 5 reads 1 once the link is wired) |

Why these: the SoC netlist has no free SPI controller and no AHB/APB slave
port towards the fabric (only the Extended AHB master port). But after the
handoff its flash SPI controller is idle and its pins are plain fabric nets,
so it becomes the companion SPI master. Its own CS# toggles on every
transfer, so SS# comes from GPIO[0] instead; that also means a stray XIP read
of 0x80000000 can never reach the core. GPIO inputs are not readable from
the fabric side in this netlist, but the UART2 modem-status inputs are, so
IRQ# and "link up" use DCD# and DSR#.

`st_helper_mculink.v` re-registers SS#/SCK/MOSI on AHB_CLK (50 MHz) and only
passes a level after two equal samples, so a LUT glitch on the SoC's SCLK net
can never clock `mcu_spi`. The cost is about 80 ns of SCK delay, so the
firmware runs SPI1 slowly for now (SCLK_DIV 15, 1.6 MHz if SPI1 is clocked
at 50 MHz). The BL616 runs this link at 13.3 MHz; faster is a later step.

**The BL616 is kept off the link.** Its SS#/SCK/MOSI inputs (and a PMOD
companion's) are ignored, its MISO pin `spi_dir` is tristated and its IRQ pin
(C22 in this build) is held inactive high, so it cannot fight the AE350. The
stock BL616 firmware still does what it does today: USB serial bridge on U15,
and JTAG for programming. It is never reflashed.

The link test in the firmware sends the FPGA-Companion
`sys_status_is_valid()` frame byte for byte (target 0, command 0) and
expects `5C 42`, as the BL616 does at start-up. Only read-only commands are
sent: the core's coldboot IRQ is reported, not acknowledged.

## 3. Mailbox: the ST talks to the helper

A 32-byte register block at **$FFFB00-$FFFB1F** (`st_helper_mailbox.v`,
decoded in `atarist.v`). Supervisor data accesses only, like all ST I/O; A23:5
decoded, so it also appears at $FFFFFB00 through the 030's 24-bit mirror.
Bytes on odd addresses (D7:0), like the MFP; a word read returns $FF in D15:8.

| Address | Name | R/W | Meaning |
|---|---|---|---|
| $FFFB01 | ID | R | `H` ($48) |
| $FFFB03 | VER | R | $01 |
| $FFFB05 | STATUS | R | b0 TXRDY, b1 RXAVL, b2 HELPER_UP, b3 HELPER_FAIL, b4 RXOVR (sticky), b5 TXIDLE, b6 RXFERR (sticky) |
| $FFFB07 | TXDATA | W | send one byte to the helper (dropped if TX is full) |
| $FFFB07 | TXFREE | R | free TX FIFO slots (0-16) |
| $FFFB09 | RXDATA | R | next byte from the helper, removed at the end of the read; $00 if empty |
| $FFFB0B | RXCOUNT | R | bytes waiting (saturates at 255) |
| $FFFB0D | CTRL | W | b0 flush RX, b1 clear RXOVR/RXFERR, b2 flush TX |
| $FFFB0F | HGPIO | R | AE350 GPIO[7:0] ($A5 after the handoff; bit 0 is the companion SS#) |
| $FFFB11 | BOOT | R | $00 helper up, $01 DDR3 timeout, $02 no flash-done, $03 S1 skip, $04 CS# never idle |
| $FFFB13-$FFFB1F | SCRATCH0-6 | R/W | scratch bytes for a bus test |

**Why $FFFB00.** It is unused on ST, STE, Mega STE, TT and Falcon (hardware
register listing v9.1: between TT MFP2 at $FFFA81-$FFFAAF and the ACIAs at
$FFFC00). The GSTMCU does not decode it (VPA covers $FFFC00-$FFFDFF), so before
this device an access there ended in the bus-error timeout. $FF9000 (STE
GAMECART) and $FFFE00 (MonSTer) were avoided. TOS 2.06 is not known to probe
$FFFBxx; this has not been tested on hardware.

**Transport.** The mailbox talks to the helper's UART2 inside the FPGA: TX
FIFO (16) -> 115200 8N1 -> UART2_RXD; UART2_TXD -> RX FIFO (256, block RAM).
UART2_TXD also goes to U15, so everything the helper says appears on David's
terminal too. Everything is in clk32; the only asynchronous input is
UART2_TXD (2-flop synchroniser). No interrupts yet (the ST polls); an MFP or
level-6 interrupt is possible future work.

For the end goal the mailbox is a debug console, not the companion path:
FPGA-Companion reaches the ST through the normal core targets (IKBD, FDC,
ACSI/SD) over the SPI link above.

## 4. U15, V14 and C22

U15 is the FPGA-to-BL616 UART line; the stock BL616 bridges it to its USB
serial port (115200 8N1). In ST_HELPER, U15 carries the fabric boot letters
while the AE350 is in reset and the AE350's UART2 afterwards, as in the
serial proof. `spi_irqn` moves to C22 (held high, see above). Only the pin
file differs from the desktop: `tang/console138k/atarist_st_helper.cst`.

The other direction, PC -> BL616 -> FPGA, is ball V14 (`uart_rx` in the CST
comments; in this design the input is called `bl616_jtagsel` and idles high
with a pull-up). ST_HELPER ANDs it into UART2 RX next to the mailbox, so
typing in the same PC terminal talks to the helper directly (expected from
the CST's "internal BL616 UART" note; not yet tested). Typing on the PC while
the ST sends garbles both; the firmware drops bytes with framing errors and
NULs, so an idle-low V14 cannot flood it.

## 4a. Getting test code onto the ST in this build

The ST normally gets its floppy and hard disk images, and its USB keyboard
and mouse, from FPGA-Companion on the BL616. The stock BL616 firmware on this
board does not do that (it never did in the desktop build either), and the
AE350 port of FPGA-Companion does not exist yet. So there is no disk and no
keyboard to start `MBXTERM.PRG` from. Three ways, simplest first:

1. **U15 + V14 only (no ST program).** The helper's boot text, including the
   companion-link test (`core status: 5C 42 ... link OK`), appears on U15 by
   itself. Typing in the PC terminal reaches the helper (V14), so `s`, `i`
   and echo lines work from the PC. This tests the flash handoff, the AE350
   and the AE350-to-core link. It does not test the ST side of the mailbox.
2. **Self-test cartridge (build option `ST_HELPER_CART`, on in
   `build_st_helper.tcl`).** A 644-byte cartridge ROM at $FA0000 is built
   into the bitstream (`st_helper_cart_rom.v`, one block RAM, contents
   `st_helper_cart.hex` generated from `helper_fw/st_test/mbxcart.s`). The GSTMCU already decodes ROM4 and
   acknowledges it like the TOS ROM; the core only supplies the data. TOS 2.06
   finds the cartridge magic at boot and calls it once (CA_INIT bit 3, after
   GEMDOS, before the boot disk). It prints BOOT and STATUS on the ST screen,
   sends `hello from the ST` to the helper, shows the helper's answer
   (`helper: got 17 bytes: HELLO FROM THE ST`) for a few seconds and returns,
   so TOS carries on to the desktop. The helper prints the same exchange on
   U15. No disk, keyboard or flash write needed. **U15 alone is enough for
   the first test:** with just the U15 output in a terminal (V14 not used),
   David sees the boot letters, the link test and the cartridge exchange,
   and the ST screen shows the ST side. If the helper is not
   running it prints one line and returns at once. Remove the
   `ST_HELPER_CART` line in `build_st_helper.tcl` to build without it.
3. **Later, `MBXTERM.PRG` from a disk** once the AE350 serves a floppy or
   hard disk image (FPGA-Companion port, section 7), or on any setup with a
   working companion. It needs a keyboard too.

A cartridge ROM loaded from SPI flash was considered and not chosen: it would
change the TOS ROM read path in `flash_dspi.v`, which is the part of this
build that must not break. A tiny floppy image that the AE350 serves from
flash needs the FPGA-Companion floppy path (`sdc` sector requests over the
`mcu_spi` link) ported first, plus a keyboard or an AUTO folder to start the
program; it is the natural next step after the port, not a first test.

## 5. What to expect

U15, 115200 8N1:

```
STH
DR
AE350 helper mailbox v1 ready (flash released, running from DDR3)
link: fabric says up, probing SPI1 @F0B00000
SPI1 IDREV 0200xxxx
core status: 5C 42 id=00 cb=00 -> link OK
core IRQ# asserted (pending, not acked by this test)
commands: s = core status ..., i = core IRQ line, ? = this; ...
>
```

Then the GEM desktop appears on HDMI, a fraction of a second later than with
the desktop build. Fallback: a single `X`, `T`, `C` or `K` line instead of
the helper text, and the desktop still boots.

ST screen (with `ST_HELPER_CART`), during the TOS boot, before the desktop:

```
ST_HELPER mailbox self-test (cartridge $FA0000)
BOOT $00  STATUS $25            (or $27 if helper bytes are waiting)
sent 'hello from the ST', helper says:
hello from the ST
helper: got 17 bytes: HELLO FROM THE ST
>
-- mailbox test done, TOS continues --
```

From the PC terminal (V14), type `s` and RETURN to rerun the link test.

ST side, once a disk path exists: run `MBXTERM.PRG` (`helper_fw/st_test/`). It prints VER, BOOT,
STATUS and HGPIO, then everything typed goes to the helper and its replies
are shown. Type `hello` and RETURN: `helper: got 5 bytes: HELLO`. Type `s`
and RETURN: the helper runs the companion status frame again and shows the
result. ESC quits.

Without the program, from a monitor in supervisor mode (e.g. TEMPLMON,
MonST): read $FFFB01 (should be $48), $FFFB11 (should be $00), $FFFB05
(bit 2 set); write $41 to $FFFB07 and then $0D; read $FFFB0B (count) and
$FFFB09 repeatedly to get `A`, CR, LF and the reply.

## 6. Risks

- The flash SCK pad now goes through a LUT mux in ST_HELPER (AE350 or the PLL
  clock). This shifts the 100 MHz dual-I/O read timing slightly against the
  desktop build. If TOS does not load in this build but does with the
  desktop build, suspect this first.
- Dual-purpose pin options are the desktop's (JTAG, SSPI, READY, DONE, MSPI
  and CPU as GPIO), not the serial proof's (MSPI + CPU only). If the AE350
  does not boot, the fallback still starts the desktop.
- Boot delay: about 25 ms with the helper, up to about 6 s (DDR3 timeout +
  handshake timeout) if it is missing; S1 at power-up skips it.
- S0 resets only the ST in this build; DDR3 and the helper keep running.
- `ST_HELPER_CART` makes TOS find a cartridge. The self-test returns within
  a few seconds whatever happens on the helper side (all loops have
  budgets), but a cartridge that hung would stop the boot: remove the define
  if the boot stops after its title line.
- SPI1 base 0xF0B00000 is the Andes AE350 map for the flash controller; the
  firmware checks the ATCSPI200 ID first and leaves the link alone if it does
  not match (the desktop is unaffected either way).

## 7. Port plan (FPGA-Companion on the AE350)

FPGA-Companion keeps the hardware behind `src/mcu_hw.h`; the BL616 version is
`src/bl616/mcu_hw.c`. An AE350 port is a new `src/ae350/mcu_hw.c`:

1. `mcu_hw_spi_begin/tx_u08/end`: the three functions from
   `helper_fw/mailbox/mailbox.c` (GPIO[0] low, one ATCSPI200 write-and-read
   byte, GPIO[0] high). Then multi-byte transfers for sector data, and a
   faster SCK once the MISO margin is measured.
2. IRQ: UART2 modem-status interrupt on DCD (MSR bit 3 delta, bit 7 level)
   in place of the BL616 GPIO interrupt; `mcu_hw_irq_ack` re-enables it.
3. Scheduling: FreeRTOS on the AE350 (the Andes SDK supports it), or a
   bare-metal main loop for HID/OSD/SD first.
4. Storage: the SD card is already behind the core (`sd_card.v`, SDC target);
   FPGA-Companion reads it through the core, so no new driver is needed.
5. USB HID: the AE350 has no USB host. Keyboard and mouse for the ST still
   need a source: DB9 / the core's own inputs, a PS/2 or USB host core in the
   fabric, or HID reports forwarded by the stock BL616 over its UART. This is
   the main open design question.
6. Remove the mailbox's debug role from the console once the companion menu
   runs (or keep it as a debug channel).

## Credits

- Boot handoff and AE350 wiring follow the working AE350 bring-up in
  `Hybrid030` / 168ktest (DDR3 reset timing, flash ball map, boot loader).
- MiSTeryNano and FPGA-Companion: Till Harbaum and the MiSTle-Dev
  contributors. The link protocol, `misc/mcu_spi.v` and `misc/sysctrl.v` are
  theirs (FPGA-Companion is Apache-2.0, `helper_fw/fpga-companion/LICENSE`;
  the HDL files carry their own headers).
- The 030 bridge credits Stephen J. Leary's TerribleFire TF534 (see the
  README).
