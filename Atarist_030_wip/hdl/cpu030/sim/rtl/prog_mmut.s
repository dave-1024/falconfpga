| [PMMU3] 11.7.2 MMU instruction clocks (MC68030UM p. 11-60): loops of 8 equal instructions (I-cache case) between
| marker writes to $3400; the clock difference of the markers / 8 is the instruction time (calibration of the
| MMU padding; the regression compares the marker clocks only through the whole-log check).
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        clr.l   0x400c
        lea     0x5000,a4
        lea     0x6000,a0               | table A: all invalid
        moveq   #15,d0
1:      clr.l   (a0)+
        dbf     d0,1b
        move.l  #0x00006102,0x6000      | A[0] -> table B, DT 2 (short)
        move.l  #0x00f00001,0x603c      | A[$F]: page, early termination
        lea     0x6100,a0               | table B
        move.l  #255,d0
        moveq   #1,d1
2:      cmp.l   #0x10001,d1
        bcc.s   3f
        move.l  d1,(a0)+
        add.l   #0x1000,d1
        dbf     d0,2b
        bra.s   4f
3:      clr.l   (a0)+
        dbf     d0,2b
4:      move.l  #0x0000c001,0x6128      | B[$A] -> $C000
        clr.l   0x612c                  | B[$B] invalid
        move.l  #0x0000d005,0x6134      | B[$D] WP
        move.l  #0x0000cafe,0xc000
        move.l  #0x00001111,0xa000
        move.l  #0x0000e0e0,0xe000
        move.l  #0x7fff0002,0x4000
        move.l  #0x00006000,0x4004
        pmove   0x4000,crp
        move.l  #0x80c84800,0x4008
        pmove   0x4008,tc
        lea     0xa000,a1
        moveq   #1,d0
        moveq   #1,d1
        movec   d1,sfc
        move.l  #0x80c84800,0x4008
        lea     0x4008,a2
        moveq   #1,d6
        movec   d6,cacr                 | I-cache on: loops run in the I-cache case
        .macro  blk n, i
        move.w  #\n,0x3400
        moveq   #7,d7
        .balign 4
1:      \i
        dbf     d7,1b
        .endm
        lea     ramcode(pc),a5
        lea     0x8000,a6
        move.w  #(ramend-ramcode)/2-1,d6
0:      move.w  (a5)+,(a6)+
        dbf     d6,0b
        jmp     0x8000
        .balign 4
ramcode:                                | runs from $8000 (cachable with CIMODE 1, identity mapped)
        blk     1, "nop"
        blk     2, "pflusha"
        blk     3, "pflush #1,#7"
        blk     4, "pflush %sfc,#7"
        blk     5, "pflush #1,#7,(a1)"
        blk     6, "ptestr #1,(a1),#0"
        blk     7, "ploadr #1,(a1)"
        blk     8, "ptestr #1,(a1),#7"
        blk     9, "pflush %d0,#7"
        blk     10, "ploadr %sfc,(a1)"
        blk     11, "pmove (a2),%tc"
        blk     12, "nop"
        move.w  #13,0x3400
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
ramend:
