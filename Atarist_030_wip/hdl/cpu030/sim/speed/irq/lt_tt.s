| [F155] LOOPTEST-like bench for tb030: the Linux __delay loop (subq.l #1,d0 ; bcc.s) copied into
| the cacheable 32-bit TT port ($01000000, 2 clocks + WS per cycle) and run with caches off, I on, I+D on,
| under periodic level 4 / level 6 interrupts (IPL_MODE=3), as LOOPTEST.PRG does on the board.
| Results: $3300 = $600DC0DE after all three passes, $3304.. = d0 after each pass (expect $FFFFFFFF),
|          $3200 level-4 count, $3204 level-6 count ("_hz_200"). TIMEOUT without DONE = hang.
        .org 0
        dc.l    0x2000, start
start:  move.w  #0x2700,%sr
        lea     0x1f00,%sp
        lea     h4(%pc),%a0
        move.l  %a0,0x70
        lea     h6(%pc),%a0
        move.l  %a0,0x78
        clr.l   0x3200
        clr.l   0x3204
        move.l  #0x01000000+LOFS,%a3
        lea     loop(%pc),%a0
        move.l  %a3,%a2
        moveq   #(loopend-loop)/2-1,%d1
cp:     move.w  (%a0)+,(%a2)+
        dbf     %d1,cp
        lea     0x3304,%a5
        move.w  #0x2000,%sr
        move.l  #0x0808,%d4
        bsr.s   one
        move.l  #0x0809,%d4
        bsr.s   one
        move.l  #0x0909,%d4
        bsr.s   one
        move.l  #0x0809,%d4
        bsr.s   one
        move.w  #0x2700,%sr
        move.l  #0x600dc0de,0x3300
1:      bra.s   1b
one:    movec   %d4,%cacr
        move.l  0x3204,%d1
w1:     cmp.l   0x3204,%d1
        beq.s   w1
        move.l  0x3204,%d2
        move.l  #NLOOP,%d0
        jsr     (%a3)
        move.l  %d0,(%a5)+
        move.l  0x3204,%d3
        sub.l   %d2,%d3
        move.l  %d3,(%a5)+
        rts
        .balign 4
loop:   subq.l  #1,%d0
        bcc.s   loop
        rts
        nop
loopend:
h4:     movem.l %d0-%d1/%a0,-(%sp)
        addq.l  #1,0x3200
        move.l  14(%sp),%d1
        lea     0x3400-0x20,%a0
        move.l  %d1,(%a0)
        movem.l (%sp)+,%d0-%d1/%a0
        rte
h6:     addq.l  #1,0x3204
        rte
