| prog_ttmb: TTM (board test) from TT-RAM with a trap #13 fake BIOS, stack at the TT top area
| TTM.PRG (prgflags 7): TT-RAM address-as-data test, code in TT, run with CACR 0x3919 (I+D on) then 0x0808 (off).
| Region $01400000, 256 KB. Tests: 1 long fill/readback, 2 long write+immediate read, 3 byte write+immediate read,
| 4 byte re-read, 5 all-alignment long reads (crossing 4/16-byte boundaries), 6 word reads at all alignments.
| Each prints: test, mismatches, first addr, expected, got. Bus/address error: vector, frame dump.
        .equ R,0x01008000
        .equ N,0x400
        .text
        .long   0x0100FFF0
        .long   start
start:  move.w  #0x2700,%sr
        lea     bios(%pc),%a0
        move.l  %a0,0xb4.w
        lea     tstart(%pc),%a0
        lea     0x01004000,%a1
        move.w  #(tend-tstart)/2,%d0
1:      move.w  (%a0)+,(%a1)+
        dbra    %d0,1b
        move.l  #0x01FFFFC6,%a6
        jmp     0x01004000
| fake BIOS Bconout: saves regs on the (TT) stack, writes the char to the ST log at 0x4000.., rte
bios:   movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.w  36(%sp),%d0
        move.l  0x3ff8,%a1
        cmp.l   #0x4000,%a1
        bcc.s   1f
        lea     0x4000,%a1
1:      move.b  %d0,(%a1)+
        move.l  %a1,0x3ff8
        lea     0x6000,%a0
        moveq   #15,%d1
2:      move.l  (%a0)+,%d2
        dbra    %d1,2b
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rte
tstart: bsr     main
        move.l  #0x600dc0de,0x1ffc.w
9:      bra.s   9b
main:   lea     savsp(%pc),%a0
        move.l  %sp,(%a0)
        move.l  8.w,4(%a0)
        move.l  12.w,8(%a0)
        lea     berrh(%pc),%a1
        move.l  %a1,8.w
        lea     aerrh(%pc),%a1
        move.l  %a1,12.w
        lea     hdr(%pc),%a0
        bsr     puts
        lea     sta(%pc),%a0
        bsr     puts
        move.w  %sr,-(%sp)
        move.w  #0x2700,%sr
        move.l  #0x3919,%d0
        bsr     suite
        move.w  (%sp)+,%sr
        lea     stb(%pc),%a0
        bsr     puts
        move.l  #0x0808,%d0
        bsr     suite
        move.l  #0x3919,%d0
        movec   %d0,%cacr
mexit:  lea     savsp(%pc),%a0
        move.l  4(%a0),8.w
        move.l  8(%a0),12.w
        rts

| results: d1 count, d2 first addr, d3 exp, d4 got
suite:  movec   %d0,%cacr
        movem.l %d0-%d7/%a0-%a6,-(%sp)
| T1 long fill + readback
        lea     R,%a0
        move.l  #N/4-1,%d7
1:      move.l  %a0,(%a0)+
        subq.l  #1,%d7
        bpl.s   1b
        bsr     clr
        lea     R,%a0
        move.l  #N/4-1,%d7
2:      move.l  (%a0),%d0
        cmp.l   %a0,%d0
        beq.s   3f
        move.l  %a0,%d5
        move.l  %a0,%d6
        bsr     mis
3:      addq.l  #4,%a0
        subq.l  #1,%d7
        bpl.s   2b
        moveq   #1,%d0
        bsr     rep
| T2 long write ~a, immediate read
        bsr     clr
        lea     R,%a0
        move.l  #N/4-1,%d7
1:      move.l  %a0,%d6
        not.l   %d6
        move.l  %d6,(%a0)
        move.l  (%a0),%d0
        cmp.l   %d6,%d0
        beq.s   3f
        move.l  %a0,%d5
        bsr     mis
3:      addq.l  #4,%a0
        subq.l  #1,%d7
        bpl.s   1b
        moveq   #2,%d0
        bsr     rep
| T3 byte write (a ^ $A5), immediate read
        bsr     clr
        lea     R,%a0
        move.l  #N-1,%d7
1:      move.l  %a0,%d6
        eor.b   #0xA5,%d6
        and.l   #0xff,%d6
        move.b  %d6,(%a0)
        moveq   #0,%d0
        move.b  (%a0),%d0
        cmp.l   %d6,%d0
        beq.s   3f
        move.l  %a0,%d5
        bsr     mis
3:      addq.l  #1,%a0
        subq.l  #1,%d7
        bpl.s   1b
        moveq   #3,%d0
        bsr     rep
| T4 byte re-read
        bsr     clr
        lea     R,%a0
        move.l  #N-1,%d7
1:      move.l  %a0,%d6
        eor.b   #0xA5,%d6
        and.l   #0xff,%d6
        moveq   #0,%d0
        move.b  (%a0),%d0
        cmp.l   %d6,%d0
        beq.s   3f
        move.l  %a0,%d5
        bsr     mis
3:      addq.l  #1,%a0
        subq.l  #1,%d7
        bpl.s   1b
        moveq   #4,%d0
        bsr     rep
| refill longs with address
        lea     R,%a0
        move.l  #N/4-1,%d7
