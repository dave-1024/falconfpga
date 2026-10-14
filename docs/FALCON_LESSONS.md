# Lessons for the Falcon core

Practical notes from the ST/030 core (Tang Console 138K + AE350 helper), for David and the assistant when starting the Falcon core. Sources: `docs/float_panic/FLOAT_PANIC.md`, `docs/float_panic/BLITTER_REVIEW.md`, build notes.

## Design

1. **Put every major path behind a compile-time switch.** CPU type (`ST_CPU_68000` vs the 030), bridge, early AS, fast handoff, cartridge, caches, debug probes. *Why:* when the 030 build panicked, the quickest way to split the problem was to rebuild without one piece. *How:* `` `define `` the switch in `build_sel.vh` from a per-variant `build_*.tcl`. Never hard-code `CPU_030`.
2. **Bus-error writeback must leave the destination untouched.** On a real 030, a read that bus-errors does not change the target register. Our core wrote `$FFFF` after the `$FFFA40` (SFP004) probe. Detection code relies on this behaviour, so it has to be right.
3. **Blitter, CPU bridge and floppy DMA arbitration must be cycle-correct.** HOG/BUSY, BR/BG/BGACK, and the order of handover in both directions. *Why:* the Falcon adds more bus masters (DSP, DMA sound, VIDEL). *How:* follow the hardware handshake. Don't add "data wins" muxes. Today, if DMA and the blitter were ever active together, the DMA data would win.
4. **Gate 030-tuned shared logic.** The double cold-start reset (`DR_GAP`) and the SDRAM early start (`RAM_EARLY`) run in every build. On a 68000 they can give different boot faults (for example exception 33, TRAP #1 taken before GEMDOS sets up its handler). Tie them to the CPU switch, or expect this.
5. **Keep the autoboot cartridge and helper optional.** The cartridge runs before the memory test and before AUTO programs, so it changes the boot order compared with Hatari. Always keep a build without the cartridge so this can be ruled out.

## Debugging

6. **Probe what the CPU can't see.** A CPU write-watch misses floppy DMA, the blitter and the helper. Put watches on the RAM port, tagged with which master did the write (`DIAG_DMAWATCH`), and decode them with the `pages_*.py` scripts.
7. **Don't trust software labels alone.** Read the raw cookies (`_FPU`, `_CPU`, `_MCH`, `_SND`) and test Line-F behaviour directly. A wrong probe answer may show "no FPU type" but still change software paths. There is one cookie, `_FPU`; the type is packed into its high word.
8. **Make the Hatari comparison match the board.** Use the same machine type (`_MCH`/`_SND`, since STE vs ST changes software paths), the same TOS, RAM size and cartridge image, and compare the same memory layout. Without this, a "Hatari passes" result means little.
9. **Avoid adding new unknowns while hunting a bug.** No hard disk drivers (HDDriver, ICD) during a hunt. Dump small RAM ranges to a floppy image instead.

## Board and flash

10. **Always leave the board on a working build, and keep a known-good `.fs` as the fallback** (currently `st_helper_sdw_p3.fs`).
11. **Flash rules:** use only `programmer_cli` op 53 with `--fsFile`. Never bulk erase. Never write `0x500000` (EmuTOS/TOS) or `0x600000` (helper firmware). Never reflash the BL616.
12. **Rescan the Gowin cables every time.** The cable location changes (it was 4225 recently).
13. **A partial flash doesn't lose the debugger.** The FT2232 shows up on USB whatever is in the bitstream. If it's missing from `lsusb`, check power or the cable, not the flash.
14. **The Hagibis capture (345f:2130) needs an explicit format.** Use `-f v4l2 -input_format yuyv422 -video_size 1920x1080 -framerate 60` and skip about 60 warm-up frames (`select=gte(n\,60)`). See `~/fpga_tools/grab.sh`.

## Process

15. **Don't merge half-fixes.** The SD write fix still needs its error flag before it goes to main, and long uploads can still jam. Test new transfer paths on small chunks first.
16. **Leave a trail for overnight work.** Write notes in `docs/`, keep bitstreams in `~/fpga_bitstreams` with names that say what they are, push the branch, and record what is flashed now, so the next session can pick up without rediscovering anything.
17. **Builds take a while.** Run `gw_sh` in the background with `QT_QPA_PLATFORM=offscreen` (11 to 55 minutes). The ssh session can drop during routing, so log to a file.
