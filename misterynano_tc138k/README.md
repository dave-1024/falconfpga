# MiSTeryNano — Tang Console 138K only

Stock [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) FPGA tree, stripped to the **Tang Console + GW5AST-LV138** target. Nano 20K / Primer / Mega tops are not in this folder.

This is **fx68k** (68000), not wf68k30L. It lives next to `rigsdram/` so the two vehicles stay separate.

## Board

- Device: `GW5AST-LV138PG484AC1/I0` **Version C**
- Top: `tang/console138k/top.sv` (`module top`)
- Output name: `atarist_tc138k`
- SDRAM: Tang SDRAM X2 in J9 / SDRAM0 (`tang/mega138kpro/sdram.v`, CS0 tied low)
- TOS in SPI flash: if `tang/console60k/flash_dspi.v` stays, the address map in the HDL is **0x500000** family. The Console 138K doc table says **0x900000**. Measure `.fs` size after the first build before flashing TOS.

## Build (Windows Gowin V1.9.12)

Open this folder, not `rigsdram`.

**Preferred (options actually applied):**

```
cd misterynano_tc138k
gw_sh build_tc138k.tcl
```

TCL sets Version C, `use_jtag_as_gpio 1`, MSPI/SSPI/DONE/CPU/READY as GPIO, `replicate_resources 1`.

**IDE:** File → Open → `atarist_tc138k.gprj`. The `.gprj` is a file list. Confirm Process Configuration matches the TCL (especially JTAG-as-GPIO and device version C) before you hit Run.

Bitstream: `impl/pnr/atarist_tc138k.fs` (gitignored).

## Not in this tree

- FPGA-Companion / BL616 firmware (needed for OSD / TOS load / keyboard)
- TOS ROM images
- Nano 20K, Primer 25K, Mega 138K, Console 60K board tops

Cold-boot on this SOM is a known open item in both this core and rigsdram. Stock `top.sv` already ties `.reset` / `.user` to `0` “to fix tc138k booting”.

## License

Upstream MiSTeryNano and bundled cores (fx68k, jt49, hd63701, …) keep their original licenses. `fx68k/LICENSE` is included.
