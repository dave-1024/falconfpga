| [PMMU2b] PFLUSHA / PFLUSH / PLOAD / PTEST (MC68030UM 9.8, Table 9-3 p. 9-60), same tree as prog_xlate.s.
| MMUSR values from $5000 on (PMOVE PSR,(a4)+), then descriptors.
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
        move.l  #0x11111111,d4
        move.l  #0x22222222,d5
        move.l  #0x33333333,d3
        move.w  0xa002,d0               | ATC entry for $A000 (FC 5, read: M = 0)
        ptestr  #5,0xa000,#0
        pmove   psr,(a4)+               | -> $0000 (hit, not WP, not modified)
        move.l  d5,0x5080               | [PMMU2b] board bug: PTEST must not write a data register
        move.l  d4,0x5084
        lea     0xa000,a1
        move.l  (a1),d5
        ptestr  #5,(a1),#7
        move.l  d5,0x5088
        move.l  d4,0x508c
        move.l  d3,0x5090
        ptestr  #5,0xb000,#0
        pmove   psr,(a4)+               | -> $0400 (I: no entry)
        ptestr  #5,0xb000,#7
        pmove   psr,(a4)+               | -> $0402 (I, N = 2: A[0], B[$B] invalid)
        ptestw  #5,0xd000,#7
        pmove   psr,(a4)+               | -> $0802 (W, N = 2)
        ptestr  #5,0xd000,#1
        pmove   psr,(a4)+               | -> $0001 (level 1 only: A[0])
        pflusha
        ptestr  #5,0xa000,#0
        pmove   psr,(a4)+               | -> $0400 (flushed)
        ploadw  #5,0xa000
        ptestr  #5,0xa000,#0
        pmove   psr,(a4)+               | -> $0200 (M, from PLOADW)
        pflush  #5,#7,0xa000
        ptestr  #5,0xa000,#0
        pmove   psr,(a4)+               | -> $0400
        ploadr  #1,0xa000               | user data FC
        pflush  #5,#7                   | FC 5 only: the FC 1 entry stays
        ptestr  #1,0xa000,#0
        pmove   psr,(a4)+               | -> $0200 (hit; M as in the descriptor, set by the PLOADW)
        pflush  #1,#7
        ptestr  #1,0xa000,#0
        pmove   psr,(a4)+               | -> $0400
        pflusha                         | [PMMU3] FC operand in a data register (01RRR, p. 9-64)
        moveq   #1,d2
        ploadr  d2,0xa000               | FC 1 from d2
        ptestr  #1,0xa000,#0
        pmove   psr,(a4)+               | -> $0200 (the FC 1 entry is there)
        moveq   #5,d2
        ptestr  d2,0xa000,#0
        pmove   psr,(a4)+               | -> $0400 (no FC 5 entry)
        pflush  d2,#7                   | FC 5 only
        moveq   #1,d2
        pflush  d2,#7
        ptestr  #1,0xa000,#0
        pmove   psr,(a4)+               | -> $0400 (flushed through d2)
        move.l  #0x00ff8507,0x4010      | TT0: everything, CI
        pmove   0x4010,tt0
        ptestr  #5,0xa000,#0
        pmove   psr,(a4)+               | -> $0040 (T)
        clr.l   0x4010
        pmove   0x4010,tt0
        pmove   0x400c,tc
        move.l  0x6128,(a4)+            | B[$A] -> $0000C019 (U + M by PLOADW; reads before set U)
        move.l  0x6134,(a4)+            | B[$D] -> $0000D005 (PTEST does not set U)
        move.l  0x5088,(a4)+            | d5 after "move.l (a1),d5; ptestr (a1)": $0000CAFE
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
