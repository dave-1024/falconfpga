        .text
start:  move.w  #0x2300,%sr
        move.l  #0x00099518,%a0
        move.l  %a0,%usp
        move.l  #0x1111,%d0
        movec   %d0,%cacr
        move.l  #0x00000000,%d0
        move.l  #0x00000003,%d1
        move.l  #0x0005E77E,%d2
        move.l  #0x00035EA4,%d3
        moveq   #0,%d4
        moveq   #0,%d5
        moveq   #0,%d6
        moveq   #0,%d7
        move.l  #0x0009953A,%a0
        move.l  #0x00035EA4,%a1
        move.l  #0x0009953E,%a2
        move.l  #0x0009953A,%a3
        move.l  #0x0002D7E4,%a4
        move.l  #0x0002D856,%a5
        move.l  #0x00035A6C,%a6
        move.l  #0x0009950E,%sp
        jsr     (%a1)
        move.l  %d0,0x3404
        move.l  %d0,0x3400
9:      bra.s   9b