1:      move.l  %a0,(%a0)+
        subq.l  #1,%d7
        bpl.s   1b
| T5 long read at every byte address (first 64 KB)
        bsr     clr
        lea     R,%a0
        move.l  #0x400-8,%d7
1:      move.l  %a0,%d5
        bsr     exl
        move.l  (%a0),%d0
        cmp.l   %d6,%d0
        beq.s   3f
        bsr     mis
3:      addq.l  #1,%a0
        subq.l  #1,%d7
        bpl.s   1b
        moveq   #5,%d0
        bsr     rep
| T6 word read at every byte address
        bsr     clr
        lea     R,%a0
        move.l  #0x400-8,%d7
1:      move.l  %a0,%d5
        bsr     exl
        swap    %d6
        and.l   #0xffff,%d6
        moveq   #0,%d0
        move.w  (%a0),%d0
        cmp.l   %d6,%d0
        beq.s   3f
        bsr     mis
3:      addq.l  #1,%a0
        subq.l  #1,%d7
        bpl.s   1b
        moveq   #6,%d0
        bsr     rep
        movem.l (%sp)+,%d0-%d7/%a0-%a6
        rts

| exl: d5 = byte address -> d6 = expected long at d5 (memory holds each long's own address)
exl:    movem.l %d0-%d2,-(%sp)
        moveq   #3,%d2
        moveq   #0,%d6
        move.l  %d5,%d0
1:      move.l  %d0,%d1
        and.w   #0xfffc,%d1
        move.l  %d0,-(%sp)
        and.w   #3,%d0
        lsl.w   #3,%d0
        lsl.l   %d0,%d1
        rol.l   #8,%d1
        lsl.l   #8,%d6
        move.b  %d1,%d6
        move.l  (%sp)+,%d0
        addq.l  #1,%d0
        dbra    %d2,1b
        movem.l (%sp)+,%d0-%d2
        rts
clr:    moveq   #0,%d1
        moveq   #-1,%d2
        rts
| mis: d5 addr, d6 exp, d0 got
mis:    addq.l  #1,%d1
        tst.l   %d2
        bpl.s   1f
        move.l  %d5,%d2
        move.l  %d6,%d3
        move.l  %d0,%d4
1:      rts
| rep: d0 test number
rep:    movem.l %d0-%d4,-(%sp)
        add.b   #'0',%d0
        lea     tn(%pc),%a1
        move.b  %d0,1(%a1)
        move.l  %a1,%a0
        bsr     puts
        move.l  4(%sp),%d0
        bsr     phex
        tst.l   4(%sp)
        beq.s   9f
        move.l  8(%sp),%d0
        bsr     phex
        move.l  12(%sp),%d0
        bsr     phex
        move.l  16(%sp),%d0
        bsr     phex
9:      lea     nl(%pc),%a0
        bsr     puts
        movem.l (%sp)+,%d0-%d4
        rts

berrh:  moveq   #2,%d0
        bra.s   ex
aerrh:  moveq   #3,%d0
ex:     move.l  %d0,0x1ff8.w
        move.l  (%sp),0x1340.w
        move.l  4(%sp),0x1344.w
        move.l  8(%sp),0x1348.w
        move.l  #0xbadbad00,0x1ffc.w
        move.l  #0x0808,%d1
        movec   %d1,%cacr
        move.l  %sp,%a6
        lea     exm(%pc),%a0
        add.b   #'0',%d0
        move.b  %d0,4(%a0)
        bsr     puts
        moveq   #11,%d5
1:      move.w  (%a6)+,%d0
        swap    %d0
        move.w  (%a6)+,%d0
        bsr     phex
        dbra    %d5,1b
        lea     nl(%pc),%a0
        bsr     puts
        lea     savsp(%pc),%a0
        move.l  (%a0),%sp
        bra     mexit

| console output via BIOS Bconout (safe in supervisor)
puts:   movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,%a2
1:      moveq   #0,%d0
        move.b  (%a2)+,%d0
        beq.s   2f
        move.w  %d0,-(%sp)
        move.w  #2,-(%sp)
        move.w  #3,-(%sp)
        trap    #13
        addq.l  #6,%sp
        bra.s   1b
2:      movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
phex:   movem.l %d0-%d2/%a0,-(%sp)
        lea     hb+8(%pc),%a0
        moveq   #7,%d2
8:      move.b  %d0,%d1
        and.b   #15,%d1
        add.b   #'0',%d1
        cmp.b   #'9',%d1
        bls.s   9f
        addq.b  #7,%d1
9:      move.b  %d1,-(%a0)
        lsr.l   #4,%d0
        dbra    %d2,8b
        movem.l (%sp)+,%d0-%d2/%a0
        lea     hb(%pc),%a0
        bra.s   puts
hb:     .ascii "00000000 "
        .byte 0
hdr:    .asciz "\r\nTTM: test count first-addr exp got\r\n"
sta:    .asciz "caches ON (3919)\r\n"
stb:    .asciz "caches OFF (0808)\r\n"
tn:     .asciz "T? "
nl:     .asciz "\r\n"
exm:    .asciz "EXC ? frame: "
dn:     .asciz "TTM done\r\n"
        .even
savsp:  .long 0,0,0
tend:
