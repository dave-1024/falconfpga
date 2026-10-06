| MBXTERM.PRG - tiny ST terminal for the AE350 helper mailbox
| (FalconFPGA build option ST_HELPER, mailbox at $FFFB00, see README).
| Keys go to the helper ($FFFB07), helper output is shown ($FFFB09).
| ESC quits. Needs the ST_HELPER core: on any other core the mailbox is not
| there and the program says so (bus error caught) instead of crashing.
|
| Build (box, GNU m68k binutils): ./build.sh  -> MBXTERM.PRG
| Position independent, so the GEMDOS header has an empty relocation table.

        .equ    MB, -0x500              | $FFFB00 as a sign-extended .w address
        .text
        .globl  _start
hdr:    .word   0x601a                  | GEMDOS program header
        .long   text_end - text_start   | TEXT size
        .long   0                       | DATA
        .long   0                       | BSS
        .long   0                       | symbols
        .long   0, 0                    | reserved, flags
        .word   0                       | relocation info follows (empty)

text_start:
_start:
        clr.l   -(sp)                   | Super(0)
        move.w  #0x20, -(sp)
        trap    #1
        addq.l  #6, sp
        move.l  d0, d7                  | old SSP

        lea     s_title(pc), a0
        bsr     print

        | probe the mailbox with a temporary bus error handler
        move.l  0x8.w, a5
        lea     berr(pc), a0
        move.l  a0, 0x8.w
        move.l  sp, a6
        move.b  (MB+0x01).w, d0          | ID
        move.l  a5, 0x8.w
        cmp.b   #'H', d0
        bne     nombx

        lea     s_ver(pc), a0
        bsr     print
        move.b  (MB+0x03).w, d0
        bsr     hex2
        lea     s_boot(pc), a0
        bsr     print
        move.b  (MB+0x11).w, d0
        bsr     hex2
        lea     s_stat(pc), a0
        bsr     print
        move.b  (MB+0x05).w, d0
        bsr     hex2
        lea     s_gpio(pc), a0
        bsr     print
        move.b  (MB+0x0f).w, d0
        bsr     hex2
        lea     s_crlf(pc), a0
        bsr     print
        btst    #2, (MB+0x05).w          | HUP
        bne.s   up
        lea     s_noup(pc), a0
        bsr     print
up:     lea     s_help(pc), a0
        bsr     print

loop:   btst    #1, (MB+0x05).w          | RXAVL
        beq.s   keys
        moveq   #0, d0
        move.b  (MB+0x09).w, d0          | pop one byte
        bsr     conout
        bra.s   loop
keys:   move.w  #2, -(sp)               | Bconstat(CON)
        move.w  #1, -(sp)
        trap    #13
        addq.l  #4, sp
        tst.w   d0
        beq.s   loop
        move.w  #2, -(sp)               | Bconin(CON)
        move.w  #2, -(sp)
        trap    #13
        addq.l  #4, sp
        cmp.b   #27, d0                 | ESC
        beq.s   quit
txw:    btst    #0, (MB+0x05).w          | TXRDY
        beq.s   txw
        move.b  d0, (MB+0x07).w
        bra.s   loop

berr:   move.l  a6, sp                  | drop the bus error frame
        move.l  a5, 0x8.w
nombx:  lea     s_nombx(pc), a0
        bsr     print
        bsr     waitkey
quit:   move.l  d7, -(sp)               | back to user mode
        move.w  #0x20, -(sp)
        trap    #1
        addq.l  #6, sp
        clr.w   -(sp)                   | Pterm0
        trap    #1

| print NUL-terminated string at a0 (Cconws)
print:  move.l  a0, -(sp)
        move.w  #9, -(sp)
        trap    #1
        addq.l  #6, sp
        rts

| one character in d0 to the console (Bconout)
conout: movem.l d0-d2/a0-a2, -(sp)
        move.w  d0, -(sp)
        move.w  #2, -(sp)
        move.w  #3, -(sp)
        trap    #13
        addq.l  #6, sp
        movem.l (sp)+, d0-d2/a0-a2
        rts

| d0.b as two hex digits
hex2:   movem.l d0-d3, -(sp)
        move.b  d0, d3
        lsr.b   #4, d0
        bsr.s   nib
        move.b  d3, d0
        bsr.s   nib
        movem.l (sp)+, d0-d3
        rts
nib:    and.w   #15, d0
        lea     hexd(pc), a0
        move.b  0(a0,d0.w), d0
        bra.s   conout

waitkey:
        move.w  #2, -(sp)
        move.w  #2, -(sp)
        trap    #13
        addq.l  #4, sp
        rts

hexd:   .ascii  "0123456789ABCDEF"
s_title: .asciz "\r\nMBXTERM - AE350 helper mailbox at $FFFB00\r\n"
s_ver:  .asciz  "VER $"
s_boot: .asciz  "  BOOT $"
s_stat: .asciz  "  STATUS $"
s_gpio: .asciz  "  HGPIO $"
s_crlf: .asciz  "\r\n"
s_noup: .asciz  "Helper is NOT running (see BOOT: 1 DDR3, 2 no flash-done, 3 S1, 4 CS#).\r\n"
s_help: .asciz  "Type to the helper, RETURN sends the line. Try: s, i, ?  ESC quits.\r\n"
s_nombx: .asciz "No mailbox at $FFFB00: this core is not the ST_HELPER build. Press a key.\r\n"
        .even
text_end:
        .long   0                       | relocation: none
