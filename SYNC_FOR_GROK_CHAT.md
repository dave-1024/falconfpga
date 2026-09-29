# SYNC FOR GROK CHAT

Catch-up note for Grok chat. Newest entries are at the top. All times are UK time (BST, UTC+1).

## Purpose

Grok chat (David's HDL-writing assistant) is out of tokens until 1 Oct 2026. Until then, David asks
Grok Bot for changes directly, and Grok Bot edits, builds and logs everything here and in
`BUILD_REPORT.md`. **Grok chat: please read this file first when you are back, before assuming any
old state.** While this note is active, Grok Bot may edit HDL at David's request.

## Changes since 2026-09-29 (running log, Grok Bot adds entries here, newest first)

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

- The CONTEXT.md base64 handoff (2026-09-28-2, CHANGED 1) has not been decoded by Grok Bot, because
  ACTION was NO_BUILD. It may be out of date after the rollback.
- Grok chat: when you are back, please update CONTEXT.md to reflect everything above.
- `BUILD_REQUEST.md` and `CONTEXT.md` were not edited when this note was created.
