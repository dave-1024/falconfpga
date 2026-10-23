| [TOS206] TOS 2.06 IDE probe ($E01656): tst.b $FFF00039 under a BERR trap. $1100 = $00BE if BERR, $600D if not.
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        move.l  %sp,%a2
        clr.w   0x1100.w
        tst.b   0xfff00039
        move.w  #0x600d,0x1100.w
        bra.s   9f
berr:   move.l  %a2,%sp
        move.w  #0x00be,0x1100.w
9:      move.w  0x1100.w,0x1102.w
8:      bra.s   8b
