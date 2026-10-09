| EmuTOS FD3C9E sequence (movem / move sr,d0 / move #$2700,sr / movea.l abs / ...)
        .text
        .org 0
        .long   0x00008000
        .long   0x00fc0008
start:
        move.l  #h4,0x70
        move.l  #h2,0x68
        move.l  #0x00004000,0x20ca
        move.l  #0x11223344,0x2084
        move.l  #0x55667788,0x400e
        move.w  #0x2300,sr
        move.b  #1,0x3400               | bench: raise level 4 after this
        bsr     rout
        move.l  #0x600dc0de,0x3300      | done marker
self:   bra.s   self
rout:   movem.l d2/a2-a3,-(sp)
        move.w  sr,d0
        move.w  #0x2700,sr
        movea.l 0x20ca,a0
        move.l  0x2084,18(a0)
        move.l  14(a0),0x2084
        move.w  sr,d1
        move.w  d0,sr
        movem.l (sp)+,d2/a2-a3
        rts
h4:     move.b  #1,0x3201
        rte
h2:     move.b  #1,0x3202
        rte
