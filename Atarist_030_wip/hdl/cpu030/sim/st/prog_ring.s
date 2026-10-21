| prog_ring: TT_RING smoke test. Arm, 3 TT accesses, a BERR at $02000000, dump ring entries 0..6 to $1300.
        .text
        .long   0x0100FFF0
        .long   start
start:  move.w  #0x2700,%sr
        lea     berr(%pc),%a0
        move.l  %a0,8.w
        clr.l   0x7E000000
        move.l  #0x11223344,0x01002000
        move.l  0x01002000,%d0
        move.w  #0x5566,0x01002006
        tst.l   0x02000000
        bra.s   .
berr:   lea     0x7E000000,%a0
        lea     0x1300.w,%a1
        moveq   #6,%d1
1:      move.l  (%a0),(%a1)+
        move.l  4(%a0),(%a1)+
        move.l  8(%a0),(%a1)+
        move.l  12(%a0),(%a1)+
        lea     16(%a0),%a0
        dbra    %d1,1b
        move.l  #0xbadbad00,0x1ffc.w
        bra.s   .
