# hybrid_falcon030

Frozen archive of the **HDL fabric** from the AE350 + Musashi hybrid scaffold.

Source is not in this folder yet. David will drop the cleaned tree from the final PC zip. Until then this README is the slot.

## What will live here

Gowin project and Verilog/VHDL for the Falcon hybrid top (REV11-era fabric: ST-RAM alias, video mailbox, timebase, HID ring). Destination CPU for new work is **not** this tree — it is wf68k30L in `rigsdram/` and later the Nano splice.

## Rules

- Source only. No `impl/`, `*.fs`, `*.bin`.
- Do not hook `BUILD_REQUEST` to this folder unless a request names it.
- Read-only history once the zip is imported.
