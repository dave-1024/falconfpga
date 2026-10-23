| CMPF.PRG: compare files A:\REF\<name> (clean copies) with B:\<path>, print size,
| diff byte count, first 12 diffs (offset a b). Also lists B:\ and B:\BIN.
        .text
start:  move.l  4(sp),a0
        lea     0x1000(a0),sp
        move.l  #0x1000,-(sp)
        move.l  a0,-(sp)
        clr.w   -(sp)
        move.w  #0x4a,-(sp)
        trap    #1
        lea     12(sp),sp
        lea     t_hi(pc),a0
        bsr     puts
        lea     d_b(pc),a0
        bsr     dir
        lea     d_bb(pc),a0
        bsr     dir
        lea     list(pc),a6
1:      tst.b   (a6)
        beq     9f
        move.l  a6,a0               | A name
2:      tst.b   (a6)+
        bne     2b
        move.l  a6,a1               | B name
3:      tst.b   (a6)+
        bne     3b
        bsr     cmpf
        bra     1b
9:      lea     t_key(pc),a0
        bsr     puts
        move.w  #7,-(sp)
        trap    #1
        addq.l  #2,sp
        clr.w   -(sp)
        trap    #1

| dir a0=pattern: print names and sizes
dir:    move.l  a0,-(sp)
        bsr     puts
        bsr     nl
        move.w  #0x2f,-(sp)         | Fgetdta
        trap    #1
        addq.l  #2,sp
        move.l  d0,a5
        move.l  (sp)+,a0
        move.w  #0x10,-(sp)
        move.l  a0,-(sp)
        move.w  #0x4e,-(sp)
        trap    #1
        addq.l  #8,sp
1:      tst.l   d0
        bmi     2f
        lea     30(a5),a0
        bsr     puts
        bsr     sp1
        move.l  26(a5),d0
        bsr     hex8
        lea     t_sep(pc),a0
        bsr     puts
        move.w  #0x4f,-(sp)
        trap    #1
        addq.l  #2,sp
        bra     1b
2:      bra     nl

| cmpf a0 = A name, a1 = B name
cmpf:   movem.l a0-a1,-(sp)
        bsr     nl
        move.l  4(sp),a0
        bsr     puts
        bsr     sp1
        move.l  (sp),a0
        bsr     load
        move.l  d0,d6               | size A
        move.l  a3,a4               | buf A
        move.l  4(sp),a0
        bsr     load
        move.l  d0,d7
        lea     t_sz(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     hex8
        bsr     sp1
        move.l  d7,d0
        bsr     hex8
        tst.l   d6
        bmi     8f
        tst.l   d7
        bmi     8f
        move.l  d6,d2
        cmp.l   d7,d2
        bls     1f
        move.l  d7,d2
1:      moveq   #0,d1
        moveq   #0,d3
2:      cmp.l   d2,d1
        bhs     5f
        move.b  (a4,d1.l),d0
        cmp.b   (a3,d1.l),d0
        beq     4f
        addq.l  #1,d3
        cmp.l   #12,d3
        bhi     4f
        movem.l d1-d3,-(sp)
        bsr     nl
        move.l  d1,d0
        bsr     hex8
        bsr     sp1
        move.b  (a4,d1.l),d0
        bsr     hex2
        bsr     sp1
        move.b  (a3,d1.l),d0
        bsr     hex2
        movem.l (sp)+,d1-d3
4:      addq.l  #1,d1
        bra     2b
5:      lea     t_nd(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     hex8
8:      move.l  a4,-(sp)            | free both
        move.w  #0x49,-(sp)
        trap    #1
        addq.l  #6,sp
        move.l  a3,-(sp)
        move.w  #0x49,-(sp)
        trap    #1
        addq.l  #6,sp
        movem.l (sp)+,a0-a1
        rts

| load a0 name -> a3 buffer (200 KB), d0 size or -1
load:   move.l  a0,-(sp)
        move.l  #200000,-(sp)
        move.w  #0x48,-(sp)
        trap    #1
        addq.l  #6,sp
        move.l  d0,a3
        move.l  (sp)+,a0
        clr.w   -(sp)
        move.l  a0,-(sp)
        move.w  #0x3d,-(sp)
        trap    #1
        addq.l  #8,sp
        tst.l   d0
        bmi     9f
        move.w  d0,d5
        move.l  a3,-(sp)
        move.l  #200000,-(sp)
        move.w  d5,-(sp)
        move.w  #0x3f,-(sp)
        trap    #1
        lea     12(sp),sp
        move.l  d0,d4
        move.w  d5,-(sp)
        move.w  #0x3e,-(sp)
        trap    #1
        addq.l  #4,sp
        move.l  d4,d0
        rts
9:      moveq   #-1,d0
        rts

nl:     lea     t_nl(pc),a0
puts:   movem.l d0-d2/a0-a2,-(sp)
        move.l  a0,-(sp)
        move.w  #9,-(sp)
        trap    #1
        addq.l  #6,sp
        movem.l (sp)+,d0-d2/a0-a2
        rts
sp1:    lea     t_sp(pc),a0
        bra     puts
hex2:   ror.l   #8,d0
        moveq   #1,d2
        bra     hx
hex8:   moveq   #7,d2
hx:     movem.l d0-d2/a0-a2,-(sp)
        move.l  d0,d1
1:      rol.l   #4,d1
        move.w  d1,d0
        and.w   #15,d0
        add.w   #0x30,d0
        cmp.w   #0x3a,d0
        blo     2f
        addq.w  #7,d0
2:      movem.l d1-d2,-(sp)
        move.w  d0,-(sp)
        move.w  #2,-(sp)
        trap    #1
        addq.l  #4,sp
        movem.l (sp)+,d1-d2
        dbf     d2,1b
        movem.l (sp)+,d0-d2/a0-a2
        rts

t_hi:   .asciz  "CMPF  A:\\REF (clean gb403) vs B:\r\n"
t_sz:   .asciz  " size "
t_nd:   .asciz  "\r\n  diff bytes $"
t_key:  .asciz  "\r\n-- key --"
t_nl:   .asciz  "\r\n"
t_sp:   .asciz  " "
t_sep:  .asciz  " | "
d_b:    .asciz  "B:\\*.*"
d_bb:   .asciz  "B:\\BIN\\*.*"
list:   .asciz  "A:\\REF\\GEMBENCH.PRG"
        .asciz  "B:\\GEMBENCH.PRG"
        .asciz  "A:\\REF\\GEMBENCH.RSC"
        .asciz  "B:\\GEMBENCH.RSC"
        .asciz  "A:\\REF\\AUTOFPU.BIN"
        .asciz  "B:\\BIN\\AUTOFPU.BIN"
        .asciz  "A:\\REF\\IEEE.BIN"
        .asciz  "B:\\BIN\\IEEE.BIN"
        .byte 0
        .even
