# hybrid_falcon030

Frozen archive of the **HDL fabric** from the AE350 + Musashi hybrid scaffold.

Top is `src/Falcon030_top.v`, **REV 11b** (2026-07-24). Gowin project `Falcon030.gprj`, device `GW5AST-LV138PG484AC1/I0`.

This is history. Destination CPU for new work is **wf68k30L** in `rigsdram/`, then the Nano splice. Do not treat a rebuild of this tree as the 030 HDL path.

## What is in the tree

- Falcon glue: AHB mux, video mailbox, timebase, HID, audio/I2S, USB HID host
- Gowin PLLs (AE350, DDR3, HDMI, USB)
- Generated Andes `riscv_ae350_soc` wrapper (needed to open the project)
- Constraints: `tang_console_ae350_stage0.cst`, `ae350_stage0.sdc`

Not in git: `Falcon030.gprj.user`, IP `temp/`, `riscv_ae350_soc.vo`, `.cst.bak`, `impl/`.

## Rules

- Source only. No `impl/`, `*.fs`, `*.bin`, `*.user`.
- Do not hook `BUILD_REQUEST` to this folder unless a request names it.
- Locked AE350/DDR3/AHB errata still apply (no dead write lane4, no 64-bit read upper half, 32-bit AHB).
