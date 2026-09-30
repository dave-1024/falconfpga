# MiSTeryNano — Tang Console 138K only

[MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) FPGA tree, stripped to the **Tang Console + GW5AST-LV138** target, with our changes: an exact 32 MHz clock and a new standard 640x480 HDMI/DVI video output (see below). The ST core itself is unchanged. Nano 20K / Primer / Mega tops are not in this folder.

This is **fx68k** (68000), not wf68k30L. It lives next to `rigsdram/` so the two vehicles stay separate.

## Video output: HDMI or DVI (read this before you compile)

This build does **not** use MiSTeryNano's original video output. The ST picture
goes through an on-chip frame buffer and out as a standard **640x480 at 60 Hz**
signal. There is a switch for the type of signal, and it matters for your
display.

**The switch** is in `tang/console138k/top.sv`, on the `hdmi_testpattern_640`
instance (`hdmi_tp`):

```
hdmi_testpattern_640 #(
    .DVI_OUTPUT ( 1 ),   // 1 = plain DVI, no audio (default); 0 = HDMI with audio
    .ST_VIDEO   ( 1 )    // 1 = ST picture (default); 0 = colour bars test pattern
) hdmi_tp ( ...
```

- **`DVI_OUTPUT = 1` (default): plain DVI.** Use this for a monitor with a DVI
  input, for example through a DVI-to-HDMI cable. DVI can't carry audio, so
  none is sent. HDMI TVs accept this too.
- **`DVI_OUTPUT = 0`: full HDMI** (with the HDMI info packets and an audio
  channel). Use this for an HDMI TV if you want sound through it. At the moment
  the audio channel carries only a 1 kHz test tone; the ST's own sound is not
  routed to it yet.
- **`ST_VIDEO = 0`** shows colour bars instead of the ST picture, to check a
  display or cable on its own.

**Why the switch exists:** full HDMI adds extra data (audio and info packets)
between the lines of the picture. A DVI monitor doesn't expect that data and
shows no picture at all. Our main test monitor only has a DVI input, so DVI
is the default, and HDMI stays one setting away for TVs.

**Why we did the HDMI work at all:** with the stock MiSTeryNano output on the
Tang Console 138K, our old TV said "invalid format" and the DVI monitor showed
no signal, although the same TV worked with a Tang Nano 20K. The stock output
sends the ST's own, non-standard timing. We replaced it with a standard
640x480 at 60 Hz mode (the basic mode almost every HDMI or DVI display must
accept), fed from a frame buffer so the ST side keeps its original timing.
The colour bars and the DVI mode were confirmed working on both the monitor
and the TV.

**Things to know:**

- Colour modes (low and medium resolution) are line-doubled and centred with
  black borders; mono (high resolution) is shown 1:1. The position can be
  tuned with `ST_H_OFS_COLOR`, `ST_H_OFS_MONO` and `ST_V_BORDER` in
  `hdmi_testpattern_640.sv`.
- The on-screen menu (OSD) is **not** shown on this output yet.
- The ST picture through the frame buffer has not yet been tested on real
  hardware (the colour bars have).
- To go back to the original MiSTeryNano video output (with OSD and ST audio),
  comment out `` `define HDMI_TESTPATTERN `` near the top of `top.sv`.

## Board

- Device: `GW5AST-LV138PG484AC1/I0` **Version C**
- Top: `tang/console138k/top.sv` (`module top`)
- Output name: `atarist_tc138k`
- **Tang SDRAM module required**, in J9 / SDRAM0 (`tang/mega138kpro/sdram.v`, CS0 tied low). This is the plug-in module, not the DDR3 on the SOM. Do not flash this bitstream with J9 empty.
- `Hybrid030/` is the only tree that does **not** need that module. Every HDL build from here does, including this one, `rigsdram/`, and the 030 splice.
- TOS in SPI flash: if `tang/console60k/flash_dspi.v` stays, the address map in the HDL is **0x500000** family. The Console 138K doc table says **0x900000**. Measure `.fs` size after the first build before flashing TOS.

## Build (Windows Gowin V1.9.12)

Open this folder, not `rigsdram`.

**Preferred (options actually applied):**

```
cd misterynano_tc138k
gw_sh build_tc138k.tcl
```

TCL sets Version C, `use_jtag_as_gpio 1`, MSPI/SSPI/DONE/CPU/READY as GPIO, `replicate_resources 1`.

**IDE:** File → Open → `atarist_tc138k.gprj`. The `.gprj` is a file list. Confirm Process Configuration matches the TCL before you hit Run: SystemVerilog 2017, top module `top`, device version C, and dual-purpose pins JTAG / DONE / READY / MSPI / SSPI / CPU as GPIO. Leave MODE and I2C off.

Bitstream: `impl/pnr/atarist_tc138k.fs` (gitignored).

## Not in this tree

- FPGA-Companion / BL616 firmware (needed for OSD / TOS load / keyboard)
- TOS ROM images
- Nano 20K, Primer 25K, Mega 138K, Console 60K board tops

Cold-boot on this SOM is a known open item in both this core and rigsdram. Stock `top.sv` already ties `.reset` / `.user` to `0` “to fix tc138k booting”.

## License

Upstream MiSTeryNano and bundled cores (fx68k, jt49, hd63701, …) keep their original licenses. `fx68k/LICENSE` is included.
