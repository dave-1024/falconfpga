| report
	lea	out(%pc),%a5
	move.b	#'N',(%a5)+
	move.l	%d6,%d0
	bsr	hex8
	move.b	#13,(%a5)+
	move.b	#10,(%a5)+
	lea	fl(%pc),%a3
	moveq	#15,%d4
	cmp.l	%d4,%d6
	bge	r1
	move.l	%d6,%d4
	subq.l	#1,%d4
	bmi	r2
r1:	move.l	(%a3)+,%d0
	bsr	hex8
	move.b	#' ',(%a5)+
	move.l	(%a3)+,%d0
	bsr	hex8
	move.b	#13,(%a5)+
	move.b	#10,(%a5)+
	dbra	%d4,r1
r2:	lea	okm(%pc),%a0
	tst.l	%d6
	beq	cp
	lea	badm(%pc),%a0
cp:	move.b	(%a0)+,(%a5)+
	bne	cp
	rts
| rec: d0.w = test id, d2 = got; store up to 16 pairs (id | pass<<16)
rec:	movem.l	%d0/%a3,-(%sp)
	addq.l	#1,%d6
	cmp.l	#16,%d6
	bgt	rc9
	lea	fl(%pc),%a3
	move.l	flp-fl(%a3),%a3
	swap	%d0
	move.w	passn(%pc),%d0
	swap	%d0
	move.l	%d0,(%a3)+
	move.l	%d2,(%a3)+
	move.l	%a3,%d0
	lea	flp(%pc),%a3
	move.l	%d0,(%a3)
rc9:	movem.l	(%sp)+,%d0/%a3
	rts
hex8:	movem.l	%d0-%d3,-(%sp)
	moveq	#7,%d3
h1:	rol.l	#4,%d0
	move.b	%d0,%d1
	and.b	#15,%d1
	add.b	#'0',%d1
	cmp.b	#'9',%d1
	bls	h2
	addq.b	#7,%d1
h2:	move.b	%d1,(%a5)+
	dbra	%d3,h1
	movem.l	(%sp)+,%d0-%d3
	rts
okm:	.asciz	"EA3 PASS\r\n"
badm:	.asciz	"EA3 FAIL\r\n"
