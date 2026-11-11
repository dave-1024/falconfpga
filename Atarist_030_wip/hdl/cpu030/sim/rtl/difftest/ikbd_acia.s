# EmuTOS 1.4 int_acia / ikbdsys / ikbdraw / VDI _mouse_int / AES button bits.
# Compare F157 vs F156 in the difftest harness. Sweep IPL_MODE=2 IRQ_DLY
# so the level-4 IRQ lands at many offsets during the F157 2-clock paths
# (CMP/TST/AND.B/OR.B/BSET/LSR.B/Scc + ADD-type).
# Packet SM and button extracts are from:
#   bios/aciavecs.S  (_int_acia, _ikbdsys, ikbdraw, kbd_rel_mouse)
#   vdi/vdi_asm.S    (_mouse_int: and.b #0xF8 / cmp.b / and.w #3 / lsr.b / bset)
#   aes/gemdosif.S   (_far_bcha -> b_click)
        .text
        .long 0x00002F00
        .long 0x00FC0008
start:  move.w #0x2700,sr
        lea 0x400,a7
        lea h4(pc),a0
        move.l a0,0x70
        clr.l 0x3200
        clr.l 0x2600

        # Fake MFP ($2800) / ACIA ($2810/$2812) / packet workspace
        lea 0x2800,a0
        move.w #15,d0
1:      clr.l (a0)+
        dbf d0,1b
        # GPIP bit 4 clear => keep looping once like int_acia (btst #4,1(a1); beq loop)
        move.b #0x10,0x2801
        # ACIA: IRQ (bit7) + RDRF (bit0), no overrun (bit5)
        move.b #0x81,0x2810
        move.b #0xF9,0x2812

        lea 0x2900,a0
        move.b #0xF9,(a0)
        move.b #0x10,1(a0)
        move.b #0xE0,2(a0)
        clr.b 0x2920
        move.w #1,0x2922
        move.b #2,0x2924
        clr.b 0x2930
        move.w #0,0x2932
        move.w #320,0x2934
        move.w #100,0x2936
        clr.l 0x2940
        clr.l 0x2944
        lea mousevec(pc),a0
        move.l a0,0x2950
        lea ikbdsys(pc),a0
        move.l a0,0x2954

        # seed D registers like a live AES/VDI context
        move.l #0x000000F9,d0
        move.l #0x000000F8,d1
        move.l #0x00FF00FF,d2
        move.l #0x00000003,d3
        move.l #0xA5A5A5A5,d4
        move.l #0x00000000,d5
        move.l #0x12345678,d6
        move.l #0x00000000,d7

        move.w #0x2000,sr
        move.w #1,0x3400

        move.w #80,d7
mainlp:
        # --- F157 2-clock ADD-type / CMP / TST, then CCR consumers ---
        add.l d2,d6
        sub.l d3,d6
        and.l d2,d6
        or.l d3,d6
        eor.l d4,d6
        addq.l #1,d6
        subq.l #1,d6
        cmp.l d2,d6
        scc d5
        tst.l d6
        sne d5
        cmp.w d3,d6
        seq d5
        tst.w d6
        spl d5
        cmp.b d3,d6
        scs d5
        tst.b d6
        smi d5
        beq.s .m1
        addq.l #1,d4
.m1:    bne.s .m2
        addq.l #1,d4
.m2:    bcc.s .m3
        addq.l #1,d4
.m3:    bcs.s .m4
        addq.l #1,d4
.m4:
        # --- AES/VDI button bit ops (byte-size + flags) ---
        lea 0x2940,a2
        move.b 0x2812,d0
        move.b d0,d1
        and.b #0xF8,d1
        cmp.b #0xF8,d1
        bne.s .nothdr
        and.w #3,d0
        lsr.b #1,d0
        bcc.s .noleft
        bset #1,d0
.noleft:
        move.b 0x2930,d1
        and.w #3,d1
        cmp.b d1,d0
        beq.s .samebt
        move.w 0x2932,d2
        andi.w #0xFFFC,d2
        or.w d2,d0
        move.w d0,0x2932
        eor.b d0,d1
        ror.b #2,d1
        or.b d1,d0
        move.b d0,0x2930
        bset #0,0x2940
        or.b #1,0x2941
        addq.l #1,0x2944
        bra.s .btndone
.samebt:
        bclr #0,0x2940
        and.b #0xFE,0x2941
.btndone:
        btst #0,0x2940
        beq.s .nolt2
        addq.l #1,d4
.nolt2:
        and.b #3,0x2940
        or.b #0,0x2940
        not.b d5
        tst.b 0x2940
        sne d5
        cmp.b #1,0x2940
        scc d5
.nothdr:
        # --- int_acia-style: MOVEM, jsr through vector, MFP btst, RTE path in IRQ ---
        movem.l d0-d3/a0-a3,-(sp)
        move.l 0x2954,a0
        jsr (a0)
        lea 0x2800,a1
        btst.b #4,1(a1)
        bne.s .acia1
        move.l 0x2954,a0
        jsr (a0)
.acia1: move.b #0xBF,0x2811
        movem.l (sp)+,d0-d3/a0-a3

        # more 2-clock ops so IRQ_DLY sweep hits them
        move.l d6,d0
        add.l d0,d0
        cmp.b #0xF9,d0
        beq.s .m5
        addq.w #1,d5
.m5:    tst.b d0
        bpl.s .m6
        addq.w #1,d5
.m6:    lsr.b #1,d0
        bcc.s .m7
        bset #0,d5
.m7:    bclr #7,d5
        btst #1,d5
        bne.s .m8
        ori.b #2,d5
.m8:
        subq.w #1,d7
        bne mainlp

        move.w sr,d5
        move.w #0x2700,sr
        movem.l d0-d7/a0-a6,0x5000
        move.l a7,0x503C
        move.w d5,0x5040
        move.l 0x3200,0x3310
        move.l 0x2940,0x3314
        move.l 0x2944,0x3318
        move.w 0x2932,0x331C
        move.b 0x2930,0x331E
        move.w #0x600D,0x3320
        move.w #1,0x3300
        move.w #0xFFFF,0x3400
hang:   bra.s hang

# ---- ikbdsys (aciavecs.S) against RAM-backed ACIA ----
ikbdsys:
        moveq #0,d0
        move.b 0x2810,d1
        move.b d1,d0
        bpl.s ikbdrts
        btst #0,d0
        beq.s ikbdrts
        move.w d0,-(sp)
        move.b 0x2812,d0
        jsr ikbdraw
        move.w (sp)+,d0
        btst #5,d0
        beq.s ikbdrts
        move.b 0x2812,d0
        addq.l #1,0x2960
ikbdrts:
        rts

# ---- ikbdraw packet state machine ----
ikbdraw:
        tst.b 0x2920
        bne.s in_packet
        cmp.w #0xF6,d0
        bcc.s begin_packet
        rts
begin_packet:
        move.b d0,0x2900
        move.w #1,0x2922
        move.b d0,d1
        sub.b #0xF6,d1
        lea sttab(pc),a0
        move.b (a0,d1.w),0x2920
        lea lntab(pc),a0
        move.b (a0,d1.w),0x2924
        rts
sttab:  .dc.b 1,2,3,3,3,3,4,5,6,7
lntab:  .dc.b 7,5,2,2,2,2,6,2,1,1
        .even
in_packet:
        move.w 0x2922,d1
        lea 0x2900,a0
        move.b d0,(a0,d1.w)
        sub.b #1,0x2924
        beq.s got_packet
        addq.w #1,0x2922
        rts
got_packet:
        moveq #0,d1
        move.b 0x2920,d1
        cmp.b #3,d1
        bne.s gp_done
        lea 0x2900,a0
        move.l 0x2950,a1
        move.l a0,-(sp)
        jsr (a1)
        addq.l #4,sp
gp_done:
        clr.b 0x2920
        rts

# ---- VDI _mouse_int (trimmed) ----
mousevec:
        movem.l d0-d3/a0-a2,-(sp)
        move.l 8+28(sp),a0




        move.l 32(sp),a0
        move.b (a0),d0
        move.b d0,d1
        and.b #0xF8,d1
        cmp.b #0xF8,d1
        bne.s ms_done
        and.w #3,d0
        lsr.b #1,d0
        bcc.s no_left
        bset #1,d0
no_left:
        move.b 0x2930,d1
        and.w #3,d1
        cmp.b d1,d0
        beq.s xy_update
        move.w 0x2932,d2
        andi.w #0xFFFC,d2
        or.w d2,d0
        move.w d0,0x2932
        move.w d0,0x2940
        eor.b d0,d1
        ror.b #2,d1
        or.b d1,d0
        move.b d0,0x2930
        addq.l #1,0x2944
xy_update:
        move.b 1(a0),d0
        or.b 2(a0),d0
        beq.s ms_done
        bset #5,0x2930
        move.w 0x2934,d0
        move.b 1(a0),d1
        ext.w d1
        add.w d1,d0
        move.w d0,0x2934
        move.w 0x2936,d1
        move.b 2(a0),d3
        ext.w d3
        add.w d3,d1
        move.w d1,0x2936
ms_done:
        movem.l (sp)+,d0-d3/a0-a2
        rts

# IRQ: same MOVEM / jsr / MFP / RTE shape as _int_acia
h4:     addq.l #1,0x3200
        movem.l d0-d3/a0-a3,-(sp)
        move.l 0x2954,a0
        jsr (a0)
        lea 0x2800,a1
        btst.b #4,1(a1)
        bne.s h4x
        move.l 0x2954,a0
        jsr (a0)
h4x:    move.b #0xBF,0x11(a1)
        movem.l (sp)+,d0-d3/a0-a3
        move.w (sp),0x3208
        rte
