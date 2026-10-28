| [MINT sim] hdv_rw replacement at $3FFD00: floppy sectors from the tb030 disk window at $C00000 (no FDC model).
| hdv_rw(rw.w 4(sp), buf.l 6(sp), count.w 10(sp), recno.w 12(sp), dev.w 14(sp)) -> d0 = 0
        .text
start:  movem.l %d1-%d2/%a0-%a1,-(%sp)
        move.w  16+12(%sp),%d0
        andi.l  #0xffff,%d0
        mulu.l  #512,%d0
        movea.l #0xC00000,%a0
        adda.l  %d0,%a0
        movea.l 16+6(%sp),%a1
        move.w  16+10(%sp),%d1
        andi.l  #0xffff,%d1
        mulu.l  #512,%d1
        btst    #0,16+5(%sp)
        beq.s   2f
        exg     %a0,%a1
2:      subq.l  #1,%d1
        bmi.s   3f
1:      move.b  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bpl.s   1b
3:      movem.l (%sp)+,%d1-%d2/%a0-%a1
        moveq   #0,%d0
        rts
        .globl _start
_start = start
