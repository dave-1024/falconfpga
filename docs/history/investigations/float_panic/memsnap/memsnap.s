| MEMSNAP.PRG - AUTO folder, FalconFPGA float-panic RAM snapshot (no HD driver).
| Lowers phystop to $3E0000 (one warm reset), copies a resident hook to $3E0400.
| LD snapshot: first trap #1/#14 after Pexec(0,"...AUTOFPU...") = the child's first
| system call (code loaded+relocated, a few instructions run).
| CR snapshot: first bus/address/illegal/CHK exception after the LD snapshot.
| Range R..R+L copied to $3E1000 (LD) and $3E6000 (CR). Header at $3E0000.
        .equ H,      0x3E0000
        .equ CODE,   0x3E0400
        .equ LDBUF,  0x3E1000
        .equ CRBUF,  0x3E6000
        .equ R,      0x55600
        .equ L,      0x5000
        .equ MAGIC,  0x4D534E50      | 'MSNP'
        .equ RST1,   0x52535431      | 'RST1'
| header offsets
        .equ O_MAG,0
        .equ O_RST,4
        .equ O_LDN,8
        .equ O_CRN,12
        .equ O_ARM,16
        .equ O_CRVEC,20
        .equ O_T1,24
        .equ O_T14,28
        .equ O_V2,32
        .equ O_V3,36
        .equ O_V4,40
        .equ O_V6,44
        .equ O_LDREG,48          | d0-a7 (16 longs)
        .equ O_LDUSP,112
        .equ O_CRUSP,116
        .equ O_CRREG,120         | d0-a7
        .equ O_CRFRM,184         | 64 bytes
        .equ O_LDFRM,248         | 32 bytes
        .equ O_CRARM,280
        .equ O_R,284             | range start
        .equ O_L,288             | range length
        .equ O_LDTRAP,292        | trap number of the LD snapshot

        .text
