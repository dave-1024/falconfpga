| MBXCART - ST_HELPER mailbox self-test, built into the ST_HELPER core as a
| cartridge ROM at $FA0000 (st_helper_cart_rom.v + .hex, build option
| ST_HELPER_CART). Needs no floppy, hard disk, keyboard or mouse.
|
| TOS finds the cartridge magic at boot and calls the init entry (CA_INIT
| flag bit 3: after GEMDOS init, before the boot disk). It prints the
| mailbox state, sends one line to the AE350 helper, shows the helper's
| answer on the ST screen for a few seconds and returns, so TOS carries on
| to the desktop. The helper prints the same exchange on U15.
| If the helper is not running it prints one line and returns at once.
|
| Build (box): ./build.sh -> st_helper_cart.hex (committed) + MBXTERM.PRG

        .equ    MB, -0x500              | $FFFB00 as a sign-extended .w address
        .equ    CART, 0xfa0000
        .text
cart:   .long   0xabcdef42              | CA_MAGIC
        .long   0                       | CA_NEXT: last entry
        .long   0x08000000 + CART + (init - cart) | CA_INIT, flag bit 3
        .long   CART + (run - cart)     | CA_RUN (desktop "cartridge" program)
        .word   0x0000, 0x5d46          | CA_TIME, CA_DATE (2026-10-06)
        .long   end - cart              | CA_SIZE
        .asciz  "MBXCART.PRG"           | CA_NAME
        .even

| desktop entry: user mode, like a .PRG
run:    clr.l   -(sp)                   | Super(0)
        move.w  #0x20, -(sp)
        trap    #1
        addq.l  #6, sp
        move.l  d0, -(sp)
        bsr.s   init
        move.w  #0x20, -(sp)            | Super(old ssp) (still on the stack)
        trap    #1
        addq.l  #6, sp
        clr.w   -(sp)                   | Pterm0
        trap    #1

| boot entry: supervisor mode, called with JSR, keeps all registers
init:   movem.l d0-d7/a0-a6, -(sp)
        lea     s_title(pc), a0
        bsr     print
        bsr     ttdiag
        cmp.b   #'H', (MB+0x01).w       | ID
        bne     nombx
        lea     s_boot(pc), a0
        bsr     print
        move.b  (MB+0x11).w, d0
        bsr     hex2
        lea     s_stat(pc), a0
        bsr     print
        move.b  (MB+0x05).w, d0
        bsr     hex2
        lea     s_crlf(pc), a0
        bsr     print
        btst    #2, (MB+0x05).w         | HELPER_UP
        beq     noup

        move.b  #3, (MB+0x0d).w         | flush RX, clear flags
        lea     s_msg(pc), a1           | send the line
snd:    move.b  (a1)+, d1
        beq.s   sent
        move.l  #100000, d2             | TXRDY timeout
txw:    btst    #0, (MB+0x05).w
        bne.s   txok
        subq.l  #1, d2
        bne.s   txw
        bra.s   sent
txok:   move.b  d1, (MB+0x07).w
        bra.s   snd
sent:   lea     s_wait(pc), a0
        bsr     print

        | show the reply: stop 0.3-0.5 s after the last byte, at most a few s
        move.l  #3000000, d3            | overall poll budget
        move.l  #400000, d4             | idle budget, reset by each byte
rxl:    btst    #1, (MB+0x05).w         | RXAVL
        beq.s   rxn
        moveq   #0, d0
        move.b  (MB+0x09).w, d0
        bsr     conout
        move.l  #400000, d4
rxn:    subq.l  #1, d4
        beq.s   rxd
        subq.l  #1, d3
        bne.s   rxl
rxd:    lea     s_done(pc), a0
        bsr     print
        move.l  #4000000, d2            | leave it on screen a moment
pause:  subq.l  #1, d2
        bne.s   pause
        bra.s   out

noup:   lea     s_noup(pc), a0
        bsr     print
        bra.s   out
nombx:  lea     s_nombx(pc), a0
        bsr     print
out:    movem.l (sp)+, d0-d7/a0-a6
        rts

| TT-RAM diagnostics: memvalid, _ramtop, _ramvalid, own R/W test at $01000000,
| $01FFFFFC and bus error check at $02000000 (BERR caught via vector 2).
ttdiag: lea     s_tt2(pc), a0
        bsr     print
        move.l  0x5a4.w, d0
        bsr     hex8
        lea     s_tt3(pc), a0
        bsr     print
        move.l  0x5a8.w, d0
        bsr     hex8
        move.w  sr, -(sp)
        move.w  #0x2700, sr
        move.l  0x8.w, a4               | save BERR vector
        lea     tberr(pc), a0
        move.l  a0, 0x8.w
        move.l  sp, a5
        moveq   #0, d6                  | BERR count
| own 32-bit bus test like EmuTOS (0x0C vs 0x0100000C), d7 = 1 if 32-bit
        moveq   #1, d7
        move.l  0xc.w, a3               | keep vector 3
        move.l  #0x12345678, d2
        move.l  d2, 0xc.w
        cmp.l   0x0100000c, d2
        bne.s   b32
        not.l   d2
        move.l  d2, 0xc.w
        cmp.l   0x0100000c, d2
        bne.s   b32
        moveq   #0, d7
