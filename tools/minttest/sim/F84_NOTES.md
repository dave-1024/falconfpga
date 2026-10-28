# F84 armed trace (board, 99727cd, mint_mp2.st, MP on)
The memset at $6066E (fills the page-type map at $9B7F4 with $01) arms the trigger. The next write to $9B7F0-7 from another PC
froze the trace: a supervisor loop at $15236..$15250 (clr.l (a4,d1.l*4); movea.l 8(a0),a5; clr.w (a5,d1.l*2); addq; cmp; bne)
with a0=$9AF94: a4=($9AF9C)=$9B7D4, a5=($9AFA0)=$9B8D4. It zeroes $9B7D4.. and $9B8D4.. right through the map, so
map byte $9B7F4 reads $00 later (F83) -> type-0 invalid template -> fault after pmove tc -> double fault -> halt.
Hatari (same TOS, 030+MMU, 4 MB): the same loop runs, but with a4=$9B1D4, a5=$9B2D4 (no overlap with the map).
So the CPU and the RAM work correctly; on the board that buffer pair was allocated $600 higher and on top of the map.
Next: find what allocated $600 more first (an allocation that only happens on the board: hardware detected differently,
e.g. TT-RAM/drives/cookies), and who owns the loop at $15236 (a program loaded at $15xxx).
