| [PMMU3] Short-format indirect descriptors (DT 2 at the last level, MC68030UM 9.5.1.4 p. 9-27, Figure 9-14).
| TC = $80C84800: PS 4K, IS 8, TIA 4, TIB 8. CRP DT 2: short table A at $6000.
|   A[0] -> short table B at $6100 (identity pages), A[$F] early-termination page $F00000 (ROM).
|   B[4] = indirect (DT 2) -> short page descriptor at $6900 (-> $C000).
|   B[6] = indirect -> invalid descriptor at $6904 -> bus error.
| Results from $5000 on.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        clr.w   0x5100
        clr.l   0x400c
        lea     0x5000,a4
        lea     0x6000,a0
        moveq   #15,d0
1:      clr.l   (a0)+
        dbf     d0,1b
        move.l  #0x00006102,0x6000      | A[0] -> table B (short)
        move.l  #0x00f00001,0x603c      | A[$F]: page
        lea     0x6100,a0
        move.l  #255,d0
        moveq   #1,d1
2:      move.l  d1,(a0)+                | B[n]: identity
        add.l   #0x1000,d1
        dbf     d0,2b
        move.l  #0x00006902,0x6110      | B[4]: indirect -> $6900
        move.l  #0x00006906,0x6118      | B[6]: indirect -> $6904 (address bits 1-0 of the pointer ignored)
        move.l  #0x0000c001,0x6900      | page -> $C000
        clr.l   0x6904                  | invalid
        move.l  #0x0000cafe,0xc000
        move.l  #0x00004444,0x4000
        move.l  #0x7fff0002,0x7000
        move.l  #0x00006000,0x7004
        pmove   0x7000,crp
        move.l  #0x80c84800,0x7008
        pmove   0x7008,tc
        move.w  0x4002,(a4)+            | -> $CAFE (logical $4000 through the indirect -> $C000)
        move.w  #0xbeef,0x4002          | write: M on the page descriptor at $6900
        ptestr  #5,0x4000,#7
        pmove   psr,(a4)+               | -> $0203 (M from the page descriptor, N = 3: A, B, indirect)
| invalid descriptor behind an indirect: bus error, the handler turns TC off and the read reruns
        moveq   #0,d3
        move.w  0x6000,d3               | logical $6000 = B[6] -> indirect -> invalid -> bus error; rerun TC off
        move.w  d3,(a4)+                | -> $0000 (A[0] high word, physical $6000)
        pmove   0x7008,tc
        ptestr  #5,0x6000,#7
        pmove   psr,(a4)+               | -> $0403 (I, N = 3; no W: bit 2 of the indirect $6906 is address, not WP)
        pmove   0x700c,tc
        move.l  0x6900,(a4)+            | page descriptor -> $0000C019 (U + M set on the target, 9.5.1.4)
        move.l  0x6110,(a4)+            | B[4] indirect -> $00006902 (unchanged: no U on an indirect)
        move.w  0xc002,(a4)+            | -> $BEEF
        move.w  0x5100,(a4)+            | bus errors: 1
        move.l  0x5104,(a4)+            | fault address $00006000
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
berr:   move.l  a0,-(sp)
        move.w  0x5100,d0
        addq.w  #1,0x5100
        lea     0x5104,a0
        lsl.w   #2,d0
        move.l  4+0x10(sp),0(a0,d0.w)
        move.l  (sp)+,a0
        pmove   0x700c,tc
        rte