b32:    move.l  a5, sp
        move.l  a3, 0xc.w
| EmuTOS detect_ttram_size replica: byte probe of the last byte of each MB
        move.l  #0x010fffff, a1
        moveq   #0, d5
pl:     lea     pbe(pc), a0
        move.l  a0, 0x8.w
        tst.b   (a1)
        move.b  #0x12, (a1)
        move.b  #0x34, -1(a1)
        move.w  -1(a1), d4
        cmp.w   #0x3412, d4
        bne.s   pend
        add.l   #0x100000, a1
        bra.s   pl
pbe:    move.l  a5, sp
        addq.l  #1, d6
pend:   move.l  a1, d5
        bra.s   tdone
tberr:  move.l  a5, sp
        addq.l  #1, d6
        bra.s   b32
tdone:  move.l  a4, 0x8.w
        move.w  (sp)+, sr
        lea     s_tt4(pc), a0
        bsr     print
        move.b  d7, d0
        bsr     hex2
        lea     s_tt5(pc), a0
        bsr     print
        move.l  d5, d0
        bsr     hex8
        lea     s_tt6(pc), a0
        bsr     print
        move.w  d4, d0
        bsr     hex4
        move.b  d6, d0
        bsr     hex2
        lea     s_crlf(pc), a0
        bsr     print
| TT-RAM stress: 16 MB address-pattern longs, D-cache + I-cache on, then verify
        cmp.l   #0x010fffff, d5
        bls     mtx
        move.w  sr, -(sp)
        move.w  #0x2700, sr
        move.l  #0x0909, d0
        .long   0x4e7b0002              | movec d0,cacr
        lea     0x01000000, a1
        move.l  #0x003fffff, d1
mw:     move.l  a1, d0
        not.l   d0
        move.l  d0, (a1)+
        subq.l  #1, d1
        bpl.s   mw
        lea     0x01000000, a1
        move.l  #0x003fffff, d1
        moveq   #0, d6
        moveq   #0, d4
mr:     move.l  a1, d0
        not.l   d0
        cmp.l   (a1)+, d0
        beq.s   mo
        tst.l   d6
        bne.s   mi
        move.l  a1, d4
        move.l  -4(a1), d7
mi:     addq.l  #1, d6
mo:     subq.l  #1, d1
        bpl.s   mr
        moveq   #0, d0
        .long   0x4e7b0002              | movec d0,cacr
        move.w  (sp)+, sr
        lea     s_me(pc), a0
        bsr     print
        move.l  d6, d0
        bsr     hex8
        lea     s_tt6(pc), a0
        bsr     print
        move.l  d4, d0
        bsr     hex8
        move.b  #32, d0
        bsr     conout
        move.l  d7, d0
        bsr     hex8
        lea     s_crlf(pc), a0
        bra     print
mtx:    rts
hex8:   swap    d0
        bsr.s   hex4
        swap    d0
hex4:   move.w  d0, -(sp)
        lsr.w   #8, d0
        bsr     hex2
        move.w  (sp)+, d0
        bra     hex2

| string at a0 via BIOS Bconout(CON), keeps a1-a6/d3-d7
print:  moveq   #0, d0
        move.b  (a0)+, d0
        beq.s   pr_e
        move.l  a0, -(sp)
        bsr.s   conout
        move.l  (sp)+, a0
        bra.s   print
pr_e:   rts

conout: movem.l d0-d2/a0-a2, -(sp)
        move.w  d0, -(sp)
        move.w  #2, -(sp)
        move.w  #3, -(sp)
        trap    #13
        addq.l  #6, sp
        movem.l (sp)+, d0-d2/a0-a2
        rts

hex2:   movem.l d0-d3/a0, -(sp)
        move.b  d0, d3
        lsr.b   #4, d0
        bsr.s   nib
        move.b  d3, d0
        bsr.s   nib
        movem.l (sp)+, d0-d3/a0
        rts
nib:    and.w   #15, d0
        lea     hexd(pc), a0
        move.b  0(a0,d0.w), d0
        bra.s   conout

hexd:   .ascii  "0123456789ABCDEF"
s_title: .asciz "\r\nST_HELPER mailbox self-test (cartridge $FA0000)\r\n"
s_tt2:  .asciz  "RT "
s_tt3:  .asciz  " RV "
s_tt4:  .asciz  "\r\nB32 "
s_tt5:  .asciz  " END "
s_tt6:  .asciz  " W "
s_me:   .asciz  "MT err "
s_boot: .asciz  "BOOT $"
s_stat: .asciz  "  STATUS $"
s_crlf: .asciz  "\r\n"
s_msg:  .asciz  "hello from the ST\r"
s_wait: .asciz  "helper says:\r\n"
s_done: .asciz  "\r\n-- TOS continues --\r\n"
s_noup: .asciz  "helper not running, skipped\r\n"
s_nombx: .asciz "no mailbox at $FFFB00, skipped\r\n"
        .even
end:
