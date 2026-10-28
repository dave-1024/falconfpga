# F84 armed trace (board, 99727cd, mint_mp2.st, MP on)
The memset at $6066E (fills the page-type map at $9B7F4 with $01) arms the trigger. The next write to $9B7F0-7 from another PC
froze the trace: a supervisor loop at $15236..$15250 (clr.l (a4,d1.l*4); movea.l 8(a0),a5; clr.w (a5,d1.l*2); addq; cmp; bne)
with a0=$9AF94: a4=($9AF9C)=$9B7D4, a5=($9AFA0)=$9B8D4. It zeroes $9B7D4.. and $9B8D4.. right through the map, so
map byte $9B7F4 reads $00 later (F83) -> type-0 invalid template -> fault after pmove tc -> double fault -> halt.
Hatari (same TOS, 030+MMU, 4 MB): the same loop runs, but with a4=$9B1D4, a5=$9B2D4 (no overlap with the map).
So the CPU and the RAM work correctly; on the board that buffer pair was allocated $600 higher and on top of the map.
Next: find what allocated $600 more first (an allocation that only happens on the board: hardware detected differently,
e.g. TT-RAM/drives/cookies), and who owns the loop at $15236 (a program loaded at $15xxx).

# F87 cache-resize arithmetic (MiNT bio resize $15090..$150EC), RTL vs Hatari
Hatari operands: d0=$80 lsl #10 -> $20000; divul.l ($660FE=$8000) -> 4; muls.l $214*4 -> $850 (table kmalloc);
muls.l 4*$8000 -> $20000 (buffers); bftst $9C000{28:4} Z=1. arith_bio.s runs these (exact mint030 encodings) plus
divu.l/divs.l 32 and 64-bit, mulu.l/muls.l 64-bit, lsl/asl counts 31/32/33 on tb030 and in Hatari (loadbin): every
result and SR identical (arith_bio_rtl.txt / arith_bio_hatari.txt). The arithmetic is not the cause.

# F89 board (PC $152xx write to $9AF98, POST 8): ROOT CAUSE CANDIDATE - indexed-EA scale swapped on the board
Descriptor 0 at $9AF84 = Hatari's table (kmalloc agrees), a4=$9AFD4, a5=$9B0D4 (correct). In the clear loop
  $15238 clr.l (0,a4,d1.l*4)  ext $1C00 (scale 4)   board long writes start $9B04C, $9B04E, $9B050 ... (+2 per d1: scale 2, misaligned)
  $15240 clr.w (0,a5,d1.l*2)  ext $1A00 (scale 2)   board word writes $9B1C4, $9B1C8, $9B1CC ...     (+4 per d1: scale 4)
Each instruction uses the other's scale (stale brief extension word, one instruction late). The word clear runs at
4x2 = twice its array, and in the last descriptor it walks into the page map at $9B7F4 -> map byte 0 -> invalid page -> halt.
RTL (tb030, same loop, clrloop_scale.s): correct at WS 0..3, WSRND 0/3, caches off and CACR $0101. Board-only.
Next: F90 NOCACHE builds (I/D off), then look at the EA/extension-word path for a board-only (timing/placement) cause.
