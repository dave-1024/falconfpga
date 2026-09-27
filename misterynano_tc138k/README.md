# MiSTeryNano — Tang Console 138K only

Stock [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) FPGA tree, stripped to the **Tang Console + GW5AST-LV138** target. Nano 20K / Primer / Mega tops are not in this folder.

This is **fx68k** (68000), not wf68k30L. It lives next to `rigsdram/` so the two vehicles stay separate.

## Board

- Device: `GW5AST-LV138PG484AC1/I0` **Version C**
- Top: `tang/console138k/top.sv` (`module top`)
- Output name: `atarist_tc138k`
- **Tang SDRAM module required**, in J9 / SDRAM0 (`tang/mega138kpro/sdram.v`, CS0 tied low). This is the plug-in module, not the DDR3 on the SOM. Do not flash this bitstream with J9 empty.
- `Hybrid030/` is the only tree that does **not** need that module. Every HDL build from here does, including this one, `rigsdram/`, and the 030 splice.
- TOS in SPI flash: this core fetches it. There is no added offset. Primary ST slot is byte **0x0100000**. STE is **0x0140000**. The OSD second slots are **0x0180000** and **0x01C0000**. The programmer box wants the leading 0. `0x500000` and the Console doc-table `0x900000` are not this map, and a ROM flashed there will not be read. Do not flash TOS until HDMI syncs and the programmed bitstream length is known, so the slot is not sitting inside the bitstream.

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
