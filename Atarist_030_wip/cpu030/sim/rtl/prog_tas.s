| F64: TOS 2.06 AES semaphore (E21DEA: tas.b $CC00; beq; tst.w $59E.w; ...) as run when a menu
| title is touched. TAS (RMC) at 4n and 4n+2, abs.l and (An) forms, followed by stack frame code.
| Results at $5000..; DONE at $3300.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        lea     0x5000,a4
        move.l  #errh,0x08
        move.l  #errh,0x0c
        move.l  #errh,0x10
        move.l  #errh,0x2c
        move.l  #errh,0x28
        move.w  #1,0x059e
        moveq   #5,d6
loop:   clr.b   0x4c00
        jsr     sem_e
        move.l  d0,(a4)+
        jsr     sem_e
        move.l  d0,(a4)+
        clr.b   0x4c00
        jsr     sem_o
        move.l  d0,(a4)+
        lea     0x4c00,a0
        tas     (a0)
        sne     d1
        tas     (a0)
        sne     d2
        move.b  d1,(a4)+
        move.b  d2,(a4)+
        move.b  0x4c00,(a4)+
        addq.l  #1,a4
        dbra    d6,loop
        move.l  #0x600dc0de,0x3300
self:   bra.s   self
        .balignw 4,0x4e71
        nop
sem_e:  tas.b   0x4c00
        beq.b   1f
        moveq   #-1,d0
        bra.s   2f
1:      moveq   #1,d0
2:      tst.w   0x059e.w
        beq.b   3f
        subq.w  #2,sp
        move.l  2(sp),(sp)
        clr.w   4(sp)
        move.w  sr,-(sp)
        move.w  sr,0x6eda
        addq.l  #2,sp
        move.l  (sp),2(sp)
        addq.l  #2,sp
3:      rts
        .balignw 4,0x4e71
sem_o:  tas.b   0x4c00
        sne     d0
        ext.w   d0
        ext.l   d0
        rts
errh:   move.l  #0xeeee0000,(a4)+
        move.l  2(sp),(a4)+
        move.w  (sp),(a4)+
        move.l  #0x600dc0de,0x3300
        bra.s   errh
