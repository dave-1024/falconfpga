# Boot floppy: TT-RAM + blitter for TOS 2.06 on the 68030 STE core

`blitfix.st` (720 KB). AUTO folder, in this order (TOS runs AUTO programs in directory order):

1. `TTRAM.PRG` (ours, `ttram.s`): finds the 030-side TT-RAM at `$01000000` (512 KB steps until a bus error;
   refuses if `$01xxxxxx` mirrors ST-RAM, i.e. TT-RAM switched off), `Maddalt()`s it, sets `$5A4`/`$5A8`
   and adds an `_FRB` cookie (64 KB ST-RAM DMA bounce buffer, kept resident). No PMMU use: the core has none,
   which is why agranlund's `fastram.prg` (builds a PMMU table) is not used. Skips itself if `Mxalloc(-1,1)` > 0.
2. `BLITON.PRG` (ours, `bliton.s`): `Blitmode(1)` if a blitter is present; prints the mode ($0003).
3. `BLITFIX.PRG`: agranlund's tftools blitfix (GPL-2.0, source and licence in `blitfix_src/`, prebuilt binary
   from tftools). It needs TT-RAM registered (`$5A8` magic + `$5A4`), so it runs after TTRAM. On TOS 2.06 it
   patches the VDI/line-A blit routines to fall back to software when an address is outside the blitter's
   24-bit range, and itself calls `Blitmode(1)` (so BLITON is a belt-and-braces print of the state).

Root: `BFTEST.PRG` (ours, `bftest.s`, header flags 7 = loads and mallocs in TT-RAM): GEM test, run from the
desktop. `vro_cpyfm` from a TT-RAM buffer (`Mxalloc(,1)`) to the screen and from the screen to a second TT-RAM
buffer with the blitter on; checks the pixels and that the ST-RAM alias (address & `$FFFFFF`) of the destination
is unchanged. Prints Blitmode, its basepage and buffer addresses, PASS/FAIL; waits for a key.

Why: the STE blitter has 24 address bits on the ST bus and cannot reach TT-RAM; a blit from or to `$01xxxxxx`
would hit ST-RAM at the low 24 bits. Without BLITFIX (TTRAM + BLITON only) the TOS 2.06 desktop draws no icons
and bombs (2 bombs) on the board.

Build: `bash mk.sh ttram.s TTRAM.PRG`, `bash mk.sh bliton.s BLITON.PRG`, `bash mk.sh bftest.s BFTEST.PRG 7`
(GNU m68k as/ld/objcopy; code is PC-relative, no relocation table). Image: `mformat -C -f 720`, `mmd ::/AUTO`,
`mcopy` the three AUTO programs in the order above, then `BFTEST.PRG`.
