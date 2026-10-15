| TESTCR.PRG (Hatari test only): first run arms the CR snapshot and takes an
| address error; after a warm reset (CR# > 0) it runs A:\MEMSAVE.PRG instead.
        .equ H, 0x3E0000
start:  clr.l   -(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        tst.l   H+12
        bne     save
        move.l  #1,H+280
        move.l  #0x11111111,d1
        move.l  #0x55555,a0
        move.w  (a0),d0
        illegal
save:   move.l  d0,-(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        pea     env(pc)
        pea     env(pc)
        pea     nm(pc)
        clr.w   -(sp)
        move.w  #0x4b,-(sp)
        trap    #1
        lea     16(sp),sp
        clr.w   -(sp)
        trap    #1
env:    .long 0
nm:     .asciz "A:\\MEMSAVE.PRG"
        .even
