| MEMSAVE.PRG - writes the MEMSNAP buffers to A:\SNAP_HD.BIN / SNAP_LD.BIN / SNAP_CR.BIN
| and compares both against A:\BIN\AUTOFPU.BIN relocated to the child's text base
| (LD a2 = basepage, text = a2+$100). Prints the first differences.
        .equ H,      0x3E0000
        .equ LDBUF,  0x3E1000
        .equ CRBUF,  0x3E6000
        .equ R,      0x55600
        .equ L,      0x5000
        .equ MAGIC,  0x4D534E50
        .text
start:  move.l  4(sp),a0
        lea     0x2000(a0),sp       | own stack inside the TPA (mshrink below)
        move.l  #0x8000,-(sp)       | keep 32 KB
        move.l  a0,-(sp)
        clr.w   -(sp)
        move.w  #0x4a,-(sp)
        trap    #1
        lea     12(sp),sp
        clr.l   -(sp)               | supervisor (high RAM is fine anyway)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        lea     oldssp(pc),a0
        move.l  d0,(a0)
        lea     t_hi(pc),a0
        bsr     puts
        cmp.l   #MAGIC,H
        beq     1f
        lea     t_nomag(pc),a0
        bsr     puts
        bra     quit
1:      lea     t_cnt(pc),a0
        bsr     puts
        move.l  H+8,d0
        bsr     hex8
        lea     t_cr(pc),a0
        bsr     puts
        move.l  H+12,d0
        bsr     hex8
        lea     t_vec(pc),a0
        bsr     puts
        move.l  H+20,d0
        bsr     hex8
        lea     t_trap(pc),a0
        bsr     puts
        move.l  H+292,d0
        bsr     hex8
        bsr     nl
| crash registers d0-a7, usp, frame
        lea     t_regs(pc),a0
        bsr     puts
        lea     H+120,a3
        moveq   #15,d3
2:      move.l  (a3)+,d0
        bsr     hex8
        bsr     sp1
        cmp.w   #8,d3
        bne     3f
        bsr     nl
3:      dbf     d3,2b
        bsr     nl
        lea     t_usp(pc),a0
        bsr     puts
        move.l  H+116,d0
        bsr     hex8
        lea     t_frm(pc),a0
        bsr     puts
        lea     H+184,a3
        moveq   #15,d3
4:      move.w  (a3)+,d0
        bsr     hex4
        bsr     sp1
        dbf     d3,4b
        bsr     nl
        lea     t_ldr(pc),a0        | LD a2 (basepage), LD sr/pc from frame
        bsr     puts
        move.l  H+48+40,d0
        bsr     hex8
        lea     t_ldf(pc),a0
        bsr     puts
        lea     H+248,a3
        moveq   #3,d3
5:      move.w  (a3)+,d0
        bsr     hex4
        bsr     sp1
        dbf     d3,5b
        bsr     nl
| save files
        lea     f_hd(pc),a0
        lea     H,a1
        move.l  #1024,d4
        bsr     wfile
        lea     f_ld(pc),a0
        lea     LDBUF,a1
        move.l  #L,d4
        bsr     wfile
        lea     f_cr(pc),a0
        lea     CRBUF,a1
        move.l  #L,d4
        bsr     wfile
| reference: AUTOFPU.BIN relocated to LD a2+$100
        move.l  #20000,-(sp)
        move.w  #0x48,-(sp)
        trap    #1
        addq.l  #6,sp
        tst.l   d0
        ble     quit
        move.l  d0,a4               | file buffer
        clr.w   -(sp)
        pea     f_af(pc)
        move.w  #0x3d,-(sp)
        trap    #1
        addq.l  #8,sp
        tst.l   d0
        bmi     nofile
        move.w  d0,d5
        move.l  a4,-(sp)
        move.l  #20000,-(sp)
        move.w  d5,-(sp)
        move.w  #0x3f,-(sp)
        trap    #1
        lea     12(sp),sp
        move.w  d5,-(sp)
        move.w  #0x3e,-(sp)
        trap    #1
        addq.l  #4,sp
        move.l  H+48+40,d6          | basepage
        add.l   #0x100,d6           | text base
        lea     28(a4),a5           | image (text+data)
        move.l  2(a4),d7            | tlen
        add.l   6(a4),d7            | +dlen
        move.l  a5,a0               | reloc table
        add.l   d7,a0
        add.l   14(a4),a0           | +slen
        move.l  (a0)+,d0
        beq     rdone
        lea     (a5,d0.l),a1
        add.l   d6,(a1)
6:      moveq   #0,d0
        move.b  (a0)+,d0
        beq     rdone
        cmp.b   #1,d0
        bne     7f
        lea     254(a1),a1
        bra     6b
7:      add.l   d0,a1
        add.l   d6,(a1)
        bra     6b
