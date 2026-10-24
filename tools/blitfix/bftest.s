| BFTEST.PRG - FalconFPGA BLITFIX test (GEM program, run from the desktop).
| vro_cpyfm from a TT-RAM buffer (Mxalloc mode 1) to the screen, and from the screen to a
| second TT-RAM buffer, with the blitter on. Checks the pixels and that the ST-RAM alias
| (address & $FFFFFF) of the destination buffer is unchanged. Prints PASS/FAIL, waits for a key.
        .text
        .equ    BUFSZ,32000
start:  move.l  4(%sp),%a0
        lea     basep(%pc),%a1
        move.l  %a0,(%a1)
        move.l  #0x100+0x4000,%d0       | Mshrink: keep text/data/bss + 16 KB stack
        add.l   12(%a0),%d0
        add.l   20(%a0),%d0
        add.l   28(%a0),%d0
        and.l   #-4,%d0
        lea     (%a0,%d0.l),%sp
        move.l  %d0,-(%sp)
        move.l  %a0,-(%sp)
        clr.w   -(%sp)
        move.w  #0x4a,-(%sp)
        trap    #1
        lea     12(%sp),%sp
| AES / VDI
        lea     aesctl(%pc),%a0
        move.l  #0x000a0000,(%a0)       | appl_init 10,0,1,0,0
        move.l  #0x00010000,4(%a0)
        clr.w   8(%a0)
        bsr     aes
        lea     aesctl(%pc),%a0
        move.l  #0x004d0000,(%a0)       | graf_handle 77,0,5,0,0
        move.l  #0x00050000,4(%a0)
        bsr     aes
        lea     aesio(%pc),%a0
        move.w  (%a0),%d7               | phys handle
        lea     contrl(%pc),%a0
        move.w  #100,(%a0)
        clr.w   2(%a0)
        move.w  #11,6(%a0)
        move.w  %d7,12(%a0)
        lea     intin(%pc),%a1
        moveq   #9,%d0
1:      move.w  #1,(%a1)+
        dbra    %d0,1b
        move.w  #2,(%a1)
        bsr     vdi
        lea     contrl(%pc),%a0
        move.w  12(%a0),%d7
        lea     vh(%pc),%a0
        move.w  %d7,(%a0)
| screen geometry
        move.w  #4,-(%sp)
        trap    #14                     | Getrez
        addq.l  #2,%sp
        lea     geo(%pc),%a0
        move.w  #4,%d1
        move.w  #320,%d2
        move.w  #200,%d3
        move.w  #160,%d4
        cmp.w   #1,%d0
        bne.s   2f
        moveq   #2,%d1
        move.w  #640,%d2
2:      cmp.w   #2,%d0
        bne.s   3f
        moveq   #1,%d1
        move.w  #640,%d2
        move.w  #400,%d3
        moveq   #80,%d4
3:      movem.w %d1-%d4,(%a0)           | planes,w,h,linebytes
        move.w  #2,-(%sp)
        trap    #14                     | Physbase
        addq.l  #2,%sp
        lea     scr(%pc),%a0
        move.l  %d0,(%a0)
| Blitmode, ramtop
        move.w  #-1,-(%sp)
        move.w  #64,-(%sp)
        trap    #14
        addq.l  #4,%sp
        lea     bmode(%pc),%a0
        move.w  %d0,(%a0)
| TT buffers: 2 MB pad first so the ST alias of the test buffers is ~$200000 (free ST-RAM, not system data)
        move.w  #1,-(%sp)
        move.l  #0x200000,-(%sp)
        move.w  #0x44,-(%sp)
        trap    #1
        addq.l  #8,%sp
        move.w  #1,-(%sp)
        move.l  #BUFSZ,-(%sp)
        move.w  #0x44,-(%sp)
        trap    #1                      | Mxalloc(BUFSZ, TT only)
        addq.l  #8,%sp
        lea     buf1(%pc),%a0
        move.l  %d0,(%a0)
        move.w  #1,-(%sp)
        move.l  #BUFSZ,-(%sp)
        move.w  #0x44,-(%sp)
        trap    #1
        addq.l  #8,%sp
        lea     buf2(%pc),%a0
        move.l  %d0,(%a0)
        move.l  buf1(%pc),%d0
        cmp.l   #0x01000000,%d0
        bcs     nott
        move.l  buf2(%pc),%d0
        cmp.l   #0x01000000,%d0
        bcs     nott
