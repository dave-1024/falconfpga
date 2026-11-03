| [PMMU2b] Address translation (MC68030UM 9.4, 9.5): ATC, table search, U/M updates, faults.
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
        move.l  #irqh,0x70
        move.l  #irqh,0x78
        move.l  #irqh,0x64
        move.l  #irqh,0x68
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
        pmove   0x4000,crp
        move.l  #0x80c84800,0x4008
        pmove   0x4008,tc               | translation on (flushes the ATC)
        lea     0x7000,a0
        move.l  a0,usp
        clr.l   0x5100
        pmove   0x400c,tc
        move.l  #1,0x9000
        move.l  #2,0x9004
        clr.l   0x9008
        move.l  #0xabcd1234,0x703c
        clr.l   0x612c                | B[$B] invalid
        pmove   0x4008,tc
        move.w  #0,-(sp)
        pea     ucode
        move.w  #0x0000,-(sp)
        rte
ucode:  lea     0xb000,a5
        move.l  #0x55555555,-(sp)
        move.l  sp,d7
        .word   0x2f35,0x0170,0x0000,0x000c
        move.l  d7,0x5090
        move.l  sp,0x5094
        move.l  (sp),0x5098
        move.l  4(sp),0x509c
        move.l  #0x600dc0de,0x3300
2:      bra.s   2b
berr:   move.w  10(sp),d0
        move.w  d0,(a4)+          | SSW
        move.w  6(sp),(a4)+       | format
        move.l  2(sp),(a4)+       | PC
        move.l  16(sp),(a4)+      | daddr
        addq.l  #1,0x5100
        cmp.l   #6,0x5100
        bcc.s   9f
        move.l  16(sp),d0
        and.l   #0xf000,d0
        cmp.l   #0xb000,d0
        bne.s   5f
        move.l  #0x0000b001,0x612c
        move.l  #0x11112222,0xb00c
        bra.s   6f
5:      move.l  #0x0000d001,0x6134
6:
        pflusha
        rte
9:      move.l  #0xdeaddead,0x3300
        bra.s   9b
irqh:   addq.l  #1,0x5104
        rte
