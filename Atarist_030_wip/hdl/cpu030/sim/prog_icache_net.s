| [IC] gate-level cache check through cpu030_st_bridge: the bridge's CIIN decode makes $01xxxxxx cachable
| (it aliases the ST space on tb_bridge). Markers at $3600; fetches of the loop line counted from the trace.
        .text
        .org 0
        .long   0x00007000
        .long   0x00fc0008
start:  moveq   #9,d0                  | CI | EI
        movec   d0,cacr
        move.w  #1,0x3600               | 1: cold, via $01FC1000 (cachable): fills
        jsr     0x01fc1000
        move.w  #2,0x3600               | 2: warm: no fetches
        jsr     0x01fc1000
        move.w  #3,0x3600               | 3: same code via $00FC1000 (ST side, CIIN asserted): no hits (other tag), no fills
        jsr     0x00fc1000
        move.w  #4,0x3600               | 4: $01FC1000 again: still hits (CIIN on other cycles never disables the cache)
        jsr     0x01fc1000
        moveq   #0,d0
        movec   d0,cacr
        move.w  #5,0x3600               | 5: EI off: fetches
        jsr     0x01fc1000
        move.w  #6,0x3600
        move.l  #0x600dc0de,0x3300
1:      bra.s   1b
        .org    0x1000
lp:     moveq   #8,d1
2:      subq.l  #1,d1
        bne.s   2b
        rts