rdone:  lea     t_ref(pc),a0
        bsr     puts
        move.l  d6,d0
        bsr     hex8
        lea     t_len(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     hex8
        bsr     nl
        lea     t_cld(pc),a0
        bsr     puts
        lea     LDBUF,a2
        bsr     cmpbuf
        lea     t_ccr(pc),a0
        bsr     puts
        lea     CRBUF,a2
        bsr     cmpbuf
        bra     quit
nofile: lea     t_nof(pc),a0
        bsr     puts
quit:   lea     t_key(pc),a0
        bsr     puts
        move.w  #7,-(sp)
        trap    #1
        addq.l  #2,sp
        move.l  oldssp(pc),-(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp
        clr.w   -(sp)
        trap    #1

| cmpbuf: a2 = snapshot buffer (covers R..R+L). Compare words of text+data (d7 bytes)
| at d6 against a5. Prints count, text/data split, first 10 diffs "addr exp act".
cmpbuf: move.l  d6,d0
        sub.l   #R,d0
        lea     (a2,d0.l),a3        | snapshot copy of text base
        move.l  a5,a1
        moveq   #0,d3               | diff count (words)
        moveq   #0,d4               | diffs in text
        move.l  d7,d2
        lsr.l   #1,d2
        subq.l  #1,d2
        moveq   #0,d1               | offset
1:      move.w  (a1,d1.l),d0
        cmp.w   (a3,d1.l),d0
        beq     3f
        addq.l  #1,d3
        cmp.l   2(a4),d1
        bhs     2f
        addq.l  #1,d4
2:      cmp.l   #10,d3
        bhi     3f
        movem.l d0-d4/a1,-(sp)
        bsr     nl
        move.l  d6,d0
        add.l   d1,d0
        bsr     hex8
        bsr     sp1
        move.w  (a1,d1.l),d0
        bsr     hex4
        bsr     sp1
        move.w  (a3,d1.l),d0
        bsr     hex4
        movem.l (sp)+,d0-d4/a1
3:      addq.l  #2,d1
        subq.l  #1,d2
        bpl     1b
        bsr     nl
        lea     t_nd(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     hex8
        lea     t_nt(pc),a0
        bsr     puts
        move.l  d4,d0
        bsr     hex8
        bsr     nl
        rts

| wfile: a0 name, a1 data, d4 length
wfile:  movem.l a0-a1,-(sp)
        clr.w   -(sp)
        move.l  a0,-(sp)
        move.w  #0x3c,-(sp)
        trap    #1
        addq.l  #8,sp
        movem.l (sp)+,a0-a1
        tst.l   d0
        bmi     9f
        move.w  d0,d5
        move.l  a1,-(sp)
        move.l  d4,-(sp)
        move.w  d5,-(sp)
        move.w  #0x40,-(sp)
        trap    #1
        lea     12(sp),sp
        move.l  d0,d3
        move.w  d5,-(sp)
        move.w  #0x3e,-(sp)
        trap    #1
        addq.l  #4,sp
        lea     t_w(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     hex8
        rts
9:      lea     t_werr(pc),a0
        bsr     puts
        bsr     hex8
        rts

nl:     lea     t_nl(pc),a0
puts:   movem.l d0-d2/a0-a2,-(sp)
        move.l  a0,-(sp)
        move.w  #9,-(sp)
        trap    #1
        addq.l  #6,sp
        movem.l (sp)+,d0-d2/a0-a2
        rts
sp1:    lea     t_sp(pc),a0
        bra     puts
hex4:   swap    d0
        moveq   #3,d2
        bra     hx
hex8:   moveq   #7,d2
hx:     movem.l d0-d2/a0-a2,-(sp)
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
        movem.l (sp)+,d0-d2/a0-a2
        rts

        .even
oldssp: .long 0
t_hi:   .asciz  "MEMSAVE\r\n"
t_nomag:.asciz  "no MEMSNAP header at $3E0000\r\n"
t_cnt:  .asciz  "LD# "
t_cr:   .asciz  " CR# "
t_vec:  .asciz  " crash vec "
t_trap: .asciz  " LD trap "
t_regs: .asciz  "CR d0-a7:\r\n"
t_usp:  .asciz  "CR usp "
t_frm:  .asciz  "\r\nCR frame: "
t_ldr:  .asciz  "LD a2(basepage) "
t_ldf:  .asciz  " LD frame: "
t_w:    .asciz  " wrote "
t_werr: .asciz  " Fcreate err "
t_ref:  .asciz  "\r\nref AUTOFPU text $"
t_len:  .asciz  " len $"
t_cld:  .asciz  "LD vs file (addr exp act):"
t_ccr:  .asciz  "CR vs file (addr exp act):"
t_nd:   .asciz  "diff words $"
t_nt:   .asciz  " in text $"
t_nof:  .asciz  "A:\\BIN\\AUTOFPU.BIN not found\r\n"
t_key:  .asciz  "\r\n-- key --"
t_nl:   .asciz  "\r\n"
t_sp:   .asciz  " "
f_hd:   .asciz  "A:\\SNAP_HD.BIN"
f_ld:   .asciz  "A:\\SNAP_LD.BIN"
f_cr:   .asciz  "A:\\SNAP_CR.BIN"
f_af:   .asciz  "A:\\BIN\\AUTOFPU.BIN"
        .even
