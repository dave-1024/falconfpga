| [PMMU3] RTE reruns a faulted write (SSW DF, MC68030UM 8.1.2 / 8.2.1). Same tree as prog_xlate.s;
| B[$D] -> physical $D000 write protected, B[$E] -> physical $C000 write protected.
| The bus error handler clears WP in the descriptor and does PFLUSHA (TC stays on, demand-paging style).
| TC = $80C84800: PS 4K, IS 8, TIA 4 (A23-A20), TIB 8 (A19-A12), FCL 0, SRE 0 (9.7.2 p9-54).
| CRP: DT 2 (short), table A at $6000 (9.7.1 p9-52).
|   A[$F]: early-termination page $F00000 (9.5.3.3: ROM $FC0000 identity, 1 MB).
|   A[0]: table descriptor -> table B at $6100 (256 short page descriptors).
|   B[n]: identity for n = 0..$F except: B[$A] -> $C000, B[$B] invalid, B[$D] write protected.
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
        move.l  #0x0000c005,0x6138      | B[$E] -> $C000, WP
        move.l  #0x7fff0002,0x4000
        move.l  #0x00006000,0x4004
        pmove   0x4000,crp
        move.l  #0x80c84800,0x4008
        pmove   0x4008,tc
        move.w  #0x1234,0xd000          | WP -> bus error; handler clears WP; RTE reruns the word write
        ori.l   #4,0x6134               | WP on B[$D] and B[$E] again
        ori.l   #4,0x6138
        pflusha
        move.b  #0x56,0xe003            | byte write, odd address (physical $C003) -> fault, rerun byte
        ori.l   #4,0x6134
        pflusha
        move.l  #0x89abcdef,0xd008      | long write -> fault, rerun long
        pmove   0x400c,tc
        move.w  0xd000,(a4)+            | -> $1234
        move.w  0xc002,(a4)+            | -> $CA56 ($CAFE with byte 3 = $56)
        move.l  0xd008,(a4)+            | -> $89ABCDEF
        move.w  0x5100,(a4)+            | bus errors: 3
        move.l  0x5104,(a4)+            | $0000D000
        move.l  0x5108,(a4)+            | $0000E003
        move.l  0x510c,(a4)+            | $0000D008
        move.l  0x6134,(a4)+            | B[$D] -> $0000D019 (WP cleared, U + M by the rerun)
        move.l  #0x600dc0de,0x3300
5:      bra.s   5b
berr:   movem.l d0/a0,-(sp)
        move.w  0x5100,d0
        addq.w  #1,0x5100
        lea     0x5104,a0
        lsl.w   #2,d0
        move.l  8+0x10(sp),0(a0,d0.w)
        andi.l  #0xfffffffb,0x6134      | clear WP on B[$D] and B[$E] (descriptor memory is identity)
        andi.l  #0xfffffffb,0x6138
        pflusha
        movem.l (sp)+,d0/a0
        rte
