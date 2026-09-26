# hybrid_falcon030

Frozen archive of the **HDL fabric** from the AE350 + Musashi hybrid scaffold.

Top is `src/Falcon030_top.v`, **REV 11b** (2026-07-24). Gowin project `Falcon030.gprj`, device `GW5AST-LV138PG484AC1/I0`.

This is history. Destination CPU for new work is **wf68k30L** in `rigsdram/`, then the Nano splice. Do not treat a rebuild of this tree as the 030 HDL path.

## Board

**No Tang SDRAM module.** This fabric uses the DDR3 on the 138K SOM (AE350). Leave J9 empty for a hybrid flash.

Any later HDL build (`misterynano_tc138k/`, `rigsdram/`, the 030 splice, Falcon HDL) **does** need the plug-in SDRAM module in J9.

## SOM DDR3 — unpublished faults

Not bugs in this HDL. The Gowin DDR3 IP on this SOM has dead lanes. As of September 2026 they were not in Gowin's notes, Sipeed's docs, or Sipeed's public repositories, and they were not found described anywhere else.

- Write **lane 4** never completes. Do not use it.
- A 64-bit DDR3 **read upper half** is dead. 32-bit lanes only.
- Extended AHB **`HWDATA` upper 32** is dead. 32-bit, even-word, payload at +0 and +8. Never +4.

Using the IP as documented does not work for those lanes. This fabric did not repair it. It avoided the dead parts. A real fix is your own DDR3 controller, or a Gowin IP update that did not exist when this was written. Full note: [`../AE350_ERRATA.md`](../AE350_ERRATA.md).

## What is in the tree

- Falcon glue: AHB mux, video mailbox, timebase, HID, audio/I2S, USB HID host
- Gowin PLLs (AE350, DDR3, HDMI, USB) — the DDR3 PLL is the SOM chip, not the J9 module
- Generated Andes `riscv_ae350_soc` wrapper (needed to open the project)
- Constraints: `tang_console_ae350_stage0.cst`, `ae350_stage0.sdc`

Not in git: `Falcon030.gprj.user`, IP `temp/`, `riscv_ae350_soc.vo`, `.cst.bak`, `impl/`.

## Rules

- Source only. No `impl/`, `*.fs`, `*.bin`, `*.user`.
- Do not hook `BUILD_REQUEST` to this folder unless a request names it.
- Locked AE350/DDR3/AHB errata still apply. They are not our bugs. See [`../AE350_ERRATA.md`](../AE350_ERRATA.md).
