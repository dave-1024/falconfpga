| F64: TOS 2.06 VDI line/fill inner loop (E0E85C-E0E91C): a 2-plane code fragment
| "or.w d1,(a5)+ / or.w d1,(a5)+ / jmp (a3)" is generated ON THE SUPERVISOR STACK
| (lea -20(sp),sp; movea.l sp,a2; move.w dN,(a0)+) and entered with jmp (a2) for each
| row, with periodic level 4/6 interrupts (tb030 IPL_MODE=3) pushing frames just below
| the fragment. The fragment opcode changes between passes (or/eor/and), the stack
| alternates between 4n and 4n+2. Checksum of the buffer at $5000; DONE at $3300.
        .text
        .org 0
        .long   0x00009e40
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #vblh,0x70
        move.l  #mfph,0x78
        move.l  #errh,0x08
        move.l  #errh,0x0c
        move.l  #errh,0x10
        move.l  #errh,0x2c
        move.l  #errh,0x28
        lea     0x6000,a0
        move.w  #511,d0
1:      clr.w   (a0)+
        dbra    d0,1b
        moveq   #0,d6                   | pass counter
        move.w  #0x2300,sr
pass:   move.w  d6,d0
        and.w   #3,d0
        add.w   d0,d0
        move.w  opt(pc,d0.w),d1         | fragment opcode for this pass
        btst    #2,d6
        beq.s   2f
        subq.l  #2,sp                   | fragment at 4n+2 on odd passes
2:      lea     -20(sp),sp
        movea.l sp,a2
        movea.l a2,a0
        move.w  d1,(a0)+                | plane 0
        move.w  d1,(a0)+                | plane 1
        move.w  #0x4ed3,(a0)+           | jmp (a3)
        lea     back(pc),a3
        lea     0x6000,a5
        move.w  d6,d1
        mulu.w  #0x1357,d1
        move.w  #0x9b6d,d2
        rol.w   d6,d2
        movea.w #4,a1
        moveq   #23,d7
row:    rol.w   #1,d2
        bcc.b   skip
        jmp     (a2)
back:   adda.w  a1,a5
        dbf     d7,row
        bra.s   3f
skip:   addq.l  #4,a5
        adda.w  a1,a5
        dbf     d7,row
3:      lea     20(sp),sp
        btst    #2,d6
        beq.s   4f
        addq.l  #2,sp
4:      addq.w  #1,d6
        cmp.w   #16,d6
        bne     pass
        lea     0x6000,a0
        moveq   #0,d0
        move.w  #511,d1
5:      add.w   (a0)+,d0
        rol.l   #1,d0
        dbra    d1,5b
        move.l  d0,(a4)+
        move.l  sp,(a4)+
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
opt:    .word   0x835d, 0xb35d, 0x835d, 0xc35d    | or.w, eor.w, or.w, and.w d1,(a5)+
        .balignw 4,0x4e71
        nop
vblh:   addq.l  #1,0x5100
        movem.l d0-d2/a0,-(sp)
        move.l  0x5100,d0
        moveq   #7,d1
6:      add.l   d0,d2
        dbra    d1,6b
        move.l  d2,0x5108
        movem.l (sp)+,d0-d2/a0
        rte
        .balignw 4,0x4e71
mfph:   addq.l  #1,0x5104
        move.w  #0x2500,sr
        nop
        rte
errh:   move.l  #0xeeee0000,(a4)+
        move.l  2(sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
