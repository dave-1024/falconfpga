| TTRAM cache coherence bench (TTC.PRG on the board crashed): stack in TT-RAM, D-cache write-hit
| tests (14 op shapes) on TT vs ST reference, 4 CACR configs, I-cache CI. Results $1300.., done $1FFC.
        .text
        .long   0x0100F000
        .long   start
start:  move.w  #0x2700,%sr
        move.b  #0x0a,0xffff8001.w
        lea     0x1300,%a5
        move.l  #0x3111,%d0
        bsr     dtest
        move.l  %d1,0(%a5)
        move.l  %d2,4(%a5)
        move.l  %d3,8(%a5)
        move.l  #0x0111,%d0
        bsr     dtest
        move.l  %d1,12(%a5)
        move.l  %d2,16(%a5)
        move.l  #0x0101,%d0
        bsr     dtest
        move.l  %d1,24(%a5)
        move.l  %d2,28(%a5)
        move.l  #0x0011,%d0
        bsr     dtest
        move.l  %d1,32(%a5)
        bsr     itest
        move.l  #0x0808,%d0
        movec   %d0,%cacr
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
| dtest: d0 = CACR. Runs op list on TT buf (cached) and ST ref; d1 = mismatch count (cached read),
| d3 = mismatches after flushing D cache (memory), d2 = first mismatch (op<<8|byte)
dtest:  or.l    #0x0800,%d0     | CD: clear D cache too
        movec   %d0,%cacr
        moveq   #0,%d1
        moveq   #0,%d3
        moveq   #-1,%d2
        moveq   #0,%d6          | op index
dt_op:  lea     0x01001000,%a0
        move.l  %a0,%d4
        add.l   #15,%d4
        and.w   #0xfff0,%d4
        move.l  %d4,%a0         | TT buf, 16-aligned (32 bytes)
        lea     0x10000,%a1
| fill both with pattern
        moveq   #7,%d5
        move.l  #0x11223344,%d4
2:      move.l  %d4,(%a0)+
        move.l  %d4,(%a1)+
        add.l   #0x01010101,%d4
        dbra    %d5,2b
        lea     -32(%a0),%a0
        lea     -32(%a1),%a1
| load TT lines into the D cache: read every long
        moveq   #7,%d5
3:      move.l  (%a0)+,%d4
        dbra    %d5,3b
        lea     -32(%a0),%a0
| do op d6 on both
        move.l  %a0,%a2
        bsr     doop
        move.l  %a1,%a2
        bsr     doop
| compare bytes (cached read)
        moveq   #31,%d5
4:      move.b  (%a0,%d5.w),%d4
        cmp.b   (%a1,%d5.w),%d4
        beq.s   5f
        addq.l  #1,%d1
        tst.l   %d2
        bpl.s   5f
        move.l  %d6,%d2
        lsl.l   #8,%d2
        move.b  %d5,%d2
5:      dbra    %d5,4b
| flush D (CD), compare memory
        movec   %cacr,%d4
        or.w    #0x0800,%d4
        movec   %d4,%cacr
        moveq   #31,%d5
6:      move.b  (%a0,%d5.w),%d4
        cmp.b   (%a1,%d5.w),%d4
        beq.s   7f
        addq.l  #1,%d3
7:      dbra    %d5,6b
        addq.l  #1,%d6
        cmp.l   #NOPS,%d6
        bne     dt_op
        rts

        .equ NOPS,14
| doop: op d6 on buffer a2
doop:   move.l  #0xA5B6C7D8,%d4
        move.w  %d6,%d5
        add.w   %d5,%d5
        move.w  optab(%pc,%d5.w),%d5
        jmp     optab(%pc,%d5.w)
optab:  .word   o0-optab,o1-optab,o2-optab,o3-optab,o4-optab,o5-optab,o6-optab
        .word   o7-optab,o8-optab,o9-optab,o10-optab,o11-optab,o12-optab,o13-optab
o0:     move.b  %d4,5(%a2)
        rts
o1:     move.w  %d4,6(%a2)
        rts
o2:     move.l  %d4,8(%a2)
        rts
o3:     move.l  %d4,9(%a2)
        rts
o4:     move.l  %d4,14(%a2)     | crosses line A4? 14..17 crosses 16
        rts
o5:     move.w  %d4,15(%a2)
        rts
o6:     move.l  %d4,3(%a2)
        rts
o7:     movem.l %d4/%d5/%d6,4(%a2)
        move.l  #0xA5B6C7D8,%d4
        rts
o8:     clr.l   12(%a2)
        rts
o9:     addq.l  #1,0(%a2)
        rts
o10:    move.b  %d4,(%a2)
        move.b  %d4,1(%a2)
        move.b  %d4,2(%a2)
        move.b  %d4,3(%a2)
        rts
o11:    move.l  %d4,30(%a2)     | crosses into the next 16-byte line beyond buf 32? stays in 34 -> keep in buffer: use 28
        rts
o12:    eor.w   %d4,20(%a2)
        rts
o13:    move.w  %d4,(%a2)
        move.l  %d4,2(%a2)
        move.b  %d4,6(%a2)
        rts

| itest: copy code1 to TT xbuf, run, copy code2, flush with CI, run; then copy code1, no flush, run
itest:  move.l  #0x3111,%d0
        or.w    #0x0808,%d0
        movec   %d0,%cacr
        lea     0x01002000,%a3
        lea     code1(%pc),%a0
        bsr     cpcode
        jsr     (%a3)
        lea     code2(%pc),%a0
        bsr     cpcode
        movec   %cacr,%d0
        or.w    #0x0008,%d0
        movec   %d0,%cacr
        jsr     (%a3)
        move.l  %d0,40(%a5)
        lea     code1(%pc),%a0
        bsr     cpcode
        jsr     (%a3)
        move.l  %d0,44(%a5)
        rts
cpcode: move.l  (%a0)+,(%a3)
        move.l  (%a0)+,4(%a3)
        rts
code1:  moveq   #1,%d0
        rts
        nop
        nop
code2:  moveq   #2,%d0
        rts
        nop
        nop

