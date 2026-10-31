| [PMMU3] M68000PRM ch. 6 forms the 68030 does not have -> F-line ($2C) in supervisor mode (PMMUTEST T_prm cases):
| PMOVE (An)+,TC / TC,-(An) (p. 6-48), PTEST #0 with A = 1 (p. 6-66), PFLUSH mode 010 (p. 6-34). Results from $5000:
| vector offset per case, then A0 (must be unchanged: no post-increment / pre-decrement), TC (must still be 0).
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #fline,0x2c
        lea     0x5000,a4
        lea     0x4000,a0
        move.l  #0x80c84800,(a0)        | would enable translation if loaded
        move.l  #0x80c84800,-4(a0)
        .word   0xf018,0x4000           | pmove (a0)+,tc
        .word   0xf020,0x4200           | pmove tc,-(a0)
        .word   0xf010,0x8331           | ptestr #1,(a0),#0,a1
        .word   0xf000,0x2811           | pflush mode 010
        move.l  a0,(a4)+                | -> $00004000
        pmove   tc,(a4)                 | -> $00000000
        addq.l  #4,a4
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
fline:  move.w  6(sp),d0
        and.w   #0x0fff,d0
        move.w  d0,(a4)+                | $002C
        addq.l  #4,2(sp)
        rte
