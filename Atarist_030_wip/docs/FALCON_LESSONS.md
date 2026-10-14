# Lessons for the Falcon core

What we learned on the 030 ST core (Atarist_030_wip, Tang Console 138K, AE350 helper) and want to keep
doing from day one on a Falcon core. Background: `BUILD.md`, `float_panic/FLOAT_PANIC.md`, `float_panic/BLITTER_REVIEW.md`.

## Build and switches
1. **Make every major path a compile-time switch.** CPU type (`ST_CPU_68000` vs 030), bridge, `BRIDGE_EARLY_AS`,
   `WF030_FAST_HANDOFF`, cartridge, caches, diag probes. Never hard-code `CPU_030`.
   *Why:* every A/B test (F62d vs early-AS vs F65, cart vs no cart, 68000 vs 030) only took a rebuild, not a code edit.
   *How:* one `build_*.tcl` per variant, writing `build_sel.vh` (Gowin has no command-line define).
2. **Gate shared 030-tuned logic too.** The double cold-start reset and the early SDRAM path (`RAM_EARLY`, reset gap)
   run in every build. On a 68000 they can produce a different boot fault (we saw exception 33 / TRAP #1, a GEMDOS
   call before GEMDOS was ready). Put them behind the CPU switch, or expect that.
3. **Keep the cartridge and helper hooks optional.** An autoboot cartridge runs before the memory test and before AUTO
   programs, so it changes boot order. Have a no-cart build ready, and remember the remote driving needs the mailbox.

## Flashing and the board
4. **Always leave the board on a working build.** Flash only with op 53 `--fsFile`. Never bulk erase. Never write 0x500000
   (TOS) or 0x600000 (helper firmware). Never reflash the BL616. Keep the last good `.fs` (now `st_helper_sdw_p3.fs`) as the fallback.
5. **Rescan the cables every time.** The location changes after reboots or replugs (289, 417, 4225 ...).
6. **A partial flash doesn't lose the debugger.** The FT2232 shows up on USB whatever is in flash. If it's missing
   from `lsusb`, the board has no power or the cable/port is bad. A bad flash only gives a black screen.
7. **Capture:** the Hagibis (345f:2130) needs explicit v4l2 settings and warm-up frames:
   `ffmpeg -f v4l2 -input_format yuyv422 -video_size 1920x1080 -framerate 60 -i /dev/video0 -vf 'select=gte(n\,60)' -frames:v 1 out.png`
   (`~/fpga_tools/grab.sh`). A black frame on its own doesn't prove the core is dead.

## Debugging
8. **Probe what you can't see.** A CPU-side write watch misses floppy DMA, blitter and helper writes. Watch at the RAM
   port and tag every entry with its master (CPU/DMA/blitter). Check that the probe's own decoder is right too: our
   "address corruption" was a bit-18 misread in the decoder.
9. **Don't trust software labels alone.** Read the raw cookies (`_CPU`, `_FPU`, `_MCH`, `_SND`) and test Line-F
   directly (FNOP must trap to vector 11). A wrongly answered probe might not show any FPU type in a sysinfo tool.
10. **Bus-error reads must not write back.** After a read that bus-errors, the destination register must be unchanged.
    Our core put `$FFFF` in D0 after `move.w $FFFA40,d0`. Falcon software probes a lot of addresses, so fix this before reusing the core.
11. **Match Hatari exactly before comparing.** Same machine type (`_MCH`, ST vs STE vs Falcon), `_SND`, TOS version,
    RAM size, cartridge image and resolution. STE vs ST changes software paths. Note that Hatari forces EmuTOS 192 to a 68000.
12. **Cross-check differences in a differential harness first.** Musashi vs the RTL bench (`float_panic/diff/`) cleared the
    CPU in a few hours. Then move to the board-only differences (DMA, blitter, helper, IRQ sources).
13. **Bus arbitration must be cycle-correct.** Blitter HOG/BUSY, BR/BG/BGACK through the 030 bridge, and floppy DMA must
    never own the bus together. The Falcon adds more masters (DSP, sound DMA, VIDEL), so plan arbitration and tags in from the start.

## Process
14. **Don't merge half-fixes.** The SD write fix still needs its error flag before main, and long uploads can still jam.
    Test new data paths on small chunks first.
15. **Leave a trail.** Before any overnight or token-limited run, write the state into the notes (board build, bitstream
    names, what's next) and keep the bitstreams in `~/fpga_bitstreams`, so work can pick up cold. Always end on the fallback `.fs`.
16. **Keep credits.** Keep the original authors' headers and `LICENSE-NOTES.md` up to date as cores are borrowed (WF68K30L, fx68k, FX blitter, MiSTeryNano).
