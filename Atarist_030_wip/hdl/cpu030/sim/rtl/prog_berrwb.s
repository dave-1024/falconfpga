| F66 test: a read that bus-errors must not write its destination register
| (MC68030: the destination keeps its old value). Each case loads a known value,
| reads $FFFA40 (BERR in tb030), the handler drops the frame and resumes at (a2).
| Results at $5000: register after each faulted read, then the BERR count.
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #berr,0x08
        lea     0x5000,a4
        movea.l sp,a6
        moveq   #0,d7
        move.l  #0x12345678,d0
        lea     1f(pc),a2
        move.w  0xfffa40,d0
1:      move.l  d0,(a4)+                | 12345678
        move.l  #0x11223344,d1
        lea     1f(pc),a2
        move.l  0xfffa40,d1
1:      move.l  d1,(a4)+                | 11223344
        move.l  #0x55667788,d2
        lea     1f(pc),a2
        move.b  0xfffa40,d2
1:      move.l  d2,(a4)+                | 55667788
        movea.l #0x0000abcd,a3
        lea     1f(pc),a2
        movea.w 0xfffa40,a3
1:      move.l  a3,(a4)+                | 0000abcd
        movea.l #0x00001234,a3
        lea     1f(pc),a2
        movea.l 0xfffa40,a3
1:      move.l  a3,(a4)+                | 00001234
        move.l  #0x00010001,d4
        lea     1f(pc),a2
        add.w   0xfffa40,d4
1:      move.l  d4,(a4)+                | 00010001
        move.l  #0x0badf00d,d5
        movea.l #0x00002222,a5
        lea     1f(pc),a2
        movem.l 0xfffa40,d5/a5
1:      move.l  d5,(a4)+                | 0badf00d
        move.l  a5,(a4)+                | 00002222
        movea.l #0x00fffa40,a0
        move.l  #0x0a0b0c0d,d6
        lea     1f(pc),a2
        move.w  (a0),d6
1:      move.l  d6,(a4)+                | 0a0b0c0d
        move.l  #0x77777777,d3
        lea     1f(pc),a2
        move.w  0xfffa40,d3
        moveq   #1,d3                   | must not run
1:      move.l  d3,(a4)+                | 77777777
        move.l  d7,(a4)+                | 9 bus errors
        move.w  #1,0x3300               | DONE
2:      bra.s   2b
berr:   addq.l  #1,d7
        movea.l a6,sp
        jmp     (a2)
