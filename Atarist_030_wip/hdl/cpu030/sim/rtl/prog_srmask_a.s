| SR mask test A: level 4 raised around move #$2700,sr (bench raises it after the $3400 write)
        .text
        .org 0
        .long   0x00008000              | SSP
        .long   0x00fc0008              | PC
start:
        move.l  #h4,0x70                | level 4 autovector
        move.l  #h2,0x68                | level 2 autovector
        move.w  #0x2300,sr
        move.w  sr,d0
        move.b  #1,0x3400               | bench: raise level 4 after this
        move.w  #0x2700,sr
        nop
        move.l  #0x600dc0de,0x3300      | done marker
        jsr     0x00fc772e
        move.l  #0x0000b0b0,0x3308
self:   bra.s   self
h4:     move.b  #1,0x3201
        rte
h2:     move.b  #1,0x3202
        rte
        .org 0x772e
far:    move.l  #0x0000faaa,0x3304
        rts
