| whole-ST bench: STKTEST core + >4MB decode check (ROM at E00000)
	.text
	.long	0x00008000
	.long	start
start:	move.w	#0x2700,%sr
	lea	0x8000,%sp
	move.b	#0x0a,0xffff8001.w
	lea	vars(%pc),%a5
	lea	berr(%pc),%a0
	move.l	%a0,0x8.w
	lea	trap3(%pc),%a0
	move.l	%a0,0x8c.w
	lea	hbl(%pc),%a0
	move.l	%a0,0x68.w
	move.l	%a0,0x70.w
	clr.l	0x1200.w
	clr.l	0x1204.w
	clr.l	0x1300.w
| >4MB read and fetch must bus-error
	move.l	%sp,0x1240.w
	lea	ab1(%pc),%a0
	move.l	%a0,0x1244.w
	tst.w	0x416528
ab1:	lea	ab2(%pc),%a0
	move.l	%a0,0x1244.w
	jmp	0x416528
ab2:	move.w	#0x2100,%sr		| HBL (level 2) and VBL on
	move.w	#30,%d7
loop:	move.l	%sp,0x1260.w
	moveq	#1,%d5
	moveq	#24,%d0
	bsr	rec
rec_ret:
	moveq	#2,%d5
	bsr	tmovem
	moveq	#3,%d5
	bsr	ttrap
	moveq	#4,%d5
	bsr	tfrexp
	dbra	%d7,loop
	move.w	#0x2700,%sr
	move.l	#0x600dc0de,0x1ffc.w
9:	bra.s	9b
hbl:	addq.l	#1,0x1300.w
	rte
berr:	addq.l	#1,0x1200.w
	move.l	2(%sp),0x1208.w
	move.w	6(%sp),0x120c.w
	move.l	16(%sp),0x1210.w
	move.l	0x1240.w,%sp
	move.l	0x1244.w,-(%sp)
	rts
fail_l:
fail:	lea	vars(%pc),%a5
	move.w	#0x2700,%sr
	move.l	%d5,0x1204.w
	move.l	%d3,0x1220.w
	move.l	%d4,0x1224.w
	move.l	%a3,0x1228.w
	move.l	%d7,0x122c.w
	move.l	#0x600dc0de,0x1ffc.w
8:	bra.s	8b
| test 1: recursive BSR/RTS, each level pushes $0005xxxx pattern and its
| own return address target; checks both on the way back.
rec:	lea	rec_ret(%pc),%a0	| return address must be rec_ret or rec_in
	cmpa.l	(%sp),%a0
	beq.s	1f
	lea	rec_in(%pc),%a0
	cmpa.l	(%sp),%a0
	beq.s	1f
	move.l	%a0,%d3
	move.l	(%sp),%d4
	move.l	%sp,%a3
	bra	fail
1:	subq.w	#1,%d0
	beq.s	9f
	move.l	%d0,%d1
	swap	%d1
	move.w	#0x0005,%d1
	swap	%d1			| $0005|depth
	ori.w	#0x6500,%d1
	move.l	%d1,-(%sp)
	pea	rec(%pc)		| a code address as data
	bsr	rec
rec_in:	lea	rec(%pc),%a0
	move.l	%a0,%d3
	move.l	%sp,%a3
	move.l	(%sp)+,%d4
	cmp.l	%d3,%d4
	bne	fail
	move.l	%d1,%d3
	move.l	%sp,%a3
	move.l	(%sp)+,%d4
	cmp.l	%d3,%d4
	bne	fail
9:	addq.w	#1,%d0
	move.l	%d0,%d1			| rebuild d1 = f(d0) for the caller level
	swap	%d1
	move.w	#0x0005,%d1
	swap	%d1
	ori.w	#0x6500,%d1
	rts

| test 2: MOVEM.L all registers with patterns, LINK/UNLK frame
tmovem:	movem.l	%d5/%a5,-(%sp)
	move.l	#0x00056528,%d0
	move.l	#0x00056722,%d1
	move.l	#0x0005A228,%d2
	move.l	#0x00058D76,%d3
	move.l	#0x0005581A,%d4
	move.l	#0x3FF00000,%d6
	move.l	#0x00050005,%d7
	move.l	#0x00055718,%a0
	move.l	#0x000590A1,%a1
	move.l	#0x000304F6,%a2
	move.l	#0x00055710,%a3
	move.l	#0x0005571A,%a4
	movem.l	%d0-%d4/%d6-%d7/%a0-%a4,-(%sp)
	movem.l	zeros(%pc),%d0-%d4/%d6-%d7/%a0-%a4
	link	%a6,#-8
	move.l	#0x00056528,-4(%a6)
	move.l	#0x00056722,-8(%a6)
	bsr	nop1
	cmp.l	#0x00056528,-4(%a6)
	bne.s	2f
	cmp.l	#0x00056722,-8(%a6)
	bne.s	2f
	unlk	%a6
	movem.l	(%sp)+,%d0-%d4/%d6-%d7/%a0-%a4
	lea	tab2(%pc),%a6
	move.l	(%sp),%d5		| (keep)
	cmp.l	(%a6)+,%d0
	bne.s	3f
	cmp.l	(%a6)+,%d1
	bne.s	3f
	cmp.l	(%a6)+,%d2
	bne.s	3f
	cmp.l	(%a6)+,%d3
	bne.s	3f
	cmp.l	(%a6)+,%d4
	bne.s	3f
	cmp.l	(%a6)+,%d6
	bne.s	3f
	cmp.l	(%a6)+,%d7
	bne.s	3f
	cmpa.l	(%a6)+,%a0
	bne.s	3f
	cmpa.l	(%a6)+,%a1
	bne.s	3f
	cmpa.l	(%a6)+,%a2
	bne.s	3f
	cmpa.l	(%a6)+,%a3
	bne.s	3f
	cmpa.l	(%a6)+,%a4
	bne.s	3f
	movem.l	(%sp)+,%d5/%a5
	rts
2:	move.l	-4(%a6),%d4		| LINK frame corrupted
	move.l	#0x00056528,%d3
	lea	-4(%a6),%a3
	moveq	#2,%d5
	bra	fail_l
3:	move.l	-(%a6),%d3		| expected in table; actual: find reg
	movem.l	(%sp)+,%d5/%a5
	lea	msg_movem(%pc),%a0
	moveq	#0,%d4
	sub.l	%a3,%a3
	bra	fail
nop1:	rts

| test 3: push pattern, TRAP #3 (handler just RTEs), check pattern and SR
ttrap:	move.l	#0x00056722,-(%sp)
	move.w	%sr,%d2
	trap	#3
	move.w	%sr,%d1
	cmp.w	%d1,%d2
	bne.s	1f
	move.l	%sp,%a3
	move.l	(%sp)+,%d4
	move.l	#0x00056722,%d3
	cmp.l	%d3,%d4
	bne	fail
	rts
1:	moveq	#0,%d3
	move.w	%d2,%d3
	moveq	#0,%d4
	move.w	%d1,%d4
	move.l	%sp,%a3
	bra	fail
trap3:	rte

| test 4: mirror of GEMBENCH $5671A/$564F8 (movem d2-d7/a1, bsr, frexp with
| link/movem d2/a3/a5, asr/andi/subi on the exponent, movem/unlk/rts)
tfrexp:	movem.l	%d2-%d7/%a1,-(%sp)
	lea	0x1250.w,%a0
	pea	(%a0)			| int *exp
	move.l	#0,-(%sp)		| low long of 1.0
	move.l	#0x3FF00000,-(%sp)	| high long of 1.0
	bsr	frexp
f_ret:	lea	12(%sp),%sp
	movem.l	(%sp)+,%d2-%d7/%a1
	move.l	0x1250.w,%d4
	moveq	#1,%d3			| frexp(1.0) exponent = 1
	cmp.l	%d3,%d4
	bne.s	1f
	rts
1:	lea	0x1250.w,%a3
	bra	fail
frexp:	link	%a6,#-4
	movem.l	%d2/%a3/%a5,-(%sp)
	lea	f_ret(%pc),%a3		| check own return address on the stack
	cmpa.l	4(%a6),%a3
	beq.s	2f
	move.l	%a3,%d3
	move.l	4(%a6),%d4
	lea	4(%a6),%a3
	movem.l	(%sp)+,%d2/%a3/%a5
	unlk	%a6
	lea	vars(%pc),%a5
	bra	fail
2:	movea.l	16(%a6),%a5
	move.l	8(%a6),%d0
	move.l	%d0,%d1
	lsl.l	#1,%d1
	or.l	12(%a6),%d1
	bne.s	3f
	clr.l	(%a5)
	bra.s	4f
3:	lea	8(%a6),%a3
	moveq	#0,%d1
	move.w	(%a3),%d1
	move.l	%d1,%d2
	asr.l	#4,%d2
	andi.l	#2047,%d2
	subi.l	#1022,%d2
	move.l	%d2,(%a5)
4:	movem.l	(%sp)+,%d2/%a3/%a5
	unlk	%a6
	rts


	.even
tab2:	.long	0x00056528,0x00056722,0x0005A228,0x00058D76,0x0005581A
	.long	0x3FF00000,0x00050005,0x00055718,0x000590A1,0x000304F6
	.long	0x00055710,0x0005571A
zeros:	.long	0,0,0,0,0,0,0,0,0,0,0,0
msg_movem: .asciz ""
	.even

vars:
savsp:	.long	0
