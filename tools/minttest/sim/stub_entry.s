| MiNT 1.19 mint030 entry (TEXT $CEBA, user mode) from Hatari's snapshot (ram_entry.bin), registers from Hatari.
        .text
start:  move.w  #0x2700,%sr
        move.l  #0x003F7FF8,%a0
        move.l  %a0,%usp
        moveq   #0,%d0
        movec   %d0,%cacr
        move.l  #0x000654AE,%a4
        move.l  #0x00060D0E,%a5
        move.l  #0x003F7FC6,%a6
        move.l  #0x00003DE8,%sp
        sub.l   %a0,%a0
        move.w  #0x0300,%sr
        jmp     0xceba
