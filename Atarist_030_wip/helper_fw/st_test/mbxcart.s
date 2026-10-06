| MBXCART - ST_HELPER mailbox self-test, built into the ST_HELPER core as a
| cartridge ROM at $FA0000 (st_helper_cart_rom.v, build option
| ST_HELPER_CART). Needs no floppy, hard disk, keyboard or mouse.
|
| TOS finds the cartridge magic at boot and calls the init entry (CA_INIT
| flag bit 3: after GEMDOS init, before the boot disk). It prints the
| mailbox state, sends one line to the AE350 helper, shows the helper's
| answer on the ST screen for a few seconds and returns, so TOS carries on
| to the desktop. The helper prints the same exchange on U15.
| If the helper is not running it prints one line and returns at once.
|
| Build (box): ./build.sh -> st_helper_cart_rom.v (committed) + MBXTERM.PRG

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
s_boot: .asciz  "BOOT $"
s_stat: .asciz  "  STATUS $"
s_crlf: .asciz  "\r\n"
s_msg:  .asciz  "hello from the ST\r"
s_wait: .asciz  "sent 'hello from the ST', helper says:\r\n"
s_done: .asciz  "\r\n-- mailbox test done, TOS continues --\r\n"
s_noup: .asciz  "helper not running (BOOT: 1 DDR3, 2 no flash-done, 3 S1, 4 CS#), skipped\r\n"
s_nombx: .asciz "no mailbox at $FFFB00, skipped\r\n"
        .even
end:
