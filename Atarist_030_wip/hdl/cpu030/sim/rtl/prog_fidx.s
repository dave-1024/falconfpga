| [F97] index register of an indexed EA written by the instruction right before it.
| MiNT text+19c14: ... lsl.l #3,d0 ; movea.l (bd.l,d0.l),a0 (full format, base suppressed) read the
| table with d0 from before the lsl on the board. Table at $2000: long i at $2000+24*i = $A000+i.
| Results at $5000.. (expect_fidx.txt).
        .text
        .org 0
        .long 0x00008000
        .long 0x00fc0008
        lea 0x2000,a1
        moveq #0,d7
fill:   move.l d7,d0
        mulu.w #24,d0
        move.l d7,d1
        add.l #0xa000,d1
        move.l d1,(0,a1,d0.l)
        addq.w #1,d7
        cmp.w #8,d7
        bne.s fill
        lea 0x5000,a5
        moveq #1,d6
loop:
| C1: full format, base suppressed, bd.l (MiNT)
        moveq #0,d1
        move.w d6,d1
        move.l d1,d0
        add.l d0,d0
        add.l d1,d0
        lsl.l #3,d0
        movea.l (0x2000.l,d0.l),a0
        move.l a0,(a5)+
| C2: brief format (d8,An,Dn.l) right after lsl
        move.l d1,d0
        add.l d0,d0
        add.l d1,d0
        lsl.l #3,d0
        movea.l (0,a1,d0.l),a0
        move.l a0,(a5)+
| C3: full format with base An, bd.w
        move.l d1,d0
        mulu.w #3,d0
        lsl.l #3,d0
        lea 0x1000,a2
        move.l (0x1000.w,a2,d0.l),d2
        move.l d2,(a5)+
| C4: full format, index word size, scale 8 after add
        move.l d1,d0
        add.w d0,d0
        add.w d1,d0
        move.l (0x2000.l,d0.w*8),d3
        move.l d3,(a5)+
| C5: memory indirect ([bd,Dn.l]) after lsl; pointer table at $3000+8*i -> $2000+24*i
        move.l d1,d0
        lsl.l #3,d0
        move.l d1,d4
        mulu.w #24,d4
        add.l #0x2000,d4
        move.l d4,(0x3000,d0.l)
        move.l d1,d0
        lsl.l #3,d0
        move.l ([0x3000.l,d0.l]),d5
        move.l d5,(a5)+
        addq.w #1,d6
        cmp.w #8,d6
        bne loop
        move.l #0x600dc0de,0x3300
h:      bra.s h
