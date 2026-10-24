| BLITON.PRG - switch the STE blitter on (Blitmode(1)) if TOS reports one present; print the mode.
        .text
        move.w  #-1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        btst    #1,%d0
        beq.s   1f
        move.w  #1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14                     | Blitmode(1)
        addq.l  #4,%sp
1:      move.w  #-1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     hx(%pc),%a0
        moveq   #3,%d2
2:      rol.w   #4,%d0
        move.w  %d0,%d1
        and.w   #15,%d1
        move.b  hd(%pc,%d1.w),(%a0)+
        dbra    %d2,2b
        pea     msg(%pc)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        clr.w   -(%sp)
        trap    #1
hd:     .ascii  "0123456789ABCDEF"
msg:    .ascii  "BLITON: Blitmode(-1) = $"
hx:     .asciz  "0000\r\n"
