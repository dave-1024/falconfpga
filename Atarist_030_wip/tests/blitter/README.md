# BLTTEST.PRG - cursory blitter copy check (uncommitted, 22 Oct 2026)

13 blits, HOP=2 (source) OP=3 (source), ST-RAM to ST-RAM: 1 word, 7 words, 13x9 odd at screen stride (HOG and
shared + CPU busy), skew 5 FXSR + masks, skew 11 NFSR, skew 3 FXSR+NFSR with all three end masks, negative
increments (with/without FXSR), bitplane stride 8, 1 word x 33 lines, 66,560 bytes (HOG), 73,728 bytes (shared + CPU busy).
Each test fills the 192 KB src/dst buffers with fresh patterns, computes the expected destination with a CPU model of
the STE blitter, runs a 2-word primer blit (so the blitter's 32-bit source buffer is known), runs the blit, then
compares every word of the destination buffer (guard areas included). "busy" tests run CPU write/read-back
traffic in ST-RAM while the blitter runs in shared mode; "cpu errs" counts bad read-backs.
Not covered (by request): exhaustive sweeps, TT-RAM-resident CPU traffic, xcount=1 with NFSR (undefined on real hardware).

Run: copy BLTTEST.PRG to the floppy/HD image and double-click it (or run from AUTO). Output goes to the screen and
to the serial port (Bconout AUX, MFP RS-232). Last line: `RESULT pass $0D fail $00` then `ALL PASS`. Any key exits.
A FAIL line gives the number of wrong words; "No blitter" means $FF8A00 gave a bus error.
Build: ./build.sh
