| STKTEST.PRG - stack long-word integrity test (FalconFPGA, 2026-10-12)
| Hunts the board fault where the high word of a stacked long reads back
| wrong ($0005xxxx -> $0041xxxx, GEMBENCH frexp panic). Supervisor mode,
| interrupts on. Position independent (no relocation). GNU as syntax.
	.text
start:	lea	vars(%pc),%a5
	clr.l	-(%sp)
	move.w	#0x20,-(%sp)		| Super(0)
	trap	#1
	addq.l	#6,%sp
	move.l	%d0,oldssp-vars(%a5)
	move.l	0x8c.w,oldtrap-vars(%a5)
	lea	trap3(%pc),%a0
	move.l	%a0,0x8c.w		| TRAP #3 vector
	move.w	#0x2300,%sr		| interrupts above 3 enabled (VBL/MFP)
	lea	msg_hi(%pc),%a0
	bsr	puts
	clr.l	iter-vars(%a5)
loop:	move.l	%sp,savsp-vars(%a5)
	moveq	#1,%d5			| test 1: recursion
	moveq	#48,%d0
	bsr	rec
rec_ret:
	moveq	#2,%d5			| test 2: MOVEM + LINK/UNLK
	bsr	tmovem
	moveq	#3,%d5			| test 3: TRAP/RTE round trip
	bsr	ttrap
	moveq	#4,%d5			| test 4: frexp mix
	bsr	tfrexp
	addq.l	#1,iter-vars(%a5)
	move.l	iter-vars(%a5),%d0
	divu	#10000,%d0
	swap	%d0
	tst.w	%d0
	bne.s	loop
	lea	msg_pass(%pc),%a0
	bsr	puts
	move.l	iter-vars(%a5),%d0
	bsr	puthex
	lea	msg_nl(%pc),%a0
	bsr	puts
	move.w	#0x0b,-(%sp)		| Cconis
	trap	#1
	addq.l	#2,%sp
	tst.w	%d0
	beq	loop
	bsr	getkey
quit:	move.l	oldtrap-vars(%a5),0x8c.w
	move.l	oldssp-vars(%a5),-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	clr.w	-(%sp)
	trap	#1

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
	lea	expv(%pc),%a0
	pea	(%a0)			| int *exp
	move.l	#0,-(%sp)		| low long of 1.0
	move.l	#0x3FF00000,-(%sp)	| high long of 1.0
	bsr	frexp
f_ret:	lea	12(%sp),%sp
	movem.l	(%sp)+,%d2-%d7/%a1
	move.l	expv(%pc),%d4
	moveq	#1,%d3			| frexp(1.0) exponent = 1
	cmp.l	%d3,%d4
	bne.s	1f
	rts
1:	lea	expv(%pc),%a3
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

| ---- failure: d3 expected, d4 actual, a3 address, d5 test, iter in vars
fail_l:	lea	vars(%pc),%a5
fail:	lea	vars(%pc),%a5
	move.l	savsp-vars(%a5),%sp
	movem.l	%d3-%d5/%a3,-(%sp)
	lea	msg_f(%pc),%a0
	bsr	puts
	move.l	8(%sp),%d0
	bsr	puthex
	lea	msg_e(%pc),%a0
	bsr	puts
	move.l	(%sp),%d0
	bsr	puthex
	lea	msg_a(%pc),%a0
	bsr	puts
	move.l	4(%sp),%d0
	bsr	puthex
	lea	msg_ad(%pc),%a0
	bsr	puts
	move.l	12(%sp),%d0
	bsr	puthex
	lea	msg_it(%pc),%a0
	bsr	puts
	move.l	iter-vars(%a5),%d0
	bsr	puthex
	lea	msg_key(%pc),%a0
	bsr	puts
	lea	16(%sp),%sp
	bsr	getkey
	bra	quit

getkey:	move.w	#7,-(%sp)		| Crawcin
	trap	#1
	addq.l	#2,%sp
	rts
puts:	move.l	%a0,-(%sp)		| Cconws
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	rts
puthex:	lea	hexbuf(%pc),%a0		| d0 -> 8 hex digits
	moveq	#7,%d2
1:	rol.l	#4,%d0
	move.b	%d0,%d1
	andi.w	#15,%d1
	move.b	hexd(%pc,%d1.w),(%a0)+
	dbra	%d2,1b
	clr.b	(%a0)
	lea	hexbuf(%pc),%a0
	bra	puts
hexd:	.ascii	"0123456789ABCDEF"

	.even
tab2:	.long	0x00056528,0x00056722,0x0005A228,0x00058D76,0x0005581A
	.long	0x3FF00000,0x00050005,0x00055718,0x000590A1,0x000304F6
	.long	0x00055710,0x0005571A
zeros:	.long	0,0,0,0,0,0,0,0,0,0,0,0
msg_hi:	.asciz	"STKTEST: stack long check (any key quits)\r\n"
msg_pass: .asciz "pass "
msg_nl:	.asciz	"\r\n"
msg_f:	.asciz	"\r\nFAIL test "
msg_e:	.asciz	" exp "
msg_a:	.asciz	" got "
msg_ad:	.asciz	" at "
msg_it:	.asciz	" iter "
msg_key: .asciz	"\r\npress a key\r\n"
msg_movem: .asciz ""
	.even
vars:
oldssp:	.long	0
oldtrap: .long	0
savsp:	.long	0
iter:	.long	0
expv:	.long	0
hexbuf:	.space	10
	.even