start:  clr.l   -(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        lea     oldssp(pc),a0
        move.l  d0,(a0)
        lea     t_hi(pc),a0
        bsr     puts
        cmp.l   #H,0x42e
        bls     inst
        cmp.l   #RST1,H+O_RST
        beq     rfail
        move.l  #RST1,H+O_RST
        lea     t_rst(pc),a0
        bsr     puts
        move.l  0x4ba,d0
        add.l   #200,d0
1:      cmp.l   0x4ba,d0
        bhi     1b
        move.w  #0x2700,sr
        move.l  #H,0x42e
        move.l  0x4,a0
        jmp     (a0)
rfail:  clr.l   H+O_RST
        lea     t_fail(pc),a0
        bsr     puts
        bra     out
inst:   clr.l   H+O_RST
        cmp.l   #MAGIC,H+O_MAG
        beq     1f
        lea     H+O_LDN,a0          | first time: clear header after magic
        move.w  #(1024-8)/4-1,d0
2:      clr.l   (a0)+
        dbf     d0,2b
        move.l  #MAGIC,H+O_MAG
1:      move.l  #R,H+O_R
        move.l  #L,H+O_L
        clr.l   H+O_ARM
        clr.l   H+O_CRARM
        cmp.l   #CODE+(t1h-hs),0x84
        beq     done                | already hooked (no reset since)
        lea     hs(pc),a0           | copy the hook code
        lea     CODE,a1
        move.w  #(he-hs)/2-1,d0
3:      move.w  (a0)+,(a1)+
        dbf     d0,3b
        move.l  0x84,H+O_T1
        move.l  0xb8,H+O_T14
        move.l  0x08,H+O_V2
        move.l  0x0c,H+O_V3
        move.l  0x10,H+O_V4
        move.l  0x18,H+O_V6
        move.l  #CODE+(t1h-hs),0x84
        move.l  #CODE+(t14h-hs),0xb8
        move.l  #CODE+(v2h-hs),0x08
        move.l  #CODE+(v3h-hs),0x0c
        move.l  #CODE+(v4h-hs),0x10
        move.l  #CODE+(v6h-hs),0x18
done:   lea     t_ok(pc),a0
        bsr     puts
        move.l  0x42e,d0
        bsr     hex8
        lea     t_ld(pc),a0
        bsr     puts
        move.l  H+O_LDN,d0
        bsr     hex8
        lea     t_cr(pc),a0
        bsr     puts
        move.l  H+O_CRN,d0
        bsr     hex8
        lea     t_nl(pc),a0
        bsr     puts
out:    move.l  oldssp(pc),-(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        clr.w   -(sp)
        trap    #1

puts:   move.l  a0,-(sp)
        move.w  #9,-(sp)
        trap    #1
        addq.l  #6,sp
        rts
hex8:   moveq   #7,d2
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
        rts

| ---------------- resident part (copied to CODE) ----------------
        .even
hs:
| snapshot of the child's state at its first system call
snapld: movem.l d0-a7,H+O_LDREG
        movem.l d0-d1/a0-a1,-(sp)
        move.l  usp,a0
        move.l  a0,H+O_LDUSP
        lea     20(sp),a0           | 4 regs + return address -> exception frame
        lea     H+O_LDFRM,a1
        moveq   #7,d0
1:      move.l  (a0)+,(a1)+
        dbf     d0,1b
        lea     R,a0
        lea     LDBUF,a1
        move.w  #L/4-1,d0
2:      move.l  (a0)+,(a1)+
        dbf     d0,2b
        addq.l  #1,H+O_LDN
        clr.l   H+O_ARM
        move.l  #1,H+O_CRARM
        movem.l (sp)+,d0-d1/a0-a1
        rts

t14h:   tst.l   H+O_ARM
        beq     1f
        move.l  #14,H+O_LDTRAP
        bsr     snapld
1:      move.l  H+O_T14,-(sp)
        rts

t1h:    tst.l   H+O_ARM
        beq     1f
        move.l  #1,H+O_LDTRAP
        bsr     snapld
1:      movem.l d0/a0-a1,-(sp)
        btst    #5,12(sp)           | SR of the frame: S bit
        bne     2f
        move.l  usp,a0
        bra     3f
2:      lea     18(sp),a0           | 12 + 6
        tst.w   0x59e
        beq     3f
        addq.l  #2,a0
3:      cmp.w   #0x4b,(a0)
        bne     9f
        tst.w   2(a0)
        bne     9f
        move.l  4(a0),a0            | file name: look for "AUTOFPU"
4:      move.b  (a0)+,d0
        beq     9f
        cmp.b   #'A',d0
        bne     4b
        cmp.b   #'U',(a0)
        bne     4b
        cmp.b   #'T',1(a0)
        bne     4b
        cmp.b   #'O',2(a0)
        bne     4b
        cmp.b   #'F',3(a0)
        bne     4b
        cmp.b   #'P',4(a0)
        bne     4b
        move.l  #1,H+O_ARM
9:      movem.l (sp)+,d0/a0-a1
        move.l  H+O_T1,-(sp)
        rts

v2h:    movem.l d0-a7,H+O_CRREG
        move.w  #2,H+O_CRVEC+2
        bsr     crash
        move.l  H+O_V2,-(sp)
        rts
v3h:    movem.l d0-a7,H+O_CRREG
        move.w  #3,H+O_CRVEC+2
        bsr     crash
        move.l  H+O_V3,-(sp)
        rts
v4h:    movem.l d0-a7,H+O_CRREG
        move.w  #4,H+O_CRVEC+2
        bsr     crash
        move.l  H+O_V4,-(sp)
        rts
v6h:    movem.l d0-a7,H+O_CRREG
        move.w  #6,H+O_CRVEC+2
        bsr     crash
        move.l  H+O_V6,-(sp)
        rts

crash:  tst.l   H+O_CRARM
        beq     9f
        clr.l   H+O_CRARM
        movem.l d0/a0-a1,-(sp)
        move.l  usp,a0
        move.l  a0,H+O_CRUSP
        lea     16(sp),a0
        lea     H+O_CRFRM,a1
        moveq   #15,d0
1:      move.l  (a0)+,(a1)+
        dbf     d0,1b
        lea     R,a0
        lea     CRBUF,a1
        move.w  #L/4-1,d0
2:      move.l  (a0)+,(a1)+
        dbf     d0,2b
        addq.l  #1,H+O_CRN
        movem.l (sp)+,d0/a0-a1
9:      rts
        .even
he:

        .even
oldssp: .long 0
t_hi:   .asciz  "\r\nMEMSNAP (float panic RAM snapshot)\r\n"
t_rst:  .asciz  "phystop -> $3E0000, warm reset...\r\n"
t_fail: .asciz  "phystop not kept over warm reset - NOT installed\r\n"
t_ok:   .asciz  "installed, phystop $"
t_ld:   .asciz  " LD# $"
t_cr:   .asciz  " CR# $"
t_nl:   .asciz  "\r\n"
        .even
