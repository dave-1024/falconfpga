| TTRAM.PRG - FalconFPGA: register the 030-side TT-RAM ($01000000) with TOS 2.06.
| Probes $01000000.. in 512 KB steps (bus error or ST mirror ends it), Maddalt(),
| sets ramtop $5A4 / ramvalid $5A8, installs _FRB (64 KB ST-RAM DMA bounce buffer in our BSS).
| No PMMU use (the core has none). PC-relative, no relocations.
        .text
        .equ    FRBSZ,65536
start:  move.l  4(%sp),%a5              | basepage
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1                      | Super
        addq.l  #6,%sp
        lea     ossp(%pc),%a0
        move.l  %d0,(%a0)
        lea     m_hello(%pc),%a0
        bsr     cws
        move.w  #1,-(%sp)               | already registered? Mxalloc(-1, TT only) > 0
        move.l  #-1,-(%sp)
        move.w  #0x44,-(%sp)
        trap    #1
        addq.l  #8,%sp
        tst.l   %d0
        ble.s   1f
        lea     m_already(%pc),%a0
        bra     quit
| ---- probe
1:      move.w  %sr,-(%sp)
        or.w    #0x0700,%sr
        move.l  0x8.w,%a4               | old bus error vector
        move.l  %sp,%a3
        lea     berr(%pc),%a0
        move.l  %a0,0x8.w
        movec   %cacr,%d6
        moveq   #0,%d0
        movec   %d0,%cacr               | caches off while probing
        move.l  #0x01000000,%a1         | TT base
        moveq   #0,%d5                  | size found
        move.l  0x600.w,%d3             | mirror check once: TT off -> $01000600 is ST $600
        move.l  %d3,%d1
        not.l   %d1
        move.l  %d1,0x600(%a1)          | may bus error -> no TT-RAM
        nop
        cmp.l   0x600.w,%d3
        beq.s   2f
        move.l  %d3,0x600.w             | it wrapped: restore, no TT-RAM
        bra.s   9f
2:      lea     0x7fffc(%a1,%d5.l),%a2  | last long of this 512 KB step
        cmp.l   #0x10000000,%d5         | max 256 MB
        bcc.s   9f
        move.l  #0x5aa5c33c,%d1
        add.l   %d5,%d1
        move.l  %d1,(%a2)               | bus error past the end
        nop
        cmp.l   (%a2),%d1
        bne.s   9f
        add.l   #0x80000,%d5
        bra.s   2b
berr:   move.l  %a3,%sp                 | bus error: end of TT-RAM
9:      movec   %d6,%cacr
        move.l  %a4,0x8.w
        move.w  (%sp)+,%sr
        lea     ttsize(%pc),%a0
        move.l  %d5,(%a0)
        tst.l   %d5
        bne.s   4f
        lea     m_none(%pc),%a0
        bra     quit
| ---- _FRB cookie (our BSS, ST-RAM because we load into ST-RAM)
4:      move.l  0x5a0.w,%d0
        beq.s   6f                      | no jar: skip (TOS 2.06 always has one)
        move.l  %d0,%a0
        moveq   #0,%d2
5:      tst.l   (%a0)
        beq.s   7f
        cmp.l   #0x5f465242,(%a0)       | '_FRB' already there
        beq.s   6f
        addq.l  #8,%a0
        addq.l  #1,%d2
        bra.s   5b
7:      move.l  4(%a0),%d1              | jar size
        addq.l  #1,%d2
        cmp.l   %d1,%d2
        bcc.s   6f                      | jar full: no _FRB
        move.l  #0x5f465242,(%a0)
        lea     frb(%pc),%a1
        move.l  %a1,%d0
        add.l   #15,%d0
        and.l   #0xfffffff0,%d0
        move.l  %d0,4(%a0)
        clr.l   8(%a0)
        move.l  %d1,12(%a0)
        lea     frbok(%pc),%a1
        st      (%a1)
| ---- Maddalt + ramtop/ramvalid
6:      move.l  ttsize(%pc),-(%sp)
        move.l  #0x01000000,-(%sp)
        move.w  #0x14,-(%sp)
        trap    #1                      | Maddalt
        lea     10(%sp),%sp
        move.l  ttsize(%pc),%d0
        add.l   #0x01000000,%d0
        move.l  %d0,0x5a4.w
        move.l  #0x1357bd13,0x5a8.w
        move.l  ttsize(%pc),%d0
        moveq   #20,%d1
        lsr.l   %d1,%d0
        lea     m_mb(%pc),%a0
        divu    #10,%d0
        add.b   #'0',%d0
        move.b  %d0,(%a0)
        swap    %d0
        add.b   #'0',%d0
        move.b  %d0,1(%a0)
        lea     m_ok(%pc),%a0
        bsr     cws
        tst.b   frbok(%pc)
        beq.s   8f
        lea     m_frb(%pc),%a0
        bsr     cws
8:      bsr     user
        move.l  #frbend-start+256,%d0   | keep TPA incl. the _FRB buffer
        clr.w   -(%sp)
        move.l  %d0,-(%sp)
        move.w  #0x31,-(%sp)
        trap    #1                      | Ptermres
quit:   bsr     cws
        bsr     user
        clr.w   -(%sp)
        trap    #1
user:   move.l  ossp(%pc),-(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        rts
cws:    move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        rts
        .data
m_hello:  .asciz "TTRAM (FalconFPGA): "
m_already:.asciz "already installed\r\n"
m_none:   .asciz "no TT-RAM found\r\n"
m_ok:     .ascii "Maddalt $01000000 + "
m_mb:     .asciz "00 MB\r\n"
m_frb:    .asciz "  _FRB 64 KB ST-RAM buffer\r\n"
        .even
ossp:   .long 0
ttsize: .long 0
frbok:  .byte 0
        .even
        .bss
frb:    .space FRBSZ+16
frbend:
