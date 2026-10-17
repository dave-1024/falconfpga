| [DC] gate-level data cache check through cpu030_st_bridge (DCACHE_DESIGN.md §5): the bridge's CIIN decode makes
| $01xxxxxx cachable (it aliases the ST space on tb_bridge). Case markers at $3600, results at $3700; data reads and
| writes of $8000-$80FF counted per case from the trace.
        .text
        .org 0
        .long   0x00007000
        .long   0x00fc0008
start:  lea     0x3700,a4
        moveq   #0,d1
        move.l  #0x00008000,0x8000
        move.l  #0x00008010,0x8010
        move.l  #0x900,d0               | CD | ED
        movec   d0,cacr
        move.w  #1,0x3600               | 1: cachable long: one fill (two words), then hits
        move.l  0x01008000,d0
        move.l  0x01008000,d0
        move.l  0x01008000,d0
        move.w  #2,0x3600               | 2: cachable byte at $8013: the byte cycle, a fill cycle at $8010, then hits
        move.b  0x01008013,d1
        move.b  0x01008013,d1
        move.w  #3,0x3600               | 3: the ST address (CIIN asserted, other tag): no hits, no fills
        move.l  0x00008000,d2
        move.l  0x00008000,d2
        move.w  #4,0x3600               | 4: the cachable address again: still hits
        move.l  0x01008000,d0
        move.w  #5,0x3600               | 5: write-through: a write hit goes to the bus and updates the entry
        move.w  #0xbeef,0x01008002
        move.l  0x01008000,d3
        move.l  #0x2100,d0              | WA | ED
        movec   d0,cacr
        move.w  #6,0x3600               | 6: WA: an aligned long write to the ST address allocates (CIIN is ignored
        move.l  #0x12345678,0x00008040  |    on writes, MC68030UM 6.1.2.1); the read hits
        move.l  0x00008040,d4
        moveq   #0,d0
        movec   d0,cacr
        move.w  #7,0x3600               | 7: ED off: bus reads
        move.l  0x01008000,d0
        move.l  d1,(a4)+
        move.l  d3,(a4)+
        move.l  d4,(a4)+
        move.w  #8,0x3600
        move.l  #0x600dc0de,0x3300
1:      bra.s   1b
