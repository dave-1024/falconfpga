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
3. **Later, `MBXTERM.PRG` from a floppy image on the SD card**, once the
   AE350 runs the FPGA-Companion SD/floppy code (section 7, steps 2-3; no USB
   needed for that part). `helper_fw/st_test/build.sh` also makes
   `MBXTERM.ST`, a 720 KB FAT12 floppy image with `MBXTERM.PRG` in its root
   (`mkst.py`). Copy it to the SD card, mount it as drive A: from the
   companion, and start it from the desktop. Typing into it needs the
   keyboard (section 7, step 4). It also works today on any setup with a
   working companion.

A cartridge ROM loaded from SPI flash was considered and not chosen: it would
change the TOS ROM read path in `flash_dspi.v`, which is the part of this
build that must not break. A tiny floppy image served by the AE350 from
SPI flash was also considered: in this core the floppy and ACSI sector data
always comes from the SD card through `misc/sd_card.v` (the companion only
translates the sector numbers), so serving it from flash would need new
HDL. The SD card route (item 3) needs no HDL change.

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

## 7. Port plan: the whole BL616 helper on the AE350

On MiSTeryNano the BL616 runs FPGA-Companion (Till Harbaum, Apache-2.0):
USB host for keyboard, mouse and joysticks, the OSD menu, and SD card
access with FAT, image mounting and sector translation for floppy and ACSI.
It talks to the core only through `mcu_spi` (targets SYS, HID, OSD, SDC)
and the IRQ line. This build already gives the AE350 that link, so the port
is mostly firmware. The hardware stays as it is in this build unless noted.

1. **Link layer (`src/ae350/mcu_hw.c`).** `mcu_hw_spi_begin/tx_u08/end` are
   the three functions in `helper_fw/mailbox/mailbox.c` (GPIO[0] low, one
   ATCSPI200 write-and-read byte, GPIO[0] high). Add multi-byte transfers
   (FIFO bursts) for sector data. The IRQ is the UART2 modem-status
   interrupt on DCD (MSR bit 3 delta, bit 7 level) in place of the BL616
   GPIO interrupt; `mcu_hw_irq_ack` re-arms it. Raise SCK from ~1.6 MHz once
   the MISO margin is measured. With the AHB-clock retiming in
   `st_helper_mculink.v` the link passed simulation up to 6.25 MHz
   (80 ns half-period).
2. **OS and core status.** FreeRTOS from the Andes AE350 SDK (FPGA-Companion
   already uses FreeRTOS on the BL616), or a bare-metal main loop first.
   `sys_status_is_valid` already works (the link test). Then the SYS target:
   core id, DIP/config bits, reset control.
3. **SD card, floppy and ACSI.** No new HDL or driver. The SD card is wired
   to the core (`misc/sd_card.v`, pins V15/Y16/AA15...). FPGA-Companion's
   `sdc.c` + FatFs read the card through the SDC target (the core has a
   512-byte MCU buffer). On a core request (`sdc_int` -> IRQ) the companion
   translates the image sector to an SD sector, and the core reads it
   straight into its own buffer. So the sector data never crosses the slow
   link, only FAT and directory reads do (about 3 ms per 512 bytes at the
   current SCK). `sdc.c`, `ff.c` and the image/mount code are portable C.
   This step alone makes floppy images (and `MBXTERM.ST`) usable.
4. **USB keyboard and mouse: reuse `usb_hid_host.v` from 168ktest/Hybrid030.**
   The AE350 has no USB host, but the fabric can be one. nand2mario's
   `usb_hid_host.v` (low-speed HID boot protocol, 12 MHz clock) is already
   in `/workspace/ae350_old_bringup/168ktest/src/` and
   `Hybrid030/hybrid_falcon030/src/` with its `usb_hid_host_rom.hex` and
   `gowin_pll_usb`. It runs on the Console's two USB-A host ports (USB1 D+/D-
   = H13/G13, USB2 = M15/M16, pins from the NESTang Console port). These
   pins are free in the Atarist CST. Two ways to wire it, both behind a new
   `ST_HELPER_USB` define:
   - **4a. Through the AE350 (the companion way, needed for the OSD).** Each
     `usb_hid_host` instance feeds a small register block that the AE350
     reads: `typ`, a report counter, `key_modifiers`, `key1..4`, mouse
     buttons/dx/dy. Hybrid030's `falcon_hid_ahb.v` already writes these
     events into a DDR3 ring through the AE350's Extended AHB Master port
     and can be reused. A smaller choice is an APB/GPIO-style read port.
     The firmware replaces the BL616 USB host glue (under `src/bl616/`)
     with a reader for these reports. It rebuilds an 8-byte boot-protocol
     report from the registers and hands it to the existing `hid.c`
     (`kbd_parse`/`mouse_parse`). That code
     diffs the reports into key make/break codes and mouse movement and
     sends them on the HID target, which `misc/hid.v` turns into IKBD events
     (keyboard command 1, mouse 2, joystick 3). The OSD hotkey and menu work
     because the MCU sees every key.
   - **4b. Fabric-only shortcut (no firmware).** A `hid_inject.v` diffs the
     `usb_hid_host` reports and drives `hid.v` with the same byte frames
     the MCU would send, muxed with the `mcu_spi` HID strobe. This gives
     keyboard and mouse on the ST before the firmware port (and makes
     `MBXTERM` usable), but no OSD hotkey. It is a stepping stone only.
   - **Clocks:** this build uses all 8 primary clocks (100%). The 12 MHz USB
     clock must come from a spare output of an existing PLL on a non-primary
     (long-wire) route, or a clock net must be freed. Check this first.
     Joysticks: `usb_hid_host` also decodes gamepads (`typ` = 3).
5. **OSD.** The core build has `osd_data_out = 8'h55` (no OSD in the 030
   core yet). MiSTeryNano's `misc/osd_u8g2.v` is already in the tree but not
   instantiated; wire it into the video path, or keep the menu on the
   helper's UART console at first. FPGA-Companion's menu code (`menu.c`,
   u8g2) is portable.
6. **BL616 for good.** Once steps 1-4 work, the BL616 is only the USB-serial
   bridge and JTAG for U15/V14 and programming. Its SPI pins stay tristated
   and ignored (section 2). Keep the mailbox as a debug channel or drop it.
7. **Order, simplest first:** 1+2 (link, already half done), 3 (SD
   floppy: run `MBXTERM.ST`), 4b (keys on the ST), 4a (keys through the
   companion), 5 (OSD).

## Credits

- Boot handoff and AE350 wiring follow the working AE350 bring-up in
  `Hybrid030` / 168ktest (DDR3 reset timing, flash ball map, boot loader).
- MiSTeryNano and FPGA-Companion: Till Harbaum and the MiSTle-Dev
  contributors. The link protocol, `misc/mcu_spi.v` and `misc/sysctrl.v` are
  theirs (FPGA-Companion is Apache-2.0, `helper_fw/fpga-companion/LICENSE`;
  the HDL files carry their own headers).
- `usb_hid_host.v` (port plan, step 4; not in this build): nand2mario,
  based on work by hi631, https://github.com/nand2mario/usb_hid_host, as
  used in 168ktest/Hybrid030.
- The 030 bridge credits Stephen J. Leary's TerribleFire TF534 (see the
  README).
