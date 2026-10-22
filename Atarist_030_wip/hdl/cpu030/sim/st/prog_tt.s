| TTRAM bench ROM (E00000) for tb_bus.v with `define TTRAM (run_tt.sh).
| Same store/load sequence (long, word, byte, misaligned long/word) on TT-RAM ($01000000) and
| ST-RAM ($10000); every long compared; code copied to TT-RAM and run with I/D caches on.
| Results: $1300 mismatches, $1304/$1308 TT/ST long sums, $130C/$1310 TT/ST misaligned sums,
|          $1314/$1318 TT code result (2 calls, 0x1356 each), $131C bus errors (expect 1 = $02000000),
|          $1320 cached TT re-read == first read (1), $1324 word/byte sum TT, $1328 same ST,
|          $132C tagged program fetch $03E0xxxx (1 = ST wrap, $BAD = BERR) [T10].
        .text
        .long   0x00008000
        .long   start
start:  move.w  #0x2700,%sr
        lea     0x8000,%sp
        move.b  #0x0a,0xffff8001.w
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        clr.l   0x131c.w
        lea     0x01000000,%a2
        bsr     pat
        lea     0x10000,%a2
        bsr     pat
| compare 80 longs
        lea     0x01000000,%a0
        lea     0x10000,%a1
        moveq   #0,%d7
        moveq   #0,%d5
        moveq   #0,%d6
        move.w  #79,%d4
1:      move.l  (%a0)+,%d0
        move.l  (%a1)+,%d1
        add.l   %d0,%d5
        add.l   %d1,%d6
        cmp.l   %d0,%d1
        beq.s   2f
        addq.l  #1,%d7
2:      dbra    %d4,1b
        move.l  %d7,0x1300.w
        move.l  %d5,0x1304.w
        move.l  %d6,0x1308.w
| misaligned long and word reads, byte reads
        lea     0x01000000,%a2
        bsr     rd
        move.l  %d5,0x130c.w
        move.l  %d6,0x1324.w
        lea     0x10000,%a2
        bsr     rd
        move.l  %d5,0x1310.w
        move.l  %d6,0x1328.w
| copy tcode to TT-RAM, caches on, run twice
        lea     tcode(%pc),%a0
        lea     0x01002000,%a1
        move.w  #(tend-tcode)/2-1,%d4
3:      move.w  (%a0)+,(%a1)+
        dbra    %d4,3b
        move.l  #0x0909,%d0             | EI|CI|ED|CD: enable + clear both caches
        movec   %d0,%cacr
        jsr     0x01002000
        move.l  %d0,0x1314.w
        jsr     0x01002000
        move.l  %d0,0x1318.w
| cached data re-read
        move.l  0x01000000,%d0
        move.l  0x01000000,%d1
        moveq   #0,%d2
        cmp.l   %d0,%d1
        bne.s   4f
        moveq   #1,%d2
4:      move.l  %d2,0x1320.w
        moveq   #0,%d0
        movec   %d0,%cacr
| bus error above TT-RAM
        move.l  %sp,%a5
        tst.b   0x02000000
after_berr:
        move.l  %a5,%sp
| [T10] program fetch through a tagged 68000-style pointer ($03E0xxxx, as TOS 2.06's bomb vectors):
| must take the ST side (24-bit wrap), not bus-error. $132C = 1 ok, $0BAD = BERR.
        lea     berr2(%pc),%a0
        move.l  %a0,0x8.w
        lea     tagok(%pc),%a0
        add.l   #0x03000000,%a0
        jmp     (%a0)
tagok:  move.l  #1,0x132c.w
tagdone:
        move.l  %a5,%sp
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
berr2:  move.l  #0xbad,0x132c.w
        jmp     tagdone
berr:   addq.l  #1,0x131c.w
        move.l  %a5,%sp
        jmp     after_berr
| store pattern at (a2)
pat:    move.l  #0x11223344,(%a2)
        move.w  #0x5566,4(%a2)
        move.w  #0x7788,6(%a2)
        move.b  #0x99,8(%a2)
        move.b  #0xaa,9(%a2)
        move.b  #0xbb,10(%a2)
        move.b  #0xcc,11(%a2)
        move.l  #0xdeadbeef,13(%a2)     | misaligned long (A1:0 = 01)
        move.l  #0xcafef00d,18(%a2)     | misaligned long (A1:0 = 10)
        move.w  #0x1357,23(%a2)         | odd word
        move.l  #0x0badf00d,27(%a2)     | A1:0 = 11
        lea     32(%a2),%a3
        move.l  #0x12345678,%d1
        move.w  #63,%d4
5:      move.l  %d1,(%a3)+
        rol.l   #3,%d1
        add.l   #0x01020305,%d1
        dbra    %d4,5b
        rts
| misaligned long sum -> d5, word/byte sum -> d6
rd:     moveq   #0,%d5
        moveq   #0,%d6
        lea     1(%a2),%a3
        move.w  #39,%d4
6:      add.l   (%a3),%d5
        add.w   1(%a3),%d6
        add.b   2(%a3),%d6
        rol.l   #1,%d5
        addq.l  #7,%a3
        dbra    %d4,6b
        rts
| position-independent code run from TT-RAM: sum 0..99 -> d0
tcode:  moveq   #0,%d0
        move.w  #99,%d1
7:      add.l   %d1,%d0
        dbra    %d1,7b
        rts
tend:
