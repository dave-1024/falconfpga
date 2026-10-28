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