| fill buf1 with a pattern, clear buf2
        move.l  buf1(%pc),%a0
        move.l  buf2(%pc),%a1
        move.w  #BUFSZ/2-1,%d0
        move.w  #0x1357,%d1
4:      move.w  %d1,(%a0)+
        clr.w   (%a1)+
        mulu    #0x6255,%d1             | pseudo-random words
        add.w   #0x3619,%d1
        dbra    %d0,4b
| checksum of buf2's ST alias before
        bsr     alias_sum
        lea     sum0(%pc),%a0
        move.l  %d0,(%a0)
| test 1: buf1 -> screen
        lea     mfdb1(%pc),%a0
        move.l  buf1(%pc),(%a0)
        bsr     setmfdb
        lea     mfdbs(%pc),%a0
        clr.l   (%a0)
        bsr     setmfdb
        lea     mfdb1(%pc),%a0
        lea     mfdbs(%pc),%a1
        bsr     cpyfm
| compare screen rect with buf1
        move.l  scr(%pc),%a0
        move.l  buf1(%pc),%a1
        bsr     cmprect
        lea     err1(%pc),%a0
        move.l  %d0,(%a0)
| test 2: screen -> buf2
        lea     mfdb2(%pc),%a0
        move.l  buf2(%pc),(%a0)
        bsr     setmfdb
        lea     mfdbs(%pc),%a0
        lea     mfdb2(%pc),%a1
        bsr     cpyfm
        move.l  buf2(%pc),%a0
        move.l  scr(%pc),%a1
        bsr     cmprect
        lea     err2(%pc),%a0
        move.l  %d0,(%a0)
        bsr     alias_sum
        lea     sum1(%pc),%a0
        move.l  %d0,(%a0)
| report (bottom of the screen)
        lea     m_pos(%pc),%a0
        bsr     cws
        lea     m_bm(%pc),%a0
        bsr     cws
        move.w  bmode(%pc),%d0
        bsr     hex4
        lea     m_bp(%pc),%a0
        bsr     cws
        move.l  basep(%pc),%d0
        bsr     hex8
        lea     m_b1(%pc),%a0
        bsr     cws
        move.l  buf1(%pc),%d0
        bsr     hex8
        lea     m_b2(%pc),%a0
        bsr     cws
        move.l  buf2(%pc),%d0
        bsr     hex8
        lea     m_nl(%pc),%a0
        bsr     cws
        lea     m_t1(%pc),%a0
        bsr     cws
        move.l  err1(%pc),%d0
        bsr     passfail
        lea     m_t2(%pc),%a0
        bsr     cws
        move.l  err2(%pc),%d0
        bsr     passfail
        lea     m_al(%pc),%a0
        bsr     cws
        move.l  sum0(%pc),%d0
        sub.l   sum1(%pc),%d0
        bsr     passfail2
        lea     m_res(%pc),%a0
        bsr     cws
        move.l  err1(%pc),%d0
        or.l    err2(%pc),%d0
        move.l  sum0(%pc),%d1
        sub.l   sum1(%pc),%d1
        or.l    %d1,%d0
        lea     m_pass(%pc),%a0
        tst.l   %d0
        beq.s   5f
        lea     m_fail(%pc),%a0
5:      bsr     cws
        bra.s   done
nott:   lea     m_pos(%pc),%a0
        bsr     cws
        lea     m_nott(%pc),%a0
        bsr     cws
        move.l  buf1(%pc),%d0
        bsr     hex8
done:   move.w  #7,-(%sp)
        trap    #1                      | Crawcin: wait for a key
        addq.l  #2,%sp
        lea     contrl(%pc),%a0
        move.w  #101,(%a0)              | v_clsvwk
        clr.w   2(%a0)
        clr.w   6(%a0)
        move.w  vh(%pc),12(%a0)
        bsr     vdi
        lea     aesctl(%pc),%a0
        move.l  #0x00130000,(%a0)       | appl_exit
        move.l  #0x00010000,4(%a0)
        bsr     aes
        clr.w   -(%sp)
        trap    #1
| ---- helpers
setmfdb:                                | a0 -> MFDB (addr already set)
        move.w  geo+2(%pc),4(%a0)       | w
        move.w  geo+4(%pc),6(%a0)       | h
        move.w  geo+2(%pc),%d0
        lsr.w   #4,%d0
        move.w  %d0,8(%a0)              | wdwidth
        clr.w   10(%a0)                 | device format
        move.w  geo(%pc),12(%a0)        | planes
        clr.l   14(%a0)
        clr.w   18(%a0)
        rts
cpyfm:  move.l  %a0,%d1                 | a0 src MFDB, a1 dst MFDB: copy the top-left quarter
        move.l  %a1,%d2
        lea     contrl(%pc),%a0
        move.w  #109,(%a0)
        move.w  #4,2(%a0)
        move.w  #1,6(%a0)
        move.w  vh(%pc),12(%a0)
        move.l  %d1,14(%a0)
        move.l  %d2,18(%a0)
        lea     intin(%pc),%a0
        move.w  #3,(%a0)                | S_ONLY
        lea     ptsin(%pc),%a0
        move.w  geo+2(%pc),%d0
        lsr.w   #1,%d0
        subq.w  #1,%d0
        move.w  geo+4(%pc),%d1
        lsr.w   #1,%d1
        subq.w  #1,%d1
        clr.l   (%a0)
        move.w  %d0,4(%a0)
        move.w  %d1,6(%a0)
        clr.l   8(%a0)
        move.w  %d0,12(%a0)
        move.w  %d1,14(%a0)
        bra     vdi
cmprect:                                | a0,a1 bases: top-left quarter (first half of h lines, first half of each line). d0 = mismatching words
        moveq   #0,%d0
        move.w  geo+4(%pc),%d3
        lsr.w   #1,%d3
        subq.w  #1,%d3
        move.w  geo+6(%pc),%d4          | linebytes
1:      move.w  %d4,%d2
        lsr.w   #2,%d2                  | words in half a line
        subq.w  #1,%d2
        move.l  %a0,%a2
        move.l  %a1,%a3
2:      cmpm.w  (%a2)+,(%a3)+
        beq.s   3f
        addq.l  #1,%d0
3:      dbra    %d2,2b
        add.w   %d4,%a0
        add.w   %d4,%a1
        dbra    %d3,1b
        rts
alias_sum:                              | sum of longs of (buf2 & $FFFFFF), 0 if not below phystop
        move.l  buf2(%pc),%d0
        and.l   #0x00ffffff,%d0
        move.l  %d0,%a3
        clr.l   -(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        move.l  %d0,%d5
        move.l  %a3,%a0
        move.l  %a3,%d1
        add.l   #BUFSZ,%d1
        moveq   #0,%d0
        cmp.l   0x42e.w,%d1
        bhi.s   2f
        move.w  #BUFSZ/4-1,%d1
1:      add.l   (%a0)+,%d0
        rol.l   #1,%d0
        dbra    %d1,1b
2:      move.l  %d0,-(%sp)
        move.l  %d5,-(%sp)
        move.w  #0x20,-(%sp)
        trap    #1
        addq.l  #6,%sp
        move.l  (%sp)+,%d0
        rts
passfail:                               | d0 = error count
        tst.l   %d0
        bne.s   1f
        lea     m_ok(%pc),%a0
        bra     cws
1:      move.l  %d0,-(%sp)
        lea     m_bad(%pc),%a0
        bsr     cws
        move.l  (%sp)+,%d0
        bsr     hex8
        lea     m_nl(%pc),%a0
        bra     cws
passfail2:
        tst.l   %d0
        bne.s   1f
        lea     m_ok(%pc),%a0
        bra     cws
1:      lea     m_chg(%pc),%a0
        bra     cws
hex8:   swap    %d0
        bsr.s   hex4
        swap    %d0
hex4:   moveq   #3,%d2
        lea     hbuf(%pc),%a0
1:      rol.w   #4,%d0
        move.w  %d0,%d1
        and.w   #15,%d1
        move.b  hexd(%pc,%d1.w),(%a0)+
        dbra    %d2,1b
        clr.b   (%a0)
        move.l  %d0,-(%sp)
        lea     hbuf(%pc),%a0
        bsr     cws
        move.l  (%sp)+,%d0
        rts
hexd:   .ascii  "0123456789ABCDEF"
cws:    movem.l %d0-%d2/%a0-%a2,-(%sp)
        move.l  %a0,-(%sp)
        move.w  #9,-(%sp)
        trap    #1
        addq.l  #6,%sp
        movem.l (%sp)+,%d0-%d2/%a0-%a2
        rts
aes:    lea     aespb(%pc),%a0
        lea     aesctl(%pc),%a1
        move.l  %a1,(%a0)
        lea     aesglb(%pc),%a1
        move.l  %a1,4(%a0)
        lea     intin(%pc),%a1
        move.l  %a1,8(%a0)
        lea     aesio(%pc),%a1
        move.l  %a1,12(%a0)
        lea     addrin(%pc),%a1
        move.l  %a1,16(%a0)
        lea     addrout(%pc),%a1
        move.l  %a1,20(%a0)
        move.l  %a0,%d1
        move.w  #200,%d0
        trap    #2
        rts
vdi:    lea     vdipb(%pc),%a0
        lea     contrl(%pc),%a1
        move.l  %a1,(%a0)
        lea     intin(%pc),%a1
        move.l  %a1,4(%a0)
        lea     ptsin(%pc),%a1
        move.l  %a1,8(%a0)
        lea     intout(%pc),%a1
        move.l  %a1,12(%a0)
        lea     ptsout(%pc),%a1
        move.l  %a1,16(%a0)
        move.l  %a0,%d1
        move.w  #115,%d0
        trap    #2
        rts
        .data
m_pos:  .asciz  "\033Y3 \033K"
m_bm:   .asciz  "BFTEST bm $"
m_bp:   .asciz  " bp $"
m_b1:   .asciz  "\r\n\033Kbuf1 $"
m_b2:   .asciz  " buf2 $"
m_nl:   .asciz  "\r\n\033K"
m_t1:   .asciz  "TT->screen: "
m_t2:   .asciz  "screen->TT: "
m_al:   .asciz  "ST alias of dest: "
m_ok:   .asciz  "ok\r\n\033K"
m_bad:  .asciz  "BAD $"
m_chg:  .asciz  "CHANGED\r\n\033K"
m_res:  .asciz  "RESULT: "
m_pass: .asciz  "PASS"
m_fail: .asciz  "FAIL"
m_nott: .asciz  "No TT-RAM from Mxalloc(,1): $"
        .even
        .bss
basep:  .space 4
vh:     .space 2
geo:    .space 8
scr:    .space 4
bmode:  .space 2
buf1:   .space 4
buf2:   .space 4
sum0:   .space 4
sum1:   .space 4
err1:   .space 4
err2:   .space 4
hbuf:   .space 6
mfdb1:  .space 20
mfdb2:  .space 20
mfdbs:  .space 20
aespb:  .space 24
vdipb:  .space 20
aesctl: .space 10
aesglb: .space 30
aesio:  .space 14
addrin: .space 8
addrout:.space 8
contrl: .space 24
intin:  .space 32
ptsin:  .space 32
intout: .space 128
ptsout: .space 32
