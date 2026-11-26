| BLI-11g: directed ST-RAM data-cache coherency test. Results go to (a5)+ at $3000.
| Compare the RAM write stream CIMODE=4 (RAM data uncached) vs CIMODE=5.
    .text
    .org 0
    .long 0x00010000
    .long 0x00E00010
    .org 0x10
    lea     0xE00100,%a0
    lea     0x10A14,%a1
    move.w  #(cend-cstart)/2-1,%d0
1:  move.w  (%a0)+,(%a1)+
    dbf     %d0,1b
    move.l  #0x3919,%d0
    movec   %d0,%cacr
    jmp     0x10A14
    .org 0x100
cstart:
    move.l  #1,0x400.w
    move.l  #0x10A14+(hirq-cstart),0x70.w
    move.w  #0x2000,%sr
    moveq   #2,%d4
OUT:
    lea     0x3000,%a5
    lea     0x2000,%a0
| T1 long write, long read (alloc), byte write hit, long read
    move.l  #0x11223344,(%a0)
    move.l  (%a0),%d0
    move.b  #0xAA,1(%a0)
    move.l  (%a0),%d1
    move.l  %d0,(%a5)+
    move.l  %d1,(%a5)+
| T2 word write hit at +2, then long, word, byte reads
    move.w  #0xBEEF,2(%a0)
    move.l  (%a0),(%a5)+
    move.w  2(%a0),(%a5)+
    move.b  3(%a0),(%a5)+
    move.b  0(%a0),(%a5)+
| T3 cache two entries, misaligned long write across them, read back
    move.l  #0x55667788,4(%a0)
    move.l  #0x99AABBCC,8(%a0)
    move.l  4(%a0),%d0
    move.l  8(%a0),%d1
    move.l  #0xDEADF00D,6(%a0)
    move.l  4(%a0),(%a5)+
    move.l  8(%a0),(%a5)+
    move.l  6(%a0),(%a5)+
| T4 word read at +$12 (fill), byte write +$13, word and long reads
    move.l  #0x01020304,0x10(%a0)
    move.w  0x12(%a0),%d0
    move.b  #0x77,0x13(%a0)
    move.w  0x12(%a0),(%a5)+
    move.l  0x10(%a0),(%a5)+
| T5 RMW ALU ops on cached memory
    move.l  #0,0x20(%a0)
    move.l  0x20(%a0),%d0
    moveq   #9,%d2
5:  addq.l  #1,0x20(%a0)
    addq.w  #3,0x22(%a0)
    eori.b  #0x5A,0x21(%a0)
    dbf     %d2,5b
    move.l  0x20(%a0),(%a5)+
| T6 RAM->RAM copy (a1)+,(a2)+ with cached source, overlapping by 2
    lea     0x40(%a0),%a1
    moveq   #7,%d2
    move.l  #0x10203040,%d0
6:  move.l  %d0,(%a1)+
    addi.l  #0x01010101,%d0
    dbf     %d2,6b
    lea     0x40(%a0),%a1
    moveq   #7,%d2
61: move.l  (%a1)+,%d0
    dbf     %d2,61b
    lea     0x40(%a0),%a1
    lea     0x42(%a0),%a2
    moveq   #6,%d2
62: move.l  (%a1)+,(%a2)+
    dbf     %d2,62b
    lea     0x40(%a0),%a1
    moveq   #7,%d2
63: move.l  (%a1)+,(%a5)+
    dbf     %d2,63b
| T7 movem to RAM, movem from RAM, single reads
    movem.l %d0-%d7,0x80(%a0)
    move.l  #0xCAFEBABE,0x84(%a0)
    movem.l 0x80(%a0),%d0-%d7
    movem.l %d0-%d7,(%a5)
    lea     32(%a5),%a5
    move.w  #0x1234,0x8A(%a0)
    movem.l 0x80(%a0),%d0-%d3
    movem.l %d0-%d3,(%a5)
    lea     16(%a5),%a5
| T8 stack: bsr/rts, pea, -(sp)/(sp)+ under cached stack
    moveq   #20,%d2
8:  pea     0x12345678
    move.l  %d2,-(%sp)
    bsr.s   81f
    move.l  (%sp)+,%d0
    move.l  (%sp)+,%d1
    add.l   %d0,%d7
    add.l   %d1,%d7
    dbf     %d2,8b
    move.l  %d7,(%a5)+
    bra.s   82f
81: move.l  4(%sp),%d3
    addq.l  #1,4(%sp)
    rts
82:
| T9 TAS on cached byte
    move.b  #0x05,0x30(%a0)
    move.b  0x30(%a0),%d0
    tas     0x30(%a0)
    move.b  0x30(%a0),(%a5)+
    move.b  0x31(%a0),(%a5)+
| T10 misaligned reads after word/byte writes
    move.l  #0xA1B2C3D4,0x34(%a0)
    move.l  #0xE5F60718,0x38(%a0)
    move.l  0x34(%a0),%d0
    move.l  0x38(%a0),%d0
    move.b  #0x99,0x37(%a0)
    move.w  #0x8877,0x38(%a0)
    move.w  0x37(%a0),(%a5)+
    move.l  0x35(%a0),(%a5)+
    move.l  0x36(%a0),(%a5)+
| T11 memory-test style: stride write pattern then compare
    lea     0x4000,%a1
    move.w  #63,%d2
    move.l  #0x0F0F0F0F,%d0
11: move.l  %d0,(%a1)
    move.l  (%a1),%d1
    not.l   %d0
    move.l  %d0,(%a1)
    move.l  (%a1)+,%d3
    eor.l   %d3,%d1
    add.l   %d1,%d6
    dbf     %d2,11b
    move.l  %d6,(%a5)+
| T12 byte writes walk, word read back
    lea     0x4200,%a1
    moveq   #15,%d2
    move.l  (%a1),%d0
12: move.b  %d2,(%a1)+
    dbf     %d2,12b
    lea     0x4200,%a1
    moveq   #7,%d2
121: move.w (%a1)+,(%a5)+
    dbf     %d2,121b
    dbf     %d4,OUT
    move.w  #0x2700,%sr
    move.l  #2,0x404.w
2:  bra.s   2b
hirq: movem.l %d0-%d1/%a0,-(%sp)
    move.l  0x2000.w,%d0
    move.w  0x2042.w,%d1
    addq.l  #1,0x500.w
    move.l  0x4000.w,%d0
    movem.l (%sp)+,%d0-%d1/%a0
    rte
cend:
